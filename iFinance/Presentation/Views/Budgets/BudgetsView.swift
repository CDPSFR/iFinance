import SwiftUI

// MARK: - Ligne de tableau

/// Budget enrichi de sa consommation sur la période en cours, pour l'affichage et le tri
struct BudgetTableRow: Identifiable {
    let id: UUID
    let name: String
    let periodName: String
    let amount: Decimal
    let spent: Decimal
    /// Échéances récurrentes attendues d'ici la fin de la période, non validées
    let committed: Decimal

    var remaining: Decimal { amount - spent }
    var isOverBudget: Bool { spent > amount }
    /// Dépensé + engagé : ce que la période coûtera si les échéances tombent comme prévu
    var projected: Decimal { spent + committed }
    /// Pas encore dépassé, mais le sera avec les échéances à venir
    var willExceed: Bool { !isOverBudget && projected > amount }

    var progress: Double {
        guard amount > 0 else { return 0 }
        return min(1.0, Double(truncating: NSDecimalNumber(decimal: spent / amount)))
    }
}

// MARK: - Liste des budgets

struct BudgetsView: View {
    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    @State private var showForm = false
    @State private var budgetToEdit: Budget? = nil
    @State private var budgetToDelete: Budget? = nil
    @State private var showDeleteConfirmation = false
    @State private var budgetToOpen: Budget? = nil
    @State private var showAnnualBudget = false
    @State private var searchText = ""
    @State private var selection: Set<Budget.ID> = []
    @State private var sortOrder = [KeyPathComparator(\BudgetTableRow.name, comparator: .localizedStandard)]
    @AppStorage("showBudgetInspector") private var showInspector = true

    private var filtered: [Budget] {
        guard !searchText.isEmpty else { return budgetsController.budgets }
        return budgetsController.budgets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if tableRows.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summaryHeader
                Divider()
                // L'inspecteur se loge sous l'en-tête
                SidePanelLayout(isPresented: $showInspector) {
                    budgetTable
                    TableStatusBar(items: statusItems)
                } panel: {
                    inspectorContent
                }
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher un budget")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAnnualBudget = true
                } label: {
                    Label("Budget annuel", systemImage: "calendar")
                }
                .help("Afficher le budget annuel, mois par mois")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help("Afficher ou masquer l'inspecteur")
            }
        }
        .navigationDestination(item: $budgetToOpen) { budget in
            BudgetDetailView(budget: budget)
        }
        .navigationDestination(isPresented: $showAnnualBudget) {
            AnnualBudgetView()
        }
        .task {
            await reload()
        }
        .sheet(isPresented: $showForm) {
            BudgetFormView(isPresented: $showForm)
        }
        .sheet(item: $budgetToEdit) { budget in
            BudgetFormView(
                isPresented: Binding(
                    get: { budgetToEdit != nil },
                    set: { if !$0 { budgetToEdit = nil } }
                ),
                budgetToEdit: budget
            )
        }
        .alert("Supprimer le budget ?", isPresented: $showDeleteConfirmation, presenting: budgetToDelete) { budget in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await budgetsController.deleteBudget(id: budget.id)
                    selection.remove(budget.id)
                }
            }
        } message: { budget in
            Text("Le budget « \(budget.name) » et son historique de montants seront supprimés. Les transactions ne sont pas modifiées.")
        }
        .onChange(of: showForm) { _, isShowing in
            if !isShowing {
                Task { await reload() }
            }
        }
        .onChange(of: budgetToEdit) { _, value in
            if value == nil {
                Task { await reload() }
            }
        }
    }

    // MARK: - Chiffres clés

    /// Totaux des budgets affichés, sur la période en cours de chacun
    private var summaryHeader: some View {
        let rows = tableRows
        let budgeted = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let spent = rows.reduce(Decimal(0)) { $0 + $1.spent }
        let remaining = budgeted - spent
        let isOver = spent > budgeted
        let ratio: Double = budgeted > 0
            ? min(1.0, Double(truncating: NSDecimalNumber(decimal: spent / budgeted)))
            : 0
        let percent = budgeted > 0
            ? Int((Double(truncating: NSDecimalNumber(decimal: spent / budgeted)) * 100).rounded())
            : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 40) {
                summaryFigure("Budgété", amount: budgeted)
                summaryFigure("Dépensé", amount: spent)
                summaryFigure(
                    isOver ? "Dépassement" : "Reste",
                    amount: abs(remaining),
                    color: isOver ? .red : .green
                )
                Spacer(minLength: 0)
            }

            ProgressView(value: ratio)
                .progressViewStyle(.linear)
                .tint(isOver ? Color.red : Color.accentColor)

            Text("\(percent) % des budgets utilisés, sur la période en cours de chaque budget")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func summaryFigure(_ title: String, amount: Decimal, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(amount, format: .currency(code: currency))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Tableau

    private var budgetTable: some View {
        Table(tableRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Budget", value: \.name, comparator: .localizedStandard) { row in
                Text(row.name)
            }
            .width(min: 140, ideal: 220)

            TableColumn("Période", value: \.periodName) { row in
                Text(row.periodName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Progression", value: \.progress) { row in
                ProgressView(value: row.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(row.isOverBudget ? .red : .accentColor)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Budgété", value: \.amount) { row in
                amountText(row.amount)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Dépensé", value: \.spent) { row in
                amountText(row.spent)
            }
            .width(min: 90, ideal: 110)

            TableColumn("À venir", value: \.committed) { row in
                Text(row.committed == 0 ? "—" : "+" + row.committed.formatted(.currency(code: currency)))
                    .monospacedDigit()
                    .foregroundStyle(row.willExceed ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
                    .help(row.willExceed
                          ? "Les échéances récurrentes à venir feront dépasser ce budget"
                          : "Échéances récurrentes attendues d'ici la fin de la période, non validées")
            }
            .width(min: 80, ideal: 100)

            TableColumn("Reste", value: \.remaining) { row in
                amountText(row.remaining, color: row.isOverBudget ? .red : .primary)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: Budget.ID.self) { items in
            if items.count == 1, let id = items.first, let budget = budget(id: id) {
                Button {
                    budgetToOpen = budget
                } label: {
                    Label("Ouvrir le détail", systemImage: "chart.bar")
                }

                Button {
                    budgetToEdit = budget
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    budgetToDelete = budget
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
        } primaryAction: { items in
            // Double-clic : détail du budget
            if let id = items.first, let budget = budget(id: id) {
                budgetToOpen = budget
            }
        }
    }

    private func amountText(_ amount: Decimal, color: Color = .primary) -> some View {
        Text(amount, format: .currency(code: currency))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .privacyBlur(hidden: appSettings.hideAmounts)
    }

    // MARK: - Inspecteur

    private var selectedBudget: Budget? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return budget(id: id)
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let budget = selectedBudget {
            inspectorDetail(budget)
        } else {
            ContentUnavailableView(
                "Aucune sélection",
                systemImage: "sidebar.right",
                description: Text("Sélectionnez un budget pour afficher son détail.")
            )
        }
    }

    private func inspectorDetail(_ budget: Budget) -> some View {
        let amount = budget.currentVersion?.amount ?? 0
        let spent = budgetsController.spent(for: budget, transactions: transactionsController.allTransactions)
        let committed = committed(for: budget)
        let projected = spent + committed
        let remaining = amount - spent
        let isOver = spent > amount
        let window = budget.period.currentWindow(anchor: budget.anchorDate)
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        let note = budget.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let categories = budget.categoryIDs.map { categoriesController.getCategoryPath(for: $0) }.sorted()

        func money(_ value: Decimal) -> String {
            appSettings.hideAmounts ? "•••" : value.formatted(.currency(code: currency))
        }

        return InspectorContainer {
            InspectorHeader(
                title: budget.name,
                value: money(abs(remaining)),
                valueColor: isOver ? .red : .primary,
                caption: isOver ? "Dépassement sur la période" : "Reste sur la période"
            )

            InspectorSection {
                InspectorRow("Période", value: budget.period.displayName)
                InspectorRow("Du", value: window.start.formatted(date: .abbreviated, time: .omitted))
                InspectorRow("Au", value: lastDay.formatted(date: .abbreviated, time: .omitted))
                InspectorRow("Budgété", value: money(amount))
                InspectorRow("Dépensé", value: money(spent))
                if committed > 0 {
                    InspectorRow("À venir", value: "+" + money(committed))
                    InspectorRow("Projeté", value: money(projected))
                }
            }

            if committed > 0, projected > amount, spent <= amount {
                InspectorSection {
                    Label("Les échéances récurrentes à venir feront dépasser ce budget de \(money(projected - amount)).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            InspectorSection(title: "Catégories") {
                if categories.isEmpty {
                    Text("Aucune catégorie")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories, id: \.self) { path in
                        Text(path)
                    }
                }
            }

            if !note.isEmpty {
                InspectorSection(title: "Note") {
                    Text(note)
                        .textSelection(.enabled)
                }
            }

            InspectorSection {
                Button("Ouvrir le détail") {
                    budgetToOpen = budget
                }

                HStack(spacing: 8) {
                    Button("Modifier…") {
                        budgetToEdit = budget
                    }

                    Button("Supprimer…", role: .destructive) {
                        budgetToDelete = budget
                        showDeleteConfirmation = true
                    }
                }
            }
        }
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func budget(id: UUID) -> Budget? {
        budgetsController.budgets.first { $0.id == id }
    }

    private var tableRows: [BudgetTableRow] {
        let rows = filtered.map { budget in
            BudgetTableRow(
                id: budget.id,
                name: budget.name,
                periodName: budget.period.displayName,
                amount: budget.currentVersion?.amount ?? 0,
                spent: budgetsController.spent(for: budget, transactions: transactionsController.allTransactions),
                committed: committed(for: budget)
            )
        }
        return rows.sorted(using: sortOrder)
    }

    /// Échéances récurrentes en attente sur la période en cours du budget
    private func committed(for budget: Budget) -> Decimal {
        let window = budget.period.currentWindow(anchor: budget.anchorDate)
        return budgetsController.committed(for: budget, occurrences: recurringController.occurrences(until: window.end))
    }

    private var statusItems: [String] {
        let rows = tableRows
        let count = rows.count
        let over = rows.filter { $0.isOverBudget }.count
        var items = ["\(count) budget\(count > 1 ? "s" : "")"]
        if over > 0 {
            items.append("\(over) dépassé\(over > 1 ? "s" : "")")
        }
        let atRisk = rows.filter { $0.willExceed }.count
        if atRisk > 0 {
            items.append("\(atRisk) dépasser\(atRisk > 1 ? "ont" : "a") avec les échéances à venir")
        }
        return items
    }

    private func reload() async {
        if let bookID = booksController.currentBook?.id {
            await budgetsController.loadBudgets(for: bookID)
        }
    }

    // MARK: - État vide

    @ViewBuilder
    private var emptyStateView: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("Aucun budget", systemImage: "chart.pie")
            } description: {
                Text("Créez des budgets pour suivre vos dépenses par catégorie.")
            } actions: {
                Button("Créer un budget") {
                    showForm = true
                }
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }
}
