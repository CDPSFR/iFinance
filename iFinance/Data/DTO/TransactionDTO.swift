import Foundation

struct TransactionDTO {
    let id: String
    let date: String
    let amount: Double
    let accountID: String
    let toAccountID: String?
    let linkedTransactionID: String?
    let payeeID: String?
    let categoryID: String?
    let type: String
    let memo: String?
    let isReconciled: Bool
    let recurringTemplateID: String?
    let status: String
    var projectID: String? = nil
}
