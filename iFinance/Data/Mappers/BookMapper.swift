import Foundation

struct BookMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    /// Convertit un Book (Domain) en BookDTO (SQL)
    static func toDTO(_ book: Book) -> BookDTO {
        return BookDTO(
            id: book.id.uuidString,
            name: book.name,
            currency: book.currency,
            createdAt: dateFormatter.string(from: book.createdAt),
            updatedAt: dateFormatter.string(from: book.updatedAt),
            archivedAt: book.archivedAt.map { dateFormatter.string(from: $0) },
            color: book.color
        )
    }
    
    /// Convertit un BookDTO (SQL) en Book (Domain)
    static func fromDTO(_ dto: BookDTO) -> Book? {
        guard let id = UUID(uuidString: dto.id),
              let createdAt = dateFormatter.date(from: dto.createdAt),
              let updatedAt = dateFormatter.date(from: dto.updatedAt) else {
            return nil
        }
        
        let archivedAt = dto.archivedAt.flatMap { dateFormatter.date(from: $0) }
        
        return Book(
            id: id,
            name: dto.name,
            currency: dto.currency,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt,
            color: dto.color
        )
    }
    
    /// Convertit une ligne SQL brute en Book
    static func fromRow(_ row: [String: Any]) -> Book? {
        guard let id = row["id"] as? String,
              let name = row["name"] as? String,
              let currency = row["currency"] as? String,
              let createdAtStr = row["created_at"] as? String,
              let updatedAtStr = row["updated_at"] as? String else {
            return nil
        }
        
        let dto = BookDTO(
            id: id,
            name: name,
            currency: currency,
            createdAt: createdAtStr,
            updatedAt: updatedAtStr,
            archivedAt: row["archived_at"] as? String,
            color: row["color"] as? String
        )
        
        return fromDTO(dto)
    }
}
