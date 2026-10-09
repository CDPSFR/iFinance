import Foundation

// MARK: - Pyramide de liquidité

/// Niveau de la pyramide, du plus liquide au moins liquide
enum LiquidityTier: Int, CaseIterable, Identifiable {
    case immediate, days, scheduled, retirement, illiquid, debt

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediate: return "Immédiat"
        case .days: return "Sous quelques jours"
        case .scheduled: return "Selon calendrier"
        case .retirement: return "À la retraite"
        case .illiquid: return "Non liquide"
        case .debt: return "Dettes"
        }
    }

    var detail: String {
        switch self {
        case .immediate: return "comptes courants et livrets"
        case .days: return "vente de titres, rachat, épargne salariale débloquée"
        case .scheduled: return "épargne salariale encore bloquée"
        case .retirement: return "PER, PERCO, article 83"
        case .illiquid: return "biens et comptes « Autre »"
        case .debt: return "prêts et soldes débiteurs"
        }
    }
}

struct LiquidityLine: Identifiable {
    var id: UUID { account.id }
    let account: Account
    let value: Decimal
    let parts: [LiquidityTier: Decimal]
    let availability: String
}

/// Étape du calendrier « Ce qui se libère » : disponible cumulé
struct ReleaseStep: Identifiable {
    var id: String { label }
    let label: String
    let before: Decimal          // Déjà disponible avant l'étape
    let added: Decimal           // Ce qui se libère à l'étape
    let isRetirement: Bool
    var total: Decimal { before + added }
}

struct LiquidityReport {
    var lines: [LiquidityLine] = []
    var tiers: [LiquidityTier: Decimal] = [:]
    var releases: [ReleaseStep] = []
    var monthlyExpenses: Decimal?

    func total(_ tier: LiquidityTier) -> Decimal { tiers[tier] ?? 0 }
    var grossAssets: Decimal { LiquidityTier.allCases.filter { $0 != .debt }.reduce(0) { $0 + total($1) } }
    var financialAssets: Decimal { grossAssets - total(.illiquid) }
    var mobilizable: Decimal { total(.immediate) + total(.days) }
    var netWorth: Decimal { grossAssets + total(.debt) }

    /// Mois de dépenses couverts par l'épargne immédiate
    var coverageMonths: Double? {
        guard let monthlyExpenses, monthlyExpenses > 0 else { return nil }
        return NSDecimalNumber(decimal: total(.immediate) / monthlyExpenses).doubleValue
    }
}

// MARK: - Placements

struct InvestmentReportLine: Identifiable {
    var id: UUID { account.id }
    let account: Account
    let invested: Decimal
    let value: Decimal
    let unrealized: Decimal
    let realized: Decimal
    let income: Decimal              // Depuis l'ouverture
    let income12Months: Decimal
    let fees: Decimal                // Frais d'opérations depuis l'ouverture
    let annualized: Double?
    let feeRate: Double?

    var gain: Decimal { value - invested }
    var annualFeeCost: Decimal? { feeRate.map { value * Decimal($0) } }
}

struct AllocationSlice: Identifiable {
    var id: String { name }
    let name: String
    let value: Decimal
}

struct MonthlyIncome: Identifiable {
    var id: Date { month }
    let month: Date
    let dividends: Decimal
    let interest: Decimal
    var total: Decimal { dividends + interest }
}

/// Échéance fiscale d'une enveloppe : 5 ans du PEA, 8 ans de l'assurance vie
struct EnvelopeMilestone: Identifiable {
    var id: UUID { account.id }
    let account: Account
    let date: Date
    let deposits: Decimal
}

struct InvestmentReport {
    var lines: [InvestmentReportLine] = []
    var byEnvelope: [AllocationSlice] = []
    var byAssetClass: [AllocationSlice] = []
    var byCurrency: [AllocationSlice] = []
    var monthlyIncome: [MonthlyIncome] = []
    var annualized: Double?

    // Fiscalité de l'année
    var realizedThisYear: Decimal = 0          // Comptes-titres
    var dividendsThisYear: Decimal = 0         // Comptes-titres
    var peaFiveYears: [EnvelopeMilestone] = []
    var lifeInsuranceEightYears: [EnvelopeMilestone] = []

    var invested: Decimal { lines.reduce(0) { $0 + $1.invested } }
    var value: Decimal { lines.reduce(0) { $0 + $1.value } }
    var gain: Decimal { value - invested }
    var unrealized: Decimal { lines.reduce(0) { $0 + $1.unrealized } }
    var realized: Decimal { lines.reduce(0) { $0 + $1.realized } }
    var income: Decimal { lines.reduce(0) { $0 + $1.income } }
    var fees: Decimal { lines.reduce(0) { $0 + $1.fees } }
    var income12Months: Decimal { lines.reduce(0) { $0 + $1.income12Months } }
    /// Écart non expliqué par les autres composantes (transferts de titres, plans sans détail…)
    var otherGain: Decimal { gain - unrealized - realized - income + fees }

    var annualFeeCost: Decimal { lines.compactMap(\.annualFeeCost).reduce(0, +) }
    var valueWithFeeRate: Decimal { lines.filter { $0.feeRate != nil }.reduce(0) { $0 + $1.value } }
    var averageFeeRate: Double? {
        guard valueWithFeeRate > 0 else { return nil }
        return NSDecimalNumber(decimal: annualFeeCost / valueWithFeeRate).doubleValue
    }

    /// Manque à gagner des frais sur `years` ans, à rendement brut `grossReturn`, sans nouveau versement
    func feeShortfall(years: Int = 20, grossReturn: Double = 0.05) -> Decimal? {
        guard let rate = averageFeeRate else { return nil }
        let base = NSDecimalNumber(decimal: valueWithFeeRate).doubleValue
        let gross = base * pow(1 + grossReturn, Double(years))
        let net = base * pow(1 + grossReturn - rate, Double(years))
        return Decimal(gross - net)
    }
}

// MARK: - Retraite et épargne salariale

struct RetirementPlanLine: Identifiable {
    var id: UUID { account.id }
    let account: Account
    let summary: SavingsPlanSummary
    let flows: [PlanFlow]
    let settings: SavingsPlanSettings

    var kind: SavingsPlanPageKind { SavingsPlanPageKind(account.type) }
}

/// Colonne du calendrier de disponibilité, par plan
struct RetirementRelease: Identifiable {
    var id: String { label }
    let label: String
    let amounts: [UUID: Decimal]          // Par plan
    let isNow: Bool
    var total: Decimal { amounts.values.reduce(0, +) }
}

struct RetirementAdvantages {
    var matching: Decimal = 0                 // Abondement reçu dans l'année
    var perDeducted: Decimal = 0              // Versements PER déduits
    var employeeSavings: Decimal = 0          // Intéressement et participation placés
    var article83: Decimal = 0                // Cotisations obligatoires article 83
    var marginalTaxRate: Double?

    func taxSaving(_ amount: Decimal) -> Decimal? {
        marginalTaxRate.map { amount * Decimal($0) }
    }

    /// Abondement + impôt évité (si la tranche marginale est connue)
    var total: Decimal {
        matching + (taxSaving(perDeducted + employeeSavings + article83) ?? 0)
    }
}

struct RetirementReport {
    var plans: [RetirementPlanLine] = []
    var releases: [RetirementRelease] = []
    var advantages = RetirementAdvantages()
    var matchingLeft: Decimal?               // Abondement encore possible (plafond d'accord saisi)
    var matchingNeeded: Decimal?             // Versement nécessaire pour le capter
    var expiringCeiling: Decimal = 0         // Plafond PER perdu au 31 décembre
    var expiringCeilingYear: Int?
    var monthlyContributions: Decimal = 0    // Moyenne des 12 derniers mois, tous plans

    var value: Decimal { plans.reduce(0) { $0 + $1.summary.value } }
    var invested: Decimal { plans.reduce(0) { $0 + $1.summary.invested } }
    var available: Decimal { plans.reduce(0) { $0 + $1.summary.availableValue } }

    /// Capital projeté : valeur actuelle et apports mensuels capitalisés au taux annuel `rate`
    func projectedCapital(years: Double, rate: Double, monthlyContribution: Decimal) -> Double {
        let start = NSDecimalNumber(decimal: value).doubleValue
        let yearly = NSDecimalNumber(decimal: monthlyContribution).doubleValue * 12
        guard years > 0 else { return start }
        let growth = pow(1 + rate, years)
        return start * growth + (rate > 0 ? yearly * (growth - 1) / rate : yearly * years)
    }
}

// MARK: - Dettes

struct DebtLine: Identifiable {
    var id: UUID { account.id }
    let account: Account
    let balance: Decimal                 // Capital restant dû (positif)
    let schedule: LoanSchedule?

    var monthlyPayment: Double? { schedule.map { $0.payment + $0.insurance } }
}

struct DebtReport {
    var lines: [DebtLine] = []
    var monthlyIncome: Decimal?          // Revenus mensuels moyens, 12 derniers mois

    var balance: Decimal { lines.reduce(0) { $0 + $1.balance } }
    var monthlyPayments: Double { lines.compactMap(\.monthlyPayment).reduce(0, +) }
    var monthlyInsurance: Double { lines.compactMap { $0.schedule?.insurance }.reduce(0, +) }
    var remainingInterest: Double { lines.compactMap { $0.schedule?.remainingInterest() }.reduce(0, +) }
    var remainingInsurance: Double {
        lines.compactMap { line in line.schedule.map { $0.insurance * Double($0.remainingPayments()) } }.reduce(0, +)
    }
    var endDate: Date? { lines.compactMap { $0.schedule?.endDate }.max() }
    var missingTerms: [DebtLine] { lines.filter { $0.schedule == nil } }

    var debtRatio: Double? {
        guard let monthlyIncome, monthlyIncome > 0 else { return nil }
        return monthlyPayments / NSDecimalNumber(decimal: monthlyIncome).doubleValue
    }

    /// Prêt au taux le plus élevé : à rembourser en premier (méthode « avalanche »)
    var avalancheFirst: DebtLine? {
        lines.filter { $0.schedule != nil && $0.balance > 0 }.max { ($0.schedule?.terms.annualRate ?? 0) < ($1.schedule?.terms.annualRate ?? 0) }
    }
}

// MARK: - Construction

/// Construit les rapports patrimoniaux à partir des contrôleurs (valeurs au jour)
@MainActor
struct LongTermReportBuilder {
    let accountsController: AccountsController
    let transactionsController: TransactionsController
    let investmentsController: InvestmentsController
    let savingsPlansController: SavingsPlansController
    let accountTermsController: AccountTermsController
    var now = Date()
    var calendar = Calendar.current

    private var valuation: AccountValuation {
        AccountValuation(
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController
        )
    }

    /// Comptes ouverts inclus dans le patrimoine net
    private var accounts: [Account] {
        accountsController.activeAccounts.filter { !$0.isExcludedFromReports }
    }

    private var year: Int { calendar.component(.year, from: now) }

    // MARK: Moyennes mensuelles des comptes courants

    /// Moyenne mensuelle des dépenses (ou revenus) des comptes de liquidités, sur les 12 derniers mois
    func monthlyAverage(of type: TransactionType) -> Decimal? {
        guard let start = calendar.date(byAdding: .month, value: -12, to: now) else { return nil }
        let ids = accountsController.cashFlowAccountIDs
        let transactions = transactionsController.allTransactions.filter {
            ids.contains($0.accountID) && $0.status != .skipped && $0.type == type && $0.date >= start && $0.date <= now
        }
        guard let first = transactions.map(\.date).min() else { return nil }
        let months = max(min(calendar.dateComponents([.month], from: first, to: now).month ?? 12, 12), 1)
        let total = transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
        return total / Decimal(months)
    }

    // MARK: Pyramide de liquidité

    func liquidity() -> LiquidityReport {
        var report = LiquidityReport()
        var datedUnlocks: [(date: Date, amount: Decimal)] = []

        for account in accounts {
            let value = valuation.value(of: account)
            var parts: [LiquidityTier: Decimal] = [:]
            var availability = ""

            switch account.type.group {
            case .liquidity:
                parts[value >= 0 ? .immediate : .debt] = value
                availability = value >= 0 ? "Immédiat" : "—"
            case .savings:
                switch account.type {
                case .pel, .termDeposit:
                    parts[.days] = value
                    availability = account.type == .pel ? "Retrait = clôture du plan" : "À l’échéance ou par rupture"
                default:
                    parts[.immediate] = value
                    availability = "Immédiat"
                }
            case .investment:
                parts[.days] = value
                availability = account.type == .pea ? peaAvailability(account) : "Vente des titres"
            case .retirement:
                if account.type == .lifeInsurance {
                    parts[.days] = value
                    availability = "Rachat"
                } else {
                    let summary = valuation.planSummary(of: account)
                    let locked = summary.unlocks.reduce(Decimal(0)) { $0 + $1.amount }
                    let scale = locked > 0 ? summary.blockedValue / locked : 0
                    let dated = summary.unlocks.filter { $0.date != nil }
                    let datedAmount = dated.reduce(Decimal(0)) { $0 + $1.amount } * scale
                    parts[.days] = summary.availableValue
                    parts[.scheduled] = datedAmount
                    parts[.retirement] = summary.blockedValue - datedAmount
                    datedUnlocks += dated.compactMap { unlock in unlock.date.map { (date: $0, amount: unlock.amount * scale) } }
                    availability = planAvailability(summary, scale: scale, currency: account.currency)
                }
            case .debt:
                parts[.debt] = value
                availability = "—"
            case .other:
                parts[value >= 0 ? .illiquid : .debt] = value
                availability = value >= 0 ? "Non liquide" : "—"
            }

            for (tier, amount) in parts {
                report.tiers[tier, default: 0] += amount
            }
            report.lines.append(LiquidityLine(account: account, value: value, parts: parts, availability: availability))
        }

        report.lines.sort { lhs, rhs in
            let l = tierOrder(lhs), r = tierOrder(rhs)
            return l == r ? lhs.value > rhs.value : l < r
        }

        // Ce qui se libère : par année, 4 années détaillées puis « et après », puis la retraite
        var steps: [ReleaseStep] = []
        var cumulative = report.mobilizable
        steps.append(ReleaseStep(label: "Aujourd’hui", before: 0, added: cumulative, isRetirement: false))
        let byYear = Dictionary(grouping: datedUnlocks) { calendar.component(.year, from: $0.date) }
        let years = byYear.keys.sorted()
        for (index, unlockYear) in years.enumerated() {
            if index == 4 {
                let rest = years.dropFirst(4).flatMap { byYear[$0] ?? [] }.reduce(Decimal(0)) { $0 + $1.amount }
                steps.append(ReleaseStep(label: "\(unlockYear) et après", before: cumulative, added: rest, isRetirement: false))
                cumulative += rest
                break
            }
            let amount = (byYear[unlockYear] ?? []).reduce(Decimal(0)) { $0 + $1.amount }
            steps.append(ReleaseStep(label: String(unlockYear), before: cumulative, added: amount, isRetirement: false))
            cumulative += amount
        }
        if report.total(.retirement) > 0 {
            steps.append(ReleaseStep(label: "Retraite", before: cumulative, added: report.total(.retirement), isRetirement: true))
        }
        report.releases = steps
        report.monthlyExpenses = monthlyAverage(of: .debit)
        return report
    }

    private func tierOrder(_ line: LiquidityLine) -> Int {
        line.parts.filter { $0.value != 0 }.keys.map(\.rawValue).min() ?? LiquidityTier.illiquid.rawValue
    }

    private func planAvailability(_ summary: SavingsPlanSummary, scale: Decimal, currency: String) -> String {
        if let next = summary.unlocks.first(where: { $0.date != nil }), let date = next.date {
            let available = summary.availableValue > 0 ? "\(PlanFormat.round(summary.availableValue, currency)) aujourd’hui, " : ""
            return available + "puis \(PlanFormat.round(next.amount * scale, currency)) le \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
        return summary.blockedValue > 0 ? "À la retraite" : "Disponible"
    }

    // MARK: PEA et assurance vie : dates fiscales

    /// Date d'ouverture estimée : date du solde initial, sinon premier mouvement
    func openingDate(of account: Account) -> Date {
        var dates = transactionsController.allTransactions.filter { $0.accountID == account.id }.map(\.date)
        dates += (investmentsController.operations[account.id] ?? []).map(\.date)
        if account.initialBalance != 0, let date = account.initialBalanceDate { dates.append(date) }
        return dates.min() ?? account.initialBalanceDate ?? account.createdAt
    }

    private func peaAvailability(_ account: Account) -> String {
        let fiveYears = calendar.date(byAdding: .year, value: 5, to: openingDate(of: account)) ?? now
        return fiveYears > now
            ? "Retrait = clôture avant le \(fiveYears.formatted(.dateTime.day().month(.abbreviated).year()))"
            : "Vente des titres"
    }

    // MARK: Placements

    func investments() -> InvestmentReport {
        var report = InvestmentReport()
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let selected = accounts.filter { $0.type.group == .investment || $0.type == .lifeInsurance }
        var envelope: [String: Decimal] = [:], assetClass: [String: Decimal] = [:], currency: [String: Decimal] = [:]
        var allOperations: [InvestmentTransaction] = []
        var allFlows: [(date: Date, amount: Decimal)] = []

        for account in selected {
            let value = valuation.value(of: account)
            let cashTransactions = transactionsController.allTransactions.filter { $0.accountID == account.id && $0.status != .skipped }
            var flows: [(date: Date, amount: Decimal)] = cashTransactions.map { ($0.date, $0.signedAmount) }
            if account.initialBalance != 0 {
                flows.append((account.initialBalanceDate ?? openingDate(of: account), account.initialBalance))
            }
            allFlows += flows

            let line: InvestmentReportLine
            if account.type.supportsPositions {
                let operations = investmentsController.operations[account.id] ?? []
                allOperations += operations
                let byPosition = Dictionary(grouping: operations.filter { $0.positionID != nil }) { $0.positionID! }
                let realized = byPosition.values.reduce(Decimal(0)) { $0 + PositionCalculator.replay($1).realizedGain }
                let fees = operations.filter { $0.type == .fee }.reduce(Decimal(0)) { $0 + $1.amount }
                line = InvestmentReportLine(
                    account: account,
                    invested: transactionsController.calculateBalance(for: account.id, initialBalance: account.initialBalance),
                    value: value,
                    unrealized: investmentsController.unrealizedGain(for: account.id),
                    realized: realized,
                    income: InvestmentAnalytics.income(operations, since: .distantPast),
                    income12Months: InvestmentAnalytics.income(operations, since: yearAgo),
                    fees: fees,
                    annualized: InvestmentAnalytics.annualizedReturn(flows: flows, finalValue: value, at: now),
                    feeRate: accountTermsController.feeRate(for: account.id)
                )

                // Répartition des titres par classe et devise ; espèces à part
                for position in investmentsController.positions[account.id] ?? [] where position.quantity > 0 {
                    let market = PositionCalculator.marketValue(position)
                    assetClass[position.assetType.displayName, default: 0] += market
                    currency[position.currency, default: 0] += market
                }
                let cash = valuation.cash(of: account)
                if cash != 0 {
                    assetClass["Liquidités", default: 0] += cash
                    currency[account.currency, default: 0] += cash
                }

                if account.type == .investment {
                    report.realizedThisYear += investmentsController.realizedGain(for: account.id, year: year)
                    report.dividendsThisYear += operations
                        .filter { $0.type == .dividend && $0.date >= yearStart }
                        .reduce(Decimal(0)) { $0 + $1.amount }
                }
                if account.type == .pea {
                    let opening = openingDate(of: account)
                    let fiveYears = calendar.date(byAdding: .year, value: 5, to: opening) ?? opening
                    let deposits = flows.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
                    report.peaFiveYears.append(EnvelopeMilestone(account: account, date: fiveYears, deposits: deposits))
                }
            } else {
                // Assurance vie suivie par relevés : pas de détail des supports
                let summary = valuation.planSummary(of: account)
                line = InvestmentReportLine(
                    account: account,
                    invested: summary.invested,
                    value: value,
                    unrealized: summary.gain,
                    realized: 0,
                    income: 0,
                    income12Months: 0,
                    fees: 0,
                    annualized: InvestmentAnalytics.annualizedReturn(flows: flows, finalValue: value, at: now),
                    feeRate: accountTermsController.feeRate(for: account.id)
                )
                assetClass["Assurance vie (supports non détaillés)", default: 0] += value
                currency[account.currency, default: 0] += value
                let eightYears = calendar.date(byAdding: .year, value: 8, to: openingDate(of: account)) ?? now
                report.lifeInsuranceEightYears.append(EnvelopeMilestone(account: account, date: eightYears, deposits: 0))
            }

            envelope[account.type.displayName, default: 0] += value
            report.lines.append(line)
        }

        let slices: ([String: Decimal]) -> [AllocationSlice] = { dictionary in
            dictionary.filter { $0.value > 0 }.map { AllocationSlice(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
        }
        report.lines.sort { $0.value > $1.value }
        report.byEnvelope = slices(envelope)
        report.byAssetClass = slices(assetClass)
        report.byCurrency = slices(currency)
        report.annualized = InvestmentAnalytics.annualizedReturn(flows: allFlows, finalValue: report.value, at: now)

        // Revenus des 12 derniers mois, par mois
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        report.monthlyIncome = (0..<12).reversed().compactMap { offset -> MonthlyIncome? in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: currentMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let inMonth = allOperations.filter { $0.date >= start && $0.date < end }
            let net: (InvestmentTransactionType) -> Decimal = { type in
                inMonth.filter { $0.type == type }.reduce(Decimal(0)) { $0 + $1.amount - $1.fees }
            }
            return MonthlyIncome(month: start, dividends: net(.dividend), interest: net(.interest))
        }
        return report
    }

    // MARK: Retraite et épargne salariale

    func retirement() -> RetirementReport {
        var report = RetirementReport()
        let planTypes: Set<AccountType> = [.pee, .perco, .retirement, .article83]
        let transactions = transactionsController.allTransactions

        for account in accounts where planTypes.contains(account.type) {
            report.plans.append(RetirementPlanLine(
                account: account,
                summary: savingsPlansController.summary(for: account, transactions: transactions, asOf: now),
                flows: savingsPlansController.flows(for: account, transactions: transactions),
                settings: savingsPlansController.planSettings(for: account.id)
            ))
        }
        report.plans.sort { $0.summary.value > $1.summary.value }

        // Calendrier de disponibilité : aujourd'hui, 4 années détaillées, « et après », retraite
        var availableNow: [UUID: Decimal] = [:], retirement: [UUID: Decimal] = [:]
        var byYear: [Int: [UUID: Decimal]] = [:]
        for plan in report.plans {
            let summary = plan.summary
            availableNow[plan.id] = summary.availableValue
            let locked = summary.unlocks.reduce(Decimal(0)) { $0 + $1.amount }
            let scale = locked > 0 ? summary.blockedValue / locked : 0
            for unlock in summary.unlocks {
                if let date = unlock.date {
                    byYear[calendar.component(.year, from: date), default: [:]][plan.id, default: 0] += unlock.amount * scale
                } else {
                    retirement[plan.id, default: 0] += unlock.amount * scale
                }
            }
        }
        var releases = [RetirementRelease(label: "Aujourd’hui", amounts: availableNow, isNow: true)]
        let years = byYear.keys.sorted()
        for (index, unlockYear) in years.enumerated() {
            if index == 4 {
                var rest: [UUID: Decimal] = [:]
                for later in years.dropFirst(4) {
                    for (id, amount) in byYear[later] ?? [:] { rest[id, default: 0] += amount }
                }
                releases.append(RetirementRelease(label: "\(unlockYear) et après", amounts: rest, isNow: false))
                break
            }
            releases.append(RetirementRelease(label: String(unlockYear), amounts: byYear[unlockYear] ?? [:], isNow: false))
        }
        if !retirement.isEmpty {
            releases.append(RetirementRelease(label: "Retraite", amounts: retirement, isNow: false))
        }
        report.releases = releases

        // Avantages de l'année et ce qui reste à capter
        var advantages = RetirementAdvantages()
        var matchingLeft: Decimal? = nil
        var matchingNeeded: Decimal? = nil
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: self.now) ?? self.now
        var contributions12Months: Decimal = 0

        for plan in report.plans {
            let flows = plan.flows
            advantages.marginalTaxRate = advantages.marginalTaxRate ?? plan.settings.marginalTaxRate
            contributions12Months += flows.filter { $0.isContribution && !$0.isInitialBalance && $0.date >= yearAgo }.reduce(Decimal(0)) { $0 + $1.amount }

            switch plan.kind {
            case .pee, .per:
                let matching = RetirementPlanAnalytics.matchingYear(flows: flows, settings: plan.settings, accountType: plan.account.type, year: year)
                advantages.matching += matching.matching
                advantages.employeeSavings += RetirementPlanAnalytics.contributions(flows: flows, year: year, origins: [.profitSharing, .participation])
                if plan.kind == .per {
                    advantages.perDeducted += RetirementPlanAnalytics.deductedContributions(flows: flows, year: year)
                    let status = RetirementPlanAnalytics.deductionStatus(flows: flows, settings: plan.settings, year: year)
                    if status.expiringThisYear > 0 {
                        report.expiringCeiling += status.expiringThisYear
                        report.expiringCeilingYear = status.expiringYear
                    }
                }
                if plan.kind == .pee, matching.accordCap != nil {
                    matchingLeft = (matchingLeft ?? 0) + matching.remaining
                    if let needed = matching.additionalVoluntaryNeeded {
                        matchingNeeded = (matchingNeeded ?? 0) + needed
                    }
                }
            case .article83:
                advantages.article83 += RetirementPlanAnalytics.contributions(flows: flows, year: year, origins: [.matching, .employeeMandatory])
            case .generic:
                break
            }
        }

        report.advantages = advantages
        report.matchingLeft = matchingLeft
        report.matchingNeeded = matchingNeeded
        report.monthlyContributions = contributions12Months / 12
        return report
    }

    // MARK: Dettes

    func debts() -> DebtReport {
        var report = DebtReport()
        for account in accounts where account.type.group == .debt {
            let schedule = accountTermsController.loan(for: account.id).map { LoanSchedule(terms: $0, calendar: calendar) }
            let balance = schedule.map { Decimal($0.balance(asOf: now)) } ?? max(-valuation.value(of: account), 0)
            report.lines.append(DebtLine(account: account, balance: balance, schedule: schedule))
        }
        report.lines.sort { $0.balance > $1.balance }
        report.monthlyIncome = monthlyAverage(of: .credit)
        return report
    }
}
