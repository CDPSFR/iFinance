import SwiftUI
import Charts

/// Rapport « Revenus et dépenses » : chiffres clés, barres groupées par mois, tableau mensuel
struct CashFlowChartView: View {

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    // MARK: - Data Models

    struct DataPoint: Identifiable {
        let date: Date
        let income: Decimal
        let expense: Decimal

        var id: Date { date }
        var saving: Decimal { income - expense }

        /// Taux d'épargne du mois, nil sans revenus
        var savingRate: Double? {
            guard income > 0 else { return nil }
            return Double(truncating: NSDecimalNumber(decimal: saving / income))
        }
    }

    struct SeriesPoint: Identifiable {
        let date: Date
        let type: String // "Revenus" ou "Dépenses"
        let amount: Decimal

        var id: String { "\(type)-\(date.timeIntervalSince1970)" }
    }

    // MARK: - State

    @State private var selectedDate: Date?

    // MARK: - Body

    var body: some View {
        let points = dataPoints

        if points.isEmpty {
            emptyStateView
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

    private func tiles(_ points: [DataPoint]) -> some View {
        let income = points.reduce(Decimal(0)) { $0 + $1.income }
        let expense = points.reduce(Decimal(0)) { $0 + $1.expense }
        let saving = income - expense
        let rate: String = income > 0
            ? Double(truncating: NSDecimalNumber(decimal: saving / income)).formatted(.percent.precision(.fractionLength(0)))
            : "—"

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: NativeMetrics.groupSpacing)],
            spacing: NativeMetrics.groupSpacing
        ) {
            StatTile(title: "Revenus", value: money(income))
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "Dépenses", value: money(expense))
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Épargne",
                value: money(saving),
                valueColor: saving >= 0 ? .green : .red
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "Taux d'épargne", value: rate)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ points: [DataPoint]) -> some View {
        let series = points.flatMap { point in
            [
                SeriesPoint(date: point.date, type: "Revenus", amount: point.income),
                SeriesPoint(date: point.date, type: "Dépenses", amount: point.expense)
            ]
        }
        let selected = selectedPoint(in: points)

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("Revenus et dépenses par mois")

            Chart {
                ForEach(series) { point in
                    BarMark(
                        x: .value("Mois", point.date, unit: .month),
                        y: .value("Montant", NSDecimalNumber(decimal: point.amount).doubleValue)
                    )
                    .foregroundStyle(by: .value("Type", point.type))
                    .position(by: .value("Type", point.type))
                    .cornerRadius(3)
                }

                if let selected {
                    RuleMark(x: .value("Mois", selected.date, unit: .month))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            tooltipView(for: selected)
                        }
                }
            }
            .chartForegroundStyleScale([
                "Revenus": Color.green,
                "Dépenses": Color.red
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

    private func selectedPoint(in points: [DataPoint]) -> DataPoint? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return points.first { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }

    private func tooltipView(for point: DataPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(point.date, format: .dateTime.month(.wide).year())
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Revenus : \(money(point.income))")
            Text("Dépenses : \(money(point.expense))")
            Text("Épargne : \(money(point.saving))")
                .fontWeight(.semibold)
        }
        .font(.callout)
        .monospacedDigit()
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator)
        )
    }

    // MARK: - Tableau mensuel

    private func tableBlock(_ points: [DataPoint]) -> some View {
        let rows = Array(points.reversed())

        return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                Text("Mois")
                    .gridColumnAlignment(.leading)
                Text("Revenus")
                Text("Dépenses")
                Text("Épargne")
                Text("Taux")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, point in
                Divider()

                GridRow {
                    Text(point.date.formatted(.dateTime.month(.wide).year()).capitalized)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    amountCell(point.income)
                    amountCell(point.expense)
                    amountCell(point.saving, color: point.saving >= 0 ? .green : .red)
                    Text(point.savingRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                        .foregroundStyle(.secondary)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(index % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NativeMetrics.groupCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NativeMetrics.groupCornerRadius, style: .continuous)
                .strokeBorder(.separator)
        )
    }

    private func amountCell(_ amount: Decimal, color: Color = .primary) -> some View {
        Text(amount, format: .currency(code: currency))
            .foregroundStyle(color)
            .privacyBlur(hidden: appSettings.hideAmounts)
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    /// Revenus et dépenses par mois, sur les transactions filtrées et les comptes inclus dans les rapports
    private var dataPoints: [DataPoint] {
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
            return DataPoint(date: date, income: income, expense: expense)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - État vide

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Aucune donnée à afficher",
            systemImage: "chart.bar",
            description: Text("Aucune transaction ne correspond à la période et aux comptes choisis.")
        )
    }
}
