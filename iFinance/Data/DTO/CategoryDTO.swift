import Foundation

struct CategoryDTO {
    let id: String
    let bookID: String
    let name: String
    let description: String?
    let parentID: String?
    let color: String?
    let icon: String?
    let isIncome: Bool
}
