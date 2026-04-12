import Foundation

struct BudgetDTO {
    let id: String
    let bookID: String
    let name: String
    let note: String?
    let period: String
    let categoryIDs: String   // JSON-encoded [String]
    let anchorDate: String
    let createdAt: String
}

struct BudgetVersionDTO {
    let id: String
    let budgetID: String
    let amount: String        // stored as TEXT for precision
    let effectiveFrom: String
    let note: String?
}
