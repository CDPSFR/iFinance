import Foundation

struct Book: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var currency: String = "EUR"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date? = nil
    
    var isArchived: Bool {
        return archivedAt != nil
    }
}
