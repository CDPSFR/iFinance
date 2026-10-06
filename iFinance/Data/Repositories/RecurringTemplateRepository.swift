import Foundation

/// Accès aux récurrences (table recurring_templates)
class RecurringTemplateRepository {
    private let db: SQLiteManager

    private static let dateFormatter = ISO8601DateFormatter()
    private static let columns = """
        id, book_id, account_id, to_account_id, payee_id, category_id, amount, type, memo,
        frequency, start_date, end_date, day_of_month, day_of_week, is_active, created_at,
        next_due_date, auto_post, is_variable
        """

    init(db: SQLiteManager) {
        self.db = db
    }

    func fetchAll(for bookID: UUID) async throws -> [RecurringTemplate] {
        let sql = "SELECT \(Self.columns) FROM recurring_templates WHERE book_id = ? ORDER BY created_at ASC;"
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { Self.template(from: $0) }
    }

    func create(_ template: RecurringTemplate) async throws {
        let sql = """
        INSERT INTO recurring_templates (\(Self.columns))
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            template.id.uuidString,
            template.bookID.uuidString,
            template.accountID.uuidString,
            template.toAccountID?.uuidString ?? NSNull(),
            template.payeeID?.uuidString ?? NSNull(),
            template.categoryID?.uuidString ?? NSNull(),
            NSDecimalNumber(decimal: template.amount).doubleValue,
            template.type.rawValue,
            template.memo ?? NSNull(),
            template.frequency.rawValue,
            Self.dateFormatter.string(from: template.startDate),
            Self.text(template.endDate),
            template.dayOfMonth ?? NSNull(),
            template.dayOfWeek ?? NSNull(),
            template.isActive ? 1 : 0,
            Self.dateFormatter.string(from: template.createdAt),
            Self.dateFormatter.string(from: template.nextDueDate),
            template.autoPost ? 1 : 0,
            template.isVariableAmount ? 1 : 0
        ] as [Any])
    }

    func update(_ template: RecurringTemplate) async throws {
        let sql = """
        UPDATE recurring_templates
        SET account_id = ?, to_account_id = ?, payee_id = ?, category_id = ?, amount = ?, type = ?, memo = ?,
            frequency = ?, start_date = ?, end_date = ?, day_of_month = ?, day_of_week = ?, is_active = ?,
            next_due_date = ?, auto_post = ?, is_variable = ?
        WHERE id = ?;
        """

        try db.execute(sql: sql, parameters: [
            template.accountID.uuidString,
            template.toAccountID?.uuidString ?? NSNull(),
            template.payeeID?.uuidString ?? NSNull(),
            template.categoryID?.uuidString ?? NSNull(),
            NSDecimalNumber(decimal: template.amount).doubleValue,
            template.type.rawValue,
            template.memo ?? NSNull(),
            template.frequency.rawValue,
            Self.dateFormatter.string(from: template.startDate),
            Self.text(template.endDate),
            template.dayOfMonth ?? NSNull(),
            template.dayOfWeek ?? NSNull(),
            template.isActive ? 1 : 0,
            Self.dateFormatter.string(from: template.nextDueDate),
            template.autoPost ? 1 : 0,
            template.isVariableAmount ? 1 : 0,
            template.id.uuidString
        ] as [Any])
    }

    /// Supprime la récurrence ; les transactions déjà validées sont conservées et détachées
    func delete(id: UUID) async throws {
        try db.execute(
            sql: "UPDATE transactions SET recurring_template_id = NULL WHERE recurring_template_id = ?;",
            parameters: [id.uuidString]
        )
        try db.execute(sql: "DELETE FROM recurring_templates WHERE id = ?;", parameters: [id.uuidString])
    }

    // MARK: - Conversion

    private static func text(_ date: Date?) -> Any {
        date.map { dateFormatter.string(from: $0) } ?? NSNull()
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap { UUID(uuidString: $0) }
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { dateFormatter.date(from: $0) }
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? Int64).map { Int($0) }
    }

    /// La colonne amount est en REAL : on repasse par deux décimales pour éviter les arrondis binaires
    private static func decimal(_ value: Any?) -> Decimal? {
        let number: Double?
        if let double = value as? Double {
            number = double
        } else if let integer = value as? Int64 {
            number = Double(integer)
        } else if let string = value as? String {
            number = Double(string)
        } else {
            number = nil
        }
        return number.flatMap { Decimal(string: String(format: "%.2f", $0), locale: Locale(identifier: "en_US_POSIX")) }
    }

    private static func template(from row: [String: Any]) -> RecurringTemplate? {
        guard let id = uuid(row["id"]),
              let bookID = uuid(row["book_id"]),
              let accountID = uuid(row["account_id"]),
              let amount = decimal(row["amount"]),
              let type = (row["type"] as? String).flatMap({ TransactionType(rawValue: $0) }),
              let frequency = (row["frequency"] as? String).flatMap({ RecurrenceFrequency(rawValue: $0) }),
              let startDate = date(row["start_date"]) else {
            return nil
        }

        return RecurringTemplate(
            id: id,
            bookID: bookID,
            accountID: accountID,
            toAccountID: uuid(row["to_account_id"]),
            payeeID: uuid(row["payee_id"]),
            categoryID: uuid(row["category_id"]),
            amount: amount,
            type: type,
            memo: row["memo"] as? String,
            frequency: frequency,
            startDate: startDate,
            endDate: date(row["end_date"]),
            dayOfMonth: int(row["day_of_month"]),
            dayOfWeek: int(row["day_of_week"]),
            isActive: (row["is_active"] as? Int64 ?? 1) == 1,
            createdAt: date(row["created_at"]) ?? Date(),
            // Récurrences créées avant l'ajout de la colonne : on repart de la date de début
            nextDueDate: date(row["next_due_date"]) ?? startDate,
            autoPost: (row["auto_post"] as? Int64 ?? 0) == 1,
            isVariableAmount: (row["is_variable"] as? Int64 ?? 0) == 1
        )
    }
}
