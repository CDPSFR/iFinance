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
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
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
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showCategoryForm) {
            CategoryFormView(isPresented: $showCategoryForm)
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
        ScrollView {
            VStack(spacing: 0) {
                // Catégories de dépenses
                ForEach(filteredExpenseCategories.filter { $0.isRoot }) { parentCategory in
                    CategoryGroupView(
                        parentCategory: parentCategory,
                        subcategories: getFilteredSubcategories(for: parentCategory.id),
                        transactionCounts: getCategoryTransactionCounts(),
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
                
                // Catégories de revenus
                ForEach(filteredIncomeCategories.filter { $0.isRoot }) { parentCategory in
                    CategoryGroupView(
                        parentCategory: parentCategory,
                        subcategories: getFilteredSubcategories(for: parentCategory.id),
                        transactionCounts: getCategoryTransactionCounts(),
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
        
        if searchQuery.isEmpty {
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
    
    // MARK: - Transaction Count
    private func getCategoryTransactionCounts() -> [UUID: Int] {
        return categoriesController.getTransactionCounts(from: transactionsController.allTransactions)
    }
}

// MARK: - Category Group View
struct CategoryGroupView: View {
    let parentCategory: Category
    let subcategories: [Category]
    let transactionCounts: [UUID: Int]
    let onEdit: (Category) -> Void
    let onDelete: (Category) -> Void
    let onAddSubcategory: (Category) -> Void
    let onSelectCategory: (Category) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Nom de la catégorie parente (extérieur à la carte)
            Text(parentCategory.name)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .contextMenu {
                    Button { onEdit(parentCategory) } label: {
                        Label("Modifier", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { onDelete(parentCategory) } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }

            VStack(spacing: 0) {
            // Sous-catégories
            ForEach(Array(subcategories.enumerated()), id: \.element.id) { index, subcategory in
                CategoryRowView(
                    category: subcategory,
                    count: transactionCounts[subcategory.id] ?? 0,
                    onTap: { onSelectCategory(subcategory) },
                    onEdit: { onEdit(subcategory) },
                    onDelete: { onDelete(subcategory) }
                )
                if index < subcategories.count - 1 {
                    Divider()
                        .padding(.leading, 54)
                }
            }
            
            // Bouton "Nouvelle catégorie"
            Button {
                onAddSubcategory(parentCategory)
            } label: {
                HStack {
                    Text("Nouvelle catégorie")
                        .font(.subheadline)
                        .foregroundColor(.teal)
                    
                    Spacer()
                    
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .foregroundColor(.teal)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            .buttonStyle(.plain)
            .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Category Row View
struct CategoryRowView: View {
    let category: Category
    let count: Int
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showContextMenu = false
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 10) {
                // Icône de la catégorie
                Image(systemName: category.displayIcon)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: category.displayColor))
                    )
                
                // Nom de la catégorie
                Text(category.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Nombre de transactions
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
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
