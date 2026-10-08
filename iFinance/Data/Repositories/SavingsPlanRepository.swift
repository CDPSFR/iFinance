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
        SELECT d.transaction_id, d.origin, d.available_on, d.is_deducted
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
        INSERT OR REPLACE INTO contribution_details (transaction_id, origin, available_on, is_deducted)
        VALUES (?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            dto.transactionID,
            dto.origin,
            dto.availableOn ?? NSNull(),
            dto.isDeducted ?? NSNull()
        ])
    }

    func deleteContributionDetail(transactionID: UUID) async throws {
        let sql = "DELETE FROM contribution_details WHERE transaction_id = ?;"
        try db.execute(sql: sql, parameters: [transactionID.uuidString])
    }

    // MARK: - Settings

    func fetchSettings(for accountID: UUID) async throws -> SavingsPlanSettings? {
        let sql = """
        SELECT account_id, matching_cap, deduction_ceilings, marginal_rate
        FROM savings_plan_settings
        WHERE account_id = ?;
        """

        guard let row = try db.query(sql: sql, parameters: [accountID.uuidString]).first else {
            return nil
        }

        var settings = SavingsPlanSettings(accountID: accountID)
        settings.matchingCap = Self.double(row["matching_cap"]).map { Decimal($0) }
        settings.marginalTaxRate = Self.double(row["marginal_rate"])
        if let json = row["deduction_ceilings"] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            settings.deductionCeilings = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                Int(key).map { ($0, Decimal(value)) }
            })
        }
        return settings
    }

    func saveSettings(_ settings: SavingsPlanSettings) async throws {
        let ceilings = Dictionary(uniqueKeysWithValues: settings.deductionCeilings.map { key, value in
            (String(key), NSDecimalNumber(decimal: value).doubleValue)
        })
        let json = (try? JSONEncoder().encode(ceilings)).flatMap { String(data: $0, encoding: .utf8) }

        let sql = """
        INSERT OR REPLACE INTO savings_plan_settings (account_id, matching_cap, deduction_ceilings, marginal_rate)
        VALUES (?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            settings.accountID.uuidString,
            settings.matchingCap.map { NSDecimalNumber(decimal: $0).doubleValue } ?? NSNull(),
            json ?? NSNull(),
            settings.marginalTaxRate ?? NSNull()
        ])
    }

    /// SQLite renvoie un REAL en Double, un entier en Int64
    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
