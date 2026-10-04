import Foundation

protocol AnnualBudgetRepositoryProtocol {
    func fetchAll(for bookID: UUID, year: Int) async throws -> [AnnualBudgetEntry]
    func save(_ entry: AnnualBudgetEntry) async throws
    func delete(bookID: UUID, categoryID: UUID, year: Int, month: Int) async throws
}

class AnnualBudgetRepository: AnnualBudgetRepositoryProtocol {
    private let db: SQLiteManager

    private static let posix = Locale(identifier: "en_US_POSIX")

    init(db: SQLiteManager) {
        self.db = db
    }

    func fetchAll(for bookID: UUID, year: Int) async throws -> [AnnualBudgetEntry] {
        let sql = """
        SELECT category_id, month, amount
        FROM annual_budget_entries
        WHERE book_id = ? AND year = ?;
        """

        let rows = try db.query(sql: sql, parameters: [bookID.uuidString, year])
        return rows.compactMap { row in
            guard let categoryString = row["category_id"] as? String,
                  let categoryID = UUID(uuidString: categoryString),
                  let month = row["month"] as? Int64,
                  let amountString = row["amount"] as? String,
                  let amount = Decimal(string: amountString, locale: Self.posix) else {
                return nil
            }
            return AnnualBudgetEntry(bookID: bookID, categoryID: categoryID, year: year, month: Int(month), amount: amount)
        }
    }

    /// Crée ou remplace le montant prévu de la catégorie pour ce mois
    func save(_ entry: AnnualBudgetEntry) async throws {
        let sql = """
        INSERT OR REPLACE INTO annual_budget_entries (book_id, category_id, year, month, amount)
        VALUES (?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            entry.bookID.uuidString,
            entry.categoryID.uuidString,
            entry.year,
            entry.month,
            NSDecimalNumber(decimal: entry.amount).description(withLocale: Self.posix)
        ])
    }

    func delete(bookID: UUID, categoryID: UUID, year: Int, month: Int) async throws {
        let sql = """
        DELETE FROM annual_budget_entries
        WHERE book_id = ? AND category_id = ? AND year = ? AND month = ?;
        """

        try db.execute(sql: sql, parameters: [bookID.uuidString, categoryID.uuidString, year, month])
    }
}
