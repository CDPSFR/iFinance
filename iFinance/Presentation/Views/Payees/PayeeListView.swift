import SwiftUI
import Charts

// MARK: - Ligne de tableau

/// Bénéficiaire enrichi de son activité, pour l'affichage et le tri dans le tableau
struct PayeeTableRow: Identifiable {
    let id: UUID
    let name: String
    let categoryName: String
    let categoryColor: Color?
    let location: String
    let count: Int
    let total: Decimal
    let lastDate: Date?

    var lastDateForSort: Date {
        lastDate ?? .distantPast
    }
}

// MARK: - Liste des bénéficiaires

struct PayeeListView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    /// Navigation vers les transactions du bénéficiaire
    @Binding var selectedTab: MainView.SidebarItem

    @State private var showPayeeForm = false
    @State private var payeeToEdit: Payee?
    @State private var payeeToDelete: Payee?
    @State private var showDeleteConfirmation = false
    /// Bénéficiaires d'une suppression multiple (clic droit sur plusieurs lignes sélectionnées)
    @State private var payeesToDelete: [Payee] = []
    @State private var showBulkDeleteConfirmation = false
    @State private var searchQuery = ""
    @State private var selection: Set<Payee.ID> = []
    @State private var sortOrder = [KeyPathComparator(\PayeeTableRow.name, comparator: .localizedStandard)]
    @AppStorage("showPayeeInspector") private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            if !payeesController.isLoading && tableRows.isEmpty {
                // Liste vide : pas de panneau latéral, le message occupe toute la page et s'y centre
                emptyPayeesView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // L'inspecteur se loge sous l'en-tête de la page
                SidePanelLayout(isPresented: $showInspector) {
                    if payeesController.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        payeeTable
                        TableStatusBar(items: statusItems)
                    }
                } panel: {
                    inspectorContent
                }
            }
        }
        .searchable(text: $searchQuery, prompt: "Rechercher un bénéficiaire")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help("Afficher ou masquer l'inspecteur")
            }
        }
        .sheet(isPresented: $showPayeeForm) {
            PayeeFormView(isPresented: $showPayeeForm)
        }
        .sheet(item: $payeeToEdit) { payee in
            PayeeFormView(
                isPresented: Binding(
                    get: { payeeToEdit != nil },
                    set: { if !$0 { payeeToEdit = nil } }
                ),
                payeeToEdit: payee
            )
        }
        .alert("Supprimer le bénéficiaire ?", isPresented: $showDeleteConfirmation, presenting: payeeToDelete) { payee in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await payeesController.deletePayee(id: payee.id)
                    selection.remove(payee.id)
                }
            }
        } message: { payee in
            Text("Êtes-vous sûr de vouloir supprimer \"\(payee.name)\" ? Les transactions associées ne seront pas supprimées mais n'auront plus de bénéficiaire.")
        }
        .alert(
            "Supprimer \(payeesToDelete.count) bénéficiaires ?",
            isPresented: $showBulkDeleteConfirmation
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                let payees = payeesToDelete
                Task { await deletePayees(payees) }
            }
        } message: {
            Text(bulkDeleteMessage)
        }
        .task {
            if let bookID = bookController.currentBook?.id {
                await payeesController.loadPayees(for: bookID)
                await categoriesController.loadCategories(for: bookID)
            }
        }
        .onChange(of: bookController.currentBook?.id) { _, newValue in
            if let bookID = newValue {
                selection.removeAll()
                Task {
                    await payeesController.loadPayees(for: bookID)
                    await categoriesController.loadCategories(for: bookID)
                }
            }
        }
    }

    // MARK: - Tableau

    private var payeeTable: some View {
        Table(tableRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Nom", value: \.name, comparator: .localizedStandard) { row in
                Text(row.name)
            }
            .width(min: 160, ideal: 240)

            TableColumn("Catégorie par défaut", value: \.categoryName, comparator: .localizedStandard) { row in
                if row.categoryName.isEmpty {
                    Text("—")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        if let color = row.categoryColor {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                        }
                        Text(row.categoryName)
                    }
                }
            }
            .width(min: 140, ideal: 220)

            TableColumn("Opérations", value: \.count) { row in
                Text("\(row.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Total", value: \.total) { row in
                Text(row.total, format: .currency(code: currency))
                    .monospacedDigit()
                    .foregroundStyle(row.total > 0 ? Color.green : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Dernière opération", value: \.lastDateForSort) { row in
                if let date = row.lastDate {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 140)
        }
        .contextMenu(forSelectionType: Payee.ID.self) { items in
            if items.count == 1, let id = items.first, let payee = payeesController.getPayee(id: id) {
                Button {
                    showTransactions(for: payee)
                } label: {
                    Label("Afficher les transactions", systemImage: "list.bullet")
                }

                Button {
                    payeeToEdit = payee
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    payeeToDelete = payee
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } else if items.count > 1 {
                // Sélection multiple (⌘-clic ou ⇧-clic) : suppression groupée
                Button(role: .destructive) {
                    payeesToDelete = items.compactMap { payeesController.getPayee(id: $0) }
                    showBulkDeleteConfirmation = !payeesToDelete.isEmpty
                } label: {
                    Label("Supprimer \(items.count) bénéficiaires…", systemImage: "trash")
                }
            }
        } primaryAction: { items in
            // Double-clic : transactions du bénéficiaire
            if let id = items.first, let payee = payeesController.getPayee(id: id) {
                showTransactions(for: payee)
            }
        }
    }

    // MARK: - Suppression groupée

    /// Message de confirmation : nombre de transactions qui perdront leur bénéficiaire
    private var bulkDeleteMessage: String {
        let ids = Set(payeesToDelete.map { $0.id })
        let count = transactionsController.allTransactions
            .filter { $0.payeeID.map { ids.contains($0) } ?? false }
            .count
        let transactions = count == 0
            ? "Aucune transaction ne leur est associée."
            : "\(count) transaction\(count > 1 ? "s" : "") ne sera\(count > 1 ? "ont" : "") pas supprimée\(count > 1 ? "s" : ""), mais n'aura\(count > 1 ? "ont" : "") plus de bénéficiaire."
        return "\(transactions) Cette action est irréversible."
    }

    private func deletePayees(_ payees: [Payee]) async {
        for payee in payees {
            await payeesController.deletePayee(id: payee.id)
            selection.remove(payee.id)
        }
        payeesToDelete = []
        // Les transactions concernées doivent refléter la perte de leur bénéficiaire
        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
    }

    // MARK: - Inspecteur

    private var selectedPayee: Payee? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return payeesController.getPayee(id: id)
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let payee = selectedPayee {
            inspectorDetail(payee)
        } else {
            ContentUnavailableView(
                "Aucune sélection",
                systemImage: "sidebar.right",
                description: Text("Sélectionnez un bénéficiaire pour afficher son détail.")
            )
        }
    }

    private func inspectorDetail(_ payee: Payee) -> some View {
        let stats = payeeStats()[payee.id] ?? PayeeStats()
        let categoryPath = payee.defaultCategoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "—"
        let totalText = appSettings.hideAmounts ? "•••" : stats.total.formatted(.currency(code: currency))
        let averageText: String = {
            guard stats.count > 0, !appSettings.hideAmounts else { return "—" }
            let average = abs(stats.total) / Decimal(stats.count)
            return average.formatted(.currency(code: currency))
        }()
        let notes = payee.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Sens dominant du bénéficiaire : revenus s'il rapporte plus qu'il ne coûte, dépenses sinon
        let history = monthlyHistory(for: payee, isIncome: stats.total > 0)
        let chartColor = payee.defaultCategoryID
            .flatMap { categoriesController.getCategory(id: $0) }
            .map { Color(hex: $0.displayColor) } ?? Color.accentColor

        return InspectorContainer {
            InspectorHeader(
                title: payee.name,
                caption: "\(stats.count) opération\(stats.count > 1 ? "s" : "")"
            )

            InspectorSection {
                InspectorRow("Catégorie", value: categoryPath)
                InspectorRow("Lieu", value: payee.locationDisplay ?? "—")
                InspectorRow("Total", value: totalText)
                InspectorRow("Moyenne", value: averageText)
                InspectorRow(
                    "Dernière",
                    value: stats.lastDate?.formatted(date: .long, time: .omitted) ?? "—"
                )
            }

            InspectorSection(title: "6 derniers mois") {
                Chart(history, id: \.month) { item in
                    BarMark(
                        x: .value("Mois", item.month, unit: .month),
                        y: .value("Montant", item.amount)
                    )
                    .foregroundStyle(chartColor)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 96)
                .privacyBlur(hidden: appSettings.hideAmounts)
            }

            InspectorSection(title: "Note") {
                Text(notes.isEmpty ? "Aucune note" : notes)
                    .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            InspectorSection {
                Button("Afficher les transactions") {
                    showTransactions(for: payee)
                }

                HStack(spacing: 8) {
                    Button("Modifier…") {
                        payeeToEdit = payee
                    }

                    Button("Supprimer…", role: .destructive) {
                        payeeToDelete = payee
                        showDeleteConfirmation = true
                    }
                }
            }
        }
    }

    // MARK: - Données

    private var currency: String {
        bookController.currentBook?.currency ?? "EUR"
    }

    private var filteredPayees: [Payee] {
        if searchQuery.isEmpty {
            return payeesController.payees
        }

        return payeesController.payees.filter { payee in
            payee.name.localizedCaseInsensitiveContains(searchQuery) ||
            payee.city?.localizedCaseInsensitiveContains(searchQuery) == true
        }
    }

    private var tableRows: [PayeeTableRow] {
        let stats = payeeStats()

        let rows = filteredPayees.map { payee -> PayeeTableRow in
            let entry = stats[payee.id] ?? PayeeStats()
            let category = payee.defaultCategoryID.flatMap { categoriesController.getCategory(id: $0) }

            return PayeeTableRow(
                id: payee.id,
                name: payee.name,
                categoryName: category.map { categoriesController.getCategoryPath(for: $0.id) } ?? "",
                categoryColor: category.map { Color(hex: $0.displayColor) },
                location: payee.locationDisplay ?? "",
                count: entry.count,
                total: entry.total,
                lastDate: entry.lastDate
            )
        }

        return rows.sorted(using: sortOrder)
    }

    private var statusItems: [String] {
        let shown = filteredPayees.count
        let all = payeesController.payees.count
        if shown == all {
            return ["\(all) bénéficiaire\(all > 1 ? "s" : "")"]
        }
        return ["\(shown) sur \(all) bénéficiaires"]
    }

    /// Activité par bénéficiaire, calculée sur les transactions chargées
    private func payeeStats() -> [UUID: PayeeStats] {
        var stats: [UUID: PayeeStats] = [:]

        for transaction in transactionsController.allTransactions where transaction.status != .skipped {
            guard let payeeID = transaction.payeeID else { continue }
            var entry = stats[payeeID, default: PayeeStats()]
            entry.count += 1
            entry.total += transaction.signedAmount
            if entry.lastDate.map({ transaction.date > $0 }) ?? true {
                entry.lastDate = transaction.date
            }
            stats[payeeID] = entry
        }

        return stats
    }

    /// Montants des six derniers mois (mois en cours inclus) pour un bénéficiaire, dans son sens dominant.
    /// Un seul passage sur les transactions ; les débuts de mois sont calculés une fois.
    private func monthlyHistory(for payee: Payee, isIncome: Bool) -> [(month: Date, amount: Double)] {
        let calendar = Calendar.current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthStarts = (0..<6).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: currentMonth) }
        guard let firstMonth = monthStarts.first else { return [] }

        var totals = [Decimal](repeating: 0, count: monthStarts.count)
        for transaction in transactionsController.allTransactions
        where transaction.payeeID == payee.id && transaction.status != .skipped && transaction.date >= firstMonth {
            var index = monthStarts.count - 1
            while index > 0 && transaction.date < monthStarts[index] { index -= 1 }
            totals[index] += transaction.signedAmount
        }

        let sign: Decimal = isIncome ? 1 : -1
        return zip(monthStarts, totals).map { month, total in
            (month, max(0, NSDecimalNumber(decimal: total * sign).doubleValue))
        }
    }

    /// Filtre les transactions sur le bénéficiaire puis bascule sur la liste des transactions
    private func showTransactions(for payee: Payee) {
        var filters = transactionsController.filters
        filters.payeeID = payee.id
        transactionsController.updateFilters(filters)
        selectedTab = .allTransactions
    }

    // MARK: - État vide

    @ViewBuilder
    private var emptyPayeesView: some View {
        if searchQuery.isEmpty {
            ContentUnavailableView {
                Label("Aucun bénéficiaire", systemImage: "person.2")
            } description: {
                Text("Créez des bénéficiaires pour mieux organiser vos transactions.")
            } actions: {
                Button("Créer un bénéficiaire") {
                    showPayeeForm = true
                }
            }
        } else {
            ContentUnavailableView.search(text: searchQuery)
        }
    }
}
