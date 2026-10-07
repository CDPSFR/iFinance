import SwiftUI
import Charts

/// Rapport « Taux d'épargne » : part des revenus mise de côté chaque mois, comparée à l'objectif
/// réglé dans Réglages › Général. Suit la période et le compte de la barre d'outils.
struct SavingsRateChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Objectif de taux d'épargne, en pourcentage des revenus
    @AppStorage(SettingsKeys.savingsRateGoal) private var goal = 15.0

    struct MonthPoint: Identifiable {
        let date: Date
        let income: Decimal
        let expense: Decimal

        var id: Date { date }
        var saving: Decimal { income - expense }
        /// Taux d'épargne en pourcentage ; nil sans revenu
        var rate: Double? {
            guard income > 0 else { return nil }
            return NSDecimalNumber(decimal: saving / income).doubleValue * 100
        }
    }

    @State private var selectedDate: Date?

    var body: some View {
        let points = self.points

        if points.isEmpty {
            ReportEmptyState(systemImage: "percent")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(points)
                    chartBlock(points)
                    tableBlock(points)
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ points: [MonthPoint]) -> some View {
        let income = points.reduce(Decimal(0)) { $0 + $1.income }
        let saving = points.reduce(Decimal(0)) { $0 + $1.saving }
        let average: Double? = income > 0 ? NSDecimalNumber(decimal: saving / income).doubleValue * 100 : nil
        let reached = points.filter { ($0.rate ?? -1) >= goal }.count
        let deficits = points.filter { $0.saving < 0 }
        let worst = deficits.min { $0.saving < $1.saving }

        return ReportTiles {
            StatTile(
                title: "Taux d'épargne moyen",
                value: average.map(percent) ?? "—",
                valueColor: color(for: average),
                detail: "sur \(points.count) mois"
            )

            StatTile(
                title: "Épargné sur la période",
                value: signed(saving),
                valueColor: saving >= 0 ? .green : .red,
                detail: "\(money(saving / Decimal(points.count))) par mois en moyenne"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Objectif",
                value: percent(goal),
                detail: "atteint \(reached) mois sur \(points.count)"
            )

            StatTile(
                title: deficits.count > 1 ? "Mois déficitaires" : "Mois déficitaire",
                value: "\(deficits.count)",
                valueColor: deficits.isEmpty ? .primary : .red,
                detail: worst.map { "\(monthName($0.date)) : \(money($0.saving))" } ?? "aucun sur la période"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ points: [MonthPoint]) -> some View {
        let selected = selectedPoint(in: points)

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("Part des revenus mise de côté chaque mois")

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Mois", point.date, unit: .month),
                        y: .value("Taux", point.rate ?? 0)
                    )
                    .foregroundStyle(color(for: point.rate))
                }

                RuleMark(y: .value("Objectif", goal))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("objectif \(percent(goal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                if let selected {
                    RuleMark(x: .value("Mois", selected.date, unit: .month))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ReportTooltip {
                                Text(monthName(selected.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(selected.rate.map(percent) ?? "Aucun revenu")
                                    .fontWeight(.semibold)
                                Text("Épargne \(signed(selected.saving))")
                                    .font(.caption)
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let rate = value.as(Double.self) {
                            Text(percent(rate))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 260)

            HStack(spacing: 14) {
                legend("Objectif atteint", .green)
                legend("Sous l'objectif", .orange)
                legend("Mois déficitaire", .red)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }

    private func selectedPoint(in points: [MonthPoint]) -> MonthPoint? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return points.first { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }

    // MARK: - Tableau

    private func tableBlock(_ points: [MonthPoint]) -> some View {
        ReportTable(
            columns: ["Mois", "Revenus", "Dépenses", "Épargne", "Taux"],
            rows: points.reversed().map { point in
                ReportRow(id: "\(point.date.timeIntervalSince1970)", cells: [
                    ReportCell(text: monthName(point.date)),
                    ReportCell(text: money(point.income)),
                    ReportCell(text: money(point.expense)),
                    ReportCell(text: signed(point.saving), color: point.saving >= 0 ? .green : .red),
                    ReportCell(text: point.rate.map(percent) ?? "—", color: color(for: point.rate))
                ])
            },
            footnote: "Taux d'épargne = (revenus − dépenses) ÷ revenus. L'objectif se règle dans Réglages › Général."
        )
    }

    // MARK: - Données

    /// Revenus et dépenses par mois, comme le rapport « Revenus et dépenses »
    private var points: [MonthPoint] {
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
            return MonthPoint(date: date, income: income, expense: expense)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Format

    private func color(for rate: Double?) -> Color {
        guard let rate else { return .secondary }
        if rate < 0 { return .red }
        return rate >= goal ? .green : .orange
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

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
}
