import SwiftUI
import Charts

/// Rapport « Dépenses par compte » ou « Revenus par compte » selon `flow` :
/// chiffres clés, barres classées, tableau par compte
struct AccountsChartView: View {
    var flow: ReportFlow = .expense

    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        let items = breakdown

        if items.isEmpty {
            ReportEmptyState(systemImage: "creditcard")
        } else {
            let total = items.total

            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    ReportTiles {
                        StatTile(title: flow.title, value: money(total))
                            .privacyBlur(hidden: appSettings.hideAmounts)
                        StatTile(title: "Comptes", value: "\(items.count)", detail: "avec au moins \(flow.oneOf)")
                        StatTile(
                            title: "Premier compte",
                            value: items[0].name,
                            detail: "\(percent(items[0].share)) des \(flow.plural)"
                        )
                        StatTile(title: "Moyenne par compte", value: money(total / Decimal(items.count)))
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    }

                    ReportBarsBlock(title: "\(flow.title) par compte", items: items, money: money, color: flow.color)

                    ReportTable(
                        columns: ["Compte", "Transactions", "Total", flow.averageTitle, "Part"],
                        rows: items.map { item in
                            ReportRow(id: item.id.uuidString, cells: [
                                ReportCell(text: item.name),
                                ReportCell(text: "\(item.count)", color: .secondary, isAmount: false),
                                ReportCell(text: money(item.amount)),
                                ReportCell(text: money(item.amount / Decimal(max(item.count, 1)))),
                                ReportCell(text: percent(item.share), color: .secondary)
                            ])
                        }
                    )
                }
            }
        }
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Dépenses de la période par compte, sur les comptes inclus dans les rapports
    private var breakdown: [ReportBreakdownItem] {
        let expenses = transactionsController.filteredTransactions.filter {
            $0.type == flow.transactionType
                && $0.status != .skipped
                && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID)
        }

        let grouped = Dictionary(grouping: expenses) { $0.accountID }
        return .breakdown(grouped.compactMap { accountID, transactions in
            guard let account = accountsController.getAccount(id: accountID) else { return nil }
            return (
                id: accountID,
                name: account.name,
                count: transactions.count,
                amount: transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
            )
        })
    }
}
