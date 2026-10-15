import SwiftUI
import Charts

/// Rapport « Bilan de l'année » : épargne mois par mois, faits marquants, postes de dépenses
/// comparés à l'année précédente.
struct YearReviewReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Année affichée : par défaut l'année en cours, sauf en janvier où elle est encore presque vide
    @State private var year: Int = {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) == 1 ? year - 1 : year
    }()

    private var format: AnalysisFormat {
        AnalysisFormat(currency: booksController.currentBook?.currency ?? "EUR", hidden: appSettings.hideAmounts)
    }

    private var builder: AnalysisReportBuilder {
        AnalysisReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            categoriesController: categoriesController,
            payeesController: payeesController,
            recurringController: recurringController
        )
    }

    var body: some View {
        let years = builder.availableYears
        let review = builder.yearReview(year: year)

        ScrollView {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                Picker("Année", selection: $year) {
                    ForEach(years.isEmpty ? [year] : years, id: \.self) { value in
                        Text(String(value)).tag(value)
                    }
                }
                .fixedSize()

                if review.income == 0 && review.expense == 0 {
                    ReportEmptyState(systemImage: "calendar", message: "Aucune opération sur les comptes courants en \(String(year)).")
                } else {
                    headline(review)
                    tiles(review)
                    LTBlockGrid(blocks: [AnyView(monthsBlock(review)), AnyView(highlightsBlock(review)), AnyView(categoriesBlock(review))])
                    table(review)
                }
            }
        }
    }

    private var isCurrentYear: Bool { year == Calendar.current.component(.year, from: Date()) }

    /// Période de comparaison : l'année précédente, ou sa même période quand l'année est en cours
    private var previousPeriod: String {
        isCurrentYear ? "la même période de \(String(year - 1))" : String(year - 1)
    }

    private func change(_ now: Decimal, _ before: Decimal) -> String? {
        guard before > 0 else { return nil }
        return "\(format.percent(PlanFormat.double((now - before) / before), signed: true)) vs \(isCurrentYear ? "même période " : "")\(String(year - 1))"
    }

    // MARK: - Réponse

    private func headline(_ review: YearReview) -> some View {
        let saving = review.saving
        let previousSaving = review.previousIncome - review.previousExpense
        let period = isCurrentYear ? "Depuis janvier" : String(year)
        return ReportHeadline(
            question: "Comment s’est passée mon année ?",
            answer: saving >= 0
                ? "\(period) : vous avez mis de côté \(format.money(saving)), soit \(format.percent(PlanFormat.ratio(saving, review.income) ?? 0)) de vos revenus."
                : "\(period) : vos dépenses ont dépassé vos revenus de \(format.money(-saving)).",
            detail: "\(review.positiveMonths) mois sur \(review.months.count) se terminent en positif."
                + (previousSaving > 0 && saving > previousSaving ? (isCurrentYear ? " Vous avez épargné plus que sur \(previousPeriod)." : " Vous avez épargné plus qu’en \(previousPeriod).") : ""),
            tone: saving > 0 ? .good : .warning
        )
    }

    // MARK: - Chiffres clés

    private func tiles(_ review: YearReview) -> some View {
        ReportTiles {
            StatTile(title: "Revenus", value: format.money(review.income), detail: change(review.income, review.previousIncome))
            StatTile(title: "Dépenses", value: format.money(review.expense), detail: change(review.expense, review.previousExpense))
            StatTile(
                title: "Épargné",
                value: format.signed(review.saving),
                valueColor: review.saving >= 0 ? .green : .red,
                detail: PlanFormat.ratio(review.saving, review.income).map { "\(format.percent($0)) des revenus" }
            )
            StatTile(
                title: "Mois dans le vert",
                value: "\(review.positiveMonths) sur \(review.months.count)",
                valueColor: review.positiveMonths * 3 >= review.months.count * 2 ? .green : .orange,
                detail: "revenus supérieurs aux dépenses"
            )
        }
    }

    // MARK: - Mois par mois

    private func monthsBlock(_ review: YearReview) -> some View {
        PlanBlock(title: "Ce que vous avez mis de côté, mois par mois") {
            Chart(review.months) { month in
                BarMark(x: .value("Mois", month.month, unit: .month), y: .value("Épargne", PlanFormat.double(month.saving)))
                    .foregroundStyle(month.saving >= 0 ? Color.green : Color.red)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(appSettings.hideAmounts ? "" : amount.formatted(.currency(code: format.currency).precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 190)
            if let worst = review.months.filter({ $0.saving < 0 }).min(by: { $0.saving < $1.saving }) {
                PlanNote("\(worst.month.formatted(.dateTime.month(.wide)).capitalized) est le mois le plus difficile (\(format.signed(worst.saving))).")
            }
        }
    }

    // MARK: - Faits marquants

    private func highlightsBlock(_ review: YearReview) -> some View {
        PlanBlock(title: "Les faits marquants") {
            VStack(alignment: .leading, spacing: 2) {
                if let month = review.mostExpensive {
                    LTNoticeRow(title: "Le mois le plus cher : \(month.month.formatted(.dateTime.month(.wide)))", value: format.money(month.expense), color: .orange)
                }
                if let biggest = review.biggestExpense {
                    LTNoticeRow(
                        title: "La plus grosse dépense",
                        detail: "\(builder.label(of: biggest)), le \(biggest.date.formatted(.dateTime.day().month(.wide)))",
                        value: format.money(abs(biggest.amount)),
                        color: .gray
                    )
                }
                if let riser = review.risers.first, let change = riser.change {
                    LTNoticeRow(title: "Le poste qui a le plus augmenté", detail: "\(riser.name), comparé à \(previousPeriod)", value: format.percent(change, signed: true), color: .red, valueColor: .red)
                }
                if let faller = review.fallers.first, let change = faller.change {
                    LTNoticeRow(title: "Le poste qui a le plus baissé", detail: "\(faller.name), comparé à \(previousPeriod)", value: format.percent(change, signed: true), color: .green, valueColor: .green)
                }
            }
        }
    }

    // MARK: - Où est passé l'argent

    private func categoriesBlock(_ review: YearReview) -> some View {
        let top = review.categories.prefix(7)
        let largest = PlanFormat.double(top.first?.amount ?? 1)

        return PlanBlock(title: "Où est passé l’argent", subtitle: "comparé à \(previousPeriod)") {
            VStack(spacing: 10) {
                ForEach(Array(top)) { category in
                    LTBarRow(
                        label: category.name,
                        bar: LTBar(fraction: PlanFormat.double(category.amount) / max(largest, 1), color: .accentColor),
                        value: format.money(category.amount),
                        extra: category.change.map { "\(format.percent($0, signed: true)) vs \(String(year - 1))" } ?? "nouveau",
                        labelWidth: 170
                    )
                }
            }
        }
    }

    // MARK: - Tableau

    private func table(_ review: YearReview) -> some View {
        ReportTable(
            columns: ["Mois", "Revenus", "Dépenses", "Épargne", "Taux d’épargne"],
            rows: review.months.map { month in
                ReportRow(id: "\(month.month.timeIntervalSince1970)", cells: [
                    ReportCell(text: month.month.formatted(.dateTime.month(.wide)).capitalized, isAmount: false),
                    ReportCell(text: format.money(month.income)),
                    ReportCell(text: format.money(month.expense)),
                    ReportCell(text: format.signed(month.saving), color: month.saving >= 0 ? .green : .red),
                    ReportCell(text: PlanFormat.ratio(month.saving, month.income).map { format.percent($0) } ?? "—", color: .secondary, isAmount: false)
                ])
            },
            footnote: "Comptes courants, hors virements entre vos comptes."
        )
    }
}
