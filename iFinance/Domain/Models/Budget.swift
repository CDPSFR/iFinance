import Foundation

// MARK: - BudgetPeriod

enum BudgetPeriod: String, Codable, CaseIterable {
    case daily           = "daily"
    case weekly          = "weekly"
    case everyTwoWeeks   = "everyTwoWeeks"
    case everyThreeWeeks = "everyThreeWeeks"
    case everyFourWeeks  = "everyFourWeeks"
    case monthly         = "monthly"
    case everyTwoMonths  = "everyTwoMonths"
    case quarterly       = "quarterly"
    case semiAnnual      = "semiAnnual"

    var displayName: String {
        switch self {
        case .daily:           return "Quotidien"
        case .weekly:          return "Hebdomadaire"
        case .everyTwoWeeks:   return "Toutes les 2 semaines"
        case .everyThreeWeeks: return "Toutes les 3 semaines"
        case .everyFourWeeks:  return "Toutes les 4 semaines"
        case .monthly:         return "Mensuel"
        case .everyTwoMonths:  return "Tous les 2 mois"
        case .quarterly:       return "Trimestriel"
        case .semiAnnual:      return "Semestriel"
        }
    }

    /// Returns the (start, end) of the current window given an anchor date.
    func currentWindow(anchor: Date, relativeTo now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        switch self {
        case .daily:
            let start = calendar.startOfDay(for: now)
            let end   = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .weekly, .everyTwoWeeks, .everyThreeWeeks, .everyFourWeeks:
            let weeks: Int
            switch self {
            case .everyTwoWeeks:   weeks = 2
            case .everyThreeWeeks: weeks = 3
            case .everyFourWeeks:  weeks = 4
            default:               weeks = 1
            }
            return periodicWindow(anchor: anchor, now: now, intervalDays: weeks * 7, calendar: calendar)

        case .monthly:
            let anchorDay = calendar.component(.day, from: anchor)
            var start = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))!
            start = calendar.date(bySetting: .day, value: anchorDay, of: start) ?? start
            while start > now {
                start = calendar.date(byAdding: .month, value: -1, to: start)!
            }
            var next = calendar.date(byAdding: .month, value: 1, to: start)!
            while next <= now {
                start = next
                next = calendar.date(byAdding: .month, value: 1, to: start)!
            }
            return (start, next)

        case .everyTwoMonths:
            return multiMonthWindow(anchor: anchor, now: now, months: 2, calendar: calendar)
        case .quarterly:
            return multiMonthWindow(anchor: anchor, now: now, months: 3, calendar: calendar)
        case .semiAnnual:
            return multiMonthWindow(anchor: anchor, now: now, months: 6, calendar: calendar)
        }
    }

    private func periodicWindow(anchor: Date, now: Date, intervalDays: Int, calendar: Calendar) -> (Date, Date) {
        let anchorStart = calendar.startOfDay(for: anchor)
        let nowStart    = calendar.startOfDay(for: now)
        let diff = calendar.dateComponents([.day], from: anchorStart, to: nowStart).day ?? 0
        let periods = max(0, diff / intervalDays)
        let start = calendar.date(byAdding: .day, value: periods * intervalDays, to: anchorStart)!
        let end   = calendar.date(byAdding: .day, value: intervalDays, to: start)!
        return (start, end)
    }

    private func multiMonthWindow(anchor: Date, now: Date, months: Int, calendar: Calendar) -> (Date, Date) {
        var start = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: anchor))!
        while start > now {
            start = calendar.date(byAdding: .month, value: -months, to: start)!
        }
        var next = calendar.date(byAdding: .month, value: months, to: start)!
        while next <= now {
            start = next
            next = calendar.date(byAdding: .month, value: months, to: start)!
        }
        return (start, next)
    }
}

// MARK: - Budget

struct Budget: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var bookID: UUID
    var name: String
    var note: String?
    var period: BudgetPeriod
    var categoryIDs: [UUID]
    var anchorDate: Date
    var createdAt: Date
    var currentVersion: BudgetVersion?

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String,
        note: String? = nil,
        period: BudgetPeriod,
        categoryIDs: [UUID] = [],
        anchorDate: Date = Date(),
        createdAt: Date = Date(),
        currentVersion: BudgetVersion? = nil
    ) {
        self.id             = id
        self.bookID         = bookID
        self.name           = name
        self.note           = note
        self.period         = period
        self.categoryIDs    = categoryIDs
        self.anchorDate     = anchorDate
        self.createdAt      = createdAt
        self.currentVersion = currentVersion
    }
}

// MARK: - BudgetVersion

struct BudgetVersion: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var budgetID: UUID
    var amount: Decimal
    var effectiveFrom: Date
    var note: String?

    init(
        id: UUID = UUID(),
        budgetID: UUID,
        amount: Decimal,
        effectiveFrom: Date = Date(),
        note: String? = nil
    ) {
        self.id            = id
        self.budgetID      = budgetID
        self.amount        = amount
        self.effectiveFrom = effectiveFrom
        self.note          = note
    }
}
