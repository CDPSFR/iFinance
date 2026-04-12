import Foundation

struct BudgetMapper {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Budget

    static func toDTO(_ budget: Budget) -> BudgetDTO {
        let categoryIDStrings = budget.categoryIDs.map { $0.uuidString }
        let categoryJSON = (try? JSONEncoder().encode(categoryIDStrings)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return BudgetDTO(
            id: budget.id.uuidString,
            bookID: budget.bookID.uuidString,
            name: budget.name,
            note: budget.note,
            period: budget.period.rawValue,
            categoryIDs: categoryJSON,
            anchorDate: iso8601.string(from: budget.anchorDate),
            createdAt: iso8601.string(from: budget.createdAt)
        )
    }

    static func fromDTO(_ dto: BudgetDTO) -> Budget? {
        guard let id     = UUID(uuidString: dto.id),
              let bookID = UUID(uuidString: dto.bookID),
              let period = BudgetPeriod(rawValue: dto.period),
              let anchor = iso8601.date(from: dto.anchorDate),
              let created = iso8601.date(from: dto.createdAt) else { return nil }

        let categoryIDs: [UUID]
        if let data = dto.categoryIDs.data(using: .utf8),
           let strings = try? JSONDecoder().decode([String].self, from: data) {
            categoryIDs = strings.compactMap { UUID(uuidString: $0) }
        } else {
            categoryIDs = []
        }

        return Budget(
            id: id,
            bookID: bookID,
            name: dto.name,
            note: dto.note,
            period: period,
            categoryIDs: categoryIDs,
            anchorDate: anchor,
            createdAt: created
        )
    }

    static func fromRow(_ row: [String: Any]) -> Budget? {
        guard let id       = row["id"] as? String,
              let bookID   = row["book_id"] as? String,
              let name     = row["name"] as? String,
              let period   = row["period"] as? String,
              let catIDs   = row["category_ids"] as? String,
              let anchor   = row["anchor_date"] as? String,
              let created  = row["created_at"] as? String else { return nil }

        let dto = BudgetDTO(
            id: id,
            bookID: bookID,
            name: name,
            note: row["note"] as? String,
            period: period,
            categoryIDs: catIDs,
            anchorDate: anchor,
            createdAt: created
        )
        return fromDTO(dto)
    }

    // MARK: - BudgetVersion

    static func toDTO(_ version: BudgetVersion) -> BudgetVersionDTO {
        BudgetVersionDTO(
            id: version.id.uuidString,
            budgetID: version.budgetID.uuidString,
            amount: "\(version.amount)",
            effectiveFrom: iso8601.string(from: version.effectiveFrom),
            note: version.note
        )
    }

    static func fromDTO(_ dto: BudgetVersionDTO) -> BudgetVersion? {
        guard let id       = UUID(uuidString: dto.id),
              let budgetID = UUID(uuidString: dto.budgetID),
              let amount   = Decimal(string: dto.amount),
              let date     = iso8601.date(from: dto.effectiveFrom) else { return nil }

        return BudgetVersion(
            id: id,
            budgetID: budgetID,
            amount: amount,
            effectiveFrom: date,
            note: dto.note
        )
    }

    static func versionFromRow(_ row: [String: Any]) -> BudgetVersion? {
        guard let id       = row["id"] as? String,
              let budgetID = row["budget_id"] as? String,
              let amount   = row["amount"] as? String,
              let effFrom  = row["effective_from"] as? String else { return nil }

        let dto = BudgetVersionDTO(
            id: id,
            budgetID: budgetID,
            amount: amount,
            effectiveFrom: effFrom,
            note: row["note"] as? String
        )
        return fromDTO(dto)
    }
}
