import Foundation

/// Mouvement d'argent sur un plan (apport, retrait ou solde initial)
struct PlanFlow: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let amount: Decimal                 // Signé : > 0 apport, < 0 retrait / déblocage
    let origin: ContributionOrigin?     // Apports uniquement (nil pour le solde initial)
    let availableOn: Date?              // nil = jusqu'à la retraite
    let transactionID: UUID?            // nil pour le solde initial
    let hasDetail: Bool                 // false = origine / disponibilité déduites par défaut
    var isDeducted: Bool = true         // PER : versement volontaire déduit du revenu imposable

    var isContribution: Bool { amount > 0 }
    var isInitialBalance: Bool { transactionID == nil }
}

struct SavingsPlanHistoryPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let value: Decimal
    let invested: Decimal
}

struct SavingsPlanUnlock: Identifiable, Equatable {
    var id: String { date.map { "\($0.timeIntervalSince1970)" } ?? "retirement" }
    let date: Date?                     // nil = à la retraite
    let amount: Decimal                 // Montant investi qui se débloque
}

struct SavingsPlanSummary: Equatable {
    var value: Decimal = 0                          // Valeur estimée aujourd'hui
    var invested: Decimal = 0                       // Versements nets (solde initial + apports − retraits)
    var gain: Decimal { value - invested }
    var gainRatio: Double? {
        guard invested > 0 else { return nil }
        return Double(truncating: NSDecimalNumber(decimal: gain / invested))
    }

    var lastSnapshot: ValuationSnapshot?
    var flowsSinceSnapshot: Decimal = 0

    var initialBalance: Decimal = 0
    var totalsByOrigin: [ContributionOrigin: Decimal] = [:]
    var withdrawals: Decimal = 0                    // Montant positif

    var availableValue: Decimal = 0
    var blockedValue: Decimal = 0
    var unlocks: [SavingsPlanUnlock] = []           // Échéancier des sommes encore bloquées

    var history: [SavingsPlanHistoryPoint] = []

    var employerContributions: Decimal {
        totalsByOrigin.filter { $0.key.isEmployerFunded }.values.reduce(0, +)
    }
}

/// Calculs purs sur les plans d'épargne valorisés (PEE, PERCO, PER, assurance vie)
enum SavingsPlanCalculator {

    // MARK: - Flux

    /// Mouvements du plan, triés par date, avec origine et disponibilité (saisies ou par défaut)
    static func flows(
        account: Account,
        transactions: [Transaction],
        details: [UUID: ContributionDetail]
    ) -> [PlanFlow] {
        let rule = account.type.availabilityRule
        var result: [PlanFlow] = []

        if account.initialBalance != 0 {
            result.append(PlanFlow(
                id: account.id,
                date: account.createdAt,
                amount: account.initialBalance,
                origin: nil,
                availableOn: rule.defaultAvailability(for: account.createdAt),
                transactionID: nil,
                hasDetail: false
            ))
        }

        for transaction in transactions where transaction.accountID == account.id && transaction.status != .skipped {
            let amount = transaction.signedAmount
            guard amount != 0 else { continue }
            let detail = details[transaction.id]
            let isContribution = amount > 0
            result.append(PlanFlow(
                id: transaction.id,
                date: transaction.date,
                amount: amount,
                origin: isContribution ? (detail?.origin ?? defaultOrigin(for: transaction)) : nil,
                availableOn: detail.map { $0.availableOn } ?? rule.defaultAvailability(for: transaction.date),
                transactionID: transaction.id,
                hasDetail: detail != nil,
                isDeducted: detail?.isDeducted ?? true
            ))
        }

        return result.sorted { $0.date < $1.date }
    }

    /// Un virement entrant vient de l'épargnant, un crédit de l'entreprise
    static func defaultOrigin(for transaction: Transaction) -> ContributionOrigin {
        transaction.type == .transfer ? .voluntary : .matching
    }

    // MARK: - Synthèse

    static func summary(
        account: Account,
        transactions: [Transaction],
        valuations: [ValuationSnapshot],
        details: [UUID: ContributionDetail],
        asOf now: Date = Date()
    ) -> SavingsPlanSummary {
        let planFlows = flows(account: account, transactions: transactions, details: details)
        let snapshots = valuations.sorted { $0.date < $1.date }
        var summary = SavingsPlanSummary()

        summary.invested = planFlows.reduce(0) { $0 + $1.amount }
        summary.lastSnapshot = snapshots.last { $0.date <= now } ?? snapshots.last
        summary.value = estimatedValue(flows: planFlows, snapshots: snapshots, at: now)
        if let snapshot = summary.lastSnapshot {
            summary.flowsSinceSnapshot = planFlows.filter { $0.date > snapshot.date }.reduce(0) { $0 + $1.amount }
        }

        for flow in planFlows {
            if flow.isInitialBalance {
                summary.initialBalance += flow.amount
            } else if let origin = flow.origin {
                summary.totalsByOrigin[origin, default: 0] += flow.amount
            } else {
                summary.withdrawals += -flow.amount
            }
        }

        applyAvailability(flows: planFlows, to: &summary, asOf: now)

        if !snapshots.isEmpty {
            summary.history = snapshots.map { snapshot in
                SavingsPlanHistoryPoint(
                    date: snapshot.date,
                    value: snapshot.value,
                    invested: invested(flows: planFlows, at: snapshot.date)
                )
            }
            if let last = snapshots.last, last.date < now {
                summary.history.append(SavingsPlanHistoryPoint(date: now, value: summary.value, invested: summary.invested))
            }
        }

        return summary
    }

    /// Dernière valeur relevée + mouvements postérieurs. Sans relevé : versements nets.
    static func estimatedValue(flows: [PlanFlow], snapshots: [ValuationSnapshot], at date: Date) -> Decimal {
        guard let snapshot = snapshots.last(where: { $0.date <= date }) else {
            return invested(flows: flows, at: date)
        }
        let since = flows
            .filter { $0.date > snapshot.date && $0.date <= date }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return snapshot.value + since
    }

    static func invested(flows: [PlanFlow], at date: Date) -> Decimal {
        flows.filter { $0.date <= date }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Disponibilité

    /// Les retraits consomment d'abord les sommes disponibles le plus tôt ; la valeur est
    /// répartie entre disponible et bloqué au prorata des montants investis restants.
    private static func applyAvailability(flows: [PlanFlow], to summary: inout SavingsPlanSummary, asOf now: Date) {
        var buckets = flows
            .filter { $0.isContribution }
            .map { (availableOn: $0.availableOn, remaining: $0.amount) }
            .sorted { lhs, rhs in
                switch (lhs.availableOn, rhs.availableOn) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                default: return false
                }
            }

        var toConsume = flows.filter { !$0.isContribution }.reduce(Decimal(0)) { $0 - $1.amount }
        for index in buckets.indices where toConsume > 0 {
            let used = min(buckets[index].remaining, toConsume)
            buckets[index].remaining -= used
            toConsume -= used
        }

        let isAvailable: (Date?) -> Bool = { date in date.map { $0 <= now } ?? false }
        let availableInvested = buckets.filter { isAvailable($0.availableOn) }.reduce(Decimal(0)) { $0 + $1.remaining }
        let totalInvested = buckets.reduce(Decimal(0)) { $0 + $1.remaining }

        if totalInvested > 0 {
            summary.availableValue = summary.value * availableInvested / totalInvested
            summary.blockedValue = summary.value - summary.availableValue
        } else {
            summary.availableValue = summary.value
            summary.blockedValue = 0
        }

        var unlocks: [Date?: Decimal] = [:]
        for bucket in buckets where bucket.remaining > 0 && !isAvailable(bucket.availableOn) {
            let key = bucket.availableOn.map { Calendar.current.startOfDay(for: $0) }
            unlocks[key, default: 0] += bucket.remaining
        }
        summary.unlocks = unlocks
            .map { SavingsPlanUnlock(date: $0.key, amount: $0.value) }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                default: return false
                }
            }
    }
}
