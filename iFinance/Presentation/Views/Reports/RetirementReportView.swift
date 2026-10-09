import SwiftUI
import Charts

/// Rapport « Retraite et épargne salariale » : PEE, PERCO, PER et article 83 réunis.
/// Valeurs au jour et avantages de l'année civile en cours.
struct RetirementReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var accountTermsController: AccountTermsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Hypothèses de la projection, mémorisées
    @AppStorage("retirementBirthYear") private var birthYear = 0
    @AppStorage("retirementAge") private var retirementAge = 64
    @AppStorage("retirementMonthlyContribution") private var monthlyContributionText = ""

    private let rates: [(name: String, rate: Double)] = [("Prudente", 0.02), ("Centrale", 0.04), ("Dynamique", 0.06)]
    /// Ordre de grandeur du taux de conversion d'un capital en rente viagère vers 64 ans
    private let annuityRate = 0.04

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        let report = LongTermReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController,
            accountTermsController: accountTermsController
        ).retirement()

        if report.plans.isEmpty {
            ReportEmptyState(systemImage: "figure.walk", message: "Aucun PEE, PERCO, PER ni article 83.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(report)
                    LTBlockGrid(blocks: [
                        AnyView(availabilityBlock(report)),
                        AnyView(advantagesBlock(report)),
                        AnyView(projectionBlock(report)),
                        AnyView(todoBlock(report))
                    ])
                    table(report)
                }
            }
        }
    }

    private var currency: String { booksController.currentBook?.currency ?? "EUR" }
    /// Montant affiché, ou « ••• » quand les montants sont masqués (tuiles, lignes, tableaux)
    private func money(_ value: Decimal) -> String { appSettings.hideAmounts ? "•••" : PlanFormat.round(value, currency) }

    // MARK: - Hypothèses

    private var monthlyContributionOverride: Decimal? {
        let trimmed = monthlyContributionText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private func monthlyContribution(_ report: RetirementReport) -> Decimal {
        monthlyContributionOverride ?? report.monthlyContributions
    }

    /// Années restantes avant le départ ; nil si l'année de naissance n'est pas renseignée
    private var yearsToRetirement: Int? {
        guard birthYear > 0 else { return nil }
        return max(birthYear + retirementAge - currentYear, 0)
    }

    private func centralCapital(_ report: RetirementReport) -> Double? {
        yearsToRetirement.map { report.projectedCapital(years: Double($0), rate: 0.04, monthlyContribution: monthlyContribution(report)) }
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: RetirementReport) -> some View {
        ReportTiles {
            StatTile(title: "Valeur des plans", value: money(report.value), detail: "\(report.plans.count) plan\(report.plans.count > 1 ? "s" : "")")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Disponible aujourd’hui",
                value: money(report.available),
                valueColor: report.available > 0 ? .green : .secondary,
                detail: PlanFormat.ratio(report.available, report.value).map { "\(PlanFormat.percent($0)) des plans" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Gagné grâce aux dispositifs",
                value: money(report.advantages.total),
                valueColor: .green,
                detail: report.advantages.marginalTaxRate == nil
                    ? "abondement \(String(currentYear)) ; impôt évité : tranche à saisir"
                    : "en \(String(currentYear)) : abondement et impôt évité"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Encore à capter",
                value: report.matchingLeft.map(money) ?? "—",
                valueColor: (report.matchingLeft ?? 0) > 0 ? .orange : .secondary,
                detail: report.matchingLeft == nil ? "plafond de l’accord non saisi" : "d’abondement d’ici le 31 décembre"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Capital estimé à \(retirementAge) ans",
                value: centralCapital(report).map { "≈ \(money(Decimal($0)))" } ?? "—",
                detail: yearsToRetirement.map { "en \(String(currentYear + $0)), hypothèse centrale 4 %" } ?? "année de naissance à saisir"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Disponibilité

    private struct ReleaseBar: Identifiable {
        let id: String
        let label: String
        let plan: String
        let amount: Double
    }

    private func availabilityBlock(_ report: RetirementReport) -> some View {
        let names = Dictionary(uniqueKeysWithValues: report.plans.map { ($0.id, $0.account.name) })
        let bars = report.releases.flatMap { release in
            report.plans.compactMap { plan -> ReleaseBar? in
                guard let amount = release.amounts[plan.id], amount > 0 else { return nil }
                return ReleaseBar(id: "\(release.label)-\(plan.id)", label: release.label, plan: names[plan.id] ?? "", amount: PlanFormat.double(amount))
            }
        }
        let planNames = report.plans.map(\.account.name)

        return PlanBlock(title: "Quand l’argent devient disponible", subtitle: "tous plans confondus") {
            Chart(bars) { bar in
                BarMark(x: .value("Échéance", bar.label), y: .value("Montant", bar.amount))
                    .foregroundStyle(by: .value("Plan", bar.plan))
            }
            .chartForegroundStyleScale(domain: planNames, range: planNames.indices.map { LTPalette.color(at: $0) })
            .chartXScale(domain: report.releases.map(\.label))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .currency(code: currency).precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 190)
            .privacyBlur(hidden: appSettings.hideAmounts)

            PlanNote("Valeur estimée répartie au prorata des sommes versées. À la retraite, l’article 83 sort en rente ; PER et PERCO en capital ou en rente.")
        }
    }

    // MARK: - Avantages de l'année

    private func advantagesBlock(_ report: RetirementReport) -> some View {
        let advantages = report.advantages
        let rateText = advantages.marginalTaxRate.map { "tranche à \(PlanFormat.percent($0))" } ?? "tranche marginale à saisir dans les réglages du PER"

        func saving(_ amount: Decimal) -> String {
            advantages.taxSaving(amount).map { "≈ \(money($0))" } ?? "—"
        }

        var rows: [PlanFactRow] = []
        if advantages.matching > 0 || report.plans.contains(where: { $0.kind == .pee }) {
            rows.append(PlanFactRow(label: "Abondement reçu", detail: "versé par l’employeur cette année", value: "+\(money(advantages.matching))", color: .green))
        }
        if advantages.perDeducted > 0 {
            rows.append(PlanFactRow(label: "Déduction PER", detail: "\(money(advantages.perDeducted)) déduits · \(rateText)", value: saving(advantages.perDeducted), color: .green))
        }
        if advantages.employeeSavings > 0 {
            rows.append(PlanFactRow(label: "Intéressement et participation placés", detail: "\(money(advantages.employeeSavings)) exonérés d’impôt sur le revenu", value: saving(advantages.employeeSavings), color: .green))
        }
        if advantages.article83 > 0 {
            rows.append(PlanFactRow(label: "Cotisations article 83", detail: "\(money(advantages.article83)) déduites du salaire imposable", value: saving(advantages.article83), color: .green))
        }
        rows.append(PlanFactRow(label: "Total gagné en \(String(currentYear))", value: money(advantages.total), color: .green))

        return PlanFactsBlock(
            title: "Avantages de l’année",
            subtitle: String(currentYear),
            rows: rows,
            footnote: "Impôt évité estimé avec la tranche marginale saisie dans les réglages d’un PER. Les prélèvements sociaux restent dus."
        )
        .privacyBlur(hidden: appSettings.hideAmounts)
    }

    // MARK: - Projection

    private struct ProjectionPoint: Identifiable {
        var id: Int { year }
        let year: Int
        let low: Double
        let central: Double
        let high: Double
    }

    private func projectionBlock(_ report: RetirementReport) -> some View {
        let monthly = monthlyContribution(report)

        return PlanBlock(title: "Projection jusqu’à la retraite", subtitle: "si rien n’est retiré") {
            HStack(spacing: 16) {
                Picker("Né en", selection: $birthYear) {
                    Text("Non renseigné").tag(0)
                    ForEach(Array((1940...(currentYear - 16)).reversed()), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .fixedSize()

                Stepper("Départ à \(retirementAge) ans", value: $retirementAge, in: 55...75)
                    .fixedSize()

                HStack(spacing: 6) {
                    Text("Apports")
                    TextField(PlanFormat.round(report.monthlyContributions, currency), text: $monthlyContributionText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("/ mois")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.callout)

            if let years = yearsToRetirement, years > 0 {
                let points = (0...years).map { offset in
                    ProjectionPoint(
                        year: currentYear + offset,
                        low: report.projectedCapital(years: Double(offset), rate: rates[0].rate, monthlyContribution: monthly),
                        central: report.projectedCapital(years: Double(offset), rate: rates[1].rate, monthlyContribution: monthly),
                        high: report.projectedCapital(years: Double(offset), rate: rates[2].rate, monthlyContribution: monthly)
                    )
                }
                let last = points.last!

                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Année", point.year), yStart: .value("Prudente", point.low), yEnd: .value("Dynamique", point.high))
                            .foregroundStyle(Color.teal.opacity(0.18))
                        LineMark(x: .value("Année", point.year), y: .value("Capital", point.central), series: .value("Hypothèse", "Centrale 4 %"))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        LineMark(x: .value("Année", point.year), y: .value("Capital", point.low), series: .value("Hypothèse", "Prudente 2 %"))
                            .foregroundStyle(Color.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        LineMark(x: .value("Année", point.year), y: .value("Capital", point.high), series: .value("Hypothèse", "Dynamique 6 %"))
                            .foregroundStyle(Color.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: points.first!.year...last.year)
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
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let year = value.as(Int.self) {
                                Text(String(year))
                            }
                        }
                    }
                }
                .frame(height: 220)
                .privacyBlur(hidden: appSettings.hideAmounts)

                HStack(spacing: 20) {
                    projectionFigure("Prudente 2 %", last.low, .teal)
                    projectionFigure("Centrale 4 %", last.central, .accentColor)
                    projectionFigure("Dynamique 6 %", last.high, .teal)
                    Spacer()
                }

                PlanNote("Ordre de grandeur, en euros courants et avant impôt. En rente viagère, le capital central représenterait environ \(money(Decimal(last.central * annuityRate / 12))) par mois. Apports par défaut : moyenne des 12 derniers mois (\(money(report.monthlyContributions)) / mois).")
            } else {
                PlanNote(birthYear == 0
                         ? "Indiquez votre année de naissance pour projeter le capital jusqu’au départ."
                         : "L’âge de départ choisi est déjà atteint.")
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }
        }
    }

    private func projectionFigure(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("≈ \(money(Decimal(value)))")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - À faire

    private struct UnlockNotice: Identifiable {
        let id: UUID
        let name: String
        let date: Date
        let amount: Decimal
    }

    private func todoBlock(_ report: RetirementReport) -> some View {
        let now = Date()
        let calendar = Calendar.current
        let inAYear = calendar.date(byAdding: .year, value: 1, to: now) ?? now

        let stale = report.plans.filter { plan in
            guard let snapshot = plan.summary.lastSnapshot else { return true }
            return (calendar.dateComponents([.month], from: snapshot.date, to: now).month ?? 0) >= 6
        }
        let unlocks: [UnlockNotice] = report.plans.compactMap { plan in
            let summary = plan.summary
            let locked = summary.unlocks.reduce(Decimal(0)) { $0 + $1.amount }
            guard locked > 0, let next = summary.unlocks.first(where: { $0.date != nil }), let date = next.date, date <= inAYear else { return nil }
            return UnlockNotice(id: plan.id, name: plan.account.name, date: date, amount: next.amount * summary.blockedValue / locked)
        }
        let isEmpty = (report.matchingLeft ?? 0) == 0 && report.expiringCeiling == 0 && stale.isEmpty && unlocks.isEmpty

        return PlanBlock(title: "À faire avant le 31 décembre") {
            VStack(alignment: .leading, spacing: 2) {
                if let left = report.matchingLeft, left > 0 {
                    LTNoticeRow(
                        title: report.matchingNeeded.map { "Verser environ \(money($0)) sur l’épargne salariale" } ?? "Faire un versement volontaire sur l’épargne salariale",
                        detail: "pour capter l’abondement restant prévu par votre accord",
                        value: "+\(money(left))",
                        color: .orange,
                        valueColor: .green
                    )
                }
                if report.expiringCeiling > 0 {
                    LTNoticeRow(
                        title: "\(money(report.expiringCeiling)) de plafond PER\(report.expiringCeilingYear.map { " de \(String($0))" } ?? "") seront perdus",
                        detail: "un versement déductible d’ici fin décembre les utilise en priorité",
                        value: money(report.expiringCeiling),
                        color: .orange,
                        valueColor: .orange
                    )
                }
                ForEach(stale, id: \.id) { plan in
                    LTNoticeRow(
                        title: "Mettre à jour la valeur de \(plan.account.name)",
                        detail: plan.summary.lastSnapshot.map { "dernier relevé le \($0.date.formatted(.dateTime.day().month(.abbreviated).year()))" } ?? "aucune valeur relevée",
                        color: .gray
                    )
                }
                ForEach(unlocks) { unlock in
                    LTNoticeRow(
                        title: "\(money(unlock.amount)) de \(unlock.name) se débloquent le \(unlock.date.formatted(.dateTime.day().month(.wide).year()))",
                        detail: "disponibles sans condition à cette date",
                        color: .green
                    )
                }
                if isEmpty {
                    PlanNote("Rien d’urgent : vos plans sont à jour.")
                }
            }
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Tableau

    private func table(_ report: RetirementReport) -> some View {
        var rows = report.plans.map { plan -> ReportRow in
            let summary = plan.summary
            let locked = summary.unlocks.reduce(Decimal(0)) { $0 + $1.amount }
            let next = summary.unlocks.first { $0.date != nil }
            let nextText: String
            if let next, let date = next.date, locked > 0 {
                nextText = "\(money(next.amount * summary.blockedValue / locked)) le \(date.formatted(.dateTime.day().month(.abbreviated).year()))"
            } else {
                nextText = summary.blockedValue > 0 ? "Retraite" : "—"
            }
            let exit: String
            switch plan.account.type {
            case .article83: exit = "Rente"
            case .pee: exit = "Capital"
            default: exit = "Capital ou rente"
            }
            return ReportRow(id: plan.id.uuidString, cells: [
                ReportCell(text: plan.account.name, isAmount: false),
                ReportCell(text: money(summary.value)),
                ReportCell(text: money(summary.invested)),
                ReportCell(text: (summary.gain > 0 ? "+" : "") + money(summary.gain), color: summary.gain >= 0 ? .green : .red),
                ReportCell(text: money(summary.availableValue)),
                ReportCell(text: nextText, color: .secondary),
                ReportCell(text: exit, color: .secondary, isAmount: false)
            ])
        }
        let gain = report.value - report.invested
        rows.append(ReportRow(id: "total", cells: [
            ReportCell(text: "Total", isAmount: false),
            ReportCell(text: money(report.value)),
            ReportCell(text: money(report.invested)),
            ReportCell(text: (gain > 0 ? "+" : "") + money(gain), color: gain >= 0 ? .green : .red),
            ReportCell(text: money(report.available)),
            ReportCell(text: "", isAmount: false),
            ReportCell(text: "", isAmount: false)
        ]))

        return ReportTable(
            columns: ["Plan", "Valeur", "Versé net", "Plus-value", "Disponible", "Prochain déblocage", "Sortie"],
            rows: rows,
            footnote: "Valeurs estimées à partir du dernier relevé de chaque plan et des versements faits depuis."
        )
    }
}
