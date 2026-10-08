import Foundation

/// Mise en page d'un plan selon son type : chaque dispositif a ses propres blocs
enum SavingsPlanPageKind {
    case pee            // Disponibilité à 5 ans, origines, abondement
    case per            // Plafond de déduction, rythme de versement (PER, PERCO / PERECO)
    case article83      // Sortie en rente, cotisations employeur / salarié
    case generic        // Assurance vie et autres plans valorisés

    init(_ type: AccountType) {
        switch type {
        case .pee: self = .pee
        case .retirement, .perco: self = .per
        case .article83: self = .article83
        default: self = .generic
        }
    }
}

// MARK: - Résultats

/// Tranche du calendrier de disponibilité
struct AvailabilityBucket: Identifiable, Equatable {
    enum Kind: Equatable { case available, year(Int), laterYears(Int), retirement, annuity, capitalAfterTransfer }

    var id: String { label }
    let kind: Kind
    let label: String
    let detail: String
    let value: Decimal
}

/// Apports d'une origine sur une année civile
struct YearlyOriginAmount: Identifiable, Equatable {
    var id: String { "\(year)-\(origin.rawValue)" }
    let year: Int
    let origin: ContributionOrigin
    let amount: Decimal
}

/// Bloc « Abondement de l'année » (PEE)
struct MatchingYear: Equatable {
    let year: Int
    let voluntary: Decimal          // Versements volontaires de l'année
    let matching: Decimal           // Abondement reçu dans l'année
    let accordCap: Decimal?         // Plafond de l'accord, saisi par l'utilisateur
    let legalCap: Decimal           // 8 % du PASS

    var rate: Double? {
        guard voluntary > 0 else { return nil }
        return NSDecimalNumber(decimal: matching / voluntary).doubleValue
    }

    /// Plafond effectif : celui de l'accord, borné par le plafond légal
    var effectiveCap: Decimal { min(accordCap ?? legalCap, legalCap) }
    var remaining: Decimal { max(effectiveCap - matching, 0) }

    /// Versement supplémentaire nécessaire pour capter le reste au taux constaté
    var additionalVoluntaryNeeded: Decimal? {
        guard let rate, rate > 0, remaining > 0 else { return nil }
        return remaining / Decimal(rate)
    }

    /// Règle du triple : l'abondement ne peut dépasser 3 fois les versements du salarié
    var tripleCap: Decimal { voluntary * 3 }
}

/// Une année fiscale du PER : versements déduits face au plafond
struct DeductionYear: Identifiable, Equatable {
    var id: Int { year }
    let year: Int
    let deducted: Decimal           // Versements volontaires déduits
    let ceiling: Decimal            // Plafond de l'année (hors reports)
    let isFloorCeiling: Bool        // Plafond non saisi : plancher légal (10 % du PASS N−1)

    var ratio: Double {
        guard ceiling > 0 else { return 0 }
        return NSDecimalNumber(decimal: deducted / ceiling).doubleValue
    }
}

/// Bloc « Déduction fiscale de l'année » (PER)
struct DeductionStatus: Equatable {
    let year: Int
    let deducted: Decimal
    let ceiling: Decimal
    let isFloorCeiling: Bool
    let carriedOver: Decimal                // Plafonds des années précédentes encore utilisables (avant versements)
    let carriedOverFirstYear: Int?
    let carriedOverLastYear: Int?
    let remaining: Decimal                  // Reste déductible cette année
    let expiringThisYear: Decimal           // Partie du reste perdue au 31 décembre
    let expiringYear: Int?                  // Année d'origine de cette partie
    let marginalTaxRate: Double?
    let history: [DeductionYear]            // Années récentes, la plus récente d'abord

    var taxSaving: Decimal? {
        marginalTaxRate.map { deducted * Decimal($0) }
    }

    var totalCeiling: Decimal { ceiling + carriedOver }
}

/// Bloc « Rythme de versement » (PER)
struct ContributionPace: Equatable {
    struct Month: Identifiable, Equatable {
        var id: Date { start }
        let start: Date
        let amount: Decimal
    }

    let months: [Month]                     // 12 derniers mois, du plus ancien au mois en cours
    let usualAmount: Decimal?               // Montant le plus fréquent
    let paidMonths: Int
    let total: Decimal
    let lastContribution: Date?

    var missedMonths: [Month] { months.filter { $0.amount == 0 } }
}

// MARK: - Calculs

enum RetirementPlanAnalytics {

    // MARK: Disponibilité

    /// Calendrier de disponibilité exprimé en valeur : la valeur bloquée est répartie au prorata des montants versés
    static func availabilityBuckets(
        summary: SavingsPlanSummary,
        kind: SavingsPlanPageKind,
        calendar: Calendar = .current
    ) -> [AvailabilityBucket] {
        var buckets: [AvailabilityBucket] = [
            AvailabilityBucket(
                kind: .available,
                label: "Disponible",
                detail: summary.availableValue > 0 ? "déjà débloqué" : "aucune somme",
                value: summary.availableValue
            )
        ]

        if kind == .article83 {
            // Les cotisations obligatoires sortent en rente, les versements facultatifs en capital après transfert vers un PER
            let mandatory = (summary.totalsByOrigin[.matching] ?? 0) + (summary.totalsByOrigin[.employeeMandatory] ?? 0)
                + (summary.totalsByOrigin[.participation] ?? 0) + (summary.totalsByOrigin[.profitSharing] ?? 0)
                + max(summary.initialBalance, 0)
            let optional = summary.totalsByOrigin[.voluntary] ?? 0
            let total = mandatory + optional
            let annuity = total > 0 ? summary.blockedValue * mandatory / total : summary.blockedValue
            buckets.append(AvailabilityBucket(kind: .annuity, label: "En rente à la retraite", detail: "cotisations obligatoires", value: annuity))
            if optional > 0 {
                buckets.append(AvailabilityBucket(
                    kind: .capitalAfterTransfer,
                    label: "En capital après transfert vers un PER",
                    detail: "versements facultatifs",
                    value: summary.blockedValue - annuity
                ))
            }
            return buckets
        }

        let lockedInvested = summary.unlocks.reduce(Decimal(0)) { $0 + $1.amount }
        guard lockedInvested > 0 else { return buckets }
        let scale = summary.blockedValue / lockedInvested

        // Échéances datées, regroupées par année : 3 années détaillées, puis « et après »
        let dated = summary.unlocks.compactMap { unlock in unlock.date.map { ($0, unlock.amount) } }
        let byYear = Dictionary(grouping: dated) { calendar.component(.year, from: $0.0) }
        let years = byYear.keys.sorted()
        let detailed = years.prefix(3)

        for year in detailed {
            let entries = byYear[year] ?? []
            let dates = Set(entries.map { calendar.startOfDay(for: $0.0) }).sorted()
            let detail = dates.count == 1
                ? "le \(dates[0].formatted(.dateTime.day().month(.wide).year()))"
                : "\(dates.count) échéances, dès le \(dates[0].formatted(.dateTime.day().month(.abbreviated)))"
            let amount = entries.reduce(Decimal(0)) { $0 + $1.1 }
            buckets.append(AvailabilityBucket(kind: .year(year), label: "\(year)", detail: detail, value: amount * scale))
        }

        let later = years.dropFirst(3)
        if let first = later.first {
            let entries = later.flatMap { byYear[$0] ?? [] }
            let firstDate = entries.map { $0.0 }.min() ?? Date()
            let amount = entries.reduce(Decimal(0)) { $0 + $1.1 }
            buckets.append(AvailabilityBucket(
                kind: .laterYears(first),
                label: "\(first) et après",
                detail: "à partir de \(firstDate.formatted(.dateTime.month(.wide).year()))",
                value: amount * scale
            ))
        }

        let atRetirement = summary.unlocks.filter { $0.date == nil }.reduce(Decimal(0)) { $0 + $1.amount }
        if atRetirement > 0 {
            buckets.append(AvailabilityBucket(kind: .retirement, label: "À la retraite", detail: "date non fixée", value: atRetirement * scale))
        }

        return buckets
    }

    // MARK: Origines

    /// Apports par année et par origine (hors solde initial et retraits)
    static func yearlyOrigins(flows: [PlanFlow], calendar: Calendar = .current) -> [YearlyOriginAmount] {
        var totals: [Int: [ContributionOrigin: Decimal]] = [:]
        for flow in flows where flow.isContribution && !flow.isInitialBalance {
            guard let origin = flow.origin else { continue }
            totals[calendar.component(.year, from: flow.date), default: [:]][origin, default: 0] += flow.amount
        }
        return totals.keys.sorted().flatMap { year in
            ContributionOrigin.allCases.compactMap { origin in
                totals[year]?[origin].map { YearlyOriginAmount(year: year, origin: origin, amount: $0) }
            }
        }
    }

    /// Apports d'une année, par origine
    static func contributions(
        flows: [PlanFlow],
        year: Int,
        origins: Set<ContributionOrigin>,
        calendar: Calendar = .current
    ) -> Decimal {
        flows
            .filter { $0.isContribution && calendar.component(.year, from: $0.date) == year }
            .filter { flow in flow.origin.map { origins.contains($0) } ?? false }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    // MARK: Abondement (PEE)

    static func matchingYear(
        flows: [PlanFlow],
        settings: SavingsPlanSettings,
        accountType: AccountType,
        year: Int
    ) -> MatchingYear {
        MatchingYear(
            year: year,
            voluntary: contributions(flows: flows, year: year, origins: [.voluntary]),
            matching: contributions(flows: flows, year: year, origins: [.matching]),
            accordCap: settings.matchingCap,
            legalCap: accountType == .perco ? PASS.percoMatchingCap(year: year) : PASS.peeMatchingCap(year: year)
        )
    }

    // MARK: Déduction (PER)

    /// Versements volontaires déduits de l'année
    static func deductedContributions(flows: [PlanFlow], year: Int, calendar: Calendar = .current) -> Decimal {
        flows
            .filter { $0.isContribution && $0.origin == .voluntary && $0.isDeducted }
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Plafond de l'année : celui de l'avis d'impôt s'il est saisi, sinon le plancher légal
    static func ceiling(for year: Int, settings: SavingsPlanSettings) -> (value: Decimal, isFloor: Bool) {
        if let value = settings.deductionCeilings[year] { return (value, false) }
        return (PASS.perDeductionFloor(year: year), true)
    }

    /// Les versements consomment d'abord le plafond de l'année, puis les reports les plus anciens.
    /// Un plafond non utilisé se reporte 3 ans (5 ans pour ceux nés à partir de 2026).
    static func deductionStatus(
        flows: [PlanFlow],
        settings: SavingsPlanSettings,
        year currentYear: Int,
        calendar: Calendar = .current
    ) -> DeductionStatus {
        let flowYears = flows
            .filter { $0.isContribution && $0.origin == .voluntary }
            .map { calendar.component(.year, from: $0.date) }
        let firstYear = min(flowYears.min() ?? currentYear, settings.deductionCeilings.keys.min() ?? currentYear, currentYear)

        var pools: [(year: Int, remaining: Decimal)] = []
        var history: [DeductionYear] = []
        var carriedOverAtStart: Decimal = 0
        var carriedYears: [Int] = []

        for year in firstYear...currentYear {
            // Plafonds expirés
            pools.removeAll { year > $0.year + PASS.perCarryOverYears(ceilingYear: $0.year) }

            if year == currentYear {
                let alive = pools.filter { $0.remaining > 0 }
                carriedOverAtStart = alive.reduce(Decimal(0)) { $0 + $1.remaining }
                carriedYears = alive.map { $0.year }
            }

            let ceiling = self.ceiling(for: year, settings: settings)
            pools.append((year, ceiling.value))

            var toConsume = deductedContributions(flows: flows, year: year, calendar: calendar)
            history.append(DeductionYear(year: year, deducted: toConsume, ceiling: ceiling.value, isFloorCeiling: ceiling.isFloor))

            // D'abord le plafond de l'année (dernier ajouté), puis les plus anciens
            if let last = pools.indices.last {
                let used = min(pools[last].remaining, toConsume)
                pools[last].remaining -= used
                toConsume -= used
            }
            for index in pools.indices.dropLast() where toConsume > 0 {
                let used = min(pools[index].remaining, toConsume)
                pools[index].remaining -= used
                toConsume -= used
            }
        }

        let remaining = pools.reduce(Decimal(0)) { $0 + $1.remaining }
        let expiring = pools.filter { $0.year < currentYear && $0.year + PASS.perCarryOverYears(ceilingYear: $0.year) == currentYear && $0.remaining > 0 }
        let current = ceiling(for: currentYear, settings: settings)

        return DeductionStatus(
            year: currentYear,
            deducted: deductedContributions(flows: flows, year: currentYear, calendar: calendar),
            ceiling: current.value,
            isFloorCeiling: current.isFloor,
            carriedOver: carriedOverAtStart,
            carriedOverFirstYear: carriedYears.min(),
            carriedOverLastYear: carriedYears.max(),
            remaining: remaining,
            expiringThisYear: expiring.reduce(Decimal(0)) { $0 + $1.remaining },
            expiringYear: expiring.map { $0.year }.min(),
            marginalTaxRate: settings.marginalTaxRate,
            history: Array(history.suffix(5).reversed())
        )
    }

    // MARK: Rythme (PER)

    static func pace(flows: [PlanFlow], asOf now: Date = Date(), calendar: Calendar = .current) -> ContributionPace {
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let starts = (0..<12).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: currentMonth) }
        let voluntary = flows.filter { $0.isContribution && $0.origin == .voluntary }

        let months = starts.map { start -> ContributionPace.Month in
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let amount = voluntary.filter { $0.date >= start && $0.date < end }.reduce(Decimal(0)) { $0 + $1.amount }
            return ContributionPace.Month(start: start, amount: amount)
        }

        let paid = months.filter { $0.amount > 0 }
        let frequencies = Dictionary(grouping: paid.map(\.amount)) { $0 }.mapValues(\.count)
        let usual = frequencies.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }?.key

        return ContributionPace(
            months: months,
            usualAmount: usual,
            paidMonths: paid.count,
            total: months.reduce(Decimal(0)) { $0 + $1.amount },
            lastContribution: voluntary.filter { $0.date <= now }.map(\.date).max()
        )
    }

    /// Projection des versements déduits à la fin de l'année au rythme habituel
    static func projectedYearEnd(deducted: Decimal, pace: ContributionPace, asOf now: Date = Date(), calendar: Calendar = .current) -> Decimal {
        guard let usual = pace.usualAmount else { return deducted }
        let month = calendar.component(.month, from: now)
        return deducted + usual * Decimal(12 - month)
    }

    // MARK: Relevés

    /// Évolution entre deux relevés, hors apports et retraits de la période
    static func performance(from previous: ValuationSnapshot, to snapshot: ValuationSnapshot, flows: [PlanFlow]) -> (ratio: Double, hasFlows: Bool)? {
        guard previous.value > 0 else { return nil }
        let between = flows
            .filter { $0.date > previous.date && $0.date <= snapshot.date }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let gain = snapshot.value - previous.value - between
        return (NSDecimalNumber(decimal: gain / previous.value).doubleValue, between != 0)
    }
}
