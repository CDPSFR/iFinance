import SwiftUI
import Charts

/// Rapport « Dépenses par catégorie » ou « Revenus par catégorie » selon `flow` :
/// chiffres clés, anneau de répartition, tableau par catégorie.
/// Les sous-catégories sont regroupées sous leur catégorie parente.
struct CategoriesChartView: View {
    var flow: ReportFlow = .expense

    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var appSettings: AppSettings

    /// Nombre de parts distinctes dans l'anneau ; le reste est regroupé dans « Autres »
    private static let maxSlices = 7

    var body: some View {
        let expenses = self.expenses
        let items = breakdown(expenses)

        if items.isEmpty {
            ReportEmptyState(
                systemImage: "chart.pie",
                message: "Aucune transaction catégorisée en \(flow.plural) sur la période et les comptes choisis."
            )
        } else {
            let total = items.total
            let months = max(monthCount(expenses), 1)

            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    ReportTiles {
                        StatTile(title: flow.title, value: money(total))
                            .privacyBlur(hidden: appSettings.hideAmounts)
                        StatTile(title: "Moyenne mensuelle", value: money(total / Decimal(months)), detail: "sur \(months) mois")
                            .privacyBlur(hidden: appSettings.hideAmounts)
                        StatTile(
                            title: "Première catégorie",
                            value: items[0].name,
                            detail: "\(percent(items[0].share)) des \(flow.plural)"
                        )
                        StatTile(title: "Catégories", value: "\(items.count)")
                    }

                    ReportDonutBlock(
                        title: "Répartition des \(flow.plural)",
                        items: slices(items),
                        total: total,
                        money: money
                    )

                    ReportTable(
                        columns: ["Catégorie", "Transactions", "Total", "Moyenne par mois", "Part"],
                        rows: items.map { item in
                            ReportRow(id: item.id.uuidString, cells: [
                                ReportCell(text: item.name),
                                ReportCell(text: "\(item.count)", color: .secondary, isAmount: false),
                                ReportCell(text: money(item.amount)),
                                ReportCell(text: money(item.amount / Decimal(months))),
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

    /// Dépenses catégorisées de la période, sur les comptes inclus dans les rapports
    private var expenses: [Transaction] {
        transactionsController.filteredTransactions.filter {
            $0.type == flow.transactionType
                && $0.status != .skipped
                && $0.categoryID != nil
                && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID)
        }
    }

    private func monthCount(_ transactions: [Transaction]) -> Int {
        let calendar = Calendar.current
        return Set(transactions.map { calendar.dateComponents([.year, .month], from: $0.date) }).count
    }

    /// Total par catégorie racine
    private func breakdown(_ transactions: [Transaction]) -> [ReportBreakdownItem] {
        var totals: [UUID: (name: String, count: Int, amount: Decimal)] = [:]

        for transaction in transactions {
            guard let categoryID = transaction.categoryID,
                  let category = categoriesController.getCategory(id: categoryID) else { continue }
            let root = category.parentID.flatMap { categoriesController.getCategory(id: $0) } ?? category
            var entry = totals[root.id] ?? (root.name, 0, 0)
            entry.count += 1
            entry.amount += abs(transaction.amount)
            totals[root.id] = entry
        }

        return .breakdown(totals.map { (id: $0.key, name: $0.value.name, count: $0.value.count, amount: $0.value.amount) })
    }

    /// Parts de l'anneau : les premières catégories, puis « Autres »
    private func slices(_ items: [ReportBreakdownItem]) -> [ReportBreakdownItem] {
        guard items.count > Self.maxSlices + 1 else { return items }
        let head = Array(items.prefix(Self.maxSlices))
        let tail = items.dropFirst(Self.maxSlices)
        let other = ReportBreakdownItem(
            id: UUID(),
            name: "Autres",
            count: tail.reduce(0) { $0 + $1.count },
            amount: tail.reduce(Decimal(0)) { $0 + $1.amount },
            share: tail.reduce(0) { $0 + $1.share }
        )
        return head + [other]
    }
}
