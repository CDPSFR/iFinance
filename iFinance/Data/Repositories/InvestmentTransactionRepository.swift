import Foundation

class InvestmentTransactionRepository: InvestmentTransactionRepositoryProtocol {
    private let db: SQLiteManager

    init(db: SQLiteManager) {
        self.db = db
    }

    // MARK: - Fetch All

    func fetchAll(for accountID: UUID) async throws -> [InvestmentTransaction] {
        let sql = """
        SELECT id, account_id, position_id, date, type, symbol, quantity, price, amount, fees, memo
        FROM investment_transactions
        WHERE account_id = ?
        ORDER BY date, rowid;
        """

        let rows = try db.query(sql: sql, parameters: [accountID.uuidString])
        return rows.compactMap { InvestmentTransactionMapper.fromRow($0) }
    }

    func fetchAll(forPosition positionID: UUID) async throws -> [InvestmentTransaction] {
        let sql = """
        SELECT id, account_id, position_id, date, type, symbol, quantity, price, amount, fees, memo
        FROM investment_transactions
        WHERE position_id = ?
        ORDER BY date, rowid;
        """

        let rows = try db.query(sql: sql, parameters: [positionID.uuidString])
        return rows.compactMap { InvestmentTransactionMapper.fromRow($0) }
    }

    // MARK: - Create

    func create(_ operation: InvestmentTransaction) async throws {
        let dto = InvestmentTransactionMapper.toDTO(operation)

        let sql = """
        INSERT INTO investment_transactions (id, account_id, position_id, date, type, symbol, quantity, price, amount, fees, memo)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.accountID,
            dto.positionID ?? NSNull(),
            dto.date,
            dto.type,
            dto.symbol ?? NSNull(),
            dto.quantity ?? NSNull(),
            dto.price ?? NSNull(),
            dto.amount,
            dto.fees,
            dto.memo ?? NSNull()
        ])
    }

    // MARK: - Update

    func update(_ operation: InvestmentTransaction) async throws {
        let dto = InvestmentTransactionMapper.toDTO(operation)

        let sql = """
        UPDATE investment_transactions
        SET position_id = ?, date = ?, type = ?, symbol = ?, quantity = ?, price = ?, amount = ?, fees = ?, memo = ?
        WHERE id = ?;
        """

        try db.execute(sql: sql, parameters: [
            dto.positionID ?? NSNull(),
            dto.date,
            dto.type,
            dto.symbol ?? NSNull(),
            dto.quantity ?? NSNull(),
            dto.price ?? NSNull(),
            dto.amount,
            dto.fees,
            dto.memo ?? NSNull(),
            dto.id
        ])
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        let sql = "DELETE FROM investment_transactions WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }

    func deleteAll(forPosition positionID: UUID) async throws {
        let sql = "DELETE FROM investment_transactions WHERE position_id = ?;"
        try db.execute(sql: sql, parameters: [positionID.uuidString])
    }
}
