import SwiftUI
import Charts

/// Rapport « Évolution du solde » : chiffres clés, courbe du solde cumulé, tableau mensuel
struct BalanceChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    struct DataPoint: Identifiable {
        let date: Date
        let balance: Decimal

        var id: Date { date }
        var doubleBalance: Double { NSDecimalNumber(decimal: balance).doubleValue }
    }

    /// Solde de fin de mois et variation par rapport à la fin du mois précédent
    struct MonthPoint: Identifiable {
        let date: Date
        let balance: Decimal
        let variation: Decimal

        var id: Date { date }
    }

    @State private var selectedDate: Date?

    var body: some View {
        let series = self.series

        if series.points.isEmpty {
            ReportEmptyState(systemImage: "chart.line.uptrend.xyaxis")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(series.points, start: series.start)
                    chartBlock(series.points)
                    tableBlock(series.points, start: series.start)
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ points: [DataPoint], start: Decimal) -> some View {
        let current = points.last?.balance ?? 0
        let variation = current - start
        let highest = points.max { $0.balance < $1.balance }
        let lowest = points.min { $0.balance < $1.balance }

        return ReportTiles {
            StatTile(title: "Solde actuel", value: money(current))
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Variation",
                value: signed(variation),
                valueColor: variation >= 0 ? .green : .red,
                detail: "sur la période"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Plus haut",
                value: money(highest?.balance ?? 0),
                detail: highest.map { day($0.date) }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Plus bas",
                value: money(lowest?.balance ?? 0),
                detail: lowest.map { day($0.date) }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ points: [DataPoint]) -> some View {
        let selected = selectedPoint(in: points)
        let low = points.map { $0.doubleBalance }.min() ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle(accountFilterName.map { "Solde de \($0)" } ?? "Solde cumulé des comptes")

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", low),
                        yEnd: .value("Solde", point.doubleBalance)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.14))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Solde", point.doubleBalance)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let selected {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ReportTooltip {
                                Text(day(selected.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(money(selected.balance))
                                    .fontWeight(.semibold)
                            }
                        }

                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Solde", selected.doubleBalance)
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 260)
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    private func selectedPoint(in points: [DataPoint]) -> DataPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    // MARK: - Tableau mensuel

    private func tableBlock(_ points: [DataPoint], start: Decimal) -> some View {
        let months = monthPoints(points, start: start)

        return ReportTable(
            columns: ["Mois", "Solde de fin de mois", "Variation"],
            rows: months.reversed().map { month in
                ReportRow(id: "\(month.date.timeIntervalSince1970)", cells: [
                    ReportCell(text: month.date.formatted(.dateTime.month(.wide).year()).capitalized),
                    ReportCell(text: money(month.balance), color: month.balance < 0 ? .red : .primary),
                    ReportCell(text: signed(month.variation), color: month.variation >= 0 ? .green : .red)
                ])
            }
        )
    }

    private func monthPoints(_ points: [DataPoint], start: Decimal) -> [MonthPoint] {
        let calendar = Calendar.current
        var result: [MonthPoint] = []
        var previous = start

        let grouped = Dictionary(grouping: points) { point in
            calendar.date(from: calendar.dateComponents([.year, .month], from: point.date)) ?? point.date
        }
        for month in grouped.keys.sorted() {
            guard let last = grouped[month]?.max(by: { $0.date < $1.date }) else { continue }
            result.append(MonthPoint(date: month, balance: last.balance, variation: last.balance - previous))
            previous = last.balance
        }
        return result
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

    private func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Nom du compte si le rapport est filtré sur un seul compte
    private var accountFilterName: String? {
        transactionsController.filters.accountID.flatMap { accountsController.getAccount(id: $0)?.name }
    }

    /// Solde jour par jour sur la période, et solde à l'ouverture de la période.
    /// Sans période choisie, la courbe part de la première transaction.
    private var series: (points: [DataPoint], start: Decimal) {
        let accounts: [Account]
        if let accountID = transactionsController.filters.accountID {
            guard let account = accountsController.getAccount(id: accountID) else { return ([], 0) }
            accounts = [account]
        } else {
            accounts = accountsController.activeAccounts.filter { $0.countsInCashFlow }
        }
        guard !accounts.isEmpty else { return ([], 0) }

        let accountIDs = Set(accounts.map { $0.id })
        let calendar = Calendar.current
        let transactions = transactionsController.allTransactions
            .filter { accountIDs.contains($0.accountID) && $0.status != .skipped }
        guard let firstDate = transactions.map({ $0.date }).min() else { return ([], 0) }

        let today = calendar.startOfDay(for: Date())
        var startDate = calendar.startOfDay(for: firstDate)
        var endDate = today
        if let dates = transactionsController.filters.dateRange.dates() {
            startDate = max(startDate, calendar.startOfDay(for: dates.0))
            // La fin de période est exclusive ; la courbe ne dépasse pas aujourd'hui
            let lastDay = calendar.date(byAdding: .day, value: -1, to: dates.1) ?? dates.1
            endDate = min(today, calendar.startOfDay(for: lastDay))
        }
        guard startDate <= endDate else { return ([], 0) }

        // Solde à l'ouverture : soldes initiaux et transactions antérieures à la période
        var balance = accounts.reduce(Decimal(0)) { $0 + $1.initialBalance }
        var byDay: [Date: Decimal] = [:]
        for transaction in transactions {
            let transactionDay = calendar.startOfDay(for: transaction.date)
            if transactionDay < startDate {
                balance += transaction.signedAmount
            } else if transactionDay <= endDate {
                byDay[transactionDay, default: 0] += transaction.signedAmount
            }
        }
        let start = balance

        var points: [DataPoint] = []
        var current = startDate
        while current <= endDate {
            balance += byDay[current] ?? 0
            points.append(DataPoint(date: current, balance: balance))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return (points, start)
    }
}
