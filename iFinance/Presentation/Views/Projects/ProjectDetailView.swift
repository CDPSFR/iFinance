import SwiftUI
import Charts

/// Détail d'un projet : chiffres clés, dépenses par catégorie et par mois, transactions rattachées
struct ProjectDetailView: View {
    let project: Project

    @EnvironmentObject var projectsController: ProjectsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<Transaction.ID> = []
    @State private var showEditForm = false
    @State private var showPicker = false
    @State private var showDeleteConfirmation = false
    @AppStorage("showProjectInspector") private var showInspector = true

    struct MonthPoint: Identifiable {
        let date: Date
        let amount: Decimal

        var id: Date { date }
    }

    /// Projet à jour après une modification
    private var current: Project {
        projectsController.project(id: project.id) ?? project
    }

    var body: some View {
        let transactions = projectsController
            .transactions(of: project.id, in: transactionsController.allTransactions)
            .sorted { $0.date > $1.date }
        let spent = projectsController.spent(transactions)

        VStack(spacing: 0) {
            summaryHeader(transactions: transactions, spent: spent)
            Divider()

            // L'inspecteur se loge sous l'en-tête
            SidePanelLayout(isPresented: $showInspector) {
                if transactions.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune transaction", systemImage: "tray")
                    } description: {
                        Text("Rattachez des transactions à ce projet ici, ou depuis l'inspecteur de l'écran Transactions.")
                    } actions: {
                        Button("Ajouter des transactions…") { showPicker = true }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: NativeMetrics.groupSpacing) {
                        ReportBarsBlock(title: "Dépenses par catégorie", items: categoryBreakdown(transactions), money: money)
                            .frame(maxWidth: .infinity)
                        monthsBlock(transactions)
                    }
                    .padding(NativeMetrics.pagePadding)
                    .fixedSize(horizontal: false, vertical: true)

                    Divider()
                    table(transactions)
                        .frame(maxHeight: .infinity)
                    TableStatusBar(items: [
                        "\(transactions.count) transaction\(transactions.count > 1 ? "s" : "")",
                        "Clic droit pour retirer une transaction du projet"
                    ])
                }
            } panel: {
                inspectorContent
            }
        }
        // Contenu ferré en haut : l'en-tête ne descend pas quand il y a peu de transactions
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
        .navigationTitle(current.name)
        .navigationSubtitle(current.isCompleted ? "Projet terminé" : "Projet en cours")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Ajouter des transactions…") { showPicker = true }
                    .help("Rattacher des transactions existantes à ce projet")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help("Afficher ou masquer l'inspecteur")
            }
        }
        .sheet(isPresented: $showEditForm) {
            ProjectFormView(isPresented: $showEditForm, projectToEdit: current)
        }
        .sheet(isPresented: $showPicker) {
            ProjectTransactionPicker(isPresented: $showPicker, project: current)
        }
        .alert("Supprimer le projet ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await projectsController.deleteProject(id: project.id)
                    await reloadTransactions()
                    dismiss()
                }
            }
        } message: {
            Text("Le projet « \(current.name) » sera supprimé. Ses transactions sont conservées et simplement détachées du projet.")
        }
    }

    // MARK: - Grands chiffres

    private func summaryHeader(transactions: [Transaction], spent: Decimal) -> some View {
        let budget = current.budget
        let remaining = (budget ?? 0) - spent
        let isOver = budget != nil && spent > (budget ?? 0)
        let ratio = fraction(spent, of: budget ?? 0)
        let categoryCount = Set(transactions.compactMap { $0.categoryID }).count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 40) {
                figure("Enveloppe", budget.map { money($0) } ?? "—", detail: budget == nil ? "Aucune enveloppe" : "Montant prévu")
                figure(
                    "Dépensé",
                    money(spent),
                    detail: budget == nil ? "Au total" : "\(Int((ratio * 100).rounded())) % de l'enveloppe"
                )
                figure(
                    isOver ? "Dépassement" : "Reste",
                    budget == nil ? "—" : money(abs(remaining)),
                    color: budget == nil ? .primary : (isOver ? .red : .green),
                    detail: current.isCompleted ? "Projet terminé" : "À dépenser"
                )
                figure(
                    "Transactions",
                    "\(transactions.count)",
                    detail: "Sur \(categoryCount) catégorie\(categoryCount > 1 ? "s" : "")",
                    isAmount: false
                )
                Spacer(minLength: 0)
            }

            if budget != nil {
                ProgressView(value: ratio)
                    .progressViewStyle(.linear)
                    .tint(isOver ? Color.red : Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func figure(_ title: String, _ value: String, color: Color = .primary, detail: String, isAmount: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: isAmount && appSettings.hideAmounts)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Graphiques

    /// Dépense nette par catégorie racine, limitée aux six premières
    private func categoryBreakdown(_ transactions: [Transaction]) -> [ReportBreakdownItem] {
        let uncategorizedID = UUID()
        var totals: [UUID: (name: String, count: Int, amount: Decimal)] = [:]

        for transaction in transactions where transaction.type != .transfer {
            let category = transaction.categoryID.flatMap { categoriesController.getCategory(id: $0) }
            let root = category.flatMap { $0.parentID.flatMap { categoriesController.getCategory(id: $0) } ?? $0 }
            let key = root?.id ?? uncategorizedID
            var entry = totals[key] ?? (root?.name ?? "Sans catégorie", 0, 0)
            entry.count += 1
            entry.amount -= transaction.signedAmount
            totals[key] = entry
        }

        let entries = totals
            .filter { $0.value.amount > 0 }
            .map { (id: $0.key, name: $0.value.name, count: $0.value.count, amount: $0.value.amount) }
        return Array([ReportBreakdownItem].breakdown(entries).prefix(6))
    }

    private func monthsBlock(_ transactions: [Transaction]) -> some View {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions.filter { $0.type != .transfer }) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date)) ?? transaction.date
        }
        let points = grouped
            .map { MonthPoint(date: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 - $1.signedAmount }) }
            .sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("Dépenses par mois")

            Chart(points) { point in
                BarMark(
                    x: .value("Mois", point.date, unit: .month),
                    y: .value("Montant", NSDecimalNumber(decimal: point.amount).doubleValue)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
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

    // MARK: - Transactions

    private func table(_ transactions: [Transaction]) -> some View {
        Table(transactions, selection: $selection) {
            TableColumn("Date") { transaction in
                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                    .foregroundStyle(.secondary)
            }
            .width(100)

            TableColumn("Bénéficiaire") { transaction in
                Text(payeeName(transaction))
            }

            TableColumn("Catégorie") { transaction in
                Text(transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "—")
            }

            TableColumn("Compte") { transaction in
                Text(accountsController.getAccount(id: transaction.accountID)?.name ?? "—")
                    .foregroundStyle(.secondary)
            }

            TableColumn("Montant") { transaction in
                Text(money(transaction.signedAmount))
                    .foregroundStyle(transaction.signedAmount > 0 ? Color.green : Color.primary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .width(120)
        }
        .contextMenu(forSelectionType: Transaction.ID.self) { ids in
            if !ids.isEmpty {
                Button(ids.count > 1 ? "Retirer \(ids.count) transactions du projet" : "Retirer du projet") {
                    Task { await detach(ids, from: transactions) }
                }
            }
        }
    }

    private func payeeName(_ transaction: Transaction) -> String {
        if let payeeID = transaction.payeeID, let payee = payeesController.getPayee(id: payeeID) {
            return payee.name
        }
        if let memo = transaction.memo, !memo.isEmpty {
            return memo
        }
        return transaction.type.displayName
    }

    private func detach(_ ids: Set<Transaction.ID>, from transactions: [Transaction]) async {
        for transaction in transactions where ids.contains(transaction.id) {
            var updated = transaction
            updated.projectID = nil
            await transactionsController.updateTransaction(updated)
        }
        selection = []
        await reloadTransactions()
    }

    private func reloadTransactions() async {
        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
    }

    // MARK: - Inspecteur

    private var inspectorContent: some View {
        let format = Date.FormatStyle.dateTime.day().month(.wide).year()

        return InspectorContainer {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: current.displayColor))
                    .frame(width: 12, height: 12)
                Text(current.name)
                    .font(.headline)
            }

            InspectorSection {
                InspectorRow("État", value: current.isCompleted ? "Terminé" : "En cours")
                InspectorRow("Début", value: current.startDate?.formatted(format) ?? "—")
                InspectorRow("Fin", value: current.endDate?.formatted(format) ?? "—")
                InspectorRow("Enveloppe", value: current.budget.map { money($0) } ?? "Aucune")
            }

            InspectorSection(title: "Note") {
                Text(current.note ?? "Aucune note")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            InspectorSection {
                Button(current.isCompleted ? "Rouvrir le projet" : "Marquer comme terminé") {
                    var updated = current
                    updated.isCompleted.toggle()
                    Task { await projectsController.updateProject(updated) }
                }

                HStack {
                    Button("Modifier…") { showEditForm = true }
                    Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                }
            }
        }
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
}

// MARK: - Sélection de transactions à rattacher

/// Feuille de sélection multiple : transactions sans projet, à rattacher au projet
struct ProjectTransactionPicker: View {
    @Binding var isPresented: Bool
    let project: Project

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    @State private var selection: Set<Transaction.ID> = []
    @State private var searchText = ""
    @State private var onlyProjectPeriod = true

    private static let rowLimit = 500

    var body: some View {
        let candidates = self.candidates

        VStack(spacing: 0) {
            SheetHeader(title: "Ajouter des transactions", subtitle: "Projet « \(project.name) »")

            HStack(spacing: 12) {
                TextField("Rechercher un bénéficiaire, une catégorie ou une note", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if project.startDate != nil || project.endDate != nil {
                    Toggle("Dates du projet uniquement", isOn: $onlyProjectPeriod)
                        .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            Table(candidates, selection: $selection) {
                TableColumn("Date") { transaction in
                    Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(.secondary)
                }
                .width(100)

                TableColumn("Bénéficiaire") { transaction in
                    Text(label(transaction))
                }

                TableColumn("Catégorie") { transaction in
                    Text(transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "—")
                }

                TableColumn("Compte") { transaction in
                    Text(accountsController.getAccount(id: transaction.accountID)?.name ?? "—")
                        .foregroundStyle(.secondary)
                }

                TableColumn("Montant") { transaction in
                    Text(transaction.signedAmount.formatted(.currency(code: booksController.currentBook?.currency ?? "EUR")))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .width(110)
            }

            SheetFooter {
                Text(candidates.count >= Self.rowLimit
                     ? "Les \(Self.rowLimit) transactions les plus récentes sans projet. Affinez avec la recherche."
                     : "\(candidates.count) transaction\(candidates.count > 1 ? "s" : "") sans projet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } actions: {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(selection.isEmpty ? "Ajouter" : "Ajouter \(selection.count)") {
                    attach(candidates)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .frame(width: 760, height: 520)
        .sheetBackground()
    }

    /// Transactions sans projet, hors transferts, les plus récentes d'abord
    private var candidates: [Transaction] {
        let calendar = Calendar.current
        let start = project.startDate.map { calendar.startOfDay(for: $0) }
        let end = project.endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        let query = searchText.trimmingCharacters(in: .whitespaces)

        let filtered = transactionsController.allTransactions.filter { transaction in
            guard transaction.projectID == nil, transaction.type != .transfer, transaction.status != .skipped else { return false }
            if onlyProjectPeriod {
                if let start, transaction.date < start { return false }
                if let end, transaction.date >= end { return false }
            }
            guard !query.isEmpty else { return true }
            let category = transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? ""
            return label(transaction).localizedCaseInsensitiveContains(query)
                || category.localizedCaseInsensitiveContains(query)
                || (transaction.memo ?? "").localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.sorted { $0.date > $1.date }.prefix(Self.rowLimit))
    }

    private func label(_ transaction: Transaction) -> String {
        if let payeeID = transaction.payeeID, let payee = payeesController.getPayee(id: payeeID) {
            return payee.name
        }
        if let memo = transaction.memo, !memo.isEmpty {
            return memo
        }
        return transaction.type.displayName
    }

    private func attach(_ candidates: [Transaction]) {
        let chosen = candidates.filter { selection.contains($0.id) }
        Task {
            for transaction in chosen {
                var updated = transaction
                updated.projectID = project.id
                await transactionsController.updateTransaction(updated)
            }
            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
            isPresented = false
        }
    }
}
