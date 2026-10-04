import SwiftUI
import Charts

/// Détail d'un budget : chiffres de la période, rythme de dépense, périodes précédentes,
/// transactions, et inspecteur (catégories, réglages, historique des montants).
struct BudgetDetailView: View {
    let budget: Budget

    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var versions: [BudgetVersion] = []
    @State private var showEditForm = false
    @State private var showAdjustSheet = false
    @State private var showDeleteConfirmation = false
    @State private var adjustAmount: String = ""
    @State private var adjustNote: String = ""
    @State private var adjustDate: Date = Date()
    @State private var referenceDate: Date = Date()
    @State private var selectedHistoryLabel: String?
    @AppStorage("showBudgetDetailInspector") private var showInspector = true

    typealias Window = (start: Date, end: Date)

    /// Dépense d'une période, pour le graphique des périodes précédentes
    struct PeriodPoint: Identifiable {
        let start: Date
        let label: String
        let spent: Decimal
        let amount: Decimal

        var id: Date { start }
        var kind: String { spent > amount && amount > 0 ? "Dépassé" : "Dans le budget" }
    }

    struct PacePoint: Identifiable {
        let date: Date
        let value: Double
        let series: String

        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    private static let historyCount = 6

    // MARK: - Période affichée

    /// Budget à jour (nom, catégories, note) après une modification
    private var current: Budget {
        budgetsController.budgets.first { $0.id == budget.id } ?? budget
    }

    private var window: Window {
        current.period.currentWindow(anchor: current.anchorDate, relativeTo: referenceDate)
    }

    private var isCurrentPeriod: Bool {
        window.start == current.period.currentWindow(anchor: current.anchorDate).start
    }

    private var canGoBack: Bool { window.start > current.anchorDate }

    private func goToPreviousPeriod() {
        referenceDate = Calendar.current.date(byAdding: .day, value: -1, to: window.start) ?? window.start
    }

    private func goToNextPeriod() {
        referenceDate = window.end
    }

    /// Montant en vigueur au début d'une période
    private func amount(for window: Window) -> Decimal {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: window.start)
        return versions
            .filter { calendar.startOfDay(for: $0.effectiveFrom) <= day }
            .max { $0.effectiveFrom < $1.effectiveFrom }?
            .amount ?? 0
    }

    /// Dépenses du budget sur une période, de la plus récente à la plus ancienne
    private func transactions(in window: Window) -> [Transaction] {
        let categorySet = Set(current.categoryIDs)
        let excludedAccounts = budgetsController.excludedAccountIDs()
        return transactionsController.allTransactions
            .filter { tx in
                !excludedAccounts.contains(tx.accountID)
                && tx.date >= window.start
                && tx.date < window.end
                && tx.signedAmount < 0
                && tx.categoryID.map { categorySet.contains($0) } ?? false
                && tx.status != .skipped
            }
            .sorted { $0.date > $1.date }
    }

    private func total(_ transactions: [Transaction]) -> Decimal {
        transactions.reduce(Decimal(0)) { $0 + abs($1.signedAmount) }
    }

    // MARK: - Body

    var body: some View {
        let window = self.window
        let transactions = transactions(in: window)
        let amount = amount(for: window)
        let spent = total(transactions)

        VStack(spacing: 0) {
            summaryHeader(window: window, amount: amount, spent: spent)
            Divider()

            // L'inspecteur se loge sous l'en-tête
            SidePanelLayout(isPresented: $showInspector) {
                ScrollView {
                    VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                        HStack(alignment: .top, spacing: NativeMetrics.groupSpacing) {
                            paceBlock(window: window, amount: amount, transactions: transactions)
                            historyBlock(selected: window)
                        }
                        transactionsBlock(transactions)
                    }
                    .padding(NativeMetrics.pagePadding)
                }

                TableStatusBar(items: statusItems(transactions, spent: spent))
            } panel: {
                inspectorContent(transactions: transactions, spent: spent)
            }
        }
        .pageBackground()
        .navigationTitle(current.name)
        .navigationSubtitle("\(current.period.displayName) · \(periodLabel(window))")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    goToPreviousPeriod()
                } label: {
                    Label("Période précédente", systemImage: "chevron.left")
                }
                .disabled(!canGoBack)
                .help("Période précédente")

                Button {
                    referenceDate = Date()
                } label: {
                    Text(isCurrentPeriod ? "Période en cours" : periodLabel(window))
                }
                .help("Revenir à la période en cours")

                Button {
                    goToNextPeriod()
                } label: {
                    Label("Période suivante", systemImage: "chevron.right")
                }
                .disabled(isCurrentPeriod)
                .help("Période suivante")

                Button("Ajuster le montant…") { showAdjustSheet = true }
                    .help("Changer le montant du budget à partir d'une date")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help("Afficher ou masquer l'inspecteur")
            }
        }
        .task { await loadVersions() }
        .onChange(of: budgetsController.budgets) { _, _ in
            Task { await loadVersions() }
        }
        .sheet(isPresented: $showEditForm) {
            BudgetFormView(isPresented: $showEditForm, budgetToEdit: current)
        }
        .sheet(isPresented: $showAdjustSheet) {
            adjustSheet
        }
        .alert("Supprimer le budget ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await budgetsController.deleteBudget(id: budget.id)
                    dismiss()
                }
            }
        } message: {
            Text("Le budget « \(current.name) » et son historique de montants seront supprimés. Les transactions ne sont pas touchées.")
        }
    }

    // MARK: - Grands chiffres

    private func summaryHeader(window: Window, amount: Decimal, spent: Decimal) -> some View {
        let remaining = amount - spent
        let isOver = spent > amount
        let calendar = Calendar.current
        let totalDays = max(calendar.dateComponents([.day], from: window.start, to: window.end).day ?? 1, 1)
        let today = calendar.startOfDay(for: Date())
        let daysLeft = max(calendar.dateComponents([.day], from: today, to: window.end).day ?? 0, 0)
        let elapsed = min(max(Double(totalDays - daysLeft) / Double(totalDays), 0), 1)
        let ratio = fraction(spent, of: amount)
        let percent = amount > 0 ? Int((NSDecimalNumber(decimal: spent / amount).doubleValue * 100).rounded()) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 40) {
                figure("Budget", money(amount), detail: current.period.displayName)
                figure("Dépensé", money(spent), detail: "\(percent) % du budget")
                figure(
                    isOver ? "Dépassement" : "Reste",
                    money(abs(remaining)),
                    color: isOver ? .red : .green,
                    detail: isCurrentPeriod ? "\(daysLeft) jour\(daysLeft > 1 ? "s" : "") restant\(daysLeft > 1 ? "s" : "")" : "Période terminée"
                )
                if isCurrentPeriod {
                    figure(
                        "Disponible par jour",
                        money(daysLeft > 0 && remaining > 0 ? remaining / Decimal(daysLeft) : 0),
                        detail: "Jusqu'à la fin de la période"
                    )
                } else {
                    figure("Dépense par jour", money(spent / Decimal(totalDays)), detail: "En moyenne")
                }
                Spacer(minLength: 0)
            }

            // Barre de progression avec le repère « aujourd'hui »
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(isOver ? Color.red : Color.accentColor)
                        .frame(width: geometry.size.width * ratio)
                    if isCurrentPeriod {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary)
                            .frame(width: 2, height: 14)
                            .offset(x: geometry.size.width * elapsed - 1)
                    }
                }
                .frame(height: geometry.size.height)
            }
            .frame(height: 6)
            .padding(.vertical, 4)

            Text(paceText(ratio: ratio, elapsed: elapsed, isOver: isOver, remaining: remaining))
                .font(.caption)
                .foregroundStyle(.secondary)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func paceText(ratio: Double, elapsed: Double, isOver: Bool, remaining: Decimal) -> String {
        if isCurrentPeriod {
            if isOver { return "Budget dépassé de \(money(-remaining)) avant la fin de la période." }
            return ratio <= elapsed
                ? "Le repère marque aujourd'hui : vous dépensez moins vite que le rythme du budget."
                : "Le repère marque aujourd'hui : vous dépensez plus vite que le rythme du budget."
        }
        return isOver
            ? "Budget dépassé de \(money(-remaining)) sur cette période."
            : "Budget respecté, \(money(remaining)) non dépensés."
    }

    private func figure(_ title: String, _ value: String, color: Color = .primary, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: appSettings.hideAmounts)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dépenses cumulées

    private func paceBlock(window: Window, amount: Decimal, transactions: [Transaction]) -> some View {
        let points = pacePoints(window: window, amount: amount, transactions: transactions)

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("Dépenses cumulées sur la période")

            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", point.value),
                    series: .value("Série", point.series)
                )
                .foregroundStyle(by: .value("Série", point.series))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: point.series == "Rythme du budget" ? [4, 4] : []))
            }
            .chartForegroundStyleScale([
                "Dépensé": Color.accentColor,
                "Rythme du budget": Color.secondary
            ])
            .chartLegend(position: .top, alignment: .trailing)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
        .frame(maxWidth: .infinity)
    }

    /// Cumul jour par jour (jusqu'à aujourd'hui pour la période en cours) et droite du rythme du budget
    private func pacePoints(window: Window, amount: Decimal, transactions: [Transaction]) -> [PacePoint] {
        let calendar = Calendar.current
        var byDay: [Date: Decimal] = [:]
        for transaction in transactions {
            byDay[calendar.startOfDay(for: transaction.date), default: 0] += abs(transaction.signedAmount)
        }

        var points: [PacePoint] = [PacePoint(date: window.start, value: 0, series: "Dépensé")]
        let lastDay = min(calendar.startOfDay(for: Date()), calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end)
        var day = calendar.startOfDay(for: window.start)
        var cumulated = Decimal(0)
        while day <= lastDay {
            cumulated += byDay[day] ?? 0
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            points.append(PacePoint(date: endOfDay, value: NSDecimalNumber(decimal: cumulated).doubleValue, series: "Dépensé"))
            day = endOfDay
        }

        points.append(PacePoint(date: window.start, value: 0, series: "Rythme du budget"))
        points.append(PacePoint(date: window.end, value: NSDecimalNumber(decimal: amount).doubleValue, series: "Rythme du budget"))
        return points
    }

    // MARK: - Périodes précédentes

    private func historyBlock(selected: Window) -> some View {
        let history = historyPoints
        let average: Decimal = history.isEmpty ? 0 : history.reduce(Decimal(0)) { $0 + $1.spent } / Decimal(history.count)
        let currentAmount = history.last?.amount ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle(title: "\(history.count) dernière\(history.count > 1 ? "s" : "") période\(history.count > 1 ? "s" : "")") {
                Text("Moyenne : \(money(average))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }

            Chart {
                ForEach(history) { point in
                    BarMark(
                        x: .value("Période", point.label),
                        y: .value("Dépensé", NSDecimalNumber(decimal: point.spent).doubleValue)
                    )
                    .foregroundStyle(by: .value("État", point.kind))
                    .opacity(point.start == selected.start ? 1 : 0.45)
                    .cornerRadius(3)
                }

                if currentAmount > 0 {
                    RuleMark(y: .value("Budget", NSDecimalNumber(decimal: currentAmount).doubleValue))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartForegroundStyleScale([
                "Dans le budget": Color.accentColor,
                "Dépassé": Color.red
            ])
            .chartXScale(domain: history.map { $0.label })
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedHistoryLabel)
            .onChange(of: selectedHistoryLabel) { _, label in
                // Un clic sur une barre affiche cette période
                if let point = history.first(where: { $0.label == label }) {
                    referenceDate = point.start
                }
            }
            .frame(height: 190)
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
        .frame(maxWidth: .infinity)
    }

    /// Les dernières périodes jusqu'à la période en cours, de la plus ancienne à la plus récente
    private var historyPoints: [PeriodPoint] {
        let calendar = Calendar.current
        var result: [PeriodPoint] = []
        var window = current.period.currentWindow(anchor: current.anchorDate)

        for _ in 0..<Self.historyCount {
            result.append(PeriodPoint(
                start: window.start,
                label: shortLabel(window),
                spent: total(transactions(in: window)),
                amount: amount(for: window)
            ))
            guard window.start > current.anchorDate,
                  let previous = calendar.date(byAdding: .day, value: -1, to: window.start) else { break }
            let previousWindow = current.period.currentWindow(anchor: current.anchorDate, relativeTo: previous)
            guard previousWindow.start < window.start else { break }
            window = previousWindow
        }
        return result.reversed()
    }

    // MARK: - Transactions

    @ViewBuilder
    private func transactionsBlock(_ transactions: [Transaction]) -> some View {
        GroupTitle("Transactions de la période")
            .padding(.top, 4)

        if transactions.isEmpty {
            Text("Aucune transaction sur cette période.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            ReportTable(
                columns: ["Date", "Bénéficiaire", "Catégorie", "Compte", "Montant"],
                rows: transactions.map { transaction in
                    ReportRow(id: transaction.id.uuidString, cells: [
                        ReportCell(text: transaction.date.formatted(.dateTime.day().month(.abbreviated))),
                        ReportCell(text: payeeName(transaction), isAmount: false),
                        ReportCell(
                            text: transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "—",
                            isAmount: false
                        ),
                        ReportCell(
                            text: accountsController.getAccount(id: transaction.accountID)?.name ?? "—",
                            color: .secondary,
                            isAmount: false
                        ),
                        ReportCell(text: money(abs(transaction.signedAmount)))
                    ])
                }
            )
        }
    }

    private func payeeName(_ transaction: Transaction) -> String {
        if let payeeID = transaction.payeeID, let payee = payeesController.getPayee(id: payeeID) {
            return payee.name
        }
        if let memo = transaction.memo, !memo.isEmpty {
            return memo
        }
        return "—"
    }

    private func statusItems(_ transactions: [Transaction], spent: Decimal) -> [String] {
        guard !transactions.isEmpty else { return ["Aucune transaction"] }
        let count = transactions.count
        return [
            "\(count) transaction\(count > 1 ? "s" : "")",
            appSettings.hideAmounts ? "Moyenne masquée" : "Moyenne : \(money(spent / Decimal(count)))"
        ]
    }

    // MARK: - Inspecteur

    private func inspectorContent(transactions: [Transaction], spent: Decimal) -> some View {
        InspectorContainer {
            InspectorHeader(title: current.name, caption: current.period.displayName)

            InspectorSection(title: "Catégories couvertes") {
                let shares = categoryShares(transactions)
                if shares.isEmpty {
                    Text("Aucune catégorie")
                        .foregroundStyle(.secondary)
                }
                ForEach(shares, id: \.id) { share in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(share.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(money(share.amount))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }
                        ProgressView(value: fraction(share.amount, of: spent))
                            .progressViewStyle(.linear)
                    }
                }
            }

            InspectorSection {
                InspectorRow("Période", value: current.period.displayName)
                InspectorRow("Début", value: current.anchorDate.formatted(.dateTime.day().month(.wide).year()))
                InspectorRow("Montant", value: money(versions.first?.amount ?? current.currentVersion?.amount ?? 0))
                InspectorRow("Comptes", value: "Tous sauf « hors budget »")
            }

            InspectorSection(title: "Historique des montants") {
                ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(money(version.amount))
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .monospacedDigit()
                                .privacyBlur(hidden: appSettings.hideAmounts)
                            Text("Depuis le \(version.effectiveFrom.formatted(.dateTime.day().month(.wide).year()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let note = version.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if index == 0 {
                            Text("En vigueur")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task {
                                    await budgetsController.deleteVersion(id: version.id)
                                    await loadVersions()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Supprimer ce montant de l'historique")
                        }
                    }
                }

                Button("Ajuster le montant…") { showAdjustSheet = true }
            }

            if let note = current.note, !note.isEmpty {
                InspectorSection(title: "Note") {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            InspectorSection {
                HStack {
                    Button("Modifier…") { showEditForm = true }
                    Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                }
            }
        }
    }

    /// Dépenses de la période par catégorie du budget, les plus élevées d'abord
    private func categoryShares(_ transactions: [Transaction]) -> [(id: UUID, name: String, amount: Decimal)] {
        var totals: [UUID: Decimal] = [:]
        for transaction in transactions {
            if let categoryID = transaction.categoryID {
                totals[categoryID, default: 0] += abs(transaction.signedAmount)
            }
        }
        return current.categoryIDs
            .compactMap { id in
                categoriesController.getCategory(id: id).map { (id: id, name: $0.name, amount: totals[id] ?? 0) }
            }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - Helpers

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func fraction(_ amount: Decimal, of maximum: Decimal) -> Double {
        guard maximum > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: amount / maximum).doubleValue, 0), 1)
    }

    /// « 1 oct. – 31 oct. 2026 » (la fin de fenêtre est exclusive)
    private func periodLabel(_ window: Window) -> String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        let start = window.start.formatted(.dateTime.day().month(.abbreviated))
        let end = lastDay.formatted(.dateTime.day().month(.abbreviated).year())
        return start == lastDay.formatted(.dateTime.day().month(.abbreviated)) ? end : "\(start) – \(end)"
    }

    /// Étiquette courte d'une période pour l'axe du graphique
    private func shortLabel(_ window: Window) -> String {
        switch current.period {
        case .monthly, .everyTwoMonths, .quarterly, .semiAnnual:
            return window.start.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        default:
            return window.start.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    // MARK: - Adjust Sheet

    private var adjustSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ajuster le budget")
                    .font(.headline)
                Spacer()
                Button { showAdjustSheet = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("Nouveau montant") {
                    HStack {
                        Text("Montant")
                        Spacer()
                        TextField("0,00", text: $adjustAmount)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    DatePicker("À partir du", selection: $adjustDate, displayedComponents: .date)
                    TextField("Note (optionnel)", text: $adjustNote)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Annuler") { showAdjustSheet = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Enregistrer") {
                    let dec = Decimal(string: adjustAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
                    Task {
                        await budgetsController.addVersion(
                            to: budget.id,
                            amount: dec,
                            effectiveFrom: adjustDate,
                            note: adjustNote.isEmpty ? nil : adjustNote
                        )
                        await loadVersions()
                        showAdjustSheet = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(adjustAmount.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 320)
    }

    private func loadVersions() async {
        versions = await budgetsController.fetchVersions(for: budget.id)
            .sorted { $0.effectiveFrom > $1.effectiveFrom }
    }
}

// MARK: - FlowLayout (simple tag cloud)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxY: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            maxY = y + lineHeight
        }
        return CGSize(width: width, height: maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
    }
}
