import Foundation

struct Category: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var name: String
    var description: String?
    var parentID: UUID?
    var color: String?        // Code couleur hex (#FF0000)
    var icon: String?         // Nom du SF Symbol
    var isIncome: Bool = false  // true = catégorie de revenus, false = dépenses
    
    // Helper pour vérifier si c'est une catégorie racine
    var isRoot: Bool {
        return parentID == nil
    }
    
    // Couleur par défaut si non définie
    var displayColor: String {
        return color ?? (isIncome ? "#4CAF50" : "#F44336")
    }
    
    // Icône par défaut si non définie
    var displayIcon: String {
        return icon ?? (isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
    }
}
