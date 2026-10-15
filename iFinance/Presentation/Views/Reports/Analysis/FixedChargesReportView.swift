import SwiftUI
import Charts

/// Rapport « Charges fixes et abonnements » : ce qui part chaque mois quoi qu'il arrive,
/// les abonnements, les hausses de prix et les doubles prélèvements.
struct FixedChargesReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

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
        ).fixedCharges()

        if report.charges.isEmpty {
            ReportEmptyState(systemImage: "repeat", message: "Aucune dépense récurrente. Les charges fixes viennent de la page « Récurrent ».")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    headline(report)
                    tiles(report)
                    groupsBlock(report)
                    LTBlockGrid(blocks: [AnyView(subscriptionsBlock(report)), AnyView(monthsBlock(report))])
                    table(report)
                }
            }
        }
    }

    private func checks(_ report: FixedChargesReport) -> Int {
        report.increases.count + report.duplicates.count
    }

    // MARK: - Réponse

    private func headline(_ report: FixedChargesReport) -> some View {
        let share = report.monthlyIncome.flatMap { PlanFormat.ratio(report.total, $0) }
        let left = report.monthlyIncome.map { $0 - report.total }
        let count = checks(report)

        return ReportHeadline(
            question: "Combien me coûtent mes charges incompressibles ?",
            answer: "Vos charges fixes représentent \(format.money(report.total)) par mois" + (share.map { ", soit \(format.percent($0)) de vos revenus." } ?? "."),
            detail: (left.map { "Il reste \(format.money($0)) par mois pour tout le reste : courses, loisirs, épargne." } ?? "")
                + (count > 0 ? " \(count) point\(count > 1 ? "s" : "") mérite\(count > 1 ? "nt" : "") un coup d’œil." : ""),
            tone: (share ?? 0) > 0.6 ? .warning : .info
        )
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: FixedChargesReport) -> some View {
        ReportTiles {
            StatTile(
                title: "Charges fixes",
                value: "\(format.money(report.total)) / mois",
                detail: report.monthlyIncome.flatMap { PlanFormat.ratio(report.total, $0) }.map { "\(format.percent($0)) des revenus" }
            )
            StatTile(
                title: "Abonnements",
                value: report.subscriptions.isEmpty ? "Aucun" : "\(format.money(report.subscriptionsTotal)) / mois",
                detail: report.subscriptions.isEmpty
                    ? "aucun abonnement repéré"
                    : "\(report.subscriptions.count) abonnement\(report.subscriptions.count > 1 ? "s" : "") · \(format.money(report.subscriptionsTotal * 12)) par an"
            )
            StatTile(
                title: "À vérifier",
                value: "\(checks(report))",
                valueColor: checks(report) > 0 ? .orange : .green,
                detail: "hausses de prix, doubles prélèvements"
            )
            StatTile(
                title: "Reste pour vivre",
                value: report.monthlyIncome.map { "\(format.money($0 - report.total)) / mois" } ?? "—",
                valueColor: .green,
                detail: "après les charges fixes"
            )
        }
    }

    // MARK: - Par poste

    private func groupsBlock(_ report: FixedChargesReport) -> some View {
        let groups = report.groups
        let largest = PlanFormat.double(groups.first?.monthly ?? 1)

        return PlanBlock(title: "Ce qui part chaque mois, quoi qu’il arrive", subtitle: "équivalent mensuel") {
            VStack(spacing: 10) {
                ForEach(groups) { group in
                    LTBarRow(
                        label: group.name,
                        detail: chargeNames(group),
                        bar: LTBar(fraction: PlanFormat.double(group.monthly) / max(largest, 1), color: .accentColor),
                        value: format.money(group.monthly),
                        extra: report.monthlyIncome.flatMap { PlanFormat.ratio(group.monthly, $0) }.map { "\(format.percent($0)) des revenus" },
                        labelWidth: 220
                    )
                }
            }
            PlanNote("Les charges fixes viennent de vos opérations récurrentes. Une charge annuelle compte pour un douzième chaque mois.")
        }
    }

    /// Charges du groupe par leur nom : les deux premières, puis le nombre restant
    private func chargeNames(_ group: ChargeGroup) -> String {
        let shown = group.names.prefix(2).joined(separator: ", ")
        let others = group.names.count - 2
        return others > 0 ? "\(shown) et \(others) autre\(others > 1 ? "s" : "")" : shown
    }

    // MARK: - Abonnements et points à vérifier

    private func subscriptionsBlock(_ report: FixedChargesReport) -> some View {
        PlanBlock(title: "Vos abonnements", subtitle: "\(format.money(report.subscriptionsTotal * 12)) par an") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(report.duplicates) { duplicate in
                    LTNoticeRow(
                        title: "\(duplicate.name) prélevé \(duplicate.dates.count) fois",
                        detail: duplicate.dates.map { format.day($0) }.joined(separator: ", ") + " : à réclamer ?",
                        value: format.cents(duplicate.amount),
                        color: .red
                    )
                }
                ForEach(report.subscriptions) { charge in
                    LTNoticeRow(
                        title: charge.name,
                        detail: [charge.template.frequency.displayName, increaseText(charge)].compactMap { $0 }.joined(separator: " · "),
                        value: "\(format.cents(charge.monthly)) / mois",
                        color: charge.increase != nil ? .orange : .gray
                    )
                }
                ForEach(report.increases.filter { !$0.isSubscription }) { charge in
                    LTNoticeRow(
                        title: charge.name,
                        detail: increaseText(charge),
                        value: "\(format.cents(charge.monthly)) / mois",
                        color: .orange
                    )
                }
                if report.subscriptions.isEmpty {
                    PlanNote("Aucun abonnement repéré. Rangez vos abonnements dans une catégorie « Abonnements » pour les retrouver ici.")
                }
            }
        }
    }

    private func increaseText(_ charge: FixedCharge) -> String? {
        guard let increase = charge.increase else { return nil }
        let since = charge.increaseSince.map { " depuis \($0.formatted(.dateTime.month(.wide)))" } ?? ""
        return "a augmenté de \(format.cents(increase))\(since)"
    }

    // MARK: - Fixe ou variable

    private struct MonthPart: Identifiable {
        let id: String
        let month: Date
        let kind: String
        let amount: Double
    }

    private func monthsBlock(_ report: FixedChargesReport) -> some View {
        let parts = report.months.flatMap { month in
            [MonthPart(id: "\(month.month)-f", month: month.month, kind: "Charges fixes", amount: PlanFormat.double(month.fixed)),
             MonthPart(id: "\(month.month)-v", month: month.month, kind: "Dépenses variables", amount: PlanFormat.double(month.variable))]
        }

        return PlanBlock(title: "Fixe ou variable, mois par mois", subtitle: "12 derniers mois") {
            Chart(parts) { part in
                BarMark(x: .value("Mois", part.month, unit: .month), y: .value("Montant", part.amount))
                    .foregroundStyle(by: .value("Type", part.kind))
            }
            .chartForegroundStyleScale(["Charges fixes": Color.gray, "Dépenses variables": Color.accentColor])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 190)
            PlanNote("Les charges fixes sont stables ; c’est la part variable qui fait la différence d’un mois à l’autre.")
        }
    }

    // MARK: - Tableau

    private func table(_ report: FixedChargesReport) -> some View {
        ReportTable(
            columns: ["Charge", "Catégorie", "Fréquence", "Montant", "Coût annuel"],
            rows: report.charges.map { charge in
                ReportRow(id: charge.id.uuidString, cells: [
                    ReportCell(text: charge.name, isAmount: false),
                    ReportCell(text: charge.group, color: .secondary, isAmount: false),
                    ReportCell(text: charge.template.frequency.displayName, color: .secondary, isAmount: false),
                    ReportCell(text: format.cents(abs(charge.template.amount))),
                    ReportCell(text: format.money(charge.monthly * 12))
                ])
            },
            footnote: "Modifiez ou arrêtez une charge depuis la page « Récurrent »."
        )
    }
}
