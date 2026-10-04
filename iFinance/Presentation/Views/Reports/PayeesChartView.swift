import SwiftUI
import Charts

/// Rapport « Dépenses par bénéficiaire » ou « Revenus par bénéficiaire » selon `flow` :
/// chiffres clés, barres des premiers bénéficiaires, tableau
struct PayeesChartView: View {
    var flow: ReportFlow = .expense

    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var appSettings: AppSettings

    private static let chartCount = 10
    private static let tableCount = 50

    var body: some View {
        let items = breakdown

        if items.isEmpty {
            ReportEmptyState(
                systemImage: "person.2",
                message: "Aucune transaction avec bénéficiaire en \(flow.plural) sur la période et les comptes choisis."
            )
        } else {
            let total = items.total
            let top = Array(items.prefix(Self.chartCount))
            let topShare = top.reduce(0) { $0 + $1.share }

            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    ReportTiles {
                        StatTile(title: flow == .expense ? "Bénéficiaires" : "Sources de revenus", value: "\(items.count)", detail: "avec au moins \(flow.oneOf)")
                        StatTile(title: flow.title, value: money(total))
                            .privacyBlur(hidden: appSettings.hideAmounts)
                        StatTile(
                            title: flow == .expense ? "Premier bénéficiaire" : "Première source",
                            value: items[0].name,
                            detail: "\(percent(items[0].share)) des \(flow.plural)"
                        )
                        StatTile(
                            title: top.count == 1 ? "Le premier" : "Les \(top.count) premiers",
                            value: percent(topShare),
                            detail: "des \(flow.plural)"
                        )
                    }

                    ReportBarsBlock(
                        title: flow == .expense ? "Bénéficiaires où vous dépensez le plus" : "D'où viennent vos revenus",
                        items: top,
                        money: money,
                        color: flow.color
                    )

                    ReportTable(
                        columns: ["Bénéficiaire", "Transactions", "Total", flow.averageTitle, "Part"],
                        rows: items.prefix(Self.tableCount).map { item in
                            ReportRow(id: item.id.uuidString, cells: [
                                ReportCell(text: item.name),
                                ReportCell(text: "\(item.count)", color: .secondary, isAmount: false),
                                ReportCell(text: money(item.amount)),
                                ReportCell(text: money(item.amount / Decimal(max(item.count, 1)))),
                                ReportCell(text: percent(item.share), color: .secondary)
                            ])
                        },
                        footnote: items.count > Self.tableCount
                            ? "Les \(Self.tableCount) premiers bénéficiaires sur \(items.count)."
                            : nil
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

    /// Dépenses de la période par bénéficiaire, sur les comptes inclus dans les rapports
    private var breakdown: [ReportBreakdownItem] {
        let expenses = transactionsController.filteredTransactions.filter {
            $0.type == flow.transactionType
                && $0.status != .skipped
                && $0.payeeID != nil
                && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID)
        }

        let grouped = Dictionary(grouping: expenses) { $0.payeeID ?? UUID() }
        return .breakdown(grouped.compactMap { payeeID, transactions in
            guard let payee = payeesController.getPayee(id: payeeID) else { return nil }
            return (
                id: payeeID,
                name: payee.name,
                count: transactions.count,
                amount: transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
            )
        })
    }
}
