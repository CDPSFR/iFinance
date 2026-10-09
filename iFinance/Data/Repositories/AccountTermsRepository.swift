import Foundation

/// Conditions de prêt et frais des comptes (table account_terms)
class AccountTermsRepository {
    private let db: SQLiteManager

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    init(db: SQLiteManager) {
        self.db = db
    }

    func fetchAll() async throws -> [AccountTerms] {
        let sql = """
        SELECT account_id, loan_principal, loan_rate, loan_months, loan_first_payment,
               loan_insurance, loan_is_mortgage, fee_rate
        FROM account_terms;
        """
        return try db.query(sql: sql).compactMap(Self.fromRow)
    }

    func save(_ terms: AccountTerms) async throws {
        let sql = """
        INSERT OR REPLACE INTO account_terms
            (account_id, loan_principal, loan_rate, loan_months, loan_first_payment,
             loan_insurance, loan_is_mortgage, fee_rate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        let loan = terms.loan
        try db.execute(sql: sql, parameters: [
            terms.accountID.uuidString,
            loan.map { NSDecimalNumber(decimal: $0.principal).doubleValue } ?? NSNull(),
            loan?.annualRate ?? NSNull(),
            loan?.months ?? NSNull(),
            loan.map { Self.dateFormatter.string(from: $0.firstPaymentDate) } ?? NSNull(),
            loan.map { NSDecimalNumber(decimal: $0.monthlyInsurance).doubleValue } ?? NSNull(),
            loan.map { $0.isMortgage ? 1 : 0 } ?? NSNull(),
            terms.annualFeeRate ?? NSNull()
        ])
    }

    func delete(accountID: UUID) async throws {
        try db.execute(sql: "DELETE FROM account_terms WHERE account_id = ?;", parameters: [accountID.uuidString])
    }

    // MARK: - Mapping

    private static func fromRow(_ row: [String: Any]) -> AccountTerms? {
        guard let idString = row["account_id"] as? String, let accountID = UUID(uuidString: idString) else {
            return nil
        }

        var terms = AccountTerms(accountID: accountID)
        terms.annualFeeRate = double(row["fee_rate"])

        if let principal = double(row["loan_principal"]),
           let rate = double(row["loan_rate"]),
           let months = int(row["loan_months"]),
           let firstString = row["loan_first_payment"] as? String,
           let first = dateFormatter.date(from: firstString) {
            terms.loan = LoanTerms(
                principal: Decimal(principal),
                annualRate: rate,
                months: months,
                firstPaymentDate: first,
                monthlyInsurance: Decimal(double(row["loan_insurance"]) ?? 0),
                isMortgage: (int(row["loan_is_mortgage"]) ?? 1) != 0
            )
        }
        return terms
    }

    /// SQLite renvoie un REAL en Double, un entier en Int64
    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}
