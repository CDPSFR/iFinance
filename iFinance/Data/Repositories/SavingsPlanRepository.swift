import Foundation

class SavingsPlanRepository: SavingsPlanRepositoryProtocol {
    private let db: SQLiteManager

    init(db: SQLiteManager) {
        self.db = db
    }

    // MARK: - Valuations

    func fetchValuations(for accountID: UUID) async throws -> [ValuationSnapshot] {
        let sql = """
        SELECT id, account_id, date, value, note
        FROM account_valuations
        WHERE account_id = ?
        ORDER BY date;
        """

        let rows = try db.query(sql: sql, parameters: [accountID.uuidString])
        return rows.compactMap { ValuationSnapshotMapper.fromRow($0) }
    }

    func createValuation(_ snapshot: ValuationSnapshot) async throws {
        let dto = ValuationSnapshotMapper.toDTO(snapshot)

        let sql = """
        INSERT INTO account_valuations (id, account_id, date, value, note)
        VALUES (?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.accountID,
            dto.date,
            dto.value,
            dto.note ?? NSNull()
        ])
    }

    func updateValuation(_ snapshot: ValuationSnapshot) async throws {
        let dto = ValuationSnapshotMapper.toDTO(snapshot)

        let sql = """
        UPDATE account_valuations
        SET date = ?, value = ?, note = ?
        WHERE id = ?;
        """

        try db.execute(sql: sql, parameters: [
            dto.date,
            dto.value,
            dto.note ?? NSNull(),
            dto.id
        ])
    }

    func deleteValuation(id: UUID) async throws {
        let sql = "DELETE FROM account_valuations WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }

    // MARK: - Contribution Details

    func fetchContributionDetails(for accountID: UUID) async throws -> [ContributionDetail] {
        let sql = """
        SELECT d.transaction_id, d.origin, d.available_on
        FROM contribution_details d
        JOIN transactions t ON t.id = d.transaction_id
        WHERE t.account_id = ?;
        """

        let rows = try db.query(sql: sql, parameters: [accountID.uuidString])
        return rows.compactMap { ContributionDetailMapper.fromRow($0) }
    }

    func saveContributionDetail(_ detail: ContributionDetail) async throws {
        let dto = ContributionDetailMapper.toDTO(detail)

        let sql = """
        INSERT OR REPLACE INTO contribution_details (transaction_id, origin, available_on)
        VALUES (?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            dto.transactionID,
            dto.origin,
            dto.availableOn ?? NSNull()
        ])
    }

    func deleteContributionDetail(transactionID: UUID) async throws {
        let sql = "DELETE FROM contribution_details WHERE transaction_id = ?;"
        try db.execute(sql: sql, parameters: [transactionID.uuidString])
    }
}
