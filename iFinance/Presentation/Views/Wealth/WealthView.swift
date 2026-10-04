import SwiftUI

struct WealthView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patrimoine")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if let book = booksController.currentBook {
                        Text(book.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                // Totaux
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    DashboardCard(
                        title: "Patrimoine net",
                        value: formatted(netWorth),
                        icon: "building.columns",
                        color: .purple
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    DashboardCard(
                        title: "Actifs",
                        value: formatted(assets),
                        icon: "arrow.up.right.circle",
                        color: .green
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)

                    DashboardCard(
                        title: "Dettes",
                        value: formatted(debts),
                        icon: "arrow.down.right.circle",
                        color: .red
                    )
                    .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .padding(.horizontal)

                if groups.isEmpty {
                    ContentUnavailableView(
                        "Aucun compte",
                        systemImage: "building.columns",
                        description: Text("Créez un compte pour suivre votre patrimoine.")
                    )
                    .padding(.top, 40)
                }

                // Détail par groupe
                ForEach(groups, id: \.group) { item in
                    WealthGroupSection(
                        group: item.group,
                        accounts: item.accounts,
                        total: item.total,
                        share: share(of: item.total),
                        currency: currency,
                        valuation: valuation
                    )
                    .padding(.horizontal)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
    }

    // MARK: - Computed Properties

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController, investmentsController: investmentsController, savingsPlansController: savingsPlansController)
    }

    private var accounts: [Account] {
        accountsController.activeAccounts.filter { !$0.isExcludedFromReports }
    }

    private var groups: [(group: AccountGroup, accounts: [Account], total: Decimal)] {
        Dictionary(grouping: accounts) { $0.type.group }
            .map { group, accounts in
                let sorted = accounts.sorted { valuation.value(of: $0) > valuation.value(of: $1) }
                return (group, sorted, valuation.total(of: accounts))
            }
            .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }

    private var netWorth: Decimal {
        valuation.total(of: accounts)
    }

    private var assets: Decimal {
        accounts.map { valuation.value(of: $0) }.filter { $0 > 0 }.reduce(0, +)
    }

    private var debts: Decimal {
        accounts.map { valuation.value(of: $0) }.filter { $0 < 0 }.reduce(0, +)
    }

    /// Part d'un groupe dans les actifs (nil pour un groupe négatif)
    private func share(of total: Decimal) -> Double? {
        guard total > 0, assets > 0 else { return nil }
        return Double(truncating: NSDecimalNumber(decimal: total / assets))
    }

    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }
}

// MARK: - Supporting Views

struct WealthGroupSection: View {
    let group: AccountGroup
    let accounts: [Account]
    let total: Decimal
    let share: Double?
    let currency: String
    let valuation: AccountValuation
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(group.color)
                    .frame(width: 10, height: 10)

                Text(group.displayName)
                    .font(.headline)

                if let share {
                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(total, format: .currency(code: currency))
                    .font(.headline)
                    .foregroundColor(total >= 0 ? .primary : .red)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }

            VStack(spacing: 8) {
                ForEach(accounts) { account in
                    HStack(spacing: 12) {
                        Image(systemName: account.type.icon)
                            .foregroundColor(account.type.color)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(account.bank.map { "\(account.type.displayName) · \($0)" } ?? account.type.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            let value = valuation.value(of: account)
                            Text(value, format: .currency(code: account.currency))
                                .foregroundColor(value >= 0 ? .primary : .red)
                                .privacyBlur(hidden: appSettings.hideAmounts)

                            let gain = valuation.unrealizedGain(of: account)
                            if account.type.trackingMode != .transactions, gain != 0 {
                                Text("\(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: account.currency))) latents")
                                    .font(.caption)
                                    .foregroundColor(gain >= 0 ? .green : .red)
                                    .privacyBlur(hidden: appSettings.hideAmounts)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .cardBackground(cornerRadius: 12)
    }
}
