import SwiftUI

struct TransactionRow: Identifiable {
    let id: UUID
    let date: Date
    let typeIcon: String
    let typeColor: Color
    let accountName: String
    let accountIcon: String
    let payeeName: String?
    let memo: String?
    let categoryName: String?
    let categoryColor: Color?
    let amount: Decimal
    let balance: Decimal
    let currency: String
    
    // Propriétés calculées pour le tri
    var payeeNameForSort: String {
        payeeName ?? memo ?? ""
    }
    
    var categoryNameForSort: String {
        categoryName ?? ""
    }
}
