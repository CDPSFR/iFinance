import Foundation

struct InvestmentTransactionMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// Évite le bruit binaire de Decimal(Double) (ex. 100.2 → 100.20000000000000512)
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }

    static func toDTO(_ operation: InvestmentTransaction) -> InvestmentTransactionDTO {
        return InvestmentTransactionDTO(
            id: operation.id.uuidString,
            accountID: operation.accountID.uuidString,
            positionID: operation.positionID?.uuidString,
            date: dateFormatter.string(from: operation.date),
            type: operation.type.rawValue,
            symbol: operation.symbol,
            quantity: operation.quantity.map { NSDecimalNumber(decimal: $0).doubleValue },
            price: operation.price.map { NSDecimalNumber(decimal: $0).doubleValue },
            amount: NSDecimalNumber(decimal: operation.amount).doubleValue,
            fees: NSDecimalNumber(decimal: operation.fees).doubleValue,
            memo: operation.memo
        )
    }

    static func fromDTO(_ dto: InvestmentTransactionDTO) -> InvestmentTransaction? {
        guard let id = UUID(uuidString: dto.id),
              let accountID = UUID(uuidString: dto.accountID),
              let date = dateFormatter.date(from: dto.date),
              let type = InvestmentTransactionType(rawValue: dto.type) else {
            return nil
        }

        return InvestmentTransaction(
            id: id,
            accountID: accountID,
            positionID: dto.positionID.flatMap { UUID(uuidString: $0) },
            date: date,
            type: type,
            symbol: dto.symbol,
            quantity: dto.quantity.map { decimal($0) },
            price: dto.price.map { decimal($0) },
            amount: decimal(dto.amount),
            fees: decimal(dto.fees),
            memo: dto.memo
        )
    }

    static func fromRow(_ row: [String: Any]) -> InvestmentTransaction? {
        guard let id = row["id"] as? String,
              let accountID = row["account_id"] as? String,
              let date = row["date"] as? String,
              let type = row["type"] as? String,
              let amount = row["amount"] as? Double else {
            return nil
        }

        let dto = InvestmentTransactionDTO(
            id: id,
            accountID: accountID,
            positionID: row["position_id"] as? String,
            date: date,
            type: type,
            symbol: row["symbol"] as? String,
            quantity: row["quantity"] as? Double,
            price: row["price"] as? Double,
            amount: amount,
            fees: row["fees"] as? Double ?? 0,
            memo: row["memo"] as? String
        )

        return fromDTO(dto)
    }
}
