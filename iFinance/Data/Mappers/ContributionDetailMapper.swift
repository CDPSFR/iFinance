import Foundation

struct ContributionDetailMapper {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    static func toDTO(_ detail: ContributionDetail) -> ContributionDetailDTO {
        return ContributionDetailDTO(
            transactionID: detail.transactionID.uuidString,
            origin: detail.origin.rawValue,
            availableOn: detail.availableOn.map { dateFormatter.string(from: $0) }
        )
    }

    static func fromDTO(_ dto: ContributionDetailDTO) -> ContributionDetail? {
        guard let transactionID = UUID(uuidString: dto.transactionID),
              let origin = ContributionOrigin(rawValue: dto.origin) else {
            return nil
        }

        return ContributionDetail(
            transactionID: transactionID,
            origin: origin,
            availableOn: dto.availableOn.flatMap { dateFormatter.date(from: $0) }
        )
    }

    static func fromRow(_ row: [String: Any]) -> ContributionDetail? {
        guard let transactionID = row["transaction_id"] as? String,
              let origin = row["origin"] as? String else {
            return nil
        }

        return fromDTO(ContributionDetailDTO(
            transactionID: transactionID,
            origin: origin,
            availableOn: row["available_on"] as? String
        ))
    }
}
