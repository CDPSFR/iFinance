import Foundation

class BudgetRepository: BudgetRepositoryProtocol {
    private let db: SQLiteManager

    init(db: SQLiteManager) {
        self.db = db
    }

    // MARK: - Fetch All

    func fetchAll(for bookID: UUID) async throws -> [Budget] {
        let sql = """
        SELECT id, book_id, name, note, period, category_ids, anchor_date, created_at
        FROM budgets
        WHERE book_id = ?
        ORDER BY created_at ASC;
        """
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        var budgets = rows.compactMap { BudgetMapper.fromRow($0) }

        // Attach current version to each budget
        for i in budgets.indices {
            budgets[i].currentVersion = try await currentVersion(for: budgets[i].id, at: Date())
        }
        return budgets
    }

    // MARK: - Fetch by ID

    func fetch(id: UUID) async throws -> Budget? {
        let sql = """
        SELECT id, book_id, name, note, period, category_ids, anchor_date, created_at
        FROM budgets
        WHERE id = ?;
        """
        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        guard var budget = rows.first.flatMap({ BudgetMapper.fromRow($0) }) else { return nil }
        budget.currentVersion = try await currentVersion(for: budget.id, at: Date())
        return budget
    }

    // MARK: - Create

    func create(_ budget: Budget) async throws {
        let dto = BudgetMapper.toDTO(budget)
        let sql = """
        INSERT INTO budgets (id, book_id, name, note, period, category_ids, anchor_date, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.bookID,
            dto.name,
            dto.note ?? NSNull(),
            dto.period,
            dto.categoryIDs,
            dto.anchorDate,
            dto.createdAt
        ])
    }

    // MARK: - Update

    func update(_ budget: Budget) async throws {
        let dto = BudgetMapper.toDTO(budget)
        let sql = """
        UPDATE budgets
        SET name = ?, note = ?, period = ?, category_ids = ?, anchor_date = ?
        WHERE id = ?;
        """
        try db.execute(sql: sql, parameters: [
            dto.name,
            dto.note ?? NSNull(),
            dto.period,
            dto.categoryIDs,
            dto.anchorDate,
            dto.id
        ])
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        let sql = "DELETE FROM budgets WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }

    // MARK: - Versions

    func fetchVersions(for budgetID: UUID) async throws -> [BudgetVersion] {
        let sql = """
        SELECT id, budget_id, amount, effective_from, note
        FROM budget_versions
        WHERE budget_id = ?
        ORDER BY effective_from DESC;
        """
        let rows = try db.query(sql: sql, parameters: [budgetID.uuidString])
        return rows.compactMap { BudgetMapper.versionFromRow($0) }
    }

    func createVersion(_ version: BudgetVersion) async throws {
        let dto = BudgetMapper.toDTO(version)
        let sql = """
        INSERT INTO budget_versions (id, budget_id, amount, effective_from, note)
        VALUES (?, ?, ?, ?, ?);
        """
        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.budgetID,
            dto.amount,
            dto.effectiveFrom,
            dto.note ?? NSNull()
        ])
    }

    func deleteVersion(id: UUID) async throws {
        let sql = "DELETE FROM budget_versions WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }

    /// Returns the version whose effectiveFrom is the latest date <= `date` (day-level comparison).
    func currentVersion(for budgetID: UUID, at date: Date) async throws -> BudgetVersion? {
        // Normalize to start-of-day so time components in effectiveFrom don't cause mismatches.
        let dayStart = Calendar.current.startOfDay(for: date)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sql = """
        SELECT id, budget_id, amount, effective_from, note
        FROM budget_versions
        WHERE budget_id = ? AND date(effective_from) <= date(?)
        ORDER BY effective_from DESC
        LIMIT 1;
        """
        let rows = try db.query(sql: sql, parameters: [budgetID.uuidString, iso.string(from: dayStart)])
        return rows.first.flatMap { BudgetMapper.versionFromRow($0) }
    }
}
