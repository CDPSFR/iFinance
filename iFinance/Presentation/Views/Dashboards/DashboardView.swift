import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var appSettings: AppSettings
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                // Chiffres clés (le titre est dans la barre d'outils)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: NativeMetrics.groupSpacing)],
                    spacing: NativeMetrics.groupSpacing
                ) {
                    StatTile(
                        title: "Patrimoine net",
                        value: formatted(valuation.total(of: wealthAccounts)),
                        detail: accountsDetail
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    StatTile(
                        title: "Liquidités",
                        value: totalBalance,
                        detail: "Comptes courants et cartes"
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    StatTile(
                        title: "Revenus ce mois",
                        value: incomeThisMonth,
                        detail: monthName
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    StatTile(
                        title: "Dépenses ce mois",
                        value: expensesThisMonth,
                        detail: "\(transactionsThisMonth) transaction\(transactionsThisMonth > 1 ? "s" : "") ce mois"
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)
                }

                HStack(alignment: .top, spacing: NativeMetrics.groupSpacing) {
                    // Comptes
                    if !accountsController.activeAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            GroupTitle("Comptes")
                                .padding(.bottom, 8)

                            ForEach(Array(accountsController.activeAccounts.enumerated()), id: \.element.id) { index, account in
                                if index > 0 {
                                    Divider()
                                }
                                DashboardAccountRow(account: account)
                            }
                        }
                        .padding(NativeMetrics.groupPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()
                    }

                    // Top catégories ce mois
                    if !topCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            GroupTitle("Top catégories ce mois")

                            ForEach(topCategories, id: \.category) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.category)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(item.amount, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                                            .monospacedDigit()
                                            .privacyBlur(hidden: appSettings.hideAmounts)
                                    }

                                    ProgressView(value: fraction(of: item.amount))
                                        .progressViewStyle(.linear)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(NativeMetrics.groupPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()
                    }
                }
            }
            .padding(NativeMetrics.pagePadding)
        }
        .pageBackground()
    }

    // MARK: - Présentation

    private var accountsDetail: String {
        let count = accountsController.activeAccounts.count
        return "\(count) compte\(count > 1 ? "s" : "") actif\(count > 1 ? "s" : "")"
    }

    private var monthName: String {
        Date().formatted(.dateTime.month(.wide).year()).capitalized
    }

    /// Part d'un montant par rapport à la première catégorie, pour la barre de progression
    private func fraction(of amount: Decimal) -> Double {
        guard let maximum = topCategories.first?.amount, maximum > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: amount / maximum).doubleValue
        return min(max(ratio, 0), 1)
    }

    // MARK: - Computed Properties
    
    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController, investmentsController: investmentsController, savingsPlansController: savingsPlansController)
    }

    private var wealthAccounts: [Account] {
        accountsController.activeAccounts.filter { !$0.isExcludedFromReports }
    }

    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: booksController.currentBook?.currency ?? "EUR"))
    }

    private var totalBalance: String {
        formatted(valuation.total(of: accountsController.activeAccounts.filter { $0.countsInCashFlow }))
    }
    
    private var cashFlowAccountIDs: Set<UUID> {
        accountsController.cashFlowAccountIDs
    }

    private var transactionsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        
        return transactionsController.allTransactions.filter { tx in
            tx.date >= start && tx.date < end
        }.count
    }
    
    private var expensesThisMonth: String {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        
        let total = transactionsController.allTransactions
            .filter { tx in
                tx.date >= start && tx.date < end && tx.type == .debit
                    && cashFlowAccountIDs.contains(tx.accountID)
            }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
        
        if let currency = booksController.currentBook?.currency {
            return total.formatted(.currency(code: currency))
        }
        return total.formatted(.currency(code: "EUR"))
    }
    
    private var incomeThisMonth: String {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        
        let total = transactionsController.allTransactions
            .filter { tx in
                tx.date >= start && tx.date < end && tx.type == .credit
                    && cashFlowAccountIDs.contains(tx.accountID)
            }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
        
        if let currency = booksController.currentBook?.currency {
            return total.formatted(.currency(code: currency))
        }
        return total.formatted(.currency(code: "EUR"))
    }
    
    private var topCategories: [(category: String, amount: Decimal)] {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        
        // Grouper par catégorie
        let expensesByCategory = Dictionary(grouping: transactionsController.allTransactions.filter { tx in
            tx.date >= start && tx.date < end && tx.type == .debit && tx.categoryID != nil
                && cashFlowAccountIDs.contains(tx.accountID)
        }) { tx in
            tx.categoryID!
        }
        
        // Calculer les totaux
        let totals = expensesByCategory.map { (categoryID, transactions) -> (category: String, amount: Decimal) in
            let total = transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
            let categoryName = categoriesController.getCategoryPath(for: categoryID)
            return (categoryName, total)
        }
        
        // Trier par montant décroissant et prendre le top 5
        return totals.sorted { $0.amount > $1.amount }.prefix(5).map { $0 }
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
