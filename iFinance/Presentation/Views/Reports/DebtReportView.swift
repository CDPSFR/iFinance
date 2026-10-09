import SwiftUI
import Charts

/// Rapport « Dettes et crédits » : capital restant dû, mensualités, taux d'endettement,
/// simulation de remboursement anticipé. S'appuie sur les conditions saisies pour chaque prêt.
struct DebtReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var accountTermsController: AccountTermsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    @State private var termsAccount: Account?
    @State private var prepaymentText = "10000"
    @State private var prepaymentLoanID: UUID?
    @State private var reduceDuration = true

    /// Seuil de taux d'endettement appliqué par les banques (recommandation du HCSF)
    private let debtRatioLimit = 0.35

    var body: some View {
        let report = LongTermReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController,
            accountTermsController: accountTermsController
        ).debts()

        Group {
            if report.lines.isEmpty {
                ReportEmptyState(systemImage: "house", message: "Aucun compte de type Prêt.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                        tiles(report)
                        if !report.missingTerms.isEmpty {
                            missingTermsBlock(report)
                        }
                        LTBlockGrid(blocks: blocks(report))
                        table(report)
                    }
                }
            }
        }
        .sheet(item: $termsAccount) { account in
            AccountTermsFormView(account: account)
        }
    }

    private func blocks(_ report: DebtReport) -> [AnyView] {
        let scheduled = report.lines.filter { $0.schedule != nil && $0.balance > 0 }
        guard !scheduled.isEmpty else { return [AnyView(ratioBlock(report))] }
        return [
            AnyView(projectionBlock(scheduled)),
            AnyView(paymentBlock(scheduled)),
            AnyView(ratioBlock(report)),
            AnyView(prepaymentBlock(scheduled, report: report))
        ]
    }

    private var currency: String { booksController.currentBook?.currency ?? "EUR" }
    /// Montant affiché, ou « ••• » quand les montants sont masqués (tuiles, lignes, tableaux)
    private func money(_ value: Decimal) -> String { appSettings.hideAmounts ? "•••" : PlanFormat.round(value, currency) }
    private func money(_ value: Double) -> String { money(Decimal(value)) }
    private func monthYear(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).year()) }
    /// Taux avec deux décimales (1,45 %)
    private func ratePercent(_ rate: Double) -> String { rate.formatted(.percent.precision(.fractionLength(0...2))) }

    // MARK: - Chiffres clés

    private func tiles(_ report: DebtReport) -> some View {
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let repaid = report.lines.compactMap { line in line.schedule.map { $0.balance(asOf: yearAgo) - $0.balance() } }.reduce(0, +)

        return ReportTiles {
            StatTile(
                title: "Capital restant dû",
                value: money(report.balance),
                valueColor: .red,
                detail: repaid > 0 ? "−\(money(repaid)) en 12 mois" : "\(report.lines.count) prêt\(report.lines.count > 1 ? "s" : "")"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Mensualités",
                value: report.monthlyPayments > 0 ? "\(money(report.monthlyPayments)) / mois" : "—",
                detail: report.monthlyInsurance > 0 ? "dont \(money(report.monthlyInsurance)) d’assurance" : "hors assurance"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Taux d’endettement",
                value: report.debtRatio.map { PlanFormat.percent($0) } ?? "—",
                valueColor: (report.debtRatio ?? 0) > debtRatioLimit ? .red : .green,
                detail: "seuil bancaire : 35 %"
            )

            StatTile(
                title: "Intérêts restant à payer",
                value: money(report.remainingInterest),
                detail: report.remainingInsurance > 0 ? "+ \(money(report.remainingInsurance)) d’assurance" : nil
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Libre de dettes",
                value: report.endDate.map { $0.formatted(.dateTime.month(.wide).year()).capitalized } ?? "—",
                detail: report.endDate.map { date in
                    let months = Calendar.current.dateComponents([.month], from: Date(), to: date).month ?? 0
                    return "dans \(months / 12) an\(months / 12 > 1 ? "s" : "") et \(months % 12) mois"
                }
            )
        }
    }

    // MARK: - Conditions manquantes

    private func missingTermsBlock(_ report: DebtReport) -> some View {
        PlanBlock(title: "Conditions à renseigner", subtitle: "nécessaires pour l’échéancier et les simulations") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(report.missingTerms) { line in
                    LTNoticeRow(
                        title: line.account.name,
                        detail: "montant emprunté, taux, durée et première échéance, depuis votre offre de prêt",
                        value: money(line.balance),
                        color: .orange,
                        action: ("Saisir…", { termsAccount = line.account })
                    )
                }
            }
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Capital restant dû

    private struct BalancePoint: Identifiable {
        let id: String
        let date: Date
        let loan: String
        let balance: Double
    }

    private func projectionBlock(_ lines: [DebtLine]) -> some View {
        let calendar = Calendar.current
        let now = Date()
        let horizon = lines.compactMap { $0.schedule?.remainingPayments() }.max() ?? 0
        let points: [BalancePoint] = stride(from: 0, through: horizon, by: 3).flatMap { offset -> [BalancePoint] in
            let date = calendar.date(byAdding: .month, value: offset, to: now) ?? now
            return lines.compactMap { line in
                guard let schedule = line.schedule else { return nil }
                let balance = schedule.balance(afterPayments: schedule.paymentsMade() + offset)
                return BalancePoint(id: "\(line.id)-\(offset)", date: date, loan: line.account.name, balance: balance)
            }
        }
        let names = lines.map(\.account.name)

        return PlanBlock(title: "Capital restant dû", subtitle: "projection selon les échéanciers") {
            Chart(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Capital", point.balance))
                    .foregroundStyle(by: .value("Prêt", point.loan))
            }
            .chartForegroundStyleScale(domain: names, range: names.indices.map { [Color.gray, .orange, .purple, .teal][$0 % 4] })
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .currency(code: currency).precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 200)
            .privacyBlur(hidden: appSettings.hideAmounts)

            PlanNote("Échéanciers calculés à partir du montant emprunté, du taux, de la durée et de la première échéance saisis pour chaque prêt (prêt amortissable à mensualités constantes).")
        }
    }

    // MARK: - Mensualité

    private func paymentBlock(_ lines: [DebtLine]) -> some View {
        let largest = lines.compactMap(\.monthlyPayment).max() ?? 1
        let total = lines.compactMap(\.monthlyPayment).reduce(0, +)
        let interest = lines.compactMap { $0.schedule?.nextPaymentSplit().interest }.reduce(0, +)

        return PlanBlock(title: "Où part la prochaine mensualité", subtitle: "capital, intérêts, assurance") {
            VStack(spacing: 10) {
                ForEach(lines) { line in
                    if let schedule = line.schedule {
                        let split = schedule.nextPaymentSplit()
                        let payment = schedule.payment + schedule.insurance
                        LTBarRow(
                            label: line.account.name,
                            detail: "\(ratePercent(schedule.terms.annualRate)) · fin en \(monthYear(schedule.endDate))",
                            bar: LTBar(segments: [
                                .init(fraction: split.capital / largest, color: .accentColor),
                                .init(fraction: split.interest / largest, color: .red),
                                .init(fraction: schedule.insurance / largest, color: .gray)
                            ]),
                            value: money(payment),
                            extra: payment > 0 ? "\(PlanFormat.percent(split.interest / payment)) d’intérêts" : nil,
                            labelWidth: 170
                        )
                    }
                }
            }
            HStack(spacing: 14) {
                legend("Capital", .accentColor)
                legend("Intérêts", .red)
                legend("Assurance", .gray)
            }
            PlanNote(total > 0
                     ? "Aujourd’hui, \(PlanFormat.percent(interest / total)) de vos mensualités paient des intérêts. La part du capital augmente à chaque échéance."
                     : "")
        }
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Taux d'endettement

    private func ratioBlock(_ report: DebtReport) -> some View {
        let income = report.monthlyIncome
        let ratio = report.debtRatio

        return PlanBlock(title: "Taux d’endettement", subtitle: "mensualités / revenus") {
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    row("Taux d’endettement", "le trait marque le seuil de 35 % appliqué par les banques",
                        ratio.map { PlanFormat.percent($0) } ?? "—", color: (ratio ?? 0) > debtRatioLimit ? .red : .green)
                    LTBar(fraction: (ratio ?? 0) / 0.5, color: (ratio ?? 0) > debtRatioLimit ? .red : .accentColor, height: 10, marker: debtRatioLimit / 0.5)
                }
                Divider()
                row("Revenus mensuels moyens", "12 derniers mois, comptes courants", income.map { money($0) } ?? "—")
                Divider()
                row("Mensualités", "assurance comprise, prêts renseignés", money(report.monthlyPayments))
                if let income {
                    Divider()
                    row("Reste à vivre", "revenus moins mensualités", money(PlanFormat.double(income) - report.monthlyPayments))
                    Divider()
                    let margin = PlanFormat.double(income) * debtRatioLimit - report.monthlyPayments
                    row("Marge avant 35 %", "mensualité supplémentaire possible", margin > 0 ? "\(money(margin)) / mois" : "aucune",
                        color: margin > 0 ? .accentColor : .red)
                }
            }
            PlanNote("Échelle de la barre : 0 à 50 %. Revenus : crédits des comptes courants, hors virements.")
        }
    }

    private func row(_ label: String, _ detail: String, _ value: String, color: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Remboursement anticipé

    private func prepaymentBlock(_ lines: [DebtLine], report: DebtReport) -> some View {
        let selected = lines.first { $0.id == prepaymentLoanID } ?? lines.first!
        let amount = Double(prepaymentText.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
        let schedule = selected.schedule!
        let result = schedule.prepayment(amount: amount, reduceDuration: reduceDuration)
        let first = report.avalancheFirst

        return PlanBlock(title: "Simuler un remboursement anticipé") {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("Montant")
                    TextField("10 000", text: $prepaymentText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text(currency).foregroundStyle(.secondary)
                }
                Picker("Sur", selection: Binding(get: { selected.id }, set: { prepaymentLoanID = $0 })) {
                    ForEach(lines) { line in
                        Text(line.account.name).tag(line.id)
                    }
                }
                .fixedSize()
                Picker("Effet", selection: $reduceDuration) {
                    Text("Réduire la durée").tag(true)
                    Text("Réduire la mensualité").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .font(.callout)

            VStack(spacing: 10) {
                row("Intérêts économisés", "sur la durée restante du prêt", "≈ \(money(result.interestSaved))", color: .green)
                Divider()
                if reduceDuration {
                    row("Fin du crédit avancée", result.monthsSaved > 0
                        ? "nouvelle dernière échéance : \(monthYear(Calendar.current.date(byAdding: .month, value: -result.monthsSaved, to: schedule.endDate) ?? schedule.endDate))"
                        : "montant trop faible pour gagner une échéance",
                        "\(result.monthsSaved) mois plus tôt", color: .green)
                } else {
                    row("Nouvelle mensualité", "même durée, hors assurance", "\(money(result.newPayment)) / mois",
                        color: .green)
                }
                Divider()
                row("Indemnités de remboursement anticipé", schedule.terms.isMortgage
                    ? "au plus 6 mois d’intérêts, plafonnés à 3 % du capital restant dû"
                    : "crédit à la consommation : 1 % au-delà de 10 000 € sur 12 mois",
                    "≈ \(money(result.penalty))", color: result.penalty > 0 ? .red : .primary)
                Divider()
                row("Rendement équivalent", "chaque euro remboursé « rapporte » le taux du crédit, sans impôt",
                    "\(ratePercent(schedule.terms.annualRate)) / an", color: .secondary)
            }

            PlanNote(advice(schedule: schedule, first: first))
        }
    }

    private func advice(schedule: LoanSchedule, first: DebtLine?) -> String {
        var text = ""
        if schedule.terms.annualRate < 0.025 {
            text = "À \(ratePercent(schedule.terms.annualRate)), un placement sans risque peut rapporter autant ou davantage : le remboursement anticipé n’est pas toujours le meilleur choix. "
        }
        if let first, let rate = first.schedule?.terms.annualRate {
            text += "Méthode « avalanche » : rembourser d’abord le prêt au taux le plus élevé, ici \(first.account.name) (\(ratePercent(rate)))."
        }
        return text
    }

    // MARK: - Tableau

    private func table(_ report: DebtReport) -> some View {
        ReportTable(
            columns: ["Prêt", "Taux", "Mensualité", "Capital restant", "Fin", "Intérêts restants", "Coût total du crédit"],
            rows: report.lines.map { line -> ReportRow in
                guard let schedule = line.schedule else {
                    return ReportRow(id: line.id.uuidString, cells: [
                        ReportCell(text: line.account.name, isAmount: false),
                        ReportCell(text: "—", color: .secondary, isAmount: false),
                        ReportCell(text: "—", color: .secondary, isAmount: false),
                        ReportCell(text: money(line.balance)),
                        ReportCell(text: "conditions à saisir", color: .orange, isAmount: false),
                        ReportCell(text: "—", color: .secondary, isAmount: false),
                        ReportCell(text: "—", color: .secondary, isAmount: false)
                    ])
                }
                return ReportRow(id: line.id.uuidString, cells: [
                    ReportCell(text: line.account.name, isAmount: false),
                    ReportCell(text: ratePercent(schedule.terms.annualRate), isAmount: false),
                    ReportCell(text: money(schedule.payment) + (schedule.insurance > 0 ? " + \(money(schedule.insurance))" : "")),
                    ReportCell(text: money(line.balance)),
                    ReportCell(text: monthYear(schedule.endDate), isAmount: false),
                    ReportCell(text: money(schedule.remainingInterest())),
                    ReportCell(text: money(schedule.totalInterest + schedule.totalInsurance))
                ])
            },
            footnote: "Coût total : intérêts et assurance sur toute la durée du crédit. Les conditions se modifient depuis la fiche du prêt (Modifier le compte › Conditions du prêt…)."
        )
    }
}
