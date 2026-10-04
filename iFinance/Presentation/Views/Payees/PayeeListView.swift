import SwiftUI

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
    @EnvironmentObject var appSettings: AppSettings

    /// Navigation vers les transactions du bénéficiaire
    @Binding var selectedTab: MainView.SidebarItem

    @State private var showPayeeForm = false
    @State private var payeeToEdit: Payee?
    @State private var payeeToDelete: Payee?
    @State private var showDeleteConfirmation = false
    @State private var searchQuery = ""
    @State private var selection: Set<Payee.ID> = []
    @State private var sortOrder = [KeyPathComparator(\PayeeTableRow.name, comparator: .localizedStandard)]
    @AppStorage("showPayeeInspector") private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            if payeesController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tableRows.isEmpty {
                emptyPayeesView
            } else {
                payeeTable
                TableStatusBar(items: statusItems)
            }
        }
        .searchable(text: $searchQuery, prompt: "Rechercher un bénéficiaire")
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 280, max: 380)
        }
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
            }
        } primaryAction: { items in
            // Double-clic : transactions du bénéficiaire
            if let id = items.first, let payee = payeesController.getPayee(id: id) {
                showTransactions(for: payee)
            }
        }
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
