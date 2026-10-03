import SwiftUI

struct CategoryListView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    
    // AJOUT: Binding pour contrôler la navigation
    @Binding var selectedTab: MainView.SidebarItem
    
    @State private var showCategoryForm = false
    @State private var categoryToEdit: Category?
    @State private var parentForNewCategory: UUID?
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirmation = false
    @State private var showDefaultCategoriesAlert = false
    @State private var searchQuery = ""
    @State private var navigateToTransactions = false
    @State private var selectedCategoryForNavigation: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Titre
            HStack {
                Text("Catégories")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Barre de recherche
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Rechercher une catégorie...", text: $searchQuery)
                    .textFieldStyle(.plain)
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Contenu
            if categoriesController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if categoriesController.categories.isEmpty {
                emptyCategoriesView
            } else {
                categoriesScrollView
            }
        }
        // Fond légèrement teinté pour détacher les cartes (blanc sur blanc depuis macOS 26)
        .background(Color(nsColor: .windowBackgroundColor).overlay(Color.primary.opacity(0.045)))
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
                Task { await categoriesController.deleteCategory(id: category.id) }
            }
        } message: { category in
            if categoriesController.hasSubcategories(category.id) {
                Text("Cette catégorie contient des sous-catégories. Elles seront également supprimées.")
            } else {
                Text("Cette action est irréversible.")
            }
        }
        .task {
            if let bookID = bookController.currentBook?.id {
                await categoriesController.loadCategories(for: bookID)
            }
        }
        .onChange(of: bookController.currentBook?.id) { oldValue, newValue in
            if let bookID = newValue {
                Task {
                    await categoriesController.loadCategories(for: bookID)
                }
            }
        }
        .onChange(of: navigateToTransactions) { oldValue, newValue in
            if newValue, let categoryID = selectedCategoryForNavigation {
                // Appliquer le filtre de catégorie
                var filters = transactionsController.filters
                filters.categoryID = categoryID
                transactionsController.updateFilters(filters)
                
                // 🔴 NAVIGATION: Changer vers la vue des transactions
                selectedTab = .allTransactions
                
                // Réinitialiser la navigation
                navigateToTransactions = false
                selectedCategoryForNavigation = nil
            }
        }
    }
    
    private var emptyCategoriesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            if searchQuery.isEmpty {
                Text("Aucune catégorie")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Créez vos catégories pour organiser vos transactions")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    showCategoryForm = true
                } label: {
                    Label("Créer une catégorie", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Aucun résultat")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Aucune catégorie ne correspond à \"\(searchQuery)\"")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var categoriesScrollView: some View {
        let stats = categoryStats()
        let currency = bookController.currentBook?.currency ?? "EUR"

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                categorySection(title: "Dépenses", roots: filteredExpenseCategories, stats: stats, currency: currency)
                categorySection(title: "Revenus", roots: filteredIncomeCategories, stats: stats, currency: currency)
            }
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func categorySection(title: String, roots: [Category], stats: [UUID: CategoryStats], currency: String) -> some View {
        if !roots.isEmpty {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(roots) { parentCategory in
                CategoryGroupView(
                    parentCategory: parentCategory,
                    subcategories: getFilteredSubcategories(for: parentCategory.id),
                    stats: stats,
                    currency: currency,
                    onEdit: { category in
                        categoryToEdit = category
                    },
                    onDelete: { category in
                        categoryToDelete = category
                        showDeleteConfirmation = true
                    },
                    onAddSubcategory: { parent in
                        parentForNewCategory = parent.id
                        showCategoryForm = true
                    },
                    onSelectCategory: { category in
                        selectedCategoryForNavigation = category.id
                        navigateToTransactions = true
                    }
                )
            }
        }
    }

    // MARK: - Filtered Categories
    private var filteredExpenseCategories: [Category] {
        let rootCategories = categoriesController.expenseCategories.filter { $0.isRoot }
        
        if searchQuery.isEmpty {
            return rootCategories
        }
        
        // Garder les parents qui correspondent OU qui ont des enfants qui correspondent
        return rootCategories.filter { parent in
            categoryMatchesSearch(parent) || hasMatchingSubcategories(parentID: parent.id)
        }
    }
    
    private var filteredIncomeCategories: [Category] {
        let rootCategories = categoriesController.incomeCategories.filter { $0.isRoot }
        
        if searchQuery.isEmpty {
            return rootCategories
        }
        
        // Garder les parents qui correspondent OU qui ont des enfants qui correspondent
        return rootCategories.filter { parent in
            categoryMatchesSearch(parent) || hasMatchingSubcategories(parentID: parent.id)
        }
    }
    
    private func getFilteredSubcategories(for parentID: UUID) -> [Category] {
        let subcategories = categoriesController.getSubcategories(for: parentID)
        
        // Si la catégorie parente correspond, on affiche toutes ses sous-catégories
        if searchQuery.isEmpty || categoriesController.getCategory(id: parentID).map(categoryMatchesSearch) == true {
            return subcategories
        }
        
        return subcategories.filter { category in
            categoryMatchesSearch(category)
        }
    }
    
    private func categoryMatchesSearch(_ category: Category) -> Bool {
        category.name.localizedCaseInsensitiveContains(searchQuery) ||
        category.description?.localizedCaseInsensitiveContains(searchQuery) == true
    }
    
    private func hasMatchingSubcategories(parentID: UUID) -> Bool {
        let subcategories = categoriesController.getSubcategories(for: parentID)
        return subcategories.contains { categoryMatchesSearch($0) }
    }
    
    // MARK: - Category Stats
    private func categoryStats() -> [UUID: CategoryStats] {
        var stats: [UUID: CategoryStats] = [:]

        for transaction in transactionsController.allTransactions where transaction.status != .skipped {
            guard let categoryID = transaction.categoryID else { continue }
            stats[categoryID, default: CategoryStats()].count += 1
            stats[categoryID, default: CategoryStats()].total += transaction.signedAmount
        }

        return stats
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.6))
        )
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
