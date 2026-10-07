import Foundation

struct TransactionFilters: Equatable {
    var transactionType: TransactionType?
    var accountID: UUID?
    var categoryID: UUID?
    var payeeID: UUID?
    var dateRange: DateRange
    /// Opérations sur titres affichées (en lecture seule) parmi les transactions
    var showInvestmentOperations: Bool = true
    
    enum DateRange: Equatable, Hashable {
        case all
        case today
        case thisWeek
        case thisMonth
        case lastMonth
        case thisYear
        case custom(start: Date, end: Date)
        
        var displayName: String {
            switch self {
            case .all: return "Tout"
            case .today: return "Aujourd'hui"
            case .thisWeek: return "Cette semaine"
            case .thisMonth: return "Ce mois"
            case .lastMonth: return "Mois dernier"
            case .thisYear: return "Cette année"
            case .custom: return "Personnalisé"
            }
        }
        
        func dates() -> (start: Date, end: Date)? {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .all:
                return nil
            case .today:
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                return (start, end)
            case .thisWeek:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
                return (start, end)
            case .thisMonth:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                return (start, end)
            case .lastMonth:
                let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let start = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
                let end = thisMonth
                return (start, end)
            case .thisYear:
                let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
                let end = calendar.date(byAdding: .year, value: 1, to: start)!
                return (start, end)
            case .custom(let start, let end):
                return (start, end)
            }
        }
    }
    
    static var empty: TransactionFilters {
        TransactionFilters(
            transactionType: nil,
            accountID: nil,
            categoryID: nil,
            payeeID: nil,
            dateRange: .all
        )
    }
    
    var isActive: Bool {
        return transactionType != nil ||
               accountID != nil ||
               categoryID != nil ||
               payeeID != nil ||
               dateRange != .all ||
               !showInvestmentOperations
    }
    
    var activeFiltersCount: Int {
        var count = 0
        if transactionType != nil { count += 1 }
        if accountID != nil { count += 1 }
        if categoryID != nil { count += 1 }
        if payeeID != nil { count += 1 }
        if dateRange != .all { count += 1 }
        if !showInvestmentOperations { count += 1 }
        return count
    }
}
