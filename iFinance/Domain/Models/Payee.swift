import Foundation

struct Payee: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var name: String
    var city: String?
    var postalCode: String?
    var notes: String?
    var defaultCategoryID: UUID?  // Catégorie par défaut pour auto-suggestion
    
    // Helper pour affichage de la localisation
    var locationDisplay: String? {
        if let city = city, let postal = postalCode {
            return "\(postal) \(city)"
        } else if let city = city {
            return city
        } else if let postal = postalCode {
            return postal
        }
        return nil
    }
}
