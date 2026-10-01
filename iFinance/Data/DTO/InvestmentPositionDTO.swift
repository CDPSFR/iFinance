import Foundation

struct InvestmentPositionDTO {
    let id: String
    let accountID: String
    let symbol: String
    let name: String
    let quantity: Double
    let averageCost: Double
    let currentPrice: Double?
    let currency: String
    let assetType: String
    let lastUpdated: String?
}
