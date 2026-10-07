import Foundation

/// Cours enregistré pour une position à une date donnée
struct PositionPrice: Identifiable, Equatable {
    var id: UUID = UUID()
    var positionID: UUID
    var date: Date
    var price: Decimal
    /// Identifiant du fournisseur, ou « manual » pour une saisie à la main
    var source: String
}

/// Historique des cours (table position_prices) : un cours par position et par jour
class PositionPriceRepository {
    private let db: SQLiteManager

    private static let dateFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(db: SQLiteManager) {
        self.db = db
    }

    /// Enregistre le cours du jour de `date` ; un cours déjà présent ce jour-là est remplacé
    func record(positionID: UUID, price: Decimal, date: Date, source: String) throws {
        let day = Self.dayFormatter.string(from: date)
        // Remplacement en une seule écriture : jamais deux cours ni zéro cours pour ce jour
        try db.inTransaction {
            try db.execute(
                sql: "DELETE FROM position_prices WHERE position_id = ? AND day = ?;",
                parameters: [positionID.uuidString, day]
            )
            try db.execute(
                sql: "INSERT INTO position_prices (id, position_id, day, date, price, source) VALUES (?, ?, ?, ?, ?, ?);",
                parameters: [
                    UUID().uuidString,
                    positionID.uuidString,
                    day,
                    Self.dateFormatter.string(from: date),
                    NSDecimalNumber(decimal: price).doubleValue,
                    source
                ] as [Any]
            )
        }
    }

    func fetchAll(for positionID: UUID) throws -> [PositionPrice] {
        let rows = try db.query(
            sql: "SELECT id, position_id, date, price, source FROM position_prices WHERE position_id = ? ORDER BY day ASC;",
            parameters: [positionID.uuidString]
        )
        return rows.compactMap { row in
            guard let id = (row["id"] as? String).flatMap({ UUID(uuidString: $0) }),
                  let date = (row["date"] as? String).flatMap({ Self.dateFormatter.date(from: $0) }) else { return nil }
            let number = (row["price"] as? Double) ?? (row["price"] as? Int64).map { Double($0) }
            guard let number, let price = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return PositionPrice(id: id, positionID: positionID, date: date, price: price, source: (row["source"] as? String) ?? "manual")
        }
    }

    func deleteAll(for positionID: UUID) throws {
        try db.execute(sql: "DELETE FROM position_prices WHERE position_id = ?;", parameters: [positionID.uuidString])
    }
}
