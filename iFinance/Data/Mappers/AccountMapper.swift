import Foundation

struct AccountMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    static func toDTO(_ account: Account) -> AccountDTO {
        return AccountDTO(
            id: account.id.uuidString,
            bookID: account.bookID.uuidString,
            name: account.name,
            bank: account.bank,
            type: account.type.rawValue,
            initialBalance: NSDecimalNumber(decimal: account.initialBalance).doubleValue,
            currency: account.currency,
            isClosed: account.isClosed,
            createdAt: dateFormatter.string(from: account.createdAt)
        )
    }
    
    static func fromDTO(_ dto: AccountDTO) -> Account? {
        guard let id = UUID(uuidString: dto.id),
              let bookID = UUID(uuidString: dto.bookID),
              let type = AccountType(rawValue: dto.type),
              let createdAt = dateFormatter.date(from: dto.createdAt) else {
            return nil
        }
        
        return Account(
            id: id,
            bookID: bookID,
            name: dto.name,
            bank: dto.bank,
            type: type,
            initialBalance: Decimal(dto.initialBalance),
            currency: dto.currency,
            isClosed: dto.isClosed,
            createdAt: createdAt
        )
    }
    
    static func fromRow(_ row: [String: Any]) -> Account? {
        guard let id = row["id"] as? String,
              let bookID = row["book_id"] as? String,
              let name = row["name"] as? String,
              let typeStr = row["type"] as? String,
              let initialBalance = row["initial_balance"] as? Double,
              let currency = row["currency"] as? String,
              let isClosedInt = row["is_closed"] as? Int64,
              let createdAtStr = row["created_at"] as? String else {
            return nil
        }
        
        let dto = AccountDTO(
            id: id,
            bookID: bookID,
            name: name,
            bank: row["bank"] as? String,
            type: typeStr,
            initialBalance: initialBalance,
            currency: currency,
            isClosed: isClosedInt == 1,
            createdAt: createdAtStr
        )
        
        return fromDTO(dto)
    }
}
