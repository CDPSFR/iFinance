import SwiftUI

/// Bandeau des filtres actifs (liste des transactions, rapports) : une étiquette par filtre,
/// retirable d'un clic, et « Tout effacer ». N'apparaît que si au moins un filtre est actif.
struct ActiveFiltersBar: View {
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController

    /// Libellé de la période, si l'écran en a un plus parlant (ex. « 12 derniers mois »)
    var periodTitle: String? = nil
    /// L'étiquette « Opérations sur titres masquées » n'a de sens que dans la liste des transactions
    var showsInvestmentOperationsFilter = true

    private var filters: TransactionFilters { transactionsController.filters }

    private var isVisible: Bool {
        filters.accountID != nil || filters.transactionType != nil || filters.categoryID != nil
            || filters.payeeID != nil || filters.dateRange != .all
            || (showsInvestmentOperationsFilter && !filters.showInvestmentOperations)
    }

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let accountID = filters.accountID,
                           let account = accountsController.getAccount(id: accountID) {
                            FilterBadge(text: account.name, icon: "creditcard") {
                                transactionsController.filterByAccount(nil)
                            }
                        }

                        if filters.dateRange != .all {
                            FilterBadge(text: periodTitle ?? filters.dateRange.displayName, icon: "calendar") {
                                update { $0.dateRange = .all }
                            }
                        }

                        if let type = filters.transactionType {
                            FilterBadge(text: type.displayName, icon: type.icon) {
                                update { $0.transactionType = nil }
                            }
                        }

                        if let categoryID = filters.categoryID {
                            FilterBadge(text: categoriesController.getCategoryPath(for: categoryID), icon: "folder") {
                                update { $0.categoryID = nil }
                            }
                        }

                        if let payeeID = filters.payeeID,
                           let payee = payeesController.getPayee(id: payeeID) {
                            FilterBadge(text: payee.name, icon: "person.crop.circle") {
                                update { $0.payeeID = nil }
                            }
                        }

                        if showsInvestmentOperationsFilter, !filters.showInvestmentOperations {
                            FilterBadge(text: "Opérations sur titres masquées", icon: "chart.line.uptrend.xyaxis") {
                                update { $0.showInvestmentOperations = true }
                            }
                        }

                        Button {
                            transactionsController.resetFilters()
                        } label: {
                            Text("Tout effacer")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                Divider()
            }
        }
    }

    private func update(_ change: (inout TransactionFilters) -> Void) {
        var newFilters = transactionsController.filters
        change(&newFilters)
        transactionsController.updateFilters(newFilters)
    }
}
