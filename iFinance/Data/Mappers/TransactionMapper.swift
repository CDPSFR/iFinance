import Foundation

struct TransactionMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    static func toDTO(_ transaction: Transaction) -> TransactionDTO {
        return TransactionDTO(
            id: transaction.id.uuidString,
            date: dateFormatter.string(from: transaction.date),
            amount: NSDecimalNumber(decimal: transaction.amount).doubleValue,
            accountID: transaction.accountID.uuidString,
            toAccountID: transaction.toAccountID?.uuidString,
            linkedTransactionID: transaction.linkedTransactionID?.uuidString,
            payeeID: transaction.payeeID?.uuidString,
            categoryID: transaction.categoryID?.uuidString,
            type: transaction.type.rawValue,
            memo: transaction.memo,
            isReconciled: transaction.isReconciled,
            recurringTemplateID: transaction.recurringTemplateID?.uuidString,
            status: transaction.status.rawValue
        )
    }
    
    static func fromDTO(_ dto: TransactionDTO) -> Transaction? {
        guard let id = UUID(uuidString: dto.id),
              let accountID = UUID(uuidString: dto.accountID),
              let type = TransactionType(rawValue: dto.type),
              let status = TransactionStatus(rawValue: dto.status),
              let date = dateFormatter.date(from: dto.date) else {
            return nil
        }
        
        return Transaction(
            id: id,
            date: date,
            amount: Decimal(dto.amount),
            accountID: accountID,
            toAccountID: dto.toAccountID.flatMap { UUID(uuidString: $0) },
            linkedTransactionID: dto.linkedTransactionID.flatMap { UUID(uuidString: $0) },
            payeeID: dto.payeeID.flatMap { UUID(uuidString: $0) },
            categoryID: dto.categoryID.flatMap { UUID(uuidString: $0) },
            type: type,
            memo: dto.memo,
            isReconciled: dto.isReconciled,
            recurringTemplateID: dto.recurringTemplateID.flatMap { UUID(uuidString: $0) },
            status: status
        )
    }
    
    static func fromRow(_ row: [String: Any]) -> Transaction? {
        guard let id = row["id"] as? String,
              let dateStr = row["date"] as? String,
              let amount = row["amount"] as? Double,
              let accountID = row["account_id"] as? String,
              let typeStr = row["type"] as? String,
              let isReconciledInt = row["is_reconciled"] as? Int64,
              let statusStr = row["status"] as? String else {
            return nil
        }
        
        let dto = TransactionDTO(
            id: id,
            date: dateStr,
            amount: amount,
            accountID: accountID,
            toAccountID: row["to_account_id"] as? String,
            linkedTransactionID: row["linked_transaction_id"] as? String,
            payeeID: row["payee_id"] as? String,
            categoryID: row["category_id"] as? String,
            type: typeStr,
            memo: row["memo"] as? String,
            isReconciled: isReconciledInt == 1,
            recurringTemplateID: row["recurring_template_id"] as? String,
            status: statusStr
        )
        
        return fromDTO(dto)
    }
}
