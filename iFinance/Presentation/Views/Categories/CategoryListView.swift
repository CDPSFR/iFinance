import SwiftUI
import Charts

// MARK: - Ligne de tableau

/// Catégorie ou sous-catégorie enrichie de son activité, pour le tableau hiérarchique
struct CategoryTableRow: Identifiable {
    let id: UUID
    let category: Category
    let isParent: Bool
    let count: Int
    let monthTotal: Decimal
    let monthlyAverage: Decimal
    /// Part du total du mois (0...1)
    let share: Double
    var children: [CategoryTableRow] = []
}

// MARK: - Liste des catégories

struct CategoryListView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    /// Navigation vers les transactions de la catégorie
    @Binding var selectedTab: MainView.SidebarItem

    /// Famille affichée : dépenses ou revenus
    enum Kind: String, CaseIterable, Identifiable {
        case expense
        case income

        var id: String { rawValue }

        var title: String {
            switch self {
            case .expense: return "Dépenses"
            case .income: return "Revenus"
            }
        }
    }

    @State private var kind: Kind = .expense
    @State private var showCategoryForm = false
    @State private var categoryToEdit: Category?
    @State private var parentForNewCategory: UUID?
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirmation = false
    /// Catégories d'une suppression multiple (clic droit sur plusieurs lignes sélectionnées)
    @State private var categoriesToDelete: [Category] = []
    @State private var showBulkDeleteConfirmation = false
    @State private var searchQuery = ""
    @State private var selection: Set<UUID> = []
    @State private var expanded: Set<UUID> = []
    @AppStorage("showCategoryInspector") private var showInspector = true

    var body: some View {
        let roots = rootRows

        VStack(spacing: 0) {
            // L'inspecteur se loge sous l'en-tête de la page
            SidePanelLayout(isPresented: $showInspector) {
                if categoriesController.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if roots.isEmpty {
                    emptyCategoriesView
                } else {
                    categoryTable(roots)
                    TableStatusBar(items: statusItems(roots))
                }
            } panel: {
                inspectorContent(roots)
            }
        }
        .searchable(text: $searchQuery, prompt: "Rechercher une catégorie")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .help("Afficher les catégories de dépenses ou de revenus")

                Button {
                    toggleAll(roots)
                } label: {
                    Label("Tout déplier ou replier", systemImage: "chevron.up.chevron.down")
                }
                .help("Tout déplier ou replier")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help("Afficher ou masquer l'inspecteur")
            }
        }
        .sheet(isPresented: $showCategoryForm, onDismiss: { parentForNewCategory = nil }) {
            CategoryFormView(
                isPresented: $showCategoryForm,
                parentCategory: parentForNewCategory.flatMap { categoriesController.getCategory(id: $0) }
            )
        }
        .sheet(item: $categoryToEdit) { category in
            CategoryFormView(
                isPresented: Binding(
                    get: { categoryToEdit != nil },
                    set: { if !$0 { categoryToEdit = nil } }
                ),
                categoryToEdit: category
            )
        }
        .alert("Supprimer la catégorie ?", isPresented: $showDeleteConfirmation, presenting: categoryToDelete) { category in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await categoriesController.deleteCategory(id: category.id)
                    selection.remove(category.id)
                }
            }
        } message: { category in
            if categoriesController.hasSubcategories(category.id) {
                Text("Cette catégorie contient des sous-catégories. Elles seront également supprimées.")
            } else {
                Text("Cette action est irréversible.")
            }
        }
        .alert(
            "Supprimer \(categoriesToDelete.count) catégories ?",
            isPresented: $showBulkDeleteConfirmation
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                let categories = categoriesToDelete
                Task { await deleteCategories(categories) }
            }
        } message: {
            Text(bulkDeleteMessage)
        }
        .task {
            if let bookID = bookController.currentBook?.id {
                await categoriesController.loadCategories(for: bookID)
            }
        }
        .onChange(of: bookController.currentBook?.id) { _, newValue in
            if let bookID = newValue {
                selection.removeAll()
                expanded.removeAll()
                Task {
                    await categoriesController.loadCategories(for: bookID)
                }
            }
        }
        .onChange(of: kind) { _, _ in
            selection.removeAll()
        }
    }

    // MARK: - Tableau

    private func categoryTable(_ roots: [CategoryTableRow]) -> some View {
        Table(of: CategoryTableRow.self, selection: $selection) {
            TableColumn("Catégorie") { row in
                HStack(spacing: 7) {
                    if row.isParent {
                        Circle()
                            .fill(Color(hex: row.category.displayColor))
                            .frame(width: 9, height: 9)
                    }
                    Text(row.category.name)
                        .fontWeight(row.isParent ? .semibold : .regular)
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Transactions") { row in
                Text("\(row.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Ce mois") { row in
                Text(row.monthTotal, format: .currency(code: currency))
                    .monospacedDigit()
                    .fontWeight(row.isParent ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Moyenne mensuelle") { row in
                Text(row.monthlyAverage, format: .currency(code: currency))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .width(min: 120, ideal: 140)

            TableColumn(kind == .expense ? "Part des dépenses" : "Part des revenus") { row in
                ProgressView(value: row.share)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(Color(hex: row.category.displayColor))
            }
            .width(min: 120, ideal: 220)
        } rows: {
            ForEach(roots) { root in
                DisclosureTableRow(root, isExpanded: expansionBinding(for: root.id)) {
                    ForEach(root.children) { child in
                        TableRow(child)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { items in
            if items.count == 1, let id = items.first, let category = categoriesController.getCategory(id: id) {
                Button {
                    showTransactions(for: category)
                } label: {
                    Label("Afficher les transactions", systemImage: "list.bullet")
                }

                Button {
                    categoryToEdit = category
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }

                if category.isRoot {
                    Button {
                        parentForNewCategory = category.id
                        showCategoryForm = true
                    } label: {
                        Label("Nouvelle sous-catégorie", systemImage: "plus")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    categoryToDelete = category
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } else if items.count > 1 {
                // Sélection multiple (⌘-clic ou ⇧-clic) : suppression groupée
                Button(role: .destructive) {
                    categoriesToDelete = items.compactMap { categoriesController.getCategory(id: $0) }
                    showBulkDeleteConfirmation = !categoriesToDelete.isEmpty
                } label: {
                    Label("Supprimer \(items.count) catégories…", systemImage: "trash")
                }
            }
        } primaryAction: { items in
            // Double-clic : transactions de la catégorie
            if let id = items.first, let category = categoriesController.getCategory(id: id) {
                showTransactions(for: category)
            }
        }
    }

    /// Pendant une recherche, tout est déplié pour montrer les sous-catégories trouvées
    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { !searchQuery.isEmpty || expanded.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            }
        )
    }

    private func toggleAll(_ roots: [CategoryTableRow]) {
        let ids = Set(roots.map { $0.id })
        if ids.isSubset(of: expanded) {
            expanded.subtract(ids)
        } else {
            expanded.formUnion(ids)
        }
    }

    // MARK: - Inspecteur

    /// Message de confirmation : sous-catégories entraînées et transactions qui perdent leur catégorie
    private var bulkDeleteMessage: String {
        let selectedIDs = Set(categoriesToDelete.map { $0.id })
        // Sous-catégories non sélectionnées mais supprimées avec leur catégorie parente
        let extraChildren = categoriesToDelete
            .flatMap { categoriesController.getSubcategories(for: $0.id) }
            .filter { !selectedIDs.contains($0.id) }
        let allIDs = selectedIDs.union(extraChildren.map { $0.id })
        let transactionCount = transactionsController.allTransactions
            .filter { $0.categoryID.map { allIDs.contains($0) } ?? false }
            .count

        var parts: [String] = []
        if !extraChildren.isEmpty {
            parts.append("\(extraChildren.count) sous-catégorie\(extraChildren.count > 1 ? "s" : "") non sélectionnée\(extraChildren.count > 1 ? "s" : "") sera\(extraChildren.count > 1 ? "ont" : "") aussi supprimée\(extraChildren.count > 1 ? "s" : "").")
        }
        if transactionCount > 0 {
            parts.append("\(transactionCount) transaction\(transactionCount > 1 ? "s" : "") ne sera\(transactionCount > 1 ? "ont" : "") plus classée\(transactionCount > 1 ? "s" : "").")
        }
        parts.append("Cette action est irréversible.")
        return parts.joined(separator: " ")
    }

    /// Supprime les sous-catégories d'abord, puis les catégories principales
    private func deleteCategories(_ categories: [Category]) async {
        let ordered = categories.sorted { !$0.isRoot && $1.isRoot }
        for category in ordered {
            await categoriesController.deleteCategory(id: category.id)
            selection.remove(category.id)
        }
        categoriesToDelete = []
        // Les transactions concernées doivent refléter la perte de leur catégorie
        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
    }

    private func selectedRow(in roots: [CategoryTableRow]) -> CategoryTableRow? {
        guard selection.count == 1, let id = selection.first else { return nil }
        for root in roots {
            if root.id == id { return root }
            if let child = root.children.first(where: { $0.id == id }) { return child }
        }
        return nil
    }

    @ViewBuilder
    private func inspectorContent(_ roots: [CategoryTableRow]) -> some View {
        if let row = selectedRow(in: roots) {
            inspectorDetail(row)
        } else {
            ContentUnavailableView(
                "Aucune sélection",
                systemImage: "sidebar.right",
                description: Text("Sélectionnez une catégorie pour afficher son détail.")
            )
        }
    }

    private func inspectorDetail(_ row: CategoryTableRow) -> some View {
        let category = row.category
        let color = Color(hex: category.displayColor)
        let parent = category.parentID.flatMap { categoriesController.getCategory(id: $0) }
        let history = monthlyHistory(for: row)
        let description = category.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        func money(_ value: Decimal) -> String {
            appSettings.hideAmounts ? "•••" : value.formatted(.currency(code: currency))
        }

        return InspectorContainer {
            HStack(spacing: 10) {
                Image(systemName: category.displayIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.headline)
                    Text(row.isParent
                         ? "Catégorie · \(row.children.count) sous-catégorie\(row.children.count > 1 ? "s" : "")"
                         : "Sous-catégorie de \(parent?.name ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            InspectorSection {
                InspectorRow("Type", value: category.isIncome ? "Revenu" : "Dépense")
                InspectorRow("Parente", value: parent?.name ?? "Aucune")
                InspectorRow("Opérations", value: "\(row.count)")
                InspectorRow("Ce mois", value: money(row.monthTotal))
                InspectorRow("Moyenne", value: "\(money(row.monthlyAverage)) par mois")
            }

            if !description.isEmpty {
                InspectorSection(title: "Description") {
                    Text(description)
                        .textSelection(.enabled)
                }
            }

            InspectorSection(title: "6 derniers mois") {
                Chart(history, id: \.month) { item in
                    BarMark(
                        x: .value("Mois", item.month, unit: .month),
                        y: .value("Montant", item.amount)
                    )
                    .foregroundStyle(color)
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

            if row.isParent {
                InspectorSection(title: "Sous-catégories") {
                    if row.children.isEmpty {
                        Text("Aucune sous-catégorie")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(row.children) { child in
                            HStack {
                                Text(child.category.name)
                                Spacer()
                                Text(money(child.monthTotal))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button("Nouvelle sous-catégorie…") {
                        parentForNewCategory = category.id
                        showCategoryForm = true
                    }
                }
            }

            InspectorSection {
                Button("Afficher les transactions") {
                    showTransactions(for: category)
                }

                HStack(spacing: 8) {
                    Button("Modifier…") {
                        categoryToEdit = category
                    }

                    Button("Supprimer…", role: .destructive) {
                        categoryToDelete = category
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

    /// Activité d'une catégorie sur les transactions chargées
    private struct Activity {
        var count = 0
        var month: Decimal = 0                  // Mois en cours
        var year: Decimal = 0                   // 12 derniers mois, mois en cours inclus
        var perMonth: [Date: Decimal] = [:]     // Par début de mois, sur 12 mois
    }

    private var monthStart: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    /// Montants positifs dans la famille affichée : dépenses pour les dépenses, revenus pour les revenus
    private func activity() -> [UUID: Activity] {
        let calendar = Calendar.current
        let start = monthStart
        let yearStart = calendar.date(byAdding: .month, value: -11, to: start) ?? start
        let sign: Decimal = kind == .income ? 1 : -1
        var result: [UUID: Activity] = [:]

        for transaction in transactionsController.allTransactions where transaction.status != .skipped {
            guard let categoryID = transaction.categoryID else { continue }
            var entry = result[categoryID, default: Activity()]
            let value = transaction.signedAmount * sign

            entry.count += 1
            if transaction.date >= start {
                entry.month += value
            }
            if transaction.date >= yearStart {
                entry.year += value
                let key = calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date)) ?? start
                entry.perMonth[key, default: 0] += value
            }
            result[categoryID] = entry
        }

        return result
    }

    private func matchesSearch(_ category: Category) -> Bool {
        category.name.localizedCaseInsensitiveContains(searchQuery) ||
        category.description?.localizedCaseInsensitiveContains(searchQuery) == true
    }

    /// Catégories racines de la famille affichée, avec leurs sous-catégories et leur activité
    private var rootRows: [CategoryTableRow] {
        let stats = activity()
        let source = kind == .income ? categoriesController.incomeCategories : categoriesController.expenseCategories
        let roots = source
            .filter { $0.isRoot }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // Total du mois par catégorie racine (elle-même + toutes ses sous-catégories)
        func groupActivity(_ root: Category) -> Activity {
            let ids = [root.id] + categoriesController.getSubcategories(for: root.id).map { $0.id }
            var total = Activity()
            for id in ids {
                guard let entry = stats[id] else { continue }
                total.count += entry.count
                total.month += entry.month
                total.year += entry.year
            }
            return total
        }

        let groups = roots.map { ($0, groupActivity($0)) }
        let monthTotal = groups.reduce(Decimal(0)) { $0 + max($1.1.month, 0) }

        func share(_ amount: Decimal) -> Double {
            guard monthTotal > 0, amount > 0 else { return 0 }
            return min(1, Double(truncating: NSDecimalNumber(decimal: amount / monthTotal)))
        }

        var rows: [CategoryTableRow] = []

        for (root, group) in groups {
            let subcategories = categoriesController.getSubcategories(for: root.id)
            let rootMatches = searchQuery.isEmpty || matchesSearch(root)
            let visible = rootMatches ? subcategories : subcategories.filter { matchesSearch($0) }

            // Recherche : garder la catégorie si elle ou l'une de ses sous-catégories correspond
            guard rootMatches || !visible.isEmpty else { continue }

            let children = visible.map { subcategory -> CategoryTableRow in
                let entry = stats[subcategory.id] ?? Activity()
                return CategoryTableRow(
                    id: subcategory.id,
                    category: subcategory,
                    isParent: false,
                    count: entry.count,
                    monthTotal: entry.month,
                    monthlyAverage: entry.year / 12,
                    share: share(entry.month)
                )
            }

            rows.append(
                CategoryTableRow(
                    id: root.id,
                    category: root,
                    isParent: true,
                    count: group.count,
                    monthTotal: group.month,
                    monthlyAverage: group.year / 12,
                    share: share(group.month),
                    children: children
                )
            )
        }

        return rows
    }

    /// Totaux des six derniers mois pour la ligne (sous-catégories incluses pour une catégorie)
    private func monthlyHistory(for row: CategoryTableRow) -> [(month: Date, amount: Double)] {
        let calendar = Calendar.current
        let stats = activity()
        var ids = [row.id]
        if row.isParent {
            ids += categoriesController.getSubcategories(for: row.id).map { $0.id }
        }

        return (0..<6).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: monthStart) else { return nil }
            let total = ids.reduce(Decimal(0)) { $0 + (stats[$1]?.perMonth[month] ?? 0) }
            return (month, max(0, NSDecimalNumber(decimal: total).doubleValue))
        }
    }

    private func statusItems(_ roots: [CategoryTableRow]) -> [String] {
        let subcategories = roots.reduce(0) { $0 + $1.children.count }
        var items = [
            "\(roots.count) catégorie\(roots.count > 1 ? "s" : "") · \(subcategories) sous-catégorie\(subcategories > 1 ? "s" : "")"
        ]

        if !appSettings.hideAmounts {
            let total = roots.reduce(Decimal(0)) { $0 + $1.monthTotal }
            let label = kind == .expense ? "de dépenses ce mois" : "de revenus ce mois"
            items.append("\(total.formatted(.currency(code: currency))) \(label)")
        }
        return items
    }

    /// Filtre les transactions sur la catégorie puis bascule sur la liste des transactions
    private func showTransactions(for category: Category) {
        var filters = transactionsController.filters
        filters.categoryID = category.id
        transactionsController.updateFilters(filters)
        selectedTab = .allTransactions
    }

    // MARK: - État vide

    @ViewBuilder
    private var emptyCategoriesView: some View {
        if searchQuery.isEmpty {
            ContentUnavailableView {
                Label(kind == .expense ? "Aucune catégorie de dépenses" : "Aucune catégorie de revenus", systemImage: "tag")
            } description: {
                Text("Créez vos catégories pour organiser vos transactions.")
            } actions: {
                Button("Créer une catégorie") {
                    showCategoryForm = true
                }
            }
        } else {
            ContentUnavailableView.search(text: searchQuery)
        }
    }
}

/// Activité d'une catégorie calculée à partir des transactions chargées
struct CategoryStats {
    var count = 0
    var total: Decimal = 0          // Somme signée : < 0 dépenses, > 0 revenus

    static func + (lhs: CategoryStats, rhs: CategoryStats) -> CategoryStats {
        CategoryStats(count: lhs.count + rhs.count, total: lhs.total + rhs.total)
    }
}

// MARK: - Category Group View
struct CategoryGroupView: View {
    let parentCategory: Category
    let subcategories: [Category]
    let stats: [UUID: CategoryStats]
    let currency: String
    let onEdit: (Category) -> Void
    let onDelete: (Category) -> Void
    let onAddSubcategory: (Category) -> Void
    let onSelectCategory: (Category) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Catégorie parente : total du groupe (parente + sous-catégories)
            CategoryRowView(
                category: parentCategory,
                stats: groupStats,
                currency: currency,
                isParent: true,
                onTap: { onSelectCategory(parentCategory) },
                onEdit: { onEdit(parentCategory) },
                onDelete: { onDelete(parentCategory) }
            )

            ForEach(subcategories) { subcategory in
                Divider()
                    .padding(.leading, 62)

                CategoryRowView(
                    category: subcategory,
                    stats: stats[subcategory.id] ?? CategoryStats(),
                    currency: currency,
                    isParent: false,
                    onTap: { onSelectCategory(subcategory) },
                    onEdit: { onEdit(subcategory) },
                    onDelete: { onDelete(subcategory) }
                )
            }

            Divider()
                .padding(.leading, 62)

            // Ajouter une sous-catégorie
            Button {
                onAddSubcategory(parentCategory)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .frame(width: 36)
                    Text("Nouvelle sous-catégorie")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .cardBackground()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var groupStats: CategoryStats {
        subcategories.reduce(stats[parentCategory.id] ?? CategoryStats()) { $0 + (stats[$1.id] ?? CategoryStats()) }
    }
}

// MARK: - Category Row View
struct CategoryRowView: View {
    let category: Category
    let stats: CategoryStats
    let currency: String
    let isParent: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Icône de la catégorie
                Image(systemName: category.displayIcon)
                    .font(isParent ? .body : .subheadline)
                    .foregroundColor(.white)
                    .frame(width: isParent ? 36 : 28, height: isParent ? 36 : 28)
                    .background(
                        RoundedRectangle(cornerRadius: isParent ? 9 : 7)
                            .fill(Color(hex: category.displayColor).gradient)
                    )
                    .frame(width: 36)

                // Nom de la catégorie
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(isParent ? .headline : .body)
                        .foregroundColor(.primary)

                    if isParent, let description = category.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Activité
                VStack(alignment: .trailing, spacing: 2) {
                    if stats.count > 0 {
                        Text(totalText)
                            .font(isParent ? .body.weight(.semibold) : .body)
                            .monospacedDigit()
                            .foregroundColor(stats.total > 0 ? .green : .primary)
                    }
                    Text(stats.count > 0 ? "\(stats.count) opération\(stats.count > 1 ? "s" : "")" : "Aucune opération")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isParent ? 11 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Voir les transactions de \(category.name)")
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Voir les transactions", systemImage: "list.bullet.rectangle")
            }

            Divider()

            Button {
                onEdit()
            } label: {
                Label("Modifier", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private var totalText: String {
        let amount = abs(stats.total).formatted(.currency(code: currency))
        return stats.total > 0 ? "+\(amount)" : amount
    }
}

// Note: L'extension Color(hex:) doit déjà exister dans votre projet
// Si ce n'est pas le cas, décommentez le code ci-dessous :
/*
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
*/

// MARK: - View Extension for Rounded Corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()
        
        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)
        
        let maxX = rect.maxX
        let minX = rect.minX
        let maxY = rect.maxY
        let minY = rect.minY
        
        let radiusWidth = cornerRadii.width
        let radiusHeight = cornerRadii.height
        
        move(to: CGPoint(x: minX + (topLeft ? radiusWidth : 0), y: minY))
        
        // Top edge and top-right corner
        line(to: CGPoint(x: maxX - (topRight ? radiusWidth : 0), y: minY))
        if topRight {
            appendArc(withCenter: CGPoint(x: maxX - radiusWidth, y: minY + radiusHeight),
                     radius: radiusWidth, startAngle: 270, endAngle: 0, clockwise: false)
        }
        
        // Right edge and bottom-right corner
        line(to: CGPoint(x: maxX, y: maxY - (bottomRight ? radiusHeight : 0)))
        if bottomRight {
            appendArc(withCenter: CGPoint(x: maxX - radiusWidth, y: maxY - radiusHeight),
                     radius: radiusWidth, startAngle: 0, endAngle: 90, clockwise: false)
        }
        
        // Bottom edge and bottom-left corner
        line(to: CGPoint(x: minX + (bottomLeft ? radiusWidth : 0), y: maxY))
        if bottomLeft {
            appendArc(withCenter: CGPoint(x: minX + radiusWidth, y: maxY - radiusHeight),
                     radius: radiusWidth, startAngle: 90, endAngle: 180, clockwise: false)
        }
        
        // Left edge and top-left corner
        line(to: CGPoint(x: minX, y: minY + (topLeft ? radiusHeight : 0)))
        if topLeft {
            appendArc(withCenter: CGPoint(x: minX + radiusWidth, y: minY + radiusHeight),
                     radius: radiusWidth, startAngle: 180, endAngle: 270, clockwise: false)
        }
        
        close()
    }
    
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        
        return path
    }
}

struct UIRectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
