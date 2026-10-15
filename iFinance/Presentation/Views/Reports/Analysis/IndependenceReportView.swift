import SwiftUI
import Charts

/// Rapport « Indépendance financière » : quand l'épargne placée pourrait couvrir les dépenses,
/// avec la règle des 4 % (capital visé = 25 fois les dépenses annuelles).
struct IndependenceReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var accountTermsController: AccountTermsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    @AppStorage("retirementBirthYear") private var birthYear = 0
    /// Rendement après inflation, en pourcentage
    @AppStorage("independenceRealReturn") private var realReturn = 3.0

    private var format: AnalysisFormat {
        AnalysisFormat(currency: booksController.currentBook?.currency ?? "EUR", hidden: appSettings.hideAmounts)
    }

    private struct Inputs {
        let capital: Double
        let spending: Double        // Par an
        let saving: Double          // Par an
        var target: Double { spending * 25 }
    }

    /// Première année où le capital atteint l'objectif (nil au-delà de 60 ans)
    private func targetYear(_ inputs: Inputs, saving: Double? = nil, spending: Double? = nil, rate: Double? = nil) -> Int? {
        let yearlySaving = saving ?? inputs.saving
        let target = (spending ?? inputs.spending) * 25
        let r = rate ?? realReturn / 100
        var capital = inputs.capital
        var year = Calendar.current.component(.year, from: Date())
        var steps = 0
        while capital < target {
            capital = capital * (1 + r) + yearlySaving
            year += 1
            steps += 1
            if steps > 60 { return nil }
        }
        return year
    }

    var body: some View {
        let builder = LongTermReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController,
            accountTermsController: accountTermsController
        )
        let expenses = builder.monthlyAverage(of: .debit) ?? 0
        let income = builder.monthlyAverage(of: .credit) ?? 0
        let inputs = Inputs(
            capital: PlanFormat.double(builder.liquidity().financialAssets),
            spending: PlanFormat.double(expenses) * 12,
            saving: max(PlanFormat.double(income - expenses) * 12, 0)
        )

        if inputs.spending == 0 {
            ReportEmptyState(systemImage: "sun.horizon", message: "Il faut quelques mois de dépenses sur les comptes courants pour estimer l’objectif.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    controls
                    headline(inputs)
                    tiles(inputs)
                    chartBlock(inputs)
                    LTBlockGrid(blocks: [AnyView(leversBlock(inputs)), AnyView(methodBlock(inputs))])
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Rendement après inflation", selection: $realReturn) {
                Text("2 % (prudent)").tag(2.0)
                Text("3 % (équilibré)").tag(3.0)
                Text("4 % (dynamique)").tag(4.0)
            }
            .fixedSize()
            Picker("Né en", selection: $birthYear) {
                Text("Non renseigné").tag(0)
                ForEach(Array((1940...(Calendar.current.component(.year, from: Date()) - 16)).reversed()), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .fixedSize()
            Spacer()
        }
    }

    private func ageText(_ year: Int) -> String {
        birthYear > 0 ? ", à \(year - birthYear) ans" : ""
    }

    // MARK: - Réponse

    private func headline(_ inputs: Inputs) -> some View {
        let share = inputs.capital / inputs.target
        if share >= 1 {
            return ReportHeadline(
                question: "Quand pourrais-je vivre de mon épargne ?",
                answer: "C’est déjà le cas en théorie : votre épargne couvre 25 fois vos dépenses annuelles.",
                detail: "Pensez aux impôts sur les retraits et aux imprévus avant de décider quoi que ce soit.",
                tone: .good
            )
        }
        let year = targetYear(inputs)
        return ReportHeadline(
            question: "Quand pourrais-je vivre de mon épargne ?",
            answer: year.map { "À votre rythme actuel, vous pourriez vivre de votre épargne vers \(String($0))\(ageText($0))." }
                ?? "À votre rythme actuel, l’objectif n’est pas atteignable : il faudrait épargner davantage.",
            detail: "Il faudrait un capital d’environ \(format.money(Decimal(inputs.target))), soit 25 fois vos dépenses annuelles. Vous en avez déjà \(format.percent(share)).",
            tone: .info
        )
    }

    // MARK: - Chiffres clés

    private func tiles(_ inputs: Inputs) -> some View {
        let year = targetYear(inputs)
        return ReportTiles {
            StatTile(title: "Capital visé", value: format.money(Decimal(inputs.target)), detail: "25 × \(format.money(Decimal(inputs.spending))) de dépenses par an")
            StatTile(title: "Déjà atteint", value: format.percent(min(inputs.capital / inputs.target, 1)), valueColor: .accentColor, detail: "\(format.money(Decimal(inputs.capital))) d’épargne")
            StatTile(title: "Vous épargnez", value: "\(format.money(Decimal(inputs.saving / 12))) / mois", valueColor: .green, detail: "moyenne des 12 derniers mois")
            StatTile(
                title: "Date estimée",
                value: year.map { String($0) } ?? "—",
                detail: year.map { "dans \($0 - Calendar.current.component(.year, from: Date())) ans\(ageText($0))" } ?? "au-delà de 60 ans"
            )
        }
    }

    // MARK: - Courbe

    private struct Point: Identifiable {
        var id: Int { year }
        let year: Int
        let capital: Double
    }

    private func chartBlock(_ inputs: Inputs) -> some View {
        let start = Calendar.current.component(.year, from: Date())
        let end = min((targetYear(inputs) ?? start + 40) + 3, start + 45)
        var capital = inputs.capital
        var points: [Point] = []
        for year in start...end {
            if year > start { capital = capital * (1 + realReturn / 100) + inputs.saving }
            points.append(Point(year: year, capital: capital))
        }

        return PlanBlock(title: "Votre épargne face à l’objectif", subtitle: "rendement de \(Int(realReturn)) % par an après inflation") {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Année", point.year), y: .value("Capital", point.capital))
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                    LineMark(x: .value("Année", point.year), y: .value("Capital", point.capital))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                RuleMark(y: .value("Objectif", inputs.target))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("objectif \(format.money(Decimal(inputs.target)))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                if let year = targetYear(inputs) {
                    RuleMark(x: .value("Année", year))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        // Repère gardé dans le graphique, sous le titre du bloc
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))) {
                            Text(String(year)).font(.caption).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXScale(domain: start...end)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let year = value.as(Int.self) { Text(String(year)) }
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
            PlanNote("Montants en euros d’aujourd’hui : l’inflation est déjà retirée du rendement. Les marchés ne montent pas en ligne droite.")
        }
    }

    // MARK: - Leviers

    private func leversBlock(_ inputs: Inputs) -> some View {
        let base = targetYear(inputs)
        func text(_ year: Int?) -> String { year.map { String($0) } ?? "—" }
        func color(_ year: Int?) -> Color {
            guard let year, let base else { return .gray }
            return year < base ? .green : year > base ? .orange : .gray
        }
        let more = targetYear(inputs, saving: inputs.saving + 2_400)
        let less = targetYear(inputs, saving: inputs.saving + inputs.spending * 0.1, spending: inputs.spending * 0.9)
        let lower = targetYear(inputs, rate: max(realReturn - 1, 0) / 100)
        let higher = targetYear(inputs, rate: (realReturn + 1) / 100)

        return PlanBlock(title: "Ce qui avance ou recule la date") {
            VStack(alignment: .leading, spacing: 2) {
                LTNoticeRow(title: "Épargner 200 € de plus par mois", value: text(more), color: color(more), valueColor: color(more))
                LTNoticeRow(title: "Dépenser 10 % de moins", detail: "l’objectif baisse aussi : il faut moins de capital", value: text(less), color: color(less), valueColor: color(less))
                LTNoticeRow(title: "Rendement de \(Int(max(realReturn - 1, 0))) %", detail: "placements plus prudents", value: text(lower), color: color(lower), valueColor: color(lower))
                LTNoticeRow(title: "Rendement de \(Int(realReturn + 1)) %", detail: "placements plus dynamiques, plus de risques", value: text(higher), color: color(higher), valueColor: color(higher))
            }
        }
    }

    // MARK: - Méthode

    private func methodBlock(_ inputs: Inputs) -> some View {
        PlanBlock(title: "Comment c’est calculé") {
            VStack(spacing: 10) {
                ExplanationRow(label: "Vos dépenses", detail: "moyenne des 12 derniers mois, comptes courants", value: "\(format.money(Decimal(inputs.spending))) / an")
                Divider()
                ExplanationRow(label: "Règle des 4 %", detail: "on peut retirer environ 4 % par an d’un capital placé sans l’épuiser", value: "× 25")
                Divider()
                ExplanationRow(label: "Votre épargne", detail: "livrets, placements, épargne salariale et retraite (hors biens)", value: format.money(Decimal(inputs.capital)))
                Divider()
                ExplanationRow(label: "Ce que vous mettez de côté", detail: "revenus moins dépenses, 12 derniers mois", value: "\(format.money(Decimal(inputs.saving))) / an")
            }
            PlanNote("Repère simple, pas un conseil : il ne tient compte ni des pensions de retraite, ni des impôts sur les retraits.")
        }
    }
}
