import Foundation

struct ValuationSnapshotMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// Évite le bruit binaire de Decimal(Double) (ex. 100.2 → 100.20000000000000512)
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }

    static func toDTO(_ snapshot: ValuationSnapshot) -> ValuationSnapshotDTO {
        return ValuationSnapshotDTO(
            id: snapshot.id.uuidString,
            accountID: snapshot.accountID.uuidString,
            date: dateFormatter.string(from: snapshot.date),
            value: NSDecimalNumber(decimal: snapshot.value).doubleValue,
            note: snapshot.note
        )
    }

    static func fromDTO(_ dto: ValuationSnapshotDTO) -> ValuationSnapshot? {
        guard let id = UUID(uuidString: dto.id),
              let accountID = UUID(uuidString: dto.accountID),
              let date = dateFormatter.date(from: dto.date) else {
            return nil
        }

        return ValuationSnapshot(
            id: id,
            accountID: accountID,
            date: date,
            value: decimal(dto.value),
            note: dto.note
        )
    }

    static func fromRow(_ row: [String: Any]) -> ValuationSnapshot? {
        guard let id = row["id"] as? String,
              let accountID = row["account_id"] as? String,
              let date = row["date"] as? String,
              let value = row["value"] as? Double else {
            return nil
        }

        return fromDTO(ValuationSnapshotDTO(
            id: id,
            accountID: accountID,
            date: date,
            value: value,
            note: row["note"] as? String
        ))
    }
}
