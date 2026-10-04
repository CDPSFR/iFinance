import SwiftUI
import Charts

/// Rapport « Solde mensuel » : chiffres clés, barres au-dessus et en dessous de zéro, tableau mensuel
struct MonthlyBalanceChartView: View {

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    struct MonthlyBalance: Identifiable {
        let date: Date
        let income: Decimal
        let expense: Decimal

        var id: Date { date }
        var balance: Decimal { income - expense }
        var kind: String { balance >= 0 ? "Excédent" : "Déficit" }
    }

    @State private var selectedDate: Date?

    var body: some View {
        let months = balanceData

        if months.isEmpty {
            ReportEmptyState(systemImage: "chart.bar.xaxis")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(months)
                    chartBlock(months)
                    tableBlock(months)
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ months: [MonthlyBalance]) -> some View {
        let average = months.reduce(Decimal(0)) { $0 + $1.balance } / Decimal(months.count)
        let positive = months.filter { $0.balance >= 0 }.count
        let best = months.max { $0.balance < $1.balance }
        let worst = months.min { $0.balance < $1.balance }

        return ReportTiles {
            StatTile(
                title: "Solde moyen",
                value: signed(average),
                valueColor: average >= 0 ? .green : .red,
                detail: "par mois"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "Mois excédentaires", value: "\(positive) sur \(months.count)")

            StatTile(
                title: "Meilleur mois",
                value: signed(best?.balance ?? 0),
                valueColor: (best?.balance ?? 0) >= 0 ? .green : .red,
                detail: best.map { monthName($0.date) }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Moins bon mois",
                value: signed(worst?.balance ?? 0),
                valueColor: (worst?.balance ?? 0) >= 0 ? .green : .red,
                detail: worst.map { monthName($0.date) }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ months: [MonthlyBalance]) -> some View {
        let selected = selectedMonth(in: months)

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("Solde de chaque mois (revenus moins dépenses)")

            Chart {
                ForEach(months) { month in
                    BarMark(
                        x: .value("Mois", month.date, unit: .month),
                        y: .value("Solde", NSDecimalNumber(decimal: month.balance).doubleValue)
                    )
                    .foregroundStyle(by: .value("Type", month.kind))
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Zéro", 0))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let selected {
                    RuleMark(x: .value("Mois", selected.date, unit: .month))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ReportTooltip {
                                Text(monthName(selected.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Revenus : \(money(selected.income))")
                                Text("Dépenses : \(money(selected.expense))")
                                Text("Solde : \(signed(selected.balance))")
                                    .fontWeight(.semibold)
                            }
                        }
                }
            }
            .chartForegroundStyleScale([
                "Excédent": Color.green,
                "Déficit": Color.red
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .chartXSelection(value: $selectedDate)
            .frame(height: 260)
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    private func selectedMonth(in months: [MonthlyBalance]) -> MonthlyBalance? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return months.first { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }

    // MARK: - Tableau mensuel

    private func tableBlock(_ months: [MonthlyBalance]) -> some View {
        ReportTable(
            columns: ["Mois", "Revenus", "Dépenses", "Solde du mois"],
            rows: months.reversed().map { month in
                ReportRow(id: "\(month.date.timeIntervalSince1970)", cells: [
                    ReportCell(text: monthName(month.date)),
                    ReportCell(text: money(month.income)),
                    ReportCell(text: money(month.expense)),
                    ReportCell(text: signed(month.balance), color: month.balance >= 0 ? .green : .red)
                ])
            }
        )
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func signed(_ amount: Decimal) -> String {
        (amount > 0 ? "+" : "") + money(amount)
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year()).capitalized
    }

    /// Revenus et dépenses par mois, sur les transactions filtrées et les comptes inclus dans les rapports
    private var balanceData: [MonthlyBalance] {
        let calendar = Calendar.current
        let filtered = transactionsController.filteredTransactions
            .filter { $0.status != .skipped && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID) }

        let grouped = Dictionary(grouping: filtered) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date)) ?? transaction.date
        }

        return grouped.map { date, transactions in
            let income = transactions
                .filter { $0.signedAmount > 0 }
                .reduce(Decimal(0)) { $0 + $1.signedAmount }
            let expense = transactions
                .filter { $0.signedAmount < 0 }
                .reduce(Decimal(0)) { $0 + abs($1.signedAmount) }
            return MonthlyBalance(date: date, income: income, expense: expense)
        }
        .sorted { $0.date < $1.date }
    }
}
