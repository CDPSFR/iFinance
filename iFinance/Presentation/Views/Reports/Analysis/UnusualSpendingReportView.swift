import SwiftUI

/// Rapport « Dépenses inhabituelles » : postes et opérations qui sortent des habitudes du mois choisi.
struct UnusualSpendingReportView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Mois affiché : par défaut le mois en cours, pour repérer un doublon ou un gros achat sans attendre
    @State private var month: Date = {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    /// Opérations marquées « c'est normal » (mémorisées sur cet appareil)
    @AppStorage("dismissedUnusualTransactions") private var dismissedStorage = ""

    private var dismissed: Set<UUID> {
        Set(dismissedStorage.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func dismiss(_ id: UUID) {
        var ids = dismissed
        ids.insert(id)
        dismissedStorage = ids.map(\.uuidString).joined(separator: ",")
    }

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

    /// 12 derniers mois, le mois en cours compris
    private var months: [Date] {
        let calendar = Calendar.current
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }

    var body: some View {
        let report = builder.unusual(month: month, dismissed: dismissed)

        ScrollView {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                Picker("Mois", selection: $month) {
                    ForEach(months, id: \.self) { date in
                        Text(date.formatted(.dateTime.month(.wide).year()).capitalized).tag(date)
                    }
                }
                .fixedSize()

                if report.total == 0 {
                    ReportEmptyState(systemImage: "sparkle.magnifyingglass", message: "Aucune dépense ce mois-ci sur les comptes courants.")
                } else {
                    tiles(report)
                    categoriesBlock(report)
                    LTBlockGrid(blocks: [AnyView(itemsBlock(report)), AnyView(methodBlock)])
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ report: UnusualReport) -> some View {
        let delta = report.total - report.usualTotal
        return ReportTiles {
            StatTile(title: "Dépenses du mois", value: format.money(report.total), detail: "comptes courants")
            StatTile(title: "D’habitude", value: format.money(report.usualTotal), detail: "moyenne des 6 mois précédents")
            StatTile(
                title: "Écart",
                value: format.signed(delta),
                valueColor: delta > 0 ? .red : .green,
                detail: PlanFormat.ratio(delta, report.usualTotal).map { format.percent($0, signed: true) }
            )
            StatTile(
                title: "Points relevés",
                value: "\(report.unusualCategories.count + report.items.count)",
                valueColor: report.unusualCategories.count + report.items.count > 0 ? .orange : .green,
                detail: "postes et opérations"
            )
        }
    }

    // MARK: - Par poste

    private func categoriesBlock(_ report: UnusualReport) -> some View {
        let rows = report.categories.filter { $0.amount > 0 || $0.usual >= 50 }.prefix(10)
        let largest = PlanFormat.double(rows.map { max($0.amount, $0.usual) }.max() ?? 1)

        return PlanBlock(title: "Par poste, comparé à d’habitude", subtitle: "gris : montant habituel · couleur : ce mois-ci") {
            VStack(spacing: 10) {
                ForEach(Array(rows)) { row in
                    let usual = PlanFormat.double(min(row.amount, row.usual)) / max(largest, 1)
                    let extra = PlanFormat.double(max(row.amount - row.usual, 0)) / max(largest, 1)
                    LTBarRow(
                        label: row.name,
                        detail: row.isUnusual ? "inhabituel" : nil,
                        bar: LTBar(segments: [
                            .init(fraction: usual, color: .gray.opacity(0.45)),
                            .init(fraction: extra, color: row.isUnusual ? .red : .accentColor)
                        ]),
                        value: format.money(row.amount),
                        valueColor: row.isUnusual ? .red : .primary,
                        extra: "d’habitude \(format.money(row.usual))",
                        labelWidth: 180,
                        isEmphasized: row.isUnusual
                    )
                }
            }
        }
    }

    // MARK: - Opérations à regarder

    private func itemsBlock(_ report: UnusualReport) -> some View {
        PlanBlock(title: "À regarder") {
            if report.items.isEmpty {
                PlanNote("Aucune opération particulière : pas de nouveau bénéficiaire important, de montant inhabituel ni de doublon.")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.items) { item in
                        let category = item.transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) }
                        LTNoticeRow(
                            title: item.title,
                            detail: [category, item.detail].compactMap { $0 }.joined(separator: " · "),
                            value: format.cents(abs(item.transaction.amount)),
                            color: item.kind == .duplicate ? .red : .orange,
                            action: ("C’est normal", { dismiss(item.transaction.id) })
                        )
                    }
                }
            }
        }
    }

    // MARK: - Méthode

    private var methodBlock: some View {
        PlanBlock(title: "Comment on repère") {
            VStack(spacing: 10) {
                ExplanationRow(label: "Un poste est signalé", detail: "quand il dépasse 1,5 fois sa moyenne des 6 derniers mois, et d’au moins 50 €", value: "× 1,5")
                Divider()
                ExplanationRow(label: "Une opération est signalée", detail: "nouveau bénéficiaire de plus de 100 €, montant 3 fois plus élevé que d’habitude, ou même montant payé deux fois en une semaine", value: "")
                Divider()
                ExplanationRow(label: "Vous décidez", detail: "« C’est normal » retire l’opération de cette liste", value: "")
            }
        }
    }
}
