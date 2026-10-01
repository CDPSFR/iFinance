import Foundation

struct InvestmentPositionMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// Évite le bruit binaire de Decimal(Double) (ex. 100.2 → 100.20000000000000512)
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }

    static func toDTO(_ position: InvestmentPosition) -> InvestmentPositionDTO {
        return InvestmentPositionDTO(
            id: position.id.uuidString,
            accountID: position.accountID.uuidString,
            symbol: position.symbol,
            name: position.name,
            quantity: NSDecimalNumber(decimal: position.quantity).doubleValue,
            averageCost: NSDecimalNumber(decimal: position.averageCost).doubleValue,
            currentPrice: position.currentPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            currency: position.currency,
            assetType: position.assetType.rawValue,
            lastUpdated: position.lastUpdated.map { dateFormatter.string(from: $0) }
        )
    }

    static func fromDTO(_ dto: InvestmentPositionDTO) -> InvestmentPosition? {
        guard let id = UUID(uuidString: dto.id),
              let accountID = UUID(uuidString: dto.accountID),
              let assetType = AssetType(rawValue: dto.assetType) else {
            return nil
        }

        return InvestmentPosition(
            id: id,
            accountID: accountID,
            symbol: dto.symbol,
            name: dto.name,
            quantity: decimal(dto.quantity),
            averageCost: decimal(dto.averageCost),
            currentPrice: dto.currentPrice.map { decimal($0) },
            currency: dto.currency,
            assetType: assetType,
            lastUpdated: dto.lastUpdated.flatMap { dateFormatter.date(from: $0) }
        )
    }

    static func fromRow(_ row: [String: Any]) -> InvestmentPosition? {
        guard let id = row["id"] as? String,
              let accountID = row["account_id"] as? String,
              let symbol = row["symbol"] as? String,
              let name = row["name"] as? String,
              let quantity = row["quantity"] as? Double,
              let averageCost = row["average_cost"] as? Double,
              let currency = row["currency"] as? String,
              let assetType = row["asset_type"] as? String else {
            return nil
        }

        let dto = InvestmentPositionDTO(
            id: id,
            accountID: accountID,
            symbol: symbol,
            name: name,
            quantity: quantity,
            averageCost: averageCost,
            currentPrice: row["current_price"] as? Double,
            currency: currency,
            assetType: assetType,
            lastUpdated: row["last_updated"] as? String
        )

        return fromDTO(dto)
    }
}
