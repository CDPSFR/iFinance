import Foundation

struct InvestmentTransactionDTO {
    let id: String
    let accountID: String
    let positionID: String?
    let date: String
    let type: String
    let symbol: String?
    let quantity: Double?
    let price: Double?
    let amount: Double
    let fees: Double
    let memo: String?
}
