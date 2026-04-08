import Foundation

/// Représentation SQL du Book (correspondance exacte avec la table)
struct BookDTO {
    let id: String
    let name: String
    let currency: String
    let createdAt: String  // ISO8601
    let updatedAt: String  // ISO8601
    let archivedAt: String?  // ISO8601 nullable
}
