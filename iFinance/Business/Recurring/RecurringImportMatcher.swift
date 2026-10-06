import Foundation

/// Correspondance entre une ligne importée et une récurrence du compte
enum RecurringImportMatch: Equatable {
    /// La ligne règle une échéance en attente : elle sera rattachée à la récurrence, qui avancera
    case occurrence(template: RecurringTemplate, dueDate: Date)
    /// L'échéance a déjà été saisie (automatiquement ou validée) : la ligne ferait doublon
    case alreadyPosted(template: RecurringTemplate, transactionID: UUID)

    var template: RecurringTemplate {
        switch self {
        case .occurrence(let template, _), .alreadyPosted(let template, _): return template
        }
    }
}

/// Rapproche les lignes d'un import des récurrences du compte de destination.
///
/// Une ligne correspond à une échéance si elle est sur le même compte, dans le même sens,
/// à quelques jours de l'échéance, et du même montant (n'importe quel montant pour une
/// récurrence à montant variable, à condition que le bénéficiaire corresponde). Entre plusieurs
/// lignes possibles, celle dont le bénéficiaire correspond l'emporte, puis la plus proche en date.
/// Les échéances en attente sont rapprochées dans l'ordre : une échéance ne peut l'être que si
/// les précédentes de sa récurrence l'ont été, comme pour une validation à la main.
struct RecurringImportMatcher {
    struct Line {
        var date: Date
        /// Montant signé : négatif pour une dépense
        var amount: Decimal
        var payee: String?
    }

    var templates: [RecurringTemplate]
    /// Transactions déjà présentes sur le compte
    var existingTransactions: [Transaction]
    /// Nom du bénéficiaire d'une récurrence
    var payeeName: (UUID) -> String?
    var calendar: Calendar = .current

    /// Correspondances par indice de ligne. `excluded` : lignes que l'utilisateur a dissociées.
    func matches(for lines: [Line?], accountID: UUID, excluded: Set<Int> = []) -> [Int: RecurringImportMatch] {
        let candidates = lines.indices.filter { lines[$0] != nil && !excluded.contains($0) }
        guard !candidates.isEmpty else { return [:] }
        let accountTemplates = templates.filter { $0.isActive && $0.accountID == accountID && $0.toAccountID == nil }
        var result: [Int: RecurringImportMatch] = [:]

        // 1. Échéances déjà saisies : la ligne du relevé ferait doublon
        var claimedTransactions = Set<UUID>()
        for template in accountTemplates {
            let posted = existingTransactions.filter { $0.recurringTemplateID == template.id && $0.accountID == accountID }
            for transaction in posted.sorted(by: { $0.date < $1.date }) {
                let best = candidates
                    .filter { result[$0] == nil && matches(lines[$0]!, template: template, near: transaction.date, postedAmount: transaction.amount) }
                    .min { rank(lines[$0]!, template, transaction.date) < rank(lines[$1]!, template, transaction.date) }
                if let best, claimedTransactions.insert(transaction.id).inserted {
                    result[best] = .alreadyPosted(template: template, transactionID: transaction.id)
                }
            }
        }

        // 2. Échéances en attente, dans l'ordre, jusqu'à la dernière date du fichier
        let lastDate = candidates.compactMap { lines[$0]?.date }.max() ?? Date()
        for template in accountTemplates {
            let tolerance = toleranceDays(template.frequency)
            let horizon = calendar.date(byAdding: .day, value: tolerance, to: lastDate) ?? lastDate
            var dueDate = template.nextDueDate
            var guardCount = 0
            while dueDate <= horizon, guardCount < 400 {
                if let endDate = template.endDate, dueDate > endDate { break }
                let best = candidates
                    .filter { result[$0] == nil && matches(lines[$0]!, template: template, near: dueDate, postedAmount: nil) }
                    .min { rank(lines[$0]!, template, dueDate) < rank(lines[$1]!, template, dueDate) }
                guard let best else { break }
                result[best] = .occurrence(template: template, dueDate: dueDate)
                dueDate = template.nextDate(after: dueDate)
                guardCount += 1
            }
        }

        return result
    }

    // MARK: - Critères

    private func matches(_ line: Line, template: RecurringTemplate, near date: Date, postedAmount: Decimal?) -> Bool {
        let lineType: TransactionType = line.amount >= 0 ? .credit : .debit
        guard lineType == template.type,
              distance(line.date, date) <= toleranceDays(template.frequency) else { return false }

        if template.isVariableAmount {
            return payeeMatches(line.payee, template: template) == true
        }
        // Montant identique : les libellés bancaires (« VIR LOYER ») diffèrent souvent du bénéficiaire
        return abs(line.amount) == abs(postedAmount ?? template.amount)
    }

    /// Ordre de préférence entre lignes candidates : bénéficiaire reconnu, puis proximité de date
    private func rank(_ line: Line, _ template: RecurringTemplate, _ date: Date) -> (Int, Int) {
        (payeeMatches(line.payee, template: template) == true ? 0 : 1, distance(line.date, date))
    }

    /// true : même bénéficiaire ; false : bénéficiaires différents ; nil : impossible à dire
    private func payeeMatches(_ name: String?, template: RecurringTemplate) -> Bool? {
        guard let name = name.map(Self.normalized), !name.isEmpty,
              let templateName = template.payeeID.flatMap(payeeName).map(Self.normalized), !templateName.isEmpty
        else { return nil }
        if name == templateName { return true }
        // Libellés bancaires : « PRLV SEPA NETFLIX.COM » contient « netflix »
        let shorter = name.count < templateName.count ? name : templateName
        let longer = name.count < templateName.count ? templateName : name
        return shorter.count >= 3 && longer.contains(shorter)
    }

    nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }

    private func distance(_ a: Date, _ b: Date) -> Int {
        abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? .max)
    }

    /// Écart toléré entre la date du relevé et l'échéance, selon la fréquence
    private func toleranceDays(_ frequency: RecurrenceFrequency) -> Int {
        switch frequency {
        case .daily: return 0
        case .weekly: return 2
        case .biweekly: return 3
        case .monthly, .quarterly, .yearly: return 5
        }
    }
}
