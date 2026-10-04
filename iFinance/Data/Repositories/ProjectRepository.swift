import Foundation

protocol ProjectRepositoryProtocol {
    func fetchAll(for bookID: UUID) async throws -> [Project]
    func create(_ project: Project) async throws
    func update(_ project: Project) async throws
    func delete(id: UUID) async throws
}

class ProjectRepository: ProjectRepositoryProtocol {
    private let db: SQLiteManager

    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let dateFormatter = ISO8601DateFormatter()

    init(db: SQLiteManager) {
        self.db = db
    }

    func fetchAll(for bookID: UUID) async throws -> [Project] {
        let sql = """
        SELECT id, book_id, name, color, start_date, end_date, budget, is_completed, note, created_at
        FROM projects
        WHERE book_id = ?
        ORDER BY name ASC;
        """

        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { Self.project(from: $0) }
    }

    func create(_ project: Project) async throws {
        let sql = """
        INSERT INTO projects (id, book_id, name, color, start_date, end_date, budget, is_completed, note, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            project.id.uuidString,
            project.bookID.uuidString,
            project.name,
            project.color ?? NSNull(),
            Self.text(project.startDate),
            Self.text(project.endDate),
            Self.text(project.budget),
            project.isCompleted ? 1 : 0,
            project.note ?? NSNull(),
            Self.dateFormatter.string(from: project.createdAt)
        ] as [Any])
    }

    func update(_ project: Project) async throws {
        let sql = """
        UPDATE projects
        SET name = ?, color = ?, start_date = ?, end_date = ?, budget = ?, is_completed = ?, note = ?
        WHERE id = ?;
        """

        try db.execute(sql: sql, parameters: [
            project.name,
            project.color ?? NSNull(),
            Self.text(project.startDate),
            Self.text(project.endDate),
            Self.text(project.budget),
            project.isCompleted ? 1 : 0,
            project.note ?? NSNull(),
            project.id.uuidString
        ] as [Any])
    }

    /// Supprime le projet et détache ses transactions (elles ne sont pas supprimées)
    func delete(id: UUID) async throws {
        try db.execute(sql: "UPDATE transactions SET project_id = NULL WHERE project_id = ?;", parameters: [id.uuidString])
        try db.execute(sql: "DELETE FROM projects WHERE id = ?;", parameters: [id.uuidString])
    }

    // MARK: - Conversion

    private static func text(_ date: Date?) -> Any {
        date.map { dateFormatter.string(from: $0) } ?? NSNull()
    }

    private static func text(_ amount: Decimal?) -> Any {
        amount.map { NSDecimalNumber(decimal: $0).description(withLocale: posix) } ?? NSNull()
    }

    private static func project(from row: [String: Any]) -> Project? {
        guard let idString = row["id"] as? String, let id = UUID(uuidString: idString),
              let bookString = row["book_id"] as? String, let bookID = UUID(uuidString: bookString),
              let name = row["name"] as? String else {
            return nil
        }

        return Project(
            id: id,
            bookID: bookID,
            name: name,
            color: row["color"] as? String,
            startDate: (row["start_date"] as? String).flatMap { dateFormatter.date(from: $0) },
            endDate: (row["end_date"] as? String).flatMap { dateFormatter.date(from: $0) },
            budget: (row["budget"] as? String).flatMap { Decimal(string: $0, locale: posix) },
            isCompleted: (row["is_completed"] as? Int64 ?? 0) == 1,
            note: row["note"] as? String,
            createdAt: (row["created_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
        )
    }
}
