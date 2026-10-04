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
            iban: account.iban,
            bic: account.bic,
            isExcludedFromReports: account.isExcludedFromReports,
            initialBalanceDate: account.initialBalanceDate.map { dateFormatter.string(from: $0) },
            isHiddenFromSidebar: account.isHiddenFromSidebar,
            isExcludedFromBudgets: account.isExcludedFromBudgets,
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
            iban: dto.iban,
            bic: dto.bic,
            isExcludedFromReports: dto.isExcludedFromReports,
            initialBalanceDate: dto.initialBalanceDate.flatMap { dateFormatter.date(from: $0) },
            isHiddenFromSidebar: dto.isHiddenFromSidebar,
            isExcludedFromBudgets: dto.isExcludedFromBudgets,
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
        
        let isExcludedInt = row["is_excluded_from_reports"] as? Int64 ?? 0
        let dto = AccountDTO(
            id: id,
            bookID: bookID,
            name: name,
            bank: row["bank"] as? String,
            type: typeStr,
            initialBalance: initialBalance,
            currency: currency,
            iban: row["iban"] as? String,
            bic: row["bic"] as? String,
            isExcludedFromReports: isExcludedInt == 1,
            initialBalanceDate: row["initial_balance_date"] as? String,
            isHiddenFromSidebar: (row["is_hidden_from_sidebar"] as? Int64 ?? 0) == 1,
            isExcludedFromBudgets: (row["is_excluded_from_budgets"] as? Int64 ?? 0) == 1,
            isClosed: isClosedInt == 1,
            createdAt: createdAtStr
        )
        
        return fromDTO(dto)
    }
}
