import Foundation

struct Budget: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
        var bookID: UUID
        var categoryID: UUID
        var amount: Decimal
        var period: BudgetPeriod  // .monthly, .yearly
        var startDate: Date
        var endDate: Date?  // nil = récurrent

    enum BudgetPeriod: String, Codable, CaseIterable {
        case weekly = "Hebdomadaire"
        case monthly = "Mensuel"
        case yearly = "Annuel"
    }
}
