import Foundation

struct AccountDTO {
    let id: String
    let bookID: String
    let name: String
    let bank: String?
    let type: String
    let initialBalance: Double
    let currency: String
    let isClosed: Bool
    let createdAt: String
}
