import Foundation

/// Variations annuelles des prix téléchargées sur le site de l'INSEE (table price_indices)
class PriceIndexRepository {
    private let db: SQLiteManager

    init(db: SQLiteManager) {
        self.db = db
    }

    func fetchAll() throws -> [InflationPost: [Int: Double]] {
        let rows = try db.query(sql: "SELECT post, year, change FROM price_indices;")
        var result: [InflationPost: [Int: Double]] = [:]
        for row in rows {
            guard let postString = row["post"] as? String,
                  let post = InflationPost(rawValue: postString),
                  let year = row["year"] as? Int64,
                  let change = row["change"] as? Double else { continue }
            result[post, default: [:]][Int(year)] = change
        }
        return result
    }

    func save(_ values: [InflationPost: [Int: Double]]) throws {
        for (post, years) in values {
            for (year, change) in years {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO price_indices (post, year, change) VALUES (?, ?, ?);",
                    parameters: [post.rawValue, year, change]
                )
            }
        }
    }
}
