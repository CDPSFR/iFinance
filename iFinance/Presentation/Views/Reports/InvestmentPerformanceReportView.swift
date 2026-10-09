import SwiftUI
import Charts

/// Rapport « Performance des placements » : comptes-titres, PEA, crypto et assurance vie.
/// Valeurs au jour et depuis l'ouverture des comptes : la période de la barre d'outils ne s'applique pas.
struct InvestmentPerformanceReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var accountTermsController: AccountTermsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    enum Allocation: String, CaseIterable, Identifiable {
        case envelope = "Enveloppe"
        case assetClass = "Classe d’actifs"
        case currency = "Devise"
        var id: String { rawValue }
    }

    @State private var allocation: Allocation = .envelope
    @State private var termsAccount: Account?

    /// Prélèvement forfaitaire unique 2026 : 12,8 % d'impôt + 18,6 % de prélèvements sociaux
    private let flatTaxRate = 0.314

    var body: some View {
        let report = LongTermReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController,
            accountTermsController: accountTermsController
        ).investments()

        Group {
            if report.lines.isEmpty {
                ReportEmptyState(systemImage: "chart.line.uptrend.xyaxis", message: "Aucun compte d’investissement ni d’assurance vie.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                        tiles(report)
                        LTBlockGrid(blocks: [
                            AnyView(waterfall(report)),
                            AnyView(returns(report)),
                            AnyView(allocationBlock(report)),
                            AnyView(incomeBlock(report)),
                            AnyView(feesBlock(report)),
                            AnyView(taxBlock(report))
                        ])
                        table(report)
                    }
                }
            }
        }
        .sheet(item: $termsAccount) { account in
            AccountTermsFormView(account: account)
        }
    }

    private var currency: String { booksController.currentBook?.currency ?? "EUR" }
    /// Montant affiché, ou « ••• » quand les montants sont masqués (tuiles, lignes, tableaux)
    private func money(_ value: Decimal) -> String { appSettings.hideAmounts ? "•••" : PlanFormat.round(value, currency) }
    private func signed(_ value: Decimal) -> String { appSettings.hideAmounts ? "•••" : (value > 0 ? "+" : "") + money(value) }
    private func percent(_ value: Double?) -> String { value.map { PlanFormat.percent($0, signed: true) } ?? "—" }

    // MARK: - Chiffres clés

    private func tiles(_ report: InvestmentReport) -> some View {
        ReportTiles {
            StatTile(title: "Valeur des placements", value: money(report.value), detail: "\(report.lines.count) compte\(report.lines.count > 1 ? "s" : "")")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Gain total",
                value: signed(report.gain),
                valueColor: report.gain >= 0 ? .green : .red,
                detail: "sur \(money(report.invested)) versés nets"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Rendement annualisé",
                value: percent(report.annualized),
                valueColor: (report.annualized ?? 0) >= 0 ? .green : .red,
                detail: "versements et retraits pris en compte"
            )

            StatTile(title: "Revenus sur 12 mois", value: money(report.income12Months), detail: "dividendes et intérêts nets")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Frais estimés",
                value: report.averageFeeRate == nil ? "À saisir" : "−\(money(report.annualFeeCost)) / an",
                valueColor: report.averageFeeRate == nil ? .secondary : .red,
                detail: report.averageFeeRate.map { "\($0.formatted(.percent.precision(.fractionLength(0...2)))) de l’encours renseigné" } ?? "taux de frais des comptes"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - D'où vient la valeur

    private struct Step: Identifiable {
        var id: String { name }
        let name: String
        let start: Double
        let end: Double
        let color: Color
        let label: String
    }

    private func steps(_ report: InvestmentReport) -> [Step] {
        var result: [Step] = []
        var level = PlanFormat.double(report.invested)
        result.append(Step(name: "Versé net", start: 0, end: level, color: .gray, label: money(report.invested)))

        let parts: [(String, Decimal)] = [
            ("Plus-value latente", report.unrealized),
            ("Plus-values réalisées", report.realized),
            ("Dividendes et intérêts", report.income),
            ("Frais", -report.fees),
            ("Autres", report.otherGain)
        ]
        for (name, amount) in parts where abs(PlanFormat.double(amount)) >= 1 {
            let next = level + PlanFormat.double(amount)
            result.append(Step(name: name, start: level, end: next, color: amount >= 0 ? .green : .red, label: signed(amount)))
            level = next
        }
        result.append(Step(name: "Valeur", start: 0, end: PlanFormat.double(report.value), color: .accentColor, label: money(report.value)))
        return result
    }

    private func waterfall(_ report: InvestmentReport) -> some View {
        let steps = self.steps(report)
        let values = steps.flatMap { [$0.start, $0.end] }
        let low = max((values.filter { $0 > 0 }.min() ?? 0) * 0.85, 0)

        return PlanBlock(title: "D’où vient la valeur", subtitle: "du versé net à la valeur actuelle") {
            Chart(steps) { step in
                BarMark(
                    x: .value("Étape", step.name),
                    yStart: .value("Début", max(min(step.start, step.end), low)),
                    yEnd: .value("Fin", max(step.start, step.end))
                )
                .foregroundStyle(step.color)
                .annotation(position: .top) {
                    Text(step.label)
                        .font(.caption2)
                        .foregroundStyle(step.color == .gray || step.color == .accentColor ? Color.secondary : step.color)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
            }
            .chartYScale(domain: low...((values.max() ?? 1) * 1.05))
            .chartYAxis(.hidden)
            .frame(height: 200)
            PlanNote("Axe tronqué pour lisibilité. Latente : titres encore détenus ; réalisée : ventes passées. Pour l’assurance vie, tout le gain apparaît en latent.")
        }
        .privacyBlur(hidden: appSettings.hideAmounts)
    }

    // MARK: - Rendement par compte

    private func returns(_ report: InvestmentReport) -> some View {
        let rows = report.lines.filter { $0.annualized != nil }
        let largest = max(rows.compactMap { $0.annualized.map { abs($0) } }.max() ?? 0.01, abs(report.annualized ?? 0), 0.01)

        return PlanBlock(title: "Rendement annualisé par compte", subtitle: "versements et retraits pris en compte") {
            VStack(spacing: 10) {
                ForEach(rows) { line in
                    let value = line.annualized ?? 0
                    LTBarRow(
                        label: line.account.name,
                        detail: line.account.type.displayName,
                        bar: LTBar(fraction: abs(value) / largest, color: value >= 0 ? .teal : .red),
                        value: percent(value),
                        valueColor: value >= 0 ? .green : .red,
                        labelWidth: 160
                    )
                }
                if let total = report.annualized {
                    LTBarRow(
                        label: "Tous les comptes",
                        bar: LTBar(fraction: abs(total) / largest, color: .accentColor),
                        value: percent(total),
                        valueColor: total >= 0 ? .green : .red,
                        labelWidth: 160,
                        isEmphasized: true
                    )
                }
            }
            PlanNote(rows.isEmpty
                     ? "Il faut au moins 3 mois d’historique pour calculer un rendement annualisé."
                     : "Taux de rendement interne : chaque versement compte pour la durée où il a été placé. Moins de 3 mois d’historique : pas de calcul.")
        }
    }

    // MARK: - Répartition

    private func allocationBlock(_ report: InvestmentReport) -> some View {
        let slices: [AllocationSlice] = {
            switch allocation {
            case .envelope: return report.byEnvelope
            case .assetClass: return report.byAssetClass
            case .currency: return report.byCurrency
            }
        }()
        let total = slices.reduce(Decimal(0)) { $0 + $1.value }
        let largest = PlanFormat.double(slices.first?.value ?? 1)

        return PlanBlock(title: "Répartition") {
            Picker("Répartition", selection: $allocation) {
                ForEach(Allocation.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } content: {
            VStack(spacing: 10) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    LTBarRow(
                        label: slice.name,
                        bar: LTBar(fraction: PlanFormat.double(slice.value) / max(largest, 1), color: LTPalette.color(at: index)),
                        value: money(slice.value),
                        extra: PlanFormat.ratio(slice.value, total).map { PlanFormat.percent($0) },
                        labelWidth: 160
                    )
                }
            }
            PlanNote("Hors épargne salariale et retraite, qui ont leur propre rapport. Les supports de l’assurance vie ne sont pas détaillés.")
        }
    }

    // MARK: - Revenus

    private func incomeBlock(_ report: InvestmentReport) -> some View {
        PlanBlock(title: "Revenus des placements", subtitle: "12 derniers mois") {
            Chart {
                ForEach(report.monthlyIncome) { month in
                    BarMark(x: .value("Mois", month.month, unit: .month), y: .value("Montant", PlanFormat.double(month.dividends)))
                        .foregroundStyle(by: .value("Type", "Dividendes"))
                    BarMark(x: .value("Mois", month.month, unit: .month), y: .value("Montant", PlanFormat.double(month.interest)))
                        .foregroundStyle(by: .value("Type", "Intérêts"))
                }
            }
            .chartForegroundStyleScale(["Dividendes": Color.accentColor, "Intérêts": Color.teal])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 170)
            .privacyBlur(hidden: appSettings.hideAmounts)

            PlanNote("Montants nets de frais, tels que saisis dans les opérations (dividende, intérêts). L’assurance vie suivie par relevés n’a pas de revenus détaillés.")
        }
    }

    // MARK: - Frais

    private func feesBlock(_ report: InvestmentReport) -> some View {
        PlanBlock(title: "Ce que coûtent les frais", subtitle: "taux saisis pour chaque compte") {
            VStack(spacing: 8) {
                ForEach(report.lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.account.name)
                            Text(line.feeRate.map { "\($0.formatted(.percent.precision(.fractionLength(0...2)))) par an" } ?? "taux non renseigné")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let cost = line.annualFeeCost {
                            Text("\(money(cost)) / an")
                                .monospacedDigit()
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }
                        Button(line.feeRate == nil ? "Saisir…" : "Modifier…") {
                            termsAccount = line.account
                        }
                        .buttonStyle(.link)
                    }
                    Divider()
                }

                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(money(report.annualFeeCost)) / an")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }

                if let shortfall = report.feeShortfall() {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Manque à gagner sur 20 ans")
                            Text("à 5 % de rendement brut, sans nouveau versement")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("≈ \(money(shortfall))")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    }
                }
            }
            PlanNote("Frais de gestion du contrat et frais courants des fonds (document d’informations clés). Les frais d’opérations saisis sont déjà déduits des performances.")
        }
    }

    // MARK: - Fiscalité

    private func taxBlock(_ report: InvestmentReport) -> some View {
        let year = Calendar.current.component(.year, from: Date())
        let now = Date()

        return PlanBlock(title: "Fiscalité \(String(year))", subtitle: "à reporter sur la déclaration de revenus") {
            VStack(alignment: .leading, spacing: 2) {
                if report.realizedThisYear != 0 {
                    LTNoticeRow(
                        title: report.realizedThisYear > 0 ? "Plus-values réalisées sur les comptes-titres" : "Moins-values réalisées sur les comptes-titres",
                        detail: report.realizedThisYear > 0
                            ? "case 3VG · prélèvement forfaitaire de 31,4 % ≈ \(money(report.realizedThisYear * Decimal(flatTaxRate)))"
                            : "case 3VH · reportables sur les plus-values des 10 années suivantes",
                        value: signed(report.realizedThisYear),
                        valueColor: report.realizedThisYear > 0 ? .green : .red
                    )
                }
                if report.dividendsThisYear > 0 {
                    LTNoticeRow(
                        title: "Dividendes des comptes-titres",
                        detail: "acompte de 12,8 % et prélèvements sociaux de 18,6 % en principe prélevés à la source",
                        value: money(report.dividendsThisYear)
                    )
                }
                ForEach(report.peaFiveYears) { pea in
                    LTNoticeRow(
                        title: pea.date > now
                            ? "\(pea.account.name) : 5 ans le \(pea.date.formatted(.dateTime.day().month(.wide).year()))"
                            : "\(pea.account.name) : plus de 5 ans",
                        detail: (pea.date > now
                                 ? "avant cette date, un retrait clôture le plan · "
                                 : "retraits possibles sans clôturer le plan, gains exonérés d’impôt (prélèvements sociaux dus) · ")
                            + "\(money(pea.deposits)) versés sur 150 000 €",
                        value: PlanFormat.ratio(pea.deposits, 150_000).map { PlanFormat.percent($0) },
                        color: pea.date > now ? .orange : .green
                    )
                }
                ForEach(report.lifeInsuranceEightYears) { contract in
                    LTNoticeRow(
                        title: contract.date > now
                            ? "\(contract.account.name) : 8 ans le \(contract.date.formatted(.dateTime.day().month(.wide).year()))"
                            : "\(contract.account.name) : plus de 8 ans",
                        detail: contract.date > now
                            ? "ensuite, abattement annuel sur les gains rachetés : 4 600 € (9 200 € en couple)"
                            : "abattement annuel sur les gains rachetés : 4 600 € (9 200 € en couple)",
                        color: contract.date > now ? .orange : .green
                    )
                }
                if report.realizedThisYear == 0 && report.dividendsThisYear == 0 && report.peaFiveYears.isEmpty && report.lifeInsuranceEightYears.isEmpty {
                    PlanNote("Rien à déclarer pour l’instant cette année.")
                }
            }
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Tableau

    private func table(_ report: InvestmentReport) -> some View {
        var rows = report.lines.map { line in
            ReportRow(id: line.id.uuidString, cells: [
                ReportCell(text: line.account.name, isAmount: false),
                ReportCell(text: money(line.invested)),
                ReportCell(text: money(line.value)),
                ReportCell(text: signed(line.gain), color: line.gain >= 0 ? .green : .red),
                ReportCell(text: percent(line.annualized), color: (line.annualized ?? 0) >= 0 ? .green : .red, isAmount: false),
                ReportCell(text: line.income12Months == 0 ? "—" : money(line.income12Months)),
                ReportCell(text: line.annualFeeCost.map(money) ?? "—", color: .secondary)
            ])
        }
        rows.append(ReportRow(id: "total", cells: [
            ReportCell(text: "Total", isAmount: false),
            ReportCell(text: money(report.invested)),
            ReportCell(text: money(report.value)),
            ReportCell(text: signed(report.gain), color: report.gain >= 0 ? .green : .red),
            ReportCell(text: percent(report.annualized), color: (report.annualized ?? 0) >= 0 ? .green : .red, isAmount: false),
            ReportCell(text: money(report.income12Months)),
            ReportCell(text: report.averageFeeRate == nil ? "—" : money(report.annualFeeCost), color: .secondary)
        ]))

        return ReportTable(
            columns: ["Compte", "Versé net", "Valeur", "Plus-value", "Rendement annualisé", "Revenus 12 mois", "Frais / an"],
            rows: rows,
            footnote: "Rendement annualisé : taux de rendement interne, qui tient compte de la date de chaque versement."
        )
    }
}
