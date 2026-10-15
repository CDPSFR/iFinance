import Foundation

/// Lien entre catégories et cases de la déclaration (table category_tax_cases)
class TaxMappingRepository {
    private let db: SQLiteManager

    init(db: SQLiteManager) {
        self.db = db
    }

    func fetchAll() async throws -> [UUID: TaxCase] {
        let rows = try db.query(sql: "SELECT category_id, tax_case FROM category_tax_cases;")
        var result: [UUID: TaxCase] = [:]
        for row in rows {
            guard let idString = row["category_id"] as? String,
                  let id = UUID(uuidString: idString),
                  let caseString = row["tax_case"] as? String,
                  let taxCase = TaxCase(rawValue: caseString) else { continue }
            result[id] = taxCase
        }
        return result
    }

    func set(_ taxCase: TaxCase?, for categoryID: UUID) async throws {
        if let taxCase {
            try db.execute(
                sql: "INSERT OR REPLACE INTO category_tax_cases (category_id, tax_case) VALUES (?, ?);",
                parameters: [categoryID.uuidString, taxCase.rawValue]
            )
        } else {
            try db.execute(sql: "DELETE FROM category_tax_cases WHERE category_id = ?;", parameters: [categoryID.uuidString])
        }
    }
}
