import Foundation

// Rapports d'analyse « Au quotidien » et « Bilans et objectifs » : modèles et calculs.
// Tous les montants de dépenses sont positifs.

// MARK: - Indice des prix (INSEE)

/// Inflation moyenne annuelle en France (indice des prix à la consommation, INSEE).
/// Intégrée à l'app, à mettre à jour à chaque version.
enum InseeInflation {
    static let yearly: [Int: Double] = [
        2019: 0.011, 2020: 0.005, 2021: 0.016, 2022: 0.052, 2023: 0.049, 2024: 0.020, 2025: 0.009
    ]

    /// Postes de l'INSEE, moyenne annuelle 2025
    static let byPost2025: [String: Double] = [
        "Alimentation": 0.012, "Énergie": -0.056, "Services": 0.023, "Produits manufacturés": -0.003
    ]

    static var lastYear: Int { yearly.keys.max() ?? 2025 }
    static var last: Double { yearly[lastYear] ?? 0 }

    /// Poste INSEE probable d'une catégorie, d'après son nom
    static func post(forCategoryName name: String) -> String? {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let food = ["aliment", "course", "supermarche", "epicerie", "boulangerie"]
        let energy = ["energie", "electricite", "gaz", "carburant", "essence", "edf", "chauffage"]
        if food.contains(where: { folded.contains($0) }) { return "Alimentation" }
        if energy.contains(where: { folded.contains($0) }) { return "Énergie" }
        return nil
    }
}

// MARK: - Prévision de trésorerie

struct ForecastEvent: Identifiable {
    let id: String
    let date: Date
    let label: String
    let amount: Decimal
}

struct ForecastPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let balance: Decimal
}

struct ForecastReport {
    var startBalance: Decimal = 0
    var points: [ForecastPoint] = []
    var events: [ForecastEvent] = []
    var dailySpending: Decimal = 0
    var recurringIncome: Decimal = 0          // Par mois
    var recurringExpenses: Decimal = 0        // Par mois

    var lowest: ForecastPoint? { points.min { $0.balance < $1.balance } }
    var negativeDays: Int { points.filter { $0.balance < 0 }.count }
    var firstNegative: ForecastPoint? { points.first { $0.balance < 0 } }
    var end: ForecastPoint? { points.last }
}

// MARK: - Charges fixes et abonnements

struct FixedCharge: Identifiable {
    var id: UUID { template.id }
    let template: RecurringTemplate
    let name: String
    let group: String                 // Catégorie principale
    let monthly: Decimal
    let isSubscription: Bool
    let increase: Decimal?            // Hausse constatée sur 12 mois
    let increaseSince: Date?
}

struct DuplicateCharge: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let dates: [Date]
}

struct FixedVariableMonth: Identifiable {
    var id: Date { month }
    let month: Date
    let fixed: Decimal
    let variable: Decimal
}

struct ChargeGroup: Identifiable {
    var id: String { name }
    let name: String
    let monthly: Decimal
    let count: Int
}

struct FixedChargesReport {
    var charges: [FixedCharge] = []
    var duplicates: [DuplicateCharge] = []
    var months: [FixedVariableMonth] = []
    var monthlyIncome: Decimal?

    var total: Decimal { charges.reduce(0) { $0 + $1.monthly } }
    var subscriptions: [FixedCharge] { charges.filter(\.isSubscription) }
    var subscriptionsTotal: Decimal { subscriptions.reduce(0) { $0 + $1.monthly } }
    var increases: [FixedCharge] { charges.filter { $0.increase != nil } }

    /// Charges regroupées par catégorie principale, de la plus lourde à la plus légère
    var groups: [ChargeGroup] {
        Dictionary(grouping: charges, by: \.group)
            .map { entry in ChargeGroup(name: entry.key, monthly: entry.value.reduce(Decimal(0)) { $0 + $1.monthly }, count: entry.value.count) }
            .sorted { $0.monthly > $1.monthly }
    }
}

// MARK: - Dépenses inhabituelles

struct CategoryDeviation: Identifiable {
    let id: UUID
    let name: String
    let amount: Decimal
    let usual: Decimal

    var excess: Decimal { amount - usual }
    var isUnusual: Bool {
        usual > 0 ? (amount > usual * Decimal(string: "1.5")! && excess >= 50) : amount >= 100
    }
}

struct UnusualItem: Identifiable {
    enum Kind { case newPayee, largeAmount, duplicate }
    var id: String { "\(transaction.id)-\(kind)" }
    let kind: Kind
    let transaction: Transaction
    let title: String
    let detail: String
}

struct UnusualReport {
    var month: Date
    var total: Decimal = 0
    var usualTotal: Decimal = 0
    var categories: [CategoryDeviation] = []
    var items: [UnusualItem] = []

    var unusualCategories: [CategoryDeviation] { categories.filter(\.isUnusual) }
    var unusualExcess: Decimal { unusualCategories.reduce(0) { $0 + $1.excess } }
}

// MARK: - Frais bancaires

enum BankFeeKind: String, CaseIterable, Identifiable {
    case card = "Cotisations de cartes"
    case incident = "Commissions d’intervention"
    case overdraft = "Agios"
    case account = "Frais de tenue de compte"
    case foreign = "Retraits et paiements à l’étranger"
    case other = "Autres frais"

    var id: String { rawValue }

    /// Frais liés aux passages à découvert : les plus faciles à éviter
    var isAvoidable: Bool { self == .incident || self == .overdraft }

    static func classify(_ text: String) -> BankFeeKind {
        let t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).uppercased()
        if t.contains("AGIOS") || t.contains("DEBITEUR") { return .overdraft }
        if t.contains("INTERVENTION") || t.contains("INCIDENT") || t.contains("REJET") || t.contains("IRREGULARITE") { return .incident }
        if t.contains("TENUE") || t.contains("GESTION DE COMPTE") { return .account }
        if t.contains("DEVISE") || t.contains("ETRANGER") || t.contains("CHANGE") || t.contains("HORS ZONE") { return .foreign }
        if t.contains("COTIS") || t.contains("CARTE") { return .card }
        return .other
    }
}

struct BankFee: Identifiable {
    var id: UUID { transaction.id }
    let transaction: Transaction
    let kind: BankFeeKind
    let bank: String
    let label: String
}

struct BankFeesReport {
    var fees: [BankFee] = []
    var overdraftMonths = 0
    var months: [Date] = []

    var total: Decimal { fees.reduce(0) { $0 + abs($1.transaction.amount) } }
    var avoidable: Decimal { fees.filter { $0.kind.isAvoidable }.reduce(0) { $0 + abs($1.transaction.amount) } }
    func amount(of kind: BankFeeKind) -> Decimal {
        fees.filter { $0.kind == kind }.reduce(0) { $0 + abs($1.transaction.amount) }
    }
    var banks: [String] { Array(Set(fees.map(\.bank))).sorted() }
}

// MARK: - Inflation personnelle

struct PriceChange: Identifiable {
    let id: UUID
    let name: String
    let before: Decimal          // Moyenne mensuelle, même période il y a un an
    let now: Decimal             // Moyenne mensuelle, 3 derniers mois complets
    let inseePost: String?

    var change: Double? {
        guard before > 0 else { return nil }
        return NSDecimalNumber(decimal: (now - before) / before).doubleValue
    }
    var inseeChange: Double? { inseePost.flatMap { InseeInflation.byPost2025[$0] } }
}

struct YearSpending: Identifiable {
    var id: Int { year }
    let year: Int
    let spending: Decimal
}

struct InflationReport {
    var posts: [PriceChange] = []
    var yearly: [YearSpending] = []   // Dépenses courantes par année complète

    var before: Decimal { posts.filter { $0.before > 0 && $0.now > 0 }.reduce(0) { $0 + $1.before } }
    var now: Decimal { posts.filter { $0.before > 0 && $0.now > 0 }.reduce(0) { $0 + $1.now } }
    var change: Double? {
        guard before > 0 else { return nil }
        return NSDecimalNumber(decimal: (now - before) / before).doubleValue
    }
    /// Surcoût annuel par rapport à une hausse au rythme de l'inflation
    var extraPerYear: Decimal? {
        guard let change else { return nil }
        return before * 12 * Decimal(change - InseeInflation.last)
    }
}

// MARK: - Bilan de l'année

struct MonthFlow: Identifiable {
    var id: Date { month }
    let month: Date
    let income: Decimal
    let expense: Decimal
    var saving: Decimal { income - expense }
}

struct CategoryYear: Identifiable {
    let id: UUID
    let name: String
    let amount: Decimal
    let previous: Decimal
    var change: Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (amount - previous) / previous).doubleValue
    }
}

struct YearReview {
    var year: Int
    var months: [MonthFlow] = []
    var previousIncome: Decimal = 0
    var previousExpense: Decimal = 0
    var categories: [CategoryYear] = []
    var biggestExpense: Transaction?
    var budgetsKept: (kept: Int, total: Int)?

    var income: Decimal { months.reduce(0) { $0 + $1.income } }
    var expense: Decimal { months.reduce(0) { $0 + $1.expense } }
    var saving: Decimal { income - expense }
    var positiveMonths: Int { months.filter { $0.saving > 0 }.count }
    var mostExpensive: MonthFlow? { months.max { $0.expense < $1.expense } }
    var risers: [CategoryYear] { categories.filter { ($0.change ?? 0) > 0 && $0.previous >= 200 }.sorted { ($0.change ?? 0) > ($1.change ?? 0) } }
    var fallers: [CategoryYear] { categories.filter { ($0.change ?? 0) < 0 && $0.previous >= 200 }.sorted { ($0.change ?? 0) < ($1.change ?? 0) } }
}

// MARK: - Préparer la déclaration

struct TaxLine: Identifiable {
    var id: String { taxCase.rawValue }
    let taxCase: TaxCase
    let spent: Decimal
    let count: Int
    let categories: [String]

    var retained: Decimal { taxCase.spendingCap.map { min(spent, $0) } ?? spent }
    var advantage: Decimal { retained * taxCase.rate }
    var isOverCap: Bool { taxCase.spendingCap.map { spent > $0 } ?? false }
}

struct TaxSuggestion: Identifiable {
    var id: UUID { category.id }
    let category: Category
    let taxCase: TaxCase
}

struct TaxReport {
    var year: Int
    var lines: [TaxLine] = []
    var perDeductions: Decimal = 0
    var marginalTaxRate: Double?
    var realizedGains: Decimal = 0
    var dividends: Decimal = 0
    var suggestions: [TaxSuggestion] = []

    var advantage: Decimal { lines.reduce(0) { $0 + $1.advantage } }
    var perSaving: Decimal? { marginalTaxRate.map { perDeductions * Decimal($0) } }
}

// MARK: - Construction

@MainActor
struct AnalysisReportBuilder {
    let accountsController: AccountsController
    let transactionsController: TransactionsController
    let categoriesController: CategoriesController
    let payeesController: PayeesController
    let recurringController: RecurringController
    var now = Date()
    var calendar = Calendar.current

    // MARK: Outils

    func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    func addMonths(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: count, to: date) ?? date
    }

    /// Opérations des comptes courants (hors virements et opérations ignorées)
    func cashFlowTransactions(from start: Date, to end: Date) -> [Transaction] {
        let ids = accountsController.cashFlowAccountIDs
        return transactionsController.allTransactions.filter {
            ids.contains($0.accountID) && $0.status != .skipped && $0.type != .transfer && $0.date >= start && $0.date < end
        }
    }

    /// Date de la première opération des comptes donnés (comptes courants par défaut)
    func firstTransactionDate(accountIDs: Set<UUID>? = nil) -> Date? {
        let ids = accountIDs ?? accountsController.cashFlowAccountIDs
        return transactionsController.allTransactions
            .filter { ids.contains($0.accountID) && $0.status != .skipped }
            .map(\.date)
            .min()
    }

    /// Nombre de mois de [start, end) couverts par l'historique, à partir du mois de la première opération
    func coveredMonths(from start: Date, to end: Date, since first: Date?) -> Int {
        guard let first else { return 0 }
        let from = max(monthStart(start), monthStart(first))
        guard from < end else { return 0 }
        return max(calendar.dateComponents([.month], from: from, to: end).month ?? 0, 0)
    }

    /// Catégorie principale d'une opération (la catégorie parente, sinon elle-même)
    func topCategory(of transaction: Transaction) -> Category? {
        guard let id = transaction.categoryID, let category = categoriesController.getCategory(id: id) else { return nil }
        if let parentID = category.parentID, let parent = categoriesController.getCategory(id: parentID) { return parent }
        return category
    }

    func label(of transaction: Transaction) -> String {
        if let id = transaction.payeeID, let payee = payeesController.getPayee(id: id) { return payee.name }
        if let memo = transaction.memo, !memo.isEmpty { return memo }
        return transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "Sans libellé"
    }

    private func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    // MARK: Prévision de trésorerie

    /// Solde prévu des comptes choisis (comptes courants par défaut), jour par jour
    func forecast(accountIDs: Set<UUID>, days: Int = 90, startBalance: Decimal) -> ForecastReport {
        var report = ForecastReport()
        report.startBalance = startBalance
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: days, to: today) else { return report }

        // Échéances récurrentes (celles en retard sont comptées aujourd'hui)
        var byDay: [Date: Decimal] = [:]
        for occurrence in recurringController.occurrences(accountID: nil, until: horizon) {
            let amount = accountIDs.reduce(Decimal(0)) { $0 + occurrence.template.signedAmount(for: $1) }
            guard amount != 0 else { continue }
            let day = max(calendar.startOfDay(for: occurrence.date), today)
            byDay[day, default: 0] += amount
            if day <= (calendar.date(byAdding: .day, value: 45, to: today) ?? today) {
                report.events.append(ForecastEvent(id: occurrence.id, date: day, label: label(of: occurrence.template), amount: amount))
            }
        }

        // Dépenses courantes hors récurrences : moyenne par jour des 90 derniers jours,
        // ou des jours réellement couverts quand l'historique est plus court
        let past = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let firstDay = firstTransactionDate(accountIDs: accountIDs).map { calendar.startOfDay(for: $0) } ?? today
        let coveredDays = max(min(calendar.dateComponents([.day], from: max(firstDay, past), to: today).day ?? 90, 90), 1)
        let variable = transactionsController.allTransactions.filter {
            accountIDs.contains($0.accountID) && $0.status != .skipped && $0.type == .debit
                && $0.recurringTemplateID == nil && $0.date >= past && $0.date < today
        }
        report.dailySpending = variable.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(coveredDays)

        var balance = startBalance
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if offset > 0 { balance -= report.dailySpending }
            balance += byDay[day] ?? 0
            report.points.append(ForecastPoint(date: day, balance: balance))
        }

        let templates = recurringController.templates.filter { template in template.isActive && accountIDs.contains { template.involves($0) } }
        for template in templates {
            let monthly = accountIDs.reduce(Decimal(0)) { $0 + template.signedAmount(for: $1) } * template.frequency.occurrencesPerMonth
            if monthly > 0 { report.recurringIncome += monthly } else { report.recurringExpenses += -monthly }
        }
        report.events.sort { $0.date < $1.date }
        return report
    }

    func label(of template: RecurringTemplate) -> String {
        if let id = template.payeeID, let payee = payeesController.getPayee(id: id) { return payee.name }
        if let memo = template.memo, !memo.isEmpty { return memo }
        if let id = template.categoryID { return categoriesController.getCategoryPath(for: id) }
        if template.isTransfer, let to = template.toAccountID, let account = accountsController.getAccount(id: to) {
            return "Virement vers \(account.name)"
        }
        return "Opération récurrente"
    }

    // MARK: Charges fixes

    func fixedCharges() -> FixedChargesReport {
        var report = FixedChargesReport()
        let yearAgo = addMonths(-12, to: now)
        let cashIDs = accountsController.cashFlowAccountIDs

        for template in recurringController.templates where template.isActive && template.type == .debit && cashIDs.contains(template.accountID) {
            let topName: String
            if let id = template.categoryID, let category = categoriesController.getCategory(id: id) {
                topName = category.parentID.flatMap { categoriesController.getCategory(id: $0)?.name } ?? category.name
            } else {
                topName = "Sans catégorie"
            }
            let path = folded(template.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "")
            let isSubscription = ["abonnement", "streaming", "logiciel", "presse"].contains(where: { path.contains($0) })

            // Hausse : dernier montant payé comparé au premier des 12 derniers mois
            let paid = transactionsController.allTransactions
                .filter { $0.recurringTemplateID == template.id && $0.status != .skipped && $0.date >= yearAgo }
                .sorted { $0.date < $1.date }
            var increase: Decimal? = nil
            var since: Date? = nil
            if let first = paid.first, let last = paid.last, first.id != last.id {
                let delta = abs(last.amount) - abs(first.amount)
                if delta >= Decimal(string: "0.5")!, abs(first.amount) > 0, delta / abs(first.amount) >= Decimal(string: "0.01")! {
                    increase = delta
                    since = paid.first { abs($0.amount) == abs(last.amount) }?.date
                }
            }

            report.charges.append(FixedCharge(
                template: template,
                name: label(of: template),
                group: topName,
                monthly: abs(template.monthlyAmount),
                isSubscription: isSubscription,
                increase: increase,
                increaseSince: since
            ))
        }
        report.charges.sort { $0.monthly > $1.monthly }

        // Doubles prélèvements : même récurrence (ou même bénéficiaire d'une récurrence mensuelle),
        // même montant, deux fois dans le même mois, sur les 60 derniers jours
        let recent = cashFlowTransactions(from: calendar.date(byAdding: .day, value: -60, to: now) ?? now, to: now)
            .filter { $0.type == .debit }
        let monthlyPayees = Set(recurringController.templates.filter { $0.isActive && $0.frequency == .monthly }.compactMap(\.payeeID))
        let candidates = recent.filter { tx in tx.recurringTemplateID != nil || tx.payeeID.map { monthlyPayees.contains($0) } == true }
        let grouped = Dictionary(grouping: candidates) { tx in
            "\(tx.payeeID?.uuidString ?? tx.recurringTemplateID?.uuidString ?? "")|\(abs(tx.amount))|\(calendar.component(.month, from: tx.date))"
        }
        for (key, list) in grouped where list.count >= 2 {
            report.duplicates.append(DuplicateCharge(id: key, name: label(of: list[0]), amount: abs(list[0].amount), dates: list.map(\.date).sorted()))
        }

        // Fixe ou variable, sur les 12 derniers mois complets
        let fixedPayees = Set(recurringController.templates.filter { $0.isActive && $0.type == .debit }.compactMap(\.payeeID))
        let currentMonth = monthStart(now)
        for offset in (1...12).reversed() {
            let start = addMonths(-offset, to: currentMonth), end = addMonths(1, to: start)
            let debits = cashFlowTransactions(from: start, to: end).filter { $0.type == .debit }
            let fixed = debits.filter { $0.recurringTemplateID != nil || $0.payeeID.map { fixedPayees.contains($0) } == true }
                .reduce(Decimal(0)) { $0 + abs($1.amount) }
            let total = debits.reduce(Decimal(0)) { $0 + abs($1.amount) }
            report.months.append(FixedVariableMonth(month: start, fixed: fixed, variable: total - fixed))
        }

        let credits = cashFlowTransactions(from: yearAgo, to: now).filter { $0.type == .credit }
        if !credits.isEmpty {
            report.monthlyIncome = credits.reduce(Decimal(0)) { $0 + abs($1.amount) } / 12
        }
        return report
    }

    // MARK: Dépenses inhabituelles

    func unusual(month: Date, dismissed: Set<UUID>) -> UnusualReport {
        let start = monthStart(month), end = addMonths(1, to: start)
        var report = UnusualReport(month: start)
        let current = cashFlowTransactions(from: start, to: end).filter { $0.type == .debit }
        let history = cashFlowTransactions(from: addMonths(-6, to: start), to: start).filter { $0.type == .debit }
        let yearHistory = cashFlowTransactions(from: addMonths(-12, to: start), to: start).filter { $0.type == .debit }

        report.total = current.reduce(0) { $0 + abs($1.amount) }
        // Moyenne sur les 6 mois précédents, ou sur les mois réellement couverts par l'historique
        let historyMonths = Decimal(max(coveredMonths(from: addMonths(-6, to: start), to: start, since: firstTransactionDate()), 1))
        report.usualTotal = history.reduce(0) { $0 + abs($1.amount) } / historyMonths

        // Par catégorie principale
        let key: (Transaction) -> UUID = { tx in topCategory(of: tx)?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
        let nowBy = Dictionary(grouping: current, by: key).mapValues { $0.reduce(Decimal(0)) { $0 + abs($1.amount) } }
        let beforeBy = Dictionary(grouping: history, by: key).mapValues { $0.reduce(Decimal(0)) { $0 + abs($1.amount) } / historyMonths }
        for id in Set(nowBy.keys).union(beforeBy.keys) {
            let name = categoriesController.getCategory(id: id)?.name ?? "Sans catégorie"
            report.categories.append(CategoryDeviation(id: id, name: name, amount: nowBy[id] ?? 0, usual: beforeBy[id] ?? 0))
        }
        report.categories.sort { $0.amount > $1.amount }

        // Opérations à regarder
        let byPayee = Dictionary(grouping: yearHistory.filter { $0.payeeID != nil }) { $0.payeeID! }
        for tx in current where !dismissed.contains(tx.id) {
            let amount = abs(tx.amount)
            if let payeeID = tx.payeeID {
                let past = byPayee[payeeID] ?? []
                if past.isEmpty && amount >= 100 {
                    report.items.append(UnusualItem(kind: .newPayee, transaction: tx, title: label(of: tx),
                                                    detail: "nouveau bénéficiaire, le \(tx.date.formatted(.dateTime.day().month(.wide)))"))
                } else if past.count >= 3 {
                    let average = past.reduce(Decimal(0)) { $0 + abs($1.amount) } / Decimal(past.count)
                    if amount >= average * 3 && amount - average >= 50 {
                        let ratio = NSDecimalNumber(decimal: amount / average).doubleValue
                        report.items.append(UnusualItem(kind: .largeAmount, transaction: tx, title: label(of: tx),
                                                        detail: "\(ratio.formatted(.number.precision(.fractionLength(0)))) fois plus que d’habitude"))
                    }
                }
            }
        }
        // Même bénéficiaire, même montant, à moins de 7 jours d'intervalle
        let samePayee = Dictionary(grouping: current.filter { $0.payeeID != nil }) { "\($0.payeeID!.uuidString)|\(abs($0.amount))" }
        for list in samePayee.values where list.count >= 2 {
            let sorted = list.sorted { $0.date < $1.date }
            for (a, b) in zip(sorted, sorted.dropFirst()) where !dismissed.contains(b.id) {
                let days = calendar.dateComponents([.day], from: a.date, to: b.date).day ?? 99
                if days <= 7 {
                    report.items.append(UnusualItem(kind: .duplicate, transaction: b, title: "\(label(of: b)) payé deux fois",
                                                    detail: "le \(a.date.formatted(.dateTime.day().month(.abbreviated))) et le \(b.date.formatted(.dateTime.day().month(.abbreviated))) : à vérifier"))
                }
            }
        }
        report.items.sort { abs($0.transaction.amount) > abs($1.transaction.amount) }
        return report
    }

    // MARK: Frais bancaires

    /// Mots qui désignent des frais dans un libellé bancaire
    private static let feeKeywords = ["COTIS", "COMMISSION", "AGIOS", "INTERETS DEBITEURS", "INT. DEBITEURS",
                                      "TENUE DE COMPTE", "FRAIS TENUE", "FRAIS RETRAIT", "FRAIS PAIEMENT", "FRAIS BANCAIRE"]

    func bankFees(months count: Int = 12) -> BankFeesReport {
        var report = BankFeesReport()
        let currentMonth = monthStart(now)
        let start = addMonths(-(count - 1), to: currentMonth)
        report.months = (0..<count).map { addMonths($0, to: start) }

        let accounts = accountsController.activeAccounts.filter { $0.type.group == .liquidity || $0.type.group == .savings }
        let ids = Set(accounts.map(\.id))
        for tx in transactionsController.allTransactions where ids.contains(tx.accountID) && tx.type == .debit && tx.status != .skipped && tx.date >= start {
            let path = folded(tx.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "")
            let memo = (tx.memo ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).uppercased()
            let isFee = path.contains("frais bancaire") || path.contains("frais de banque") || Self.feeKeywords.contains(where: { memo.contains($0) })
            guard isFee else { continue }
            let account = accountsController.getAccount(id: tx.accountID)
            report.fees.append(BankFee(
                transaction: tx,
                kind: BankFeeKind.classify((tx.memo ?? "") + " " + path),
                bank: account?.bank ?? account?.name ?? "Banque",
                label: tx.memo ?? label(of: tx)
            ))
        }
        report.fees.sort { $0.transaction.date > $1.transaction.date }

        // Mois avec au moins un passage à découvert sur un compte courant
        var negativeMonths = Set<Date>()
        for account in accounts where account.type.group == .liquidity {
            var balance = account.initialBalance
            let txs = transactionsController.allTransactions.filter { $0.accountID == account.id && $0.status != .skipped }.sorted { $0.date < $1.date }
            for tx in txs {
                balance += tx.signedAmount
                if balance < 0 && tx.date >= start { negativeMonths.insert(monthStart(tx.date)) }
            }
        }
        report.overdraftMonths = negativeMonths.count
        return report
    }

    // MARK: Inflation personnelle

    func inflation() -> InflationReport {
        var report = InflationReport()
        let currentMonth = monthStart(now)
        let recentStart = addMonths(-3, to: currentMonth)
        let previousStart = addMonths(-12, to: recentStart), previousEnd = addMonths(-12, to: currentMonth)

        let key: (Transaction) -> UUID? = { topCategory(of: $0)?.id }
        let recent = cashFlowTransactions(from: recentStart, to: currentMonth).filter { $0.type == .debit }
        let previous = cashFlowTransactions(from: previousStart, to: previousEnd).filter { $0.type == .debit }
        // Moyennes mensuelles sur les mois réellement couverts par l'historique de chaque période
        let first = firstTransactionDate()
        let sum: ([Transaction], Int) -> [UUID: Decimal] = { list, months in
            var result: [UUID: Decimal] = [:]
            for tx in list { if let id = key(tx) { result[id, default: 0] += abs(tx.amount) } }
            return result.mapValues { $0 / Decimal(max(months, 1)) }
        }
        let recentBy = sum(recent, coveredMonths(from: recentStart, to: currentMonth, since: first))
        let previousBy = sum(previous, coveredMonths(from: previousStart, to: previousEnd, since: first))
        for id in Set(recentBy.keys).union(previousBy.keys) {
            guard let category = categoriesController.getCategory(id: id) else { continue }
            report.posts.append(PriceChange(
                id: id, name: category.name,
                before: previousBy[id] ?? 0, now: recentBy[id] ?? 0,
                inseePost: InseeInflation.post(forCategoryName: category.name)
            ))
        }
        report.posts.sort { $0.now > $1.now }

        // Dépenses courantes par année complète, sur 4 ans
        let year = calendar.component(.year, from: now)
        for y in (year - 4)..<year {
            guard let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: y + 1, month: 1, day: 1)) else { continue }
            let total = cashFlowTransactions(from: start, to: end).filter { $0.type == .debit }.reduce(Decimal(0)) { $0 + abs($1.amount) }
            if total > 0 { report.yearly.append(YearSpending(year: y, spending: total)) }
        }
        return report
    }

    // MARK: Bilan de l'année

    func yearReview(year: Int) -> YearReview {
        var review = YearReview(year: year)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let previousStart = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)) else { return review }
        let end = addMonths(12, to: start)

        for offset in 0..<12 {
            let month = addMonths(offset, to: start)
            guard month <= now else { break }
            let list = cashFlowTransactions(from: month, to: addMonths(1, to: month))
            review.months.append(MonthFlow(
                month: month,
                income: list.filter { $0.type == .credit }.reduce(0) { $0 + abs($1.amount) },
                expense: list.filter { $0.type == .debit }.reduce(0) { $0 + abs($1.amount) }
            ))
        }

        let all = cashFlowTransactions(from: start, to: end)
        let previous = cashFlowTransactions(from: previousStart, to: start)
        review.previousIncome = previous.filter { $0.type == .credit }.reduce(0) { $0 + abs($1.amount) }
        review.previousExpense = previous.filter { $0.type == .debit }.reduce(0) { $0 + abs($1.amount) }
        review.biggestExpense = all.filter { $0.type == .debit }.max { abs($0.amount) < abs($1.amount) }

        var nowBy: [UUID: Decimal] = [:], beforeBy: [UUID: Decimal] = [:]
        for tx in all where tx.type == .debit { if let id = topCategory(of: tx)?.id { nowBy[id, default: 0] += abs(tx.amount) } }
        for tx in previous where tx.type == .debit { if let id = topCategory(of: tx)?.id { beforeBy[id, default: 0] += abs(tx.amount) } }
        for id in Set(nowBy.keys).union(beforeBy.keys) {
            guard let category = categoriesController.getCategory(id: id) else { continue }
            review.categories.append(CategoryYear(id: id, name: category.name, amount: nowBy[id] ?? 0, previous: beforeBy[id] ?? 0))
        }
        review.categories.sort { $0.amount > $1.amount }
        return review
    }

    /// Années complètes ou en cours ayant des opérations
    var availableYears: [Int] {
        let years = Set(transactionsController.allTransactions.map { calendar.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    // MARK: Déclaration

    func taxReport(year: Int, mapping: [UUID: TaxCase]) -> TaxReport {
        var report = TaxReport(year: year)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return report }
        let end = addMonths(12, to: start)
        let transactions = transactionsController.allTransactions.filter {
            $0.type == .debit && $0.status != .skipped && $0.date >= start && $0.date < end
        }

        // Une sous-catégorie hérite de la case de sa catégorie parente
        func caseFor(_ categoryID: UUID?) -> TaxCase? {
            guard let id = categoryID else { return nil }
            if let direct = mapping[id] { return direct }
            if let parent = categoriesController.getCategory(id: id)?.parentID { return mapping[parent] }
            return nil
        }

        var spent: [TaxCase: Decimal] = [:], counts: [TaxCase: Int] = [:]
        for tx in transactions {
            guard let taxCase = caseFor(tx.categoryID) else { continue }
            spent[taxCase, default: 0] += abs(tx.amount)
            counts[taxCase, default: 0] += 1
        }
        for taxCase in TaxCase.allCases where spent[taxCase] != nil {
            let names = mapping.filter { $0.value == taxCase }.compactMap { categoriesController.getCategory(id: $0.key)?.name }.sorted()
            report.lines.append(TaxLine(taxCase: taxCase, spent: spent[taxCase] ?? 0, count: counts[taxCase] ?? 0, categories: names))
        }

        // Catégories qui ressemblent à une case mais n'y sont pas reliées
        for category in categoriesController.categories where !category.isIncome && caseFor(category.id) == nil {
            let name = folded(category.name)
            if let match = TaxCase.allCases.first(where: { taxCase in taxCase.keywords.contains { keyword in
                name == keyword || name.hasPrefix(keyword + " ") || name.contains(" " + keyword) || (keyword.count > 4 && name.contains(keyword))
            } }) {
                report.suggestions.append(TaxSuggestion(category: category, taxCase: match))
            }
        }
        return report
    }
}
