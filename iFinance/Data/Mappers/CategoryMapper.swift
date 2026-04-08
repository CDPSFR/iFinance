import Foundation

struct CategoryMapper {
    
    static func toDTO(_ category: Category) -> CategoryDTO {
        return CategoryDTO(
            id: category.id.uuidString,
            bookID: category.bookID.uuidString,
            name: category.name,
            description: category.description,
            parentID: category.parentID?.uuidString,
            color: category.color,
            icon: category.icon,
            isIncome: category.isIncome
        )
    }
    
    static func fromDTO(_ dto: CategoryDTO) -> Category? {
        guard let id = UUID(uuidString: dto.id),
              let bookID = UUID(uuidString: dto.bookID) else {
            return nil
        }
        
        return Category(
            id: id,
            bookID: bookID,
            name: dto.name,
            description: dto.description,
            parentID: dto.parentID.flatMap { UUID(uuidString: $0) },
            color: dto.color,
            icon: dto.icon,
            isIncome: dto.isIncome
        )
    }
    
    static func fromRow(_ row: [String: Any]) -> Category? {
        guard let id = row["id"] as? String,
              let bookID = row["book_id"] as? String,
              let name = row["name"] as? String,
              let isIncomeInt = row["is_income"] as? Int64 else {
            return nil
        }
        
        let dto = CategoryDTO(
            id: id,
            bookID: bookID,
            name: name,
            description: row["description"] as? String,
            parentID: row["parent_id"] as? String,
            color: row["color"] as? String,
            icon: row["icon"] as? String,
            isIncome: isIncomeInt == 1
        )
        
        return fromDTO(dto)
    }
}
