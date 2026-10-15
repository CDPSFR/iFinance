import SwiftUI
import Charts

/// Rapport « Frais bancaires » : ce que coûtent les banques sur 12 mois, par type de frais.
struct BankFeesReportView: View {
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
        ).bankFees()

        if report.fees.isEmpty {
            ReportEmptyState(
                systemImage: "building.columns",
                message: "Aucun frais bancaire repéré sur 12 mois. Ils sont reconnus à leur libellé (cotisation, commission, agios…) ou rangés dans une catégorie « Frais bancaires »."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    headline(report)
                    tiles(report)
                    LTBlockGrid(blocks: [AnyView(kindsBlock(report)), AnyView(monthsBlock(report)), AnyView(adviceBlock(report))])
                    table(report)
                }
            }
        }
    }

    // MARK: - Réponse

    private func headline(_ report: BankFeesReport) -> some View {
        ReportHeadline(
            question: "Combien me coûte ma banque ?",
            answer: "Vos banques vous ont coûté \(format.money(report.total)) sur les 12 derniers mois.",
            detail: report.avoidable > 0
                ? "Dont \(format.money(report.avoidable)) de commissions et d’agios, liés aux passages à découvert : ce sont les plus faciles à éviter."
                : "Aucun frais lié à un découvert : ce sont surtout des cotisations.",
            tone: report.avoidable > 0 ? .warning : .info
        )
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: BankFeesReport) -> some View {
        ReportTiles {
            StatTile(title: "Total sur 12 mois", value: format.money(report.total), valueColor: .red, detail: report.banks.count > 1 ? "\(report.banks.count) banques" : report.banks.first)
            StatTile(title: "Par mois", value: format.money(report.total / 12), detail: "en moyenne")
            StatTile(title: "Évitables", value: format.money(report.avoidable), valueColor: report.avoidable > 0 ? .orange : .green, detail: "commissions d’intervention et agios")
            StatTile(title: "Passages à découvert", value: "\(report.overdraftMonths) mois", valueColor: report.overdraftMonths > 0 ? .orange : .green, detail: "sur 12")
        }
    }

    private func color(_ kind: BankFeeKind) -> Color {
        switch kind {
        case .card, .account: return .gray
        case .incident, .overdraft: return .red
        case .foreign: return .accentColor
        case .other: return .purple
        }
    }

    // MARK: - Par type

    private func kindsBlock(_ report: BankFeesReport) -> some View {
        let kinds = BankFeeKind.allCases.filter { report.amount(of: $0) > 0 }
        let largest = PlanFormat.double(kinds.map { report.amount(of: $0) }.max() ?? 1)

        return PlanBlock(title: "Par type de frais") {
            VStack(spacing: 10) {
                ForEach(kinds) { kind in
                    let amount = report.amount(of: kind)
                    LTBarRow(
                        label: kind.rawValue,
                        detail: "\(report.fees.filter { $0.kind == kind }.count) opération\(report.fees.filter { $0.kind == kind }.count > 1 ? "s" : "")",
                        bar: LTBar(fraction: PlanFormat.double(amount) / max(largest, 1), color: color(kind)),
                        value: format.money(amount),
                        extra: PlanFormat.ratio(amount, report.total).map { format.percent($0) },
                        labelWidth: 220
                    )
                }
            }
        }
    }

    // MARK: - Mois par mois

    private struct FeeBar: Identifiable {
        let id: String
        let month: Date
        let kind: String
        let amount: Double
    }

    private func monthsBlock(_ report: BankFeesReport) -> some View {
        let calendar = Calendar.current
        let bars = report.fees.map { fee in
            FeeBar(
                id: fee.id.uuidString,
                month: calendar.date(from: calendar.dateComponents([.year, .month], from: fee.transaction.date)) ?? fee.transaction.date,
                kind: fee.kind.isAvoidable ? "Commissions et agios" : (fee.kind == .foreign ? "Étranger" : "Cotisations et tenue"),
                amount: PlanFormat.double(abs(fee.transaction.amount))
            )
        }

        return PlanBlock(title: "Mois par mois", subtitle: "12 derniers mois") {
            Chart(bars) { bar in
                BarMark(x: .value("Mois", bar.month, unit: .month), y: .value("Montant", bar.amount))
                    .foregroundStyle(by: .value("Type", bar.kind))
            }
            .chartForegroundStyleScale(["Cotisations et tenue": Color.gray, "Commissions et agios": Color.red, "Étranger": Color.accentColor])
            .chartXScale(domain: (report.months.first ?? Date())...(calendar.date(byAdding: .month, value: 1, to: report.months.last ?? Date()) ?? Date()))
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)
        }
    }

    // MARK: - Conseils

    private func adviceBlock(_ report: BankFeesReport) -> some View {
        let cards = report.amount(of: .card)
        return PlanBlock(title: "Pour payer moins") {
            VStack(alignment: .leading, spacing: 2) {
                if report.avoidable > 0 {
                    LTNoticeRow(
                        title: "Éviter les passages à découvert",
                        detail: "un virement automatique depuis un livret quelques jours avant la fin du mois les éviterait (voir « Prévision de trésorerie »)",
                        value: "−\(format.money(report.avoidable)) / an",
                        color: .green,
                        valueColor: .green
                    )
                }
                if cards > 100 {
                    LTNoticeRow(
                        title: "Vérifier l’utilité de vos cartes",
                        detail: "une carte haut de gamme se justifie par ses assurances et services ; beaucoup de banques proposent une carte sans cotisation",
                        value: "\(format.money(cards)) / an",
                        color: .accentColor
                    )
                }
                LTNoticeRow(
                    title: "Plafonds légaux",
                    detail: "commissions d’intervention : 8 € par opération et 80 € par mois au plus (4 € et 20 € par mois pour les clients en situation de fragilité)",
                    color: .gray
                )
            }
        }
    }

    // MARK: - Tableau

    private func table(_ report: BankFeesReport) -> some View {
        ReportTable(
            columns: ["Date", "Banque", "Libellé", "Type", "Montant"],
            rows: report.fees.prefix(30).map { fee in
                ReportRow(id: fee.id.uuidString, cells: [
                    ReportCell(text: fee.transaction.date.formatted(.dateTime.day().month(.abbreviated).year()), isAmount: false),
                    ReportCell(text: fee.bank, color: .secondary, isAmount: false),
                    ReportCell(text: fee.label, isAmount: false),
                    ReportCell(text: fee.kind.rawValue, color: .secondary, isAmount: false),
                    ReportCell(text: format.cents(abs(fee.transaction.amount)))
                ])
            },
            footnote: "Les 30 derniers frais. Rangez-les dans une catégorie « Frais bancaires » pour qu’ils soient tous reconnus."
        )
    }
}
