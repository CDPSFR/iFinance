import SwiftUI
import Charts

/// Rapports « Tendances des dépenses » et « Tendances des revenus » (selon `flow`) : montants mensuels empilés par catégorie principale,
/// et tendance récente de chaque catégorie. Suit la période et le compte de la barre d'outils.
struct CategoryTrendsChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    var flow: ReportFlow = .expense

    /// Catégories affichées séparément ; les suivantes sont regroupées dans « Autres »
    private static let maxSeries = 6
    /// Nombre de mois récents comparés à la moyenne de la période
    private static let recentMonths = 3

    struct Cell: Identifiable {
        let month: Date
        let post: String
        let amount: Decimal

        var id: String { "\(month.timeIntervalSince1970)-\(post)" }
    }

    struct Trend: Identifiable {
        let id: String
        let name: String
        let total: Decimal
        let average: Decimal
        let recentAverage: Decimal
        let last: Decimal

        /// Écart de la moyenne récente à la moyenne de la période ; nil sans dépense moyenne
        var change: Double? {
            guard average > 0 else { return nil }
            return NSDecimalNumber(decimal: (recentAverage - average) / average).doubleValue
        }
    }

    var body: some View {
        let data = self.data

        if data.months.isEmpty {
            ReportEmptyState(systemImage: "chart.bar.xaxis", message: "Aucun\(flow == .expense ? "e dépense" : " revenu") sur la période et les comptes choisis.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(data)
                    chartBlock(data)
                    tableBlock(data)
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ data: TrendData) -> some View {
        let totals = data.monthTotals
        let total = totals.values.reduce(Decimal(0), +)
        let peak = totals.max { $0.value < $1.value }
        let moving = data.trends.filter { $0.id != ReportPost.othersID && $0.change != nil }
        let rising = moving.max { ($0.change ?? 0) < ($1.change ?? 0) }
        let falling = moving.min { ($0.change ?? 0) < ($1.change ?? 0) }

        return ReportTiles {
            StatTile(
                title: flow == .expense ? "Dépense mensuelle moyenne" : "Revenu mensuel moyen",
                value: money(total / Decimal(max(data.months.count, 1))),
                detail: "sur \(data.months.count) mois"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Mois le plus élevé",
                value: peak.map { monthName($0.key) } ?? "—",
                detail: peak.map { money($0.value) }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            if let rising, (rising.change ?? 0) > 0 {
                StatTile(title: "En hausse", value: rising.name, valueColor: riseColor, detail: "\(percent(rising.change)) sur \(Self.recentMonths) mois")
            } else {
                StatTile(title: "En hausse", value: "—", detail: "aucune catégorie")
            }

            if let falling, (falling.change ?? 0) < 0 {
                StatTile(title: "En baisse", value: falling.name, valueColor: fallColor, detail: "\(percent(falling.change)) sur \(Self.recentMonths) mois")
            } else {
                StatTile(title: "En baisse", value: "—", detail: "aucune catégorie")
            }
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ data: TrendData) -> some View {
        let names = data.posts.map { $0.name }
        let colors = names.enumerated().map { index, _ in
            index == names.count - 1 && data.posts.last?.id == ReportPost.othersID ? Color.gray : ReportPalette.color(at: index)
        }

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle(flow == .expense ? "Dépenses mensuelles par catégorie" : "Revenus mensuels par catégorie")

            Chart(data.cells) { cell in
                BarMark(
                    x: .value("Mois", cell.month, unit: .month),
                    y: .value("Montant", NSDecimalNumber(decimal: cell.amount).doubleValue)
                )
                .foregroundStyle(by: .value("Catégorie", cell.post))
            }
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .frame(height: 280)
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    // MARK: - Tableau

    private func tableBlock(_ data: TrendData) -> some View {
        ReportTable(
            columns: ["Catégorie", "Total", "Moyenne par mois", "Moyenne \(Self.recentMonths) derniers mois", "Dernier mois", "Tendance"],
            rows: data.trends.map { trend in
                let change = trend.change ?? 0
                // Seuil de 5 % : en dessous, on considère la catégorie comme stable
                let color: Color = change > 0.05 ? riseColor : (change < -0.05 ? fallColor : .secondary)
                return ReportRow(id: trend.id, cells: [
                    ReportCell(text: trend.name),
                    ReportCell(text: money(trend.total)),
                    ReportCell(text: money(trend.average)),
                    ReportCell(text: money(trend.recentAverage)),
                    ReportCell(text: money(trend.last)),
                    ReportCell(text: trend.change == nil ? "—" : percent(trend.change), color: color)
                ])
            },
            footnote: "Tendance : moyenne des \(Self.recentMonths) derniers mois comparée à la moyenne de la période. Les sous-catégories sont regroupées dans leur catégorie principale ; les \(flow.plural) sans catégorie ne sont pas comptés."
        )
    }

    // MARK: - Données

    struct TrendData {
        var months: [Date] = []
        var posts: [ReportPost] = []
        var cells: [Cell] = []
        var trends: [Trend] = []

        var monthTotals: [Date: Decimal] {
            cells.reduce(into: [:]) { $0[$1.month, default: 0] += $1.amount }
        }
    }

    private var data: TrendData {
        let calendar = Calendar.current
        // Même périmètre que « Dépenses / Revenus par catégorie » : transactions catégorisées seulement
        let expenses = transactionsController.filteredTransactions.filter {
            $0.type == flow.transactionType && $0.status != .skipped && $0.categoryID != nil
                && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID)
        }
        guard !expenses.isEmpty else { return TrendData() }

        // Totaux par catégorie principale et par mois
        var names: [String: String] = [:]
        var totals: [String: Decimal] = [:]
        var byMonth: [Date: [String: Decimal]] = [:]

        for transaction in expenses {
            let root = categoriesController.topLevelCategory(of: transaction.categoryID)
            let key = root?.id.uuidString ?? ReportPost.uncategorizedID
            names[key] = root?.name ?? "Sans catégorie"
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date)) ?? transaction.date
            totals[key, default: 0] += abs(transaction.amount)
            byMonth[month, default: [:]][key, default: 0] += abs(transaction.amount)
        }

        // Mois continus, du premier au dernier mois avec dépense
        guard let first = byMonth.keys.min(), let last = byMonth.keys.max() else { return TrendData() }
        var months: [Date] = []
        var current = first
        while current <= last, months.count < 240 {
            months.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        let posts = totals
            .map { ReportPost(id: $0.key, name: names[$0.key] ?? "—", amount: $0.value) }
            .grouped(limit: Self.maxSeries)
        let keptIDs = Set(posts.map { $0.id }).subtracting([ReportPost.othersID])

        func amount(_ post: ReportPost, in month: Date) -> Decimal {
            let values = byMonth[month] ?? [:]
            if post.id == ReportPost.othersID {
                return values.filter { !keptIDs.contains($0.key) }.reduce(Decimal(0)) { $0 + $1.value }
            }
            return values[post.id] ?? 0
        }

        var cells: [Cell] = []
        for month in months {
            for post in posts {
                cells.append(Cell(month: month, post: post.name, amount: amount(post, in: month)))
            }
        }

        let recent = Array(months.suffix(Self.recentMonths))
        let trends = posts.map { post in
            let recentTotal = recent.reduce(Decimal(0)) { $0 + amount(post, in: $1) }
            return Trend(
                id: post.id,
                name: post.name,
                total: post.amount,
                average: post.amount / Decimal(months.count),
                recentAverage: recentTotal / Decimal(max(recent.count, 1)),
                last: months.last.map { amount(post, in: $0) } ?? 0
            )
        }

        return TrendData(months: months, posts: posts, cells: cells, trends: trends)
    }

    // MARK: - Format

    /// Une hausse des dépenses est défavorable (rouge), une hausse des revenus favorable (vert)
    private var riseColor: Color { flow == .expense ? .red : .green }
    private var fallColor: Color { flow == .expense ? .green : .red }

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value > 0 ? "+" : "") + value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year()).capitalized
    }
}
