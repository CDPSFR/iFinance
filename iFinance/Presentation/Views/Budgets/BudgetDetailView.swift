import SwiftUI

struct BudgetDetailView: View {
    let budget: Budget

    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    @State private var versions: [BudgetVersion] = []
    @State private var showEditForm = false
    @State private var showAdjustSheet = false
    @State private var adjustAmount: String = ""
    @State private var adjustNote: String = ""
    @State private var adjustDate: Date = Date()
    @State private var referenceDate: Date = Date()

    private var window: (start: Date, end: Date) {
        budget.period.currentWindow(anchor: budget.anchorDate, relativeTo: referenceDate)
    }
    private var isCurrentPeriod: Bool {
        let current = budget.period.currentWindow(anchor: budget.anchorDate)
        return window.start == current.start
    }

    /// Version active pour la période affichée
    private var versionForPeriod: BudgetVersion? {
        let calendar = Calendar.current
        let windowDay = calendar.startOfDay(for: window.start)
        return versions
            .filter { calendar.startOfDay(for: $0.effectiveFrom) <= windowDay }
            .sorted { $0.effectiveFrom > $1.effectiveFrom }
            .first
    }
    private var amount: Decimal { versionForPeriod?.amount ?? 0 }

    private var periodTransactions: [Transaction] {
        let categorySet = Set(budget.categoryIDs)
        return transactionsController.allTransactions
            .filter { tx in
                tx.date >= window.start
                && tx.date < window.end
                && tx.signedAmount < 0
                && tx.categoryID.map { categorySet.contains($0) } ?? false
                && tx.status != .skipped
            }
            .sorted { $0.date > $1.date }
    }

    private var spent: Decimal {
        periodTransactions.reduce(Decimal(0)) { $0 + abs($1.signedAmount) }
    }
    private var remaining: Decimal { amount - spent }
    private var progress: Double {
        guard amount > 0 else { return 0 }
        return min(1.0, Double(truncating: NSDecimalNumber(decimal: spent / amount)))
    }
    private var isOverBudget: Bool { spent > amount }

    private func goToPreviousPeriod() {
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: window.start)!
        referenceDate = prev
    }
    private func goToNextPeriod() {
        referenceDate = window.end
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(budget.name)
                    .font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    Button("Ajuster") { showAdjustSheet = true }
                        .buttonStyle(.bordered)
                    Button { showEditForm = true } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    periodCard
                    transactionList
                    versionHistory
                }
                .padding()
            }
        }
        .task { await loadVersions() }
        .sheet(isPresented: $showEditForm) {
            BudgetFormView(isPresented: $showEditForm, budgetToEdit: budget)
        }
        .sheet(isPresented: $showAdjustSheet) {
            adjustSheet
        }
        .pageBackground()
    }

    // MARK: - Period Card

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { goToPreviousPeriod() } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(window.start <= budget.anchorDate)

                Spacer()

                VStack(spacing: 2) {
                    Text(budget.period.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(window.start, format: .dateTime.day().month()) – \(window.end, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(isCurrentPeriod ? Color.accentColor : Color.secondary)
                }

                Spacer()

                Button { goToNextPeriod() } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCurrentPeriod ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isCurrentPeriod)
            }

            ProgressView(value: progress)
                .tint(isOverBudget ? Color.red : (progress > 0.8 ? Color.orange : Color.accentColor))

            HStack {
                VStack(alignment: .leading) {
                    Text("Dépensé")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(spent, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                        .font(.title3).fontWeight(.semibold)
                        .foregroundColor(isOverBudget ? .red : .primary)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Budget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(amount, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                        .font(.title3).fontWeight(.semibold)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
            }

            if isOverBudget {
                Label("Dépassé de \(spent - amount, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            } else {
                Text("\(remaining, format: .currency(code: booksController.currentBook?.currency ?? "EUR")) restants (\(Int(progress * 100))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }

            if !budget.categoryIDs.isEmpty {
                Divider()
                FlowLayout(spacing: 6) {
                    ForEach(budget.categoryIDs, id: \.self) { catID in
                        if let cat = categoriesController.getCategory(id: catID) {
                            Text(cat.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            if let note = budget.note, !note.isEmpty {
                Divider()
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardBackground(cornerRadius: 10)
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transactions")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if periodTransactions.isEmpty {
                Text("Aucune transaction sur cette période")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(periodTransactions.enumerated()), id: \.element.id) { idx, tx in
                        transactionRow(tx)
                        if idx < periodTransactions.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .cardBackground(cornerRadius: 10)
            }
        }
    }

    @ViewBuilder
    private func transactionRow(_ tx: Transaction) -> some View {
        let currency = booksController.currentBook?.currency ?? "EUR"
        HStack(spacing: 12) {
            // Icône catégorie
            if let catID = tx.categoryID,
               let cat = categoriesController.getCategory(id: catID),
               let icon = cat.icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.8)))
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.8)))
            }

            VStack(alignment: .leading, spacing: 2) {
                // Libellé : bénéficiaire > mémo > fallback
                if let payeeID = tx.payeeID,
                   let payee = payeesController.getPayee(id: payeeID) {
                    Text(payee.name).font(.body)
                } else if let memo = tx.memo, !memo.isEmpty {
                    Text(memo).font(.body)
                } else {
                    Text("Transaction").font(.body).foregroundColor(.secondary)
                }
                // Catégorie + date
                HStack(spacing: 6) {
                    if tx.categoryID != nil {
                        Text(categoriesController.getCategoryPath(for: tx.categoryID!))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("·").font(.caption).foregroundColor(.secondary)
                    }
                    Text(tx.date, format: .dateTime.day().month())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(abs(tx.amount), format: .currency(code: currency))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.red)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Version History

    private var versionHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Historique des montants")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(versions.enumerated()), id: \.element.id) { idx, v in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.amount, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                                .fontWeight(idx == 0 ? .semibold : .regular)
                                .privacyBlur(hidden: appSettings.hideAmounts)
                            if let note = v.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(v.effectiveFrom, format: .dateTime.day().month().year())
                            .font(.caption).foregroundColor(.secondary)
                        if idx != 0 {
                            Button {
                                Task { await budgetsController.deleteVersion(id: v.id) }
                            } label: {
                                Image(systemName: "trash").foregroundColor(.red).font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if idx < versions.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .cardBackground(cornerRadius: 10)
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
