import SwiftUI
import Charts

/// Rapport « Prévision de trésorerie » : solde prévu des comptes courants, jour par jour,
/// à partir des opérations récurrentes et des dépenses courantes estimées.
struct ForecastReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// nil = tous les comptes courants
    @State private var accountID: UUID?
    @State private var horizon = 90

    private var builder: AnalysisReportBuilder {
        AnalysisReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            categoriesController: categoriesController,
            payeesController: payeesController,
            recurringController: recurringController
        )
    }

    private var format: AnalysisFormat {
        AnalysisFormat(currency: booksController.currentBook?.currency ?? "EUR", hidden: appSettings.hideAmounts)
    }

    private var currentAccounts: [Account] {
        accountsController.activeAccounts.filter { $0.type.group == .liquidity && !$0.isExcludedFromReports }
    }

    private var selectedAccounts: [Account] {
        if let accountID, let account = currentAccounts.first(where: { $0.id == accountID }) { return [account] }
        return currentAccounts
    }

    var body: some View {
        let accounts = selectedAccounts
        let start = accounts.reduce(Decimal(0)) { $0 + transactionsController.calculateBalance(for: $1.id, initialBalance: $1.initialBalance) }
        let report = builder.forecast(accountIDs: Set(accounts.map(\.id)), days: horizon, startBalance: start)
        let scope = accounts.count == 1 ? accounts[0].name : "Vos comptes courants"

        if currentAccounts.isEmpty {
            ReportEmptyState(systemImage: "calendar.badge.clock", message: "Aucun compte courant à prévoir.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    controls
                    headline(report, scope: scope)
                    tiles(report)
                    chartBlock(report)
                    LTBlockGrid(blocks: [AnyView(eventsBlock(report)), AnyView(methodBlock(report))])
                }
            }
        }
    }

    // MARK: - Réglages

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Comptes", selection: $accountID) {
                Text("Tous les comptes courants").tag(UUID?.none)
                ForEach(currentAccounts) { account in
                    Text(account.name).tag(UUID?.some(account.id))
                }
            }
            .fixedSize()

            Picker("Horizon", selection: $horizon) {
                Text("30 jours").tag(30)
                Text("90 jours").tag(90)
                Text("6 mois").tag(180)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
    }

    // MARK: - Réponse

    @ViewBuilder
    private func headline(_ report: ForecastReport, scope: String) -> some View {
        if let first = report.firstNegative, let lowest = report.lowest {
            let calendar = Calendar.current
            let deadline = calendar.date(byAdding: .day, value: -1, to: first.date) ?? first.date
            let transfer = Decimal((PlanFormat.double(-lowest.balance) / 100).rounded(.up) * 100 + 100)
            ReportHeadline(
                question: "Mon compte va-t-il passer dans le rouge ?",
                answer: "\(scope) risque\(selectedAccounts.count > 1 ? "nt" : "") de passer à \(format.money(lowest.balance)) le \(format.day(lowest.date)), pendant \(report.negativeDays) jour\(report.negativeDays > 1 ? "s" : "").",
                detail: "Un virement d’environ \(format.money(transfer)) depuis un livret d’ici le \(format.day(deadline)) suffirait à l’éviter.",
                tone: .bad
            )
        } else if let lowest = report.lowest {
            ReportHeadline(
                question: "Mon compte va-t-il passer dans le rouge ?",
                answer: "Non : pas de découvert prévu dans les \(horizon) prochains jours.",
                detail: "Point le plus bas : \(format.money(lowest.balance)) le \(format.day(lowest.date)).",
                tone: lowest.balance < 300 ? .warning : .good
            )
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: ForecastReport) -> some View {
        ReportTiles {
            StatTile(title: "Solde aujourd’hui", value: format.money(report.startBalance), detail: format.day(Date()))
            StatTile(
                title: "Point le plus bas",
                value: report.lowest.map { format.money($0.balance) } ?? "—",
                valueColor: (report.lowest?.balance ?? 0) < 0 ? .red : .primary,
                detail: report.lowest.map { "le \(format.day($0.date))" }
            )
            StatTile(
                title: "Solde prévu",
                value: report.end.map { format.money($0.balance) } ?? "—",
                detail: report.end.map { "le \(format.day($0.date))" }
            )
            StatTile(
                title: "Dépenses courantes estimées",
                value: "\(format.money(report.dailySpending)) / jour",
                detail: "moyenne des 3 derniers mois"
            )
        }
    }

    // MARK: - Courbe

    private func chartBlock(_ report: ForecastReport) -> some View {
        PlanBlock(title: "Solde prévu, jour par jour", subtitle: "opérations récurrentes et dépenses courantes estimées") {
            Chart {
                ForEach(report.points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Solde", PlanFormat.double(point.balance)))
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                    LineMark(x: .value("Date", point.date), y: .value("Solde", PlanFormat.double(point.balance)))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                RuleMark(y: .value("Zéro", 0))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let lowest = report.lowest, lowest.balance < 0 {
                    PointMark(x: .value("Date", lowest.date), y: .value("Solde", PlanFormat.double(lowest.balance)))
                        .foregroundStyle(.red)
                        .annotation(position: .bottom) {
                            Text(format.money(lowest.balance))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(appSettings.hideAmounts ? "" : amount.formatted(.currency(code: format.currency).precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 230)

            PlanNote("Les dépenses courantes (courses, sorties…) sont réparties chaque jour à leur moyenne récente. La courbe ne tient compte que des opérations prévues : ajoutez une opération récurrente pour l’affiner.")
        }
    }

    // MARK: - Prochaines opérations

    private func eventsBlock(_ report: ForecastReport) -> some View {
        PlanBlock(title: "Prochaines opérations prévues", subtitle: "45 prochains jours") {
            if report.events.isEmpty {
                PlanNote("Aucune opération récurrente prévue. Créez-les depuis la page « Récurrent ».")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.events.prefix(10)) { event in
                        LTNoticeRow(
                            title: event.label,
                            detail: event.date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                            value: format.signed(event.amount),
                            color: event.amount > 0 ? .green : abs(event.amount) >= 500 ? .orange : .gray,
                            valueColor: event.amount > 0 ? .green : .primary
                        )
                    }
                }
            }
        }
    }

    // MARK: - Méthode

    private func methodBlock(_ report: ForecastReport) -> some View {
        PlanBlock(title: "Comment c’est calculé") {
            VStack(spacing: 10) {
                ExplanationRow(label: "Revenus réguliers", detail: "salaires et autres opérations récurrentes", value: "+\(format.money(report.recurringIncome)) / mois", color: .green)
                Divider()
                ExplanationRow(label: "Dépenses régulières", detail: "loyer, crédits, énergie, abonnements…", value: "−\(format.money(report.recurringExpenses)) / mois")
                Divider()
                ExplanationRow(label: "Dépenses courantes estimées", detail: "courses, sorties : moyenne des 90 derniers jours, hors récurrent", value: "\(format.money(report.dailySpending)) / jour")
            }
            PlanNote("Une prévision n’est jamais exacte : elle sert à repérer à l’avance les périodes tendues.")
        }
    }
}
