import Foundation

struct Book: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var currency: String = "EUR"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date? = nil
    var color: String? = nil  // Couleur du livre, code hex (#0A66D8) ; nil = couleur d'accent
    
    var isArchived: Bool {
        return archivedAt != nil
    }
}
