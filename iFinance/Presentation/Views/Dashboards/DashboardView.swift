import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var appSettings: AppSettings
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vue d'ensemble")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if let book = booksController.currentBook {
                            Text(book.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Date du jour
                    Text(Date(), style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Cartes récapitulatives
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    // Liquidités (comptes courants, cartes)
                    DashboardCard(
                        title: "Liquidités",
                        value: totalBalance,
                        icon: "banknote",
                        color: .blue
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    // Patrimoine net (tous les comptes)
                    DashboardCard(
                        title: "Patrimoine net",
                        value: formatted(valuation.total(of: wealthAccounts)),
                        icon: "building.columns",
                        color: .purple
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)
                    
                    // Nombre de comptes
                    DashboardCard(
                        title: "Comptes actifs",
                        value: "\(accountsController.activeAccounts.count)",
                        icon: "creditcard",
                        color: .green
                    )
                    
                    // Transactions ce mois
                    DashboardCard(
                        title: "Transactions ce mois",
                        value: "\(transactionsThisMonth)",
                        icon: "list.bullet",
                        color: .orange
                    )
                }
                .padding(.horizontal)
                
                // Dépenses ce mois
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    DashboardCard(
                        title: "Dépenses ce mois",
                        value: expensesThisMonth,
                        icon: "arrow.down.circle",
                        color: .red
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    DashboardCard(
                        title: "Revenus ce mois",
                        value: incomeThisMonth,
                        icon: "arrow.up.circle",
                        color: .green
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .padding(.horizontal)
                
                // Liste des comptes
                if !accountsController.activeAccounts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Vos comptes")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button {
                                // Navigation vers liste des comptes (à implémenter si besoin)
                            } label: {
                                Text("Voir tout")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        
                        ForEach(accountsController.activeAccounts) { account in
                            AccountSummaryRow(account: account)
                                .padding(.horizontal)
                        }
                    }
                }
                
                // Top catégories ce mois (si transactions disponibles)
                if !transactionsController.allTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top catégories ce mois")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(topCategories, id: \.category) { item in
                            TopCategoryRow(
                                category: item.category,
                                amount: item.amount,
                                currency: booksController.currentBook?.currency ?? "EUR"
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController)
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
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct AccountSummaryRow: View {
    let account: Account
    @EnvironmentObject var transactionsController: TransactionsController
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
            
            let balance = AccountValuation(transactionsController: transactionsController)
                .value(of: account)
            
            Text(balance, format: .currency(code: account.currency))
                .font(.headline)
                .foregroundColor(balance >= 0 ? .green : .red)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
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
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
