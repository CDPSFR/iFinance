import Foundation
import SwiftUI
import Combine

@MainActor
class CategoriesController: ObservableObject {
    @Published var categories: [Category] = []
    @Published var rootCategories: [Category] = []
    @Published var incomeCategories: [Category] = []
    @Published var expenseCategories: [Category] = []
    @Published var selectedCategory: Category?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository: CategoryRepositoryProtocol
    private var currentBookID: UUID?
    
    // Cache des sous-catégories par parent
    private var subcategoriesCache: [UUID: [Category]] = [:]
    
    init(repository: CategoryRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Load Categories
    
    func loadCategories(for bookID: UUID) async {
        currentBookID = bookID
        isLoading = true
        defer { isLoading = false }
        
        do {
            categories = try await repository.fetchAll(for: bookID)
            rootCategories = categories.filter { $0.isRoot }
            incomeCategories = rootCategories.filter { $0.isIncome }
            expenseCategories = rootCategories.filter { !$0.isIncome }
            
            // Construire le cache des sous-catégories
            buildSubcategoriesCache()
            
        } catch {
            self.error = error
            print("❌ Erreur chargement catégories: \(error)")
        }
    }
    
    private func buildSubcategoriesCache() {
        subcategoriesCache.removeAll()
        
        for category in categories where !category.isRoot {
            if let parentID = category.parentID {
                subcategoriesCache[parentID, default: []].append(category)
            }
        }
        
        // Trier les sous-catégories par nom
        for (key, value) in subcategoriesCache {
            subcategoriesCache[key] = value.sorted { $0.name < $1.name }
        }
    }
    
    // MARK: - Get Subcategories
    
    func getSubcategories(for parentID: UUID) -> [Category] {
        return subcategoriesCache[parentID] ?? []
    }
    
    func hasSubcategories(_ categoryID: UUID) -> Bool {
        return !(subcategoriesCache[categoryID]?.isEmpty ?? true)
    }
    
    // MARK: - Get Category by ID
    
    func getCategory(id: UUID) -> Category? {
        return categories.first { $0.id == id }
    }
    
    // MARK: - Get Full Path (Parent > Child)
    func getCategoryPath(for categoryID: UUID) -> String {
        guard let category = getCategory(id: categoryID) else {
            return "Inconnu"
        }
        
        if let parentID = category.parentID,
           let parent = getCategory(id: parentID) {
            return "\(parent.name) › \(category.name)"
        }
        
        return category.name
    }
    
    // MARK: - Create Category
    
    func createCategory(
        bookID: UUID,
        name: String,
        description: String? = nil,
        parentID: UUID? = nil,
        color: String? = nil,
        icon: String? = nil,
        isIncome: Bool = false
    ) async {
        let category = Category(
            bookID: bookID,
            name: name,
            description: description,
            parentID: parentID,
            color: color,
            icon: icon,
            isIncome: isIncome
        )
        
        do {
            try await repository.create(category)
            await loadCategories(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur création catégorie: \(error)")
        }
    }
    
    // MARK: - Update Category
    
    func updateCategory(_ category: Category) async {
        do {
            try await repository.update(category)
            if let bookID = currentBookID {
                await loadCategories(for: bookID)
            }
        } catch {
            self.error = error
            print("❌ Erreur mise à jour catégorie: \(error)")
        }
    }
    
    // MARK: - Delete Category
    
    func deleteCategory(id: UUID) async {
        do {
            try await repository.delete(id: id)
            if let bookID = currentBookID {
                await loadCategories(for: bookID)
            }
        } catch {
            self.error = error
            print("❌ Erreur suppression catégorie: \(error)")
        }
    }
    
    // MARK: - Create Default Categories
    
    func createDefaultCategories(for bookID: UUID) async {
        let defaults: [(name: String, icon: String, color: String, isIncome: Bool, subcategories: [String])] = [
            // Dépenses
            ("Alimentation", "cart.fill", "#FF9800", false, ["Supermarché", "Restaurant", "Livraison"]),
            ("Transport", "car.fill", "#2196F3", false, ["Essence", "Transports en commun", "Taxi"]),
            ("Logement", "house.fill", "#9C27B0", false, ["Loyer", "Électricité", "Internet"]),
            ("Loisirs", "tv.fill", "#E91E63", false, ["Cinéma", "Sport", "Sorties"]),
            ("Santé", "cross.case.fill", "#4CAF50", false, ["Médecin", "Pharmacie", "Assurance"]),
            ("Shopping", "bag.fill", "#FF5722", false, ["Vêtements", "Électronique", "Maison"]),
            
            // Revenus
            ("Salaire", "dollarsign.circle.fill", "#4CAF50", true, []),
            ("Freelance", "briefcase.fill", "#8BC34A", true, []),
            ("Investissements", "chart.line.uptrend.xyaxis", "#00BCD4", true, ["Dividendes", "Plus-values"]),
        ]
        
        for (name, icon, color, isIncome, subcategories) in defaults {
            let parent = Category(
                bookID: bookID,
                name: name,
                description: nil,
                parentID: nil,
                color: color,
                icon: icon,
                isIncome: isIncome
            )
            
            do {
                try await repository.create(parent)
                
                // Créer les sous-catégories
                for subName in subcategories {
                    let sub = Category(
                        bookID: bookID,
                        name: subName,
                        description: nil,
                        parentID: parent.id,
                        color: color,
                        icon: icon,
                        isIncome: isIncome
                    )
                    try await repository.create(sub)
                }
            } catch {
                print("❌ Erreur création catégorie par défaut: \(error)")
            }
        }
        
        await loadCategories(for: bookID)
    }
    
    // MARK: - Transaction Statistics

    /// Compte le nombre de transactions pour chaque catégorie
    func getTransactionCounts(from transactions: [Transaction]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        
        for transaction in transactions {
            if let categoryID = transaction.categoryID {
                counts[categoryID, default: 0] += 1
            }
        }
        
        return counts
    }

    /// Récupère le nombre de transactions pour une catégorie spécifique
    func getTransactionCount(for categoryID: UUID, from transactions: [Transaction]) -> Int {
        return transactions.filter { $0.categoryID == categoryID }.count
    }

    /// Récupère le nombre total de transactions incluant les sous-catégories
    func getTotalTransactionCount(for categoryID: UUID, from transactions: [Transaction]) -> Int {
        var total = getTransactionCount(for: categoryID, from: transactions)
        
        // Ajouter les transactions des sous-catégories
        let subcategories = getSubcategories(for: categoryID)
        for subcategory in subcategories {
            total += getTransactionCount(for: subcategory.id, from: transactions)
        }
        
        return total
    }
}
