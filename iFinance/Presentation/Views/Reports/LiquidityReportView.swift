import SwiftUI
import Charts

/// Rapport « Pyramide de liquidité » : le patrimoine classé selon le délai pour le mobiliser.
/// Valeurs au jour : la période et le filtre de compte de la barre d'outils ne s'appliquent pas.
struct LiquidityReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var accountTermsController: AccountTermsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Couverture conseillée de l'épargne de précaution, en mois de dépenses
    private let coverageGoal = 6.0

    var body: some View {
        let report = LongTermReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController,
            accountTermsController: accountTermsController
        ).liquidity()

        if report.lines.isEmpty {
            ReportEmptyState(systemImage: "drop", message: "Aucun compte inclus dans le patrimoine net.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(report)
                    pyramid(report)
                    LTBlockGrid(blocks: [AnyView(releases(report)), AnyView(precaution(report))])
                    table(report)
                }
            }
        }
    }

    private var currency: String { booksController.currentBook?.currency ?? "EUR" }
    private func money(_ value: Decimal) -> String { PlanFormat.round(value, currency) }

    private func color(_ tier: LiquidityTier) -> Color {
        switch tier {
        case .immediate: return .accentColor
        case .days: return .teal
        case .scheduled: return .purple
        case .retirement: return .gray
        case .illiquid: return .gray.opacity(0.5)
        case .debt: return .red
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: LiquidityReport) -> some View {
        ReportTiles {
            StatTile(title: "Patrimoine net", value: money(report.netWorth), detail: "actifs moins dettes")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Mobilisable sous un mois",
                value: money(report.mobilizable),
                valueColor: .green,
                detail: PlanFormat.ratio(report.mobilizable, report.financialAssets).map { "\(PlanFormat.percent($0)) du patrimoine financier" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Bloqué jusqu’à la retraite",
                value: money(report.total(.retirement)),
                detail: report.total(.scheduled) > 0 ? "et \(money(report.total(.scheduled))) bloqués à échéance" : nil
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Épargne de précaution",
                value: report.coverageMonths.map { "\($0.formatted(.number.precision(.fractionLength(1)))) mois" } ?? "—",
                valueColor: (report.coverageMonths ?? 0) >= 3 ? .green : .orange,
                detail: "de dépenses courantes"
            )

            StatTile(
                title: "Dettes",
                value: money(report.total(.debt)),
                valueColor: report.total(.debt) < 0 ? .red : .primary,
                detail: PlanFormat.ratio(-report.total(.debt), report.grossAssets).map { "\(PlanFormat.percent($0)) des actifs" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Pyramide

    private func pyramid(_ report: LiquidityReport) -> some View {
        let tiers = LiquidityTier.allCases.filter { report.total($0) != 0 }
        let largest = tiers.map { abs(PlanFormat.double(report.total($0))) }.max() ?? 1

        return PlanBlock(title: "Combien puis-je mobiliser, et quand ?", subtitle: "patrimoine classé du plus liquide au moins liquide") {
            VStack(spacing: 10) {
                ForEach(tiers) { tier in
                    let total = report.total(tier)
                    LTBarRow(
                        label: tier.title,
                        detail: tier.detail,
                        bar: LTBar(fraction: abs(PlanFormat.double(total)) / largest, color: color(tier), height: 16),
                        value: money(total),
                        valueColor: total < 0 ? .red : .primary,
                        extra: tier == .debt ? nil : PlanFormat.ratio(total, report.grossAssets).map { "\(PlanFormat.percent($0)) des actifs" },
                        labelWidth: 230,
                        isEmphasized: tier == .immediate
                    )
                }
            }
            PlanNote("Chaque compte est classé d’après son type et la date de disponibilité de ses apports. Les biens (résidence, véhicule…) se suivent avec un compte de type « Autre ».")
        }
    }

    // MARK: - Ce qui se libère

    private func releases(_ report: LiquidityReport) -> some View {
        PlanBlock(title: "Ce qui se libère", subtitle: "disponible cumulé, hors biens") {
            Chart {
                ForEach(report.releases) { step in
                    BarMark(x: .value("Échéance", step.label), y: .value("Montant", PlanFormat.double(step.before)))
                        .foregroundStyle(by: .value("Série", "Déjà disponible"))
                    BarMark(x: .value("Échéance", step.label), y: .value("Montant", PlanFormat.double(step.added)))
                        .foregroundStyle(by: .value("Série", step.isRetirement ? "À la retraite" : (step.before == 0 ? "Déjà disponible" : "Se débloque")))
                        .annotation(position: .top) {
                            Text(money(step.total))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }
                }
            }
            .chartForegroundStyleScale([
                "Déjà disponible": Color.accentColor,
                "Se débloque": Color.purple,
                "À la retraite": Color.gray
            ])
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)

            PlanNote("Les cas de déblocage anticipé de l’épargne salariale (résidence principale, mariage…) peuvent avancer ces dates.")
        }
    }

    // MARK: - Épargne de précaution

    private func precaution(_ report: LiquidityReport) -> some View {
        let coverage = report.coverageMonths
        let surplus = report.monthlyExpenses.map { report.total(.immediate) - $0 * Decimal(coverageGoal) }

        return PlanBlock(title: "Épargne de précaution", subtitle: "disponible immédiatement") {
            VStack(spacing: 10) {
                factRow("Disponible immédiatement", "comptes courants et livrets", money(report.total(.immediate)))
                Divider()
                factRow("Dépenses courantes moyennes", "12 derniers mois, comptes courants", report.monthlyExpenses.map { "\(money($0)) / mois" } ?? "—")
                Divider()
                VStack(spacing: 6) {
                    factRow("Couverture", "objectif conseillé : 3 à 6 mois", coverage.map { "\($0.formatted(.number.precision(.fractionLength(1)))) mois" } ?? "—",
                            color: (coverage ?? 0) >= 3 ? .green : .orange)
                    LTBar(fraction: (coverage ?? 0) / 12, color: (coverage ?? 0) >= 3 ? .green : .orange, height: 10, marker: coverageGoal / 12)
                }
                if let surplus, surplus > 0 {
                    Divider()
                    factRow("Au-delà de 6 mois", "pourrait être placé à plus long terme", money(surplus), color: .accentColor)
                }
            }
            PlanNote("Le trait marque 6 mois de dépenses ; l’échelle va jusqu’à 12 mois.")
        }
    }

    private func factRow(_ label: String, _ detail: String, _ value: String, color: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Tableau

    private func table(_ report: LiquidityReport) -> some View {
        ReportTable(
            columns: ["Compte", "Type", "Disponibilité", "Valeur", "Part des actifs"],
            rows: report.lines.map { line in
                ReportRow(id: line.id.uuidString, cells: [
                    ReportCell(text: line.account.name, isAmount: false),
                    ReportCell(text: line.account.type.displayName, color: .secondary, isAmount: false),
                    ReportCell(text: line.availability, color: .secondary, isAmount: false),
                    ReportCell(text: money(line.value), color: line.value < 0 ? .red : .primary),
                    ReportCell(text: line.value > 0 ? PlanFormat.ratio(line.value, report.grossAssets).map { PlanFormat.percent($0) } ?? "—" : "—", color: .secondary, isAmount: false)
                ])
            },
            footnote: "Valeurs au jour. Les comptes exclus du patrimoine net n’apparaissent pas."
        )
    }
}
