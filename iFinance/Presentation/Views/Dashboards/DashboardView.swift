import SwiftUI

/// Vue d'ensemble : situation du patrimoine, activité du mois, comptes par type,
/// top catégories et top bénéficiaires. Fusionne l'ancien écran Patrimoine.
struct DashboardView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var appSettings: AppSettings

    /// Montant classé (catégorie ou bénéficiaire) pour les blocs « top »
    struct RankedAmount: Identifiable {
        let id: UUID
        let name: String
        let count: Int
        let amount: Decimal
    }

    var body: some View {
        let groups = wealthGroups
        let expenses = monthExpenses

        ScrollView {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                situationTiles
                monthBand(expenses)
                budgetStrip

                HStack(alignment: .top, spacing: NativeMetrics.groupSpacing) {
                    accountsBlock(groups)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: NativeMetrics.groupSpacing) {
                        rankingBlock(
                            title: "Top catégories du mois",
                            items: topCategories(expenses),
                            emptyText: "Aucune dépense catégorisée ce mois-ci"
                        )
                        rankingBlock(
                            title: "Top bénéficiaires du mois",
                            items: topPayees(expenses),
                            emptyText: "Aucune dépense avec bénéficiaire ce mois-ci"
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(NativeMetrics.pagePadding)
        }
        .pageBackground()
    }

    // MARK: - Situation

    private var situationTiles: some View {
        let accounts = wealthAccounts
        let values = accounts.map { valuation.value(of: $0) }
        let assets = values.filter { $0 > 0 }.reduce(Decimal(0), +)
        let debts = values.filter { $0 < 0 }.reduce(Decimal(0), +)
        let assetCount = values.filter { $0 > 0 }.count
        let debtCount = values.filter { $0 < 0 }.count
        let liquidity = valuation.total(of: accountsController.activeAccounts.filter { $0.countsInCashFlow })

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: NativeMetrics.groupSpacing)],
            spacing: NativeMetrics.groupSpacing
        ) {
            StatTile(
                title: "Patrimoine net",
                value: formatted(assets + debts),
                detail: countLabel(accounts.count, "compte")
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Actifs",
                value: formatted(assets),
                detail: countLabel(assetCount, "compte")
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Dettes",
                value: formatted(abs(debts)),
                detail: countLabel(debtCount, "compte")
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Liquidités",
                value: formatted(liquidity),
                detail: "Comptes courants et cartes"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Activité du mois

    private func monthBand(_ expenses: [Transaction]) -> some View {
        let income = monthTransactions
            .filter { $0.type == .credit && cashFlowAccountIDs.contains($0.accountID) }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
        let expense = expenses.reduce(Decimal(0)) { $0 + abs($1.amount) }
        let saving = income - expense

        return HStack(alignment: .center, spacing: 36) {
            Text(monthName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            monthFigure("Revenus", formatted(income))
            monthFigure("Dépenses", formatted(expense))
            monthFigure("Épargne", formatted(saving), color: saving >= 0 ? .green : .red)
            monthFigure("Transactions", "\(monthTransactions.count)", isAmount: false)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    private func monthFigure(_ title: String, _ value: String, color: Color = .primary, isAmount: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: isAmount && appSettings.hideAmounts)
        }
    }

    // MARK: - Frise des budgets

    /// Budgets actifs (avec un montant en vigueur), affichés seulement s'il y en a
    private var activeBudgets: [Budget] {
        budgetsController.budgets
            .filter { ($0.currentVersion?.amount ?? 0) > 0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private var budgetStrip: some View {
        let budgets = activeBudgets
        if !budgets.isEmpty {
            let transactions = transactionsController.allTransactions
            let budgeted = budgets.reduce(Decimal(0)) { $0 + ($1.currentVersion?.amount ?? 0) }
            let spent = budgets.reduce(Decimal(0)) { $0 + budgetsController.spent(for: $1, transactions: transactions) }
            let remaining = budgeted - spent
            let isOver = spent > budgeted
            let percent = budgeted > 0
                ? Int((NSDecimalNumber(decimal: spent / budgeted).doubleValue * 100).rounded())
                : 0

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 40) {
                    Text("Budgets")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    monthFigure("Budgété", formatted(budgeted))
                    monthFigure("Dépensé", formatted(spent))
                    monthFigure(
                        isOver ? "Dépassement" : "Reste",
                        formatted(abs(remaining)),
                        color: isOver ? .red : .green
                    )
                }

                ProgressView(value: fraction(spent, of: budgeted))
                    .progressViewStyle(.linear)
                    .tint(isOver ? Color.red : Color.accentColor)

                Text("\(percent) % des budgets utilisés, sur la période en cours de chaque budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(NativeMetrics.groupPadding)
            .cardBackground()
        }
    }

    // MARK: - Comptes par type

    private func accountsBlock(_ groups: [(group: AccountGroup, accounts: [Account], total: Decimal)]) -> some View {
        let positive = groups.filter { $0.total > 0 }
        let assets = positive.reduce(Decimal(0)) { $0 + $1.total }

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle(title: "Comptes") {
                Text("Répartition des actifs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if groups.isEmpty {
                Text("Créez un compte pour suivre votre patrimoine.")
                    .foregroundStyle(.secondary)
            } else {
                if assets > 0 {
                    allocationBar(positive, assets: assets)
                }

                ForEach(groups, id: \.group) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(item.group.displayName)
                            Spacer()
                            Text(item.total, format: .currency(code: currency))
                                .monospacedDigit()
                                .foregroundStyle(item.total >= 0 ? Color.primary : Color.red)
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }
                        .fontWeight(.semibold)
                        .padding(.vertical, 6)

                        ForEach(item.accounts) { account in
                            Divider()
                            accountRow(account)
                        }
                    }
                }
            }
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    /// Barre empilée : part de chaque groupe d'actifs, avec sa légende
    private func allocationBar(_ groups: [(group: AccountGroup, accounts: [Account], total: Decimal)], assets: Decimal) -> some View {
        let shares = groups.map { item in
            (group: item.group, share: Double(truncating: NSDecimalNumber(decimal: item.total / assets)))
        }

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(shares, id: \.group) { item in
                        Rectangle()
                            .fill(item.group.color)
                            .frame(width: max(2, (geometry.size.width - CGFloat(shares.count - 1) * 2) * item.share))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityHidden(true)

            HStack(spacing: 16) {
                ForEach(shares, id: \.group) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.group.color)
                            .frame(width: 8, height: 8)
                        Text("\(item.group.displayName) · \(item.share.formatted(.percent.precision(.fractionLength(0))))")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let value = valuation.value(of: account)
        let gain = valuation.unrealizedGain(of: account)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .lineLimit(1)
                Text(account.bank.map { "\(account.type.displayName) · \($0)" } ?? account.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(value, format: .currency(code: account.currency))
                    .monospacedDigit()
                    .foregroundStyle(value >= 0 ? Color.primary : Color.red)
                    .privacyBlur(hidden: appSettings.hideAmounts)

                if account.type.trackingMode != .transactions, gain != 0 {
                    Text("\(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: account.currency))) latents")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(gain >= 0 ? Color.green : Color.red)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
    }

    // MARK: - Blocs « top »

    private func rankingBlock(title: String, items: [RankedAmount], emptyText: String) -> some View {
        let maximum = items.first?.amount ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            GroupTitle(title)

            if items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name)
                                .lineLimit(1)
                            Text("· \(countLabel(item.count, "opération"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(item.amount, format: .currency(code: currency))
                                .monospacedDigit()
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }

                        ProgressView(value: fraction(item.amount, of: maximum))
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(NativeMetrics.groupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func fraction(_ amount: Decimal, of maximum: Decimal) -> Double {
        guard maximum > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: amount / maximum).doubleValue
        return min(max(ratio, 0), 1)
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController, investmentsController: investmentsController, savingsPlansController: savingsPlansController)
    }

    /// Comptes actifs pris en compte dans le patrimoine
    private var wealthAccounts: [Account] {
        accountsController.activeAccounts.filter { !$0.isExcludedFromReports }
    }

    private var wealthGroups: [(group: AccountGroup, accounts: [Account], total: Decimal)] {
        Dictionary(grouping: wealthAccounts) { $0.type.group }
            .map { group, accounts in
                let sorted = accounts.sorted { valuation.value(of: $0) > valuation.value(of: $1) }
                return (group, sorted, valuation.total(of: accounts))
            }
            .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }

    private var cashFlowAccountIDs: Set<UUID> {
        accountsController.cashFlowAccountIDs
    }

    private var monthName: String {
        Date().formatted(.dateTime.month(.wide).year()).capitalized
    }

    /// Transactions du mois en cours, hors occurrences ignorées
    private var monthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now

        return transactionsController.allTransactions.filter { transaction in
            transaction.date >= start && transaction.date < end && transaction.status != .skipped
        }
    }

    /// Dépenses du mois sur les comptes inclus dans les rapports
    private var monthExpenses: [Transaction] {
        monthTransactions.filter { $0.type == .debit && cashFlowAccountIDs.contains($0.accountID) }
    }

    /// Cinq premières catégories de dépenses du mois
    private func topCategories(_ expenses: [Transaction]) -> [RankedAmount] {
        let grouped = Dictionary(grouping: expenses.filter { $0.categoryID != nil }) { $0.categoryID! }

        return grouped
            .map { categoryID, transactions in
                RankedAmount(
                    id: categoryID,
                    name: categoriesController.getCategoryPath(for: categoryID),
                    count: transactions.count,
                    amount: transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
                )
            }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    /// Cinq premiers bénéficiaires de dépenses du mois
    private func topPayees(_ expenses: [Transaction]) -> [RankedAmount] {
        let grouped = Dictionary(grouping: expenses.filter { $0.payeeID != nil }) { $0.payeeID! }

        return grouped
            .compactMap { payeeID, transactions -> RankedAmount? in
                guard let payee = payeesController.getPayee(id: payeeID) else { return nil }
                return RankedAmount(
                    id: payeeID,
                    name: payee.name,
                    count: transactions.count,
                    amount: transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
                )
            }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func countLabel(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count > 1 ? "s" : "")"
    }
}

// MARK: - Supporting Views

struct DashboardCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 12)
    }
}

struct AccountSummaryRow: View {
    let account: Account
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.icon)
                .font(.title2)
                .foregroundColor(account.type.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(account.type.color.opacity(0.1)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                
                if let bank = account.bank {
                    Text(bank)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            let balance = AccountValuation(transactionsController: transactionsController, investmentsController: investmentsController, savingsPlansController: savingsPlansController)
                .value(of: account)
            
            Text(balance, format: .currency(code: account.currency))
                .font(.headline)
                .foregroundColor(balance >= 0 ? .green : .red)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding()
        .cardBackground(cornerRadius: 12)
    }
}

struct TopCategoryRow: View {
    let category: String
    let amount: Decimal
    let currency: String
    
    var body: some View {
        HStack {
            Text(category)
                .font(.subheadline)
            
            Spacer()
            
            Text(amount, format: .currency(code: currency))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.red)
        }
        .padding()
        .cardBackground(cornerRadius: 8)
    }
}

/// Ligne de compte du tableau de bord : icône, nom, banque, solde
struct DashboardAccountRow: View {
    let account: Account
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: account.type.icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .lineLimit(1)

                if let bank = account.bank, !bank.isEmpty {
                    Text(bank)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let balance = AccountValuation(
                transactionsController: transactionsController,
                investmentsController: investmentsController,
                savingsPlansController: savingsPlansController
            ).value(of: account)

            Text(balance, format: .currency(code: account.currency))
                .monospacedDigit()
                .foregroundStyle(balance >= 0 ? Color.primary : Color.red)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(.vertical, 6)
    }
}
