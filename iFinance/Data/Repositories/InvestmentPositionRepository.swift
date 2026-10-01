import Foundation

class InvestmentPositionRepository: InvestmentPositionRepositoryProtocol {
    private let db: SQLiteManager

    init(db: SQLiteManager) {
        self.db = db
    }

    // MARK: - Fetch All

    func fetchAll(for accountID: UUID) async throws -> [InvestmentPosition] {
        let sql = """
        SELECT id, account_id, symbol, name, quantity, average_cost, current_price, currency, asset_type, last_updated
        FROM investment_positions
        WHERE account_id = ?
        ORDER BY name COLLATE NOCASE;
        """

        let rows = try db.query(sql: sql, parameters: [accountID.uuidString])
        return rows.compactMap { InvestmentPositionMapper.fromRow($0) }
    }

    // MARK: - Fetch by ID

    func fetch(id: UUID) async throws -> InvestmentPosition? {
        let sql = """
        SELECT id, account_id, symbol, name, quantity, average_cost, current_price, currency, asset_type, last_updated
        FROM investment_positions
        WHERE id = ?;
        """

        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        return rows.first.flatMap { InvestmentPositionMapper.fromRow($0) }
    }

    // MARK: - Create

    func create(_ position: InvestmentPosition) async throws {
        let dto = InvestmentPositionMapper.toDTO(position)

        let sql = """
        INSERT INTO investment_positions (id, account_id, symbol, name, quantity, average_cost, current_price, currency, asset_type, last_updated)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.accountID,
            dto.symbol,
            dto.name,
            dto.quantity,
            dto.averageCost,
            dto.currentPrice ?? NSNull(),
            dto.currency,
            dto.assetType,
            dto.lastUpdated ?? NSNull()
        ])
    }

    // MARK: - Update

    func update(_ position: InvestmentPosition) async throws {
        let dto = InvestmentPositionMapper.toDTO(position)

        let sql = """
        UPDATE investment_positions
        SET symbol = ?, name = ?, quantity = ?, average_cost = ?, current_price = ?, currency = ?, asset_type = ?, last_updated = ?
        WHERE id = ?;
        """

        try db.execute(sql: sql, parameters: [
            dto.symbol,
            dto.name,
            dto.quantity,
            dto.averageCost,
            dto.currentPrice ?? NSNull(),
            dto.currency,
            dto.assetType,
            dto.lastUpdated ?? NSNull(),
            dto.id
        ])
    }

    // MARK: - Update Price

    func updatePrice(id: UUID, price: Decimal, date: Date) async throws {
        let sql = "UPDATE investment_positions SET current_price = ?, last_updated = ? WHERE id = ?;"
        try db.execute(sql: sql, parameters: [
            NSDecimalNumber(decimal: price).doubleValue,
            ISO8601DateFormatter().string(from: date),
            id.uuidString
        ])
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        let sql = "DELETE FROM investment_positions WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
}
