import SwiftUI
import Charts

/// Rapport « Inflation personnelle » : l'évolution de vos dépenses courantes comparée
/// à la hausse des prix mesurée par l'INSEE (valeurs intégrées, ou téléchargées si l'option est active).
struct PersonalInflationReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var inflationService: InflationService

    private var format: AnalysisFormat {
        AnalysisFormat(currency: booksController.currentBook?.currency ?? "EUR", hidden: appSettings.hideAmounts)
    }

    var body: some View {
        let report = AnalysisReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            categoriesController: categoriesController,
            payeesController: payeesController,
            recurringController: recurringController
        ).inflation(prices: inflationService.table)

        if report.change == nil {
            ReportEmptyState(systemImage: "chart.line.uptrend.xyaxis", message: "Il faut au moins 15 mois d’historique pour comparer vos dépenses à celles de l’an dernier.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(report)
                    postsBlock(report)
                    LTBlockGrid(blocks: [AnyView(yearsBlock(report)), AnyView(methodBlock)])
                }
            }
        }
    }

    private var prices: InflationTable { inflationService.table }
    private var reference: String { "INSEE \(String(prices.lastYear))" }

    // MARK: - Chiffres clés

    private func tiles(_ report: InflationReport) -> some View {
        let change = report.change ?? 0
        let gap = change - prices.last
        let top = report.posts.filter { $0.now >= 50 }.max { ($0.change ?? -1) < ($1.change ?? -1) }

        return ReportTiles {
            StatTile(title: "Vos dépenses courantes", value: format.percent(change, signed: true), valueColor: change > prices.last ? .red : .green, detail: "sur 12 mois, postes comparables")
            StatTile(title: "Hausse des prix", value: format.percent(prices.last, signed: true), detail: "moyenne annuelle, \(reference)")
            StatTile(
                title: "Écart",
                value: "\(gap >= 0 ? "+" : "−")\(abs(gap * 100).formatted(.number.precision(.fractionLength(1)))) points",
                valueColor: gap > 0.02 ? .orange : .primary,
                detail: report.extraPerYear.map { $0 > 0 ? "≈ \(format.money($0)) de plus sur l’année" : "au-dessous de l’inflation" }
            )
            StatTile(title: "Poste en plus forte hausse", value: top?.name ?? "—", detail: top?.change.map { format.percent($0, signed: true) })
        }
    }

    // MARK: - Poste par poste

    private func postsBlock(_ report: InflationReport) -> some View {
        let posts = report.posts.filter { $0.change != nil && ($0.now >= 30 || $0.before >= 30) }.prefix(10)
        let largest = max(posts.compactMap { $0.change.map { abs($0) } }.max() ?? 0.1, 0.01)

        return PlanBlock(title: "Poste par poste", subtitle: "3 derniers mois comparés aux mêmes mois l’an dernier") {
            VStack(spacing: 10) {
                ForEach(Array(posts)) { post in
                    let change = post.change ?? 0
                    let faster = change > (post.inseeChange ?? prices.last) + 0.02
                    LTBarRow(
                        label: post.name,
                        detail: faster ? "plus vite que les prix" : change < (post.inseeChange ?? prices.last) ? "moins vite que les prix" : "comme les prix",
                        bar: LTBar(fraction: abs(change) / largest, color: change < 0 ? .green : faster ? .red : .accentColor),
                        value: format.percent(change, signed: true),
                        valueColor: faster ? .red : change < 0 ? .green : .primary,
                        extra: post.inseeChange.map { "prix : \(format.percent($0, signed: true))" } ?? "\(format.money(post.now)) / mois",
                        labelWidth: 180,
                        isEmphasized: faster
                    )
                }
            }
            PlanNote("Moyennes mensuelles sur 3 mois, pour lisser les variations. Les prix par poste (alimentation, énergie, loyers…) sont ceux de l’INSEE pour \(String(prices.lastYear)).")
        }
    }

    // MARK: - Sur plusieurs années

    private struct IndexPoint: Identifiable {
        let id: String
        let year: Int
        let series: String
        let value: Double
    }

    private func yearsBlock(_ report: InflationReport) -> some View {
        var points: [IndexPoint] = []
        if let first = report.yearly.first {
            var priceIndex = 100.0
            for entry in report.yearly {
                if entry.year > first.year { priceIndex *= 1 + self.prices.yearly(entry.year) }
                let own = PlanFormat.double(entry.spending) / PlanFormat.double(first.spending) * 100
                points.append(IndexPoint(id: "o\(entry.year)", year: entry.year, series: "Vos dépenses", value: own))
                points.append(IndexPoint(id: "p\(entry.year)", year: entry.year, series: "Prix (INSEE)", value: priceIndex))
            }
        }

        return PlanBlock(title: "Sur plusieurs années", subtitle: "base 100 la première année complète") {
            if report.yearly.count < 2 {
                PlanNote("Il faut au moins deux années complètes d’historique.")
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Année", point.year), y: .value("Indice", point.value))
                        .foregroundStyle(by: .value("Série", point.series))
                        .symbol(by: .value("Série", point.series))
                }
                .chartForegroundStyleScale(["Vos dépenses": Color.red, "Prix (INSEE)": Color.gray])
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: report.yearly.map(\.year)) { value in
                        AxisValueLabel {
                            if let year = value.as(Int.self) { Text(String(year)) }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 190)
            }
        }
    }

    // MARK: - Lecture

    private var methodBlock: some View {
        PlanBlock(title: "Comment lire ce rapport") {
            VStack(spacing: 10) {
                ExplanationRow(label: "Vos dépenses courantes", detail: "dépenses des comptes courants, par catégorie principale, hors virements vers l’épargne", value: "")
                Divider()
                ExplanationRow(label: "Hausse des prix", detail: inflationService.isEnabled
                    ? "indice des prix à la consommation de l’INSEE, mis à jour en ligne\(inflationService.lastUpdate.map { " le \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")"
                    : "indice des prix à la consommation de l’INSEE, intégré à l’app ; mise à jour en ligne possible dans Réglages › Confidentialité", value: format.percent(prices.last, signed: true))
                Divider()
                ExplanationRow(label: "Si vous dépassez les prix", detail: "vous achetez plus, ou plus cher que la moyenne : ce n’est pas forcément un problème", value: "")
            }
        }
    }
}
