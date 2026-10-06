import Foundation

// MARK: - Fréquence

extension RecurrenceFrequency {
    /// Fréquences proposées à la saisie (les autres valeurs restent lisibles en base)
    static let offered: [RecurrenceFrequency] = [.weekly, .monthly, .quarterly, .yearly]

    var displayName: String {
        switch self {
        case .daily: return "Chaque jour"
        case .weekly: return "Chaque semaine"
        case .biweekly: return "Toutes les 2 semaines"
        case .monthly: return "Chaque mois"
        case .quarterly: return "Chaque trimestre"
        case .yearly: return "Chaque année"
        }
    }

    /// Libellé court pour le sélecteur du formulaire
    var shortName: String {
        switch self {
        case .daily: return "Jour"
        case .weekly: return "Semaine"
        case .biweekly: return "2 semaines"
        case .monthly: return "Mois"
        case .quarterly: return "Trimestre"
        case .yearly: return "Année"
        }
    }

    /// Nombre moyen d'échéances par mois, pour ramener un montant à son équivalent mensuel
    var occurrencesPerMonth: Decimal {
        switch self {
        case .daily: return Decimal(365) / 12
        case .weekly: return Decimal(52) / 12
        case .biweekly: return Decimal(26) / 12
        case .monthly: return 1
        case .quarterly: return Decimal(1) / 3
        case .yearly: return Decimal(1) / 12
        }
    }

    /// Échéance suivante. `anchorDay` est le jour du mois voulu (1-31) : il évite qu'une
    /// échéance du 31 glisse définitivement au 28 après février.
    func next(after date: Date, anchorDay: Int? = nil, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly:
            return Self.addMonths(1, to: date, anchorDay: anchorDay, calendar: calendar)
        case .quarterly:
            return Self.addMonths(3, to: date, anchorDay: anchorDay, calendar: calendar)
        case .yearly:
            return Self.addMonths(12, to: date, anchorDay: anchorDay, calendar: calendar)
        }
    }

    private static func addMonths(_ months: Int, to date: Date, anchorDay: Int?, calendar: Calendar) -> Date {
        guard let shifted = calendar.date(byAdding: .month, value: months, to: date) else { return date }
        guard let anchorDay, let range = calendar.range(of: .day, in: .month, for: shifted) else { return shifted }
        var components = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: shifted)
        components.day = min(anchorDay, range.count)
        return calendar.date(from: components) ?? shifted
    }
}

// MARK: - Récurrence

extension RecurringTemplate {
    /// Les échéances sont des dates sans heure : prochaine échéance, début et fin
    /// sont ramenés au début de leur journée.
    func normalizedToDays(calendar: Calendar = .current) -> RecurringTemplate {
        var template = self
        template.nextDueDate = calendar.startOfDay(for: nextDueDate)
        template.startDate = calendar.startOfDay(for: startDate)
        template.endDate = endDate.map { calendar.startOfDay(for: $0) }
        return template
    }

    /// Montant signé : négatif pour une dépense, positif pour un revenu
    var signedAmount: Decimal {
        type == .credit ? abs(amount) : -abs(amount)
    }

    /// Équivalent mensuel signé
    var monthlyAmount: Decimal {
        signedAmount * frequency.occurrencesPerMonth
    }

    func nextDate(after date: Date) -> Date {
        frequency.next(after: date, anchorDay: dayOfMonth)
    }

    /// Règle en clair : « Chaque mois, le 5 », « Chaque année, le 15 oct. »
    var ruleText: String {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return frequency.displayName
        case .weekly, .biweekly:
            let weekday = nextDueDate.formatted(.dateTime.weekday(.wide))
            return "\(frequency.displayName), le \(weekday)"
        case .monthly, .quarterly:
            let day = dayOfMonth ?? calendar.component(.day, from: nextDueDate)
            return "\(frequency.displayName), le \(day)"
        case .yearly:
            return "\(frequency.displayName), le \(nextDueDate.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}

// MARK: - Échéance

/// Échéance calculée d'une récurrence. Elle n'existe pas en base : elle ne devient une
/// transaction (et ne compte dans les soldes) qu'une fois validée.
struct RecurringOccurrence: Identifiable, Hashable {
    let template: RecurringTemplate
    let date: Date
    /// Première échéance non traitée de sa récurrence : la seule que l'on peut valider ou passer
    let isNext: Bool

    var id: String { "\(template.id.uuidString)-\(Int(date.timeIntervalSince1970))" }

    /// Nombre de jours avant l'échéance (négatif si elle est en retard)
    func daysFromToday(calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: Date())
        let due = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: due).day ?? 0
    }

    var isLate: Bool { daysFromToday() < 0 }
    var isDue: Bool { daysFromToday() <= 0 }

    var dueLabel: String {
        let days = daysFromToday()
        switch days {
        case ..<0: return "En retard"
        case 0: return "Aujourd'hui"
        case 1: return "Demain"
        default: return "Dans \(days) jours"
        }
    }
}
