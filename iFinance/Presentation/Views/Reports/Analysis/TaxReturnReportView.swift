import SwiftUI

/// Rapport « Préparer la déclaration » : réductions et crédits d'impôt repérés dans les dépenses
/// (catégories reliées aux cases de la déclaration), versements PER et revenus de placements.
struct TaxReturnReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var accountTermsController: AccountTermsController
    @EnvironmentObject var taxMappingController: TaxMappingController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Revenus déclarés : l'année précédente jusqu'en juin, l'année en cours ensuite
    @State private var year: Int = {
        let now = Date()
        let calendar = Calendar.current
        let current = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) <= 6 ? current - 1 : current
    }()
    @State private var showMapping = false

    private var format: AnalysisFormat {
        AnalysisFormat(currency: booksController.currentBook?.currency ?? "EUR", hidden: appSettings.hideAmounts)
    }

    private func makeReport() -> TaxReport {
        var report = AnalysisReportBuilder(
            accountsController: accountsController,
            transactionsController: transactionsController,
            categoriesController: categoriesController,
            payeesController: payeesController,
            recurringController: recurringController
        ).taxReport(year: year, mapping: taxMappingController.mapping)

        // Versements PER déduits de l'année
        for account in accountsController.activeAccounts where SavingsPlanPageKind(account.type) == .per {
            let flows = savingsPlansController.flows(for: account, transactions: transactionsController.allTransactions)
            report.perDeductions += RetirementPlanAnalytics.deductedContributions(flows: flows, year: year)
            report.marginalTaxRate = report.marginalTaxRate ?? savingsPlansController.planSettings(for: account.id).marginalTaxRate
        }

        // Plus-values et dividendes des comptes-titres de l'année
        let calendar = Calendar.current
        if let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) {
            let investments = LongTermReportBuilder(
                accountsController: accountsController,
                transactionsController: transactionsController,
                investmentsController: investmentsController,
                savingsPlansController: savingsPlansController,
                accountTermsController: accountTermsController,
                now: min(end, Date())
            ).investments()
            report.realizedGains = investments.realizedThisYear
            report.dividends = investments.dividendsThisYear
        }
        return report
    }

    var body: some View {
        let report = makeReport()
        let currentYear = Calendar.current.component(.year, from: Date())

        ScrollView {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                HStack(spacing: 16) {
                    Picker("Revenus", selection: $year) {
                        ForEach([currentYear, currentYear - 1, currentYear - 2], id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Relier les catégories…") { showMapping = true }
                }

                headline(report)
                tiles(report)
                creditsBlock(report)
                LTBlockGrid(blocks: [AnyView(investmentsBlock(report)), AnyView(checksBlock(report))])
                table(report)
            }
        }
        .sheet(isPresented: $showMapping) {
            TaxCategoryMappingView()
        }
    }

    // MARK: - Réponse

    @ViewBuilder
    private func headline(_ report: TaxReport) -> some View {
        if report.lines.isEmpty {
            ReportHeadline(
                question: "Qu’est-ce que je dois déclarer, et combien je récupère ?",
                answer: "Reliez vos catégories (dons, garde d’enfant, emploi à domicile…) aux cases de la déclaration pour repérer vos réductions d’impôt.",
                detail: "Bouton « Relier les catégories… » en haut à droite. Une fois fait, le rapport se remplit tout seul chaque année.",
                tone: .info
            )
        } else {
            ReportHeadline(
                question: "Qu’est-ce que je dois déclarer, et combien je récupère ?",
                answer: "Environ \(format.money(report.advantage)) de réductions et crédits d’impôt repérés dans vos dépenses de \(String(year)).",
                detail: "À reporter au printemps \(String(year + 1)) sur votre déclaration. Les montants viennent de vos catégories : vérifiez-les avec vos reçus et attestations.",
                tone: .good
            )
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: TaxReport) -> some View {
        let checks = report.suggestions.count + report.lines.filter(\.isOverCap).count
        return ReportTiles {
            StatTile(title: "Réductions et crédits d’impôt", value: "≈ \(format.money(report.advantage))", valueColor: .green, detail: "\(report.lines.count) case\(report.lines.count > 1 ? "s" : "") à remplir")
            StatTile(
                title: "Versements PER déductibles",
                value: format.money(report.perDeductions),
                valueColor: report.perDeductions > 0 ? .green : .primary,
                detail: report.perSaving.map { "≈ \(format.money($0)) d’impôt en moins" } ?? "case 6NS"
            )
            StatTile(title: "Revenus de placements", value: format.money(report.realizedGains + report.dividends), detail: "plus-values et dividendes")
            StatTile(title: "À vérifier", value: "\(checks)", valueColor: checks > 0 ? .orange : .green, detail: "catégories, plafonds")
        }
    }

    // MARK: - Réductions et crédits

    private func creditsBlock(_ report: TaxReport) -> some View {
        let largest = PlanFormat.double(report.lines.map(\.advantage).max() ?? 1)
        return PlanBlock(title: "Ce qui vous fait payer moins d’impôt", subtitle: "réductions et crédits d’impôt") {
            if report.lines.isEmpty {
                PlanNote("Aucune catégorie reliée à une case de la déclaration pour l’instant.")
            } else {
                VStack(spacing: 10) {
                    ForEach(report.lines) { line in
                        LTBarRow(
                            label: line.taxCase.title,
                            detail: "case \(line.taxCase.rawValue) · \(line.categories.joined(separator: ", "))",
                            bar: LTBar(fraction: PlanFormat.double(line.advantage) / max(largest, 1), color: .green),
                            value: "≈ \(format.money(line.advantage))",
                            valueColor: .green,
                            extra: "\(format.money(line.spent)) · \(Int(NSDecimalNumber(decimal: line.taxCase.rate * 100).doubleValue)) %",
                            labelWidth: 260
                        )
                    }
                }
            }
            PlanNote("Un crédit d’impôt vous est remboursé même si vous ne payez pas d’impôt ; une réduction ne fait que diminuer l’impôt dû.")
        }
    }

    // MARK: - Placements et PER

    private func investmentsBlock(_ report: TaxReport) -> some View {
        PlanBlock(title: "Placements et épargne retraite") {
            VStack(spacing: 10) {
                ExplanationRow(label: "Versements PER", detail: "case 6NS · déduits de votre revenu imposable", value: format.money(report.perDeductions), color: report.perDeductions > 0 ? .green : .primary)
                Divider()
                ExplanationRow(label: "Plus-values des comptes-titres", detail: report.realizedGains >= 0 ? "case 3VG · imposées à 31,4 %" : "case 3VH · moins-values reportables 10 ans", value: format.signed(report.realizedGains))
                Divider()
                ExplanationRow(label: "Dividendes des comptes-titres", detail: "case 2DC · acompte déjà prélevé par la banque", value: format.money(report.dividends))
                Divider()
                ExplanationRow(label: "Intérêts des livrets réglementés", detail: "Livret A, LDDS, LEP : exonérés, rien à déclarer", value: "0 €", color: .secondary)
            }
            PlanNote("La banque envoie un imprimé fiscal unique (IFU) en début d’année : comparez-le avec ces montants, souvent déjà pré-remplis.")
        }
    }

    // MARK: - À vérifier

    private func checksBlock(_ report: TaxReport) -> some View {
        PlanBlock(title: "À vérifier avant de déclarer") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(report.lines.filter(\.isOverCap)) { line in
                    LTNoticeRow(
                        title: "\(line.taxCase.title) : plafond dépassé",
                        detail: "seuls \(format.money(line.retained)) sont retenus (plafond simple, il peut être majoré selon votre situation)",
                        value: format.money(line.spent),
                        color: .orange
                    )
                }
                ForEach(report.suggestions) { suggestion in
                    LTNoticeRow(
                        title: "Catégorie « \(suggestion.category.name) »",
                        detail: "relève peut-être de la case \(suggestion.taxCase.rawValue) (\(suggestion.taxCase.title))",
                        color: .orange,
                        action: ("Relier", { Task { await taxMappingController.set(suggestion.taxCase, for: suggestion.category.id) } })
                    )
                }
                LTNoticeRow(
                    title: "Montants pré-remplis par l’administration",
                    detail: "emploi à domicile via CESU+, revenus de placements : vérifiez les cases déjà remplies",
                    color: .gray
                )
            }
        }
    }

    // MARK: - Tableau

    private func table(_ report: TaxReport) -> some View {
        var rows = report.lines.map { line in
            ReportRow(id: line.id, cells: [
                ReportCell(text: line.taxCase.rawValue, isAmount: false),
                ReportCell(text: line.taxCase.title, isAmount: false),
                ReportCell(text: "\(line.count)", color: .secondary, isAmount: false),
                ReportCell(text: format.money(line.spent)),
                ReportCell(text: format.money(line.advantage), color: .green)
            ])
        }
        if report.perDeductions > 0 {
            rows.append(ReportRow(id: "6NS", cells: [
                ReportCell(text: "6NS", isAmount: false),
                ReportCell(text: "Versements PER", isAmount: false),
                ReportCell(text: "", isAmount: false),
                ReportCell(text: format.money(report.perDeductions)),
                ReportCell(text: report.perSaving.map { format.money($0) } ?? "—", color: .green)
            ]))
        }
        return ReportTable(
            columns: ["Case", "Libellé", "Opérations", "Montant", "Avantage estimé"],
            rows: rows,
            footnote: "Estimation indicative, plafonds simplifiés : seule la déclaration fait foi."
        )
    }
}

/// Relier les catégories de dépenses aux cases de la déclaration
struct TaxCategoryMappingView: View {
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var taxMappingController: TaxMappingController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Relier les catégories", subtitle: "Chaque dépense de ces catégories compte pour la case choisie. Une sous-catégorie hérite de sa catégorie parente.")

            Form {
                Section {
                    ForEach(TaxCase.allCases) { taxCase in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(taxCase.rawValue) · \(taxCase.title)").fontWeight(.semibold)
                            Text("\(taxCase.examples) · \(taxCase.ruleText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Cases disponibles")
                }

                Section("Catégories de dépenses") {
                    ForEach(categoriesController.categories.filter { !$0.isIncome }.sorted { categoriesController.getCategoryPath(for: $0.id) < categoriesController.getCategoryPath(for: $1.id) }) { category in
                        Picker(categoriesController.getCategoryPath(for: category.id), selection: Binding(
                            get: { taxMappingController.mapping[category.id] },
                            set: { newValue in Task { await taxMappingController.set(newValue, for: category.id) } }
                        )) {
                            Text("—").tag(TaxCase?.none)
                            ForEach(TaxCase.allCases) { taxCase in
                                Text("\(taxCase.rawValue) · \(taxCase.title)").tag(TaxCase?.some(taxCase))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Terminé") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: 640)
        .sheetBackground()
    }
}
