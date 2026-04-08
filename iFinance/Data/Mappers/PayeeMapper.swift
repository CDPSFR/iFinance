import Foundation

struct PayeeMapper {
    
    static func toDTO(_ payee: Payee) -> PayeeDTO {
        return PayeeDTO(
            id: payee.id.uuidString,
            bookID: payee.bookID.uuidString,
            name: payee.name,
            city: payee.city,
            postalCode: payee.postalCode,
            notes: payee.notes,
            defaultCategoryID: payee.defaultCategoryID?.uuidString
        )
    }
    
    static func fromDTO(_ dto: PayeeDTO) -> Payee? {
        guard let id = UUID(uuidString: dto.id),
              let bookID = UUID(uuidString: dto.bookID) else {
            return nil
        }
        
        return Payee(
            id: id,
            bookID: bookID,
            name: dto.name,
            city: dto.city,
            postalCode: dto.postalCode,
            notes: dto.notes,
            defaultCategoryID: dto.defaultCategoryID.flatMap { UUID(uuidString: $0) }
        )
    }
    
    static func fromRow(_ row: [String: Any]) -> Payee? {
        guard let id = row["id"] as? String,
              let bookID = row["book_id"] as? String,
              let name = row["name"] as? String else {
            return nil
        }
        
        let dto = PayeeDTO(
            id: id,
            bookID: bookID,
            name: name,
            city: row["city"] as? String,
            postalCode: row["postal_code"] as? String,
            notes: row["notes"] as? String,
            defaultCategoryID: row["default_category_id"] as? String
        )
        
        return fromDTO(dto)
    }
}
