import SwiftUI
import Charts

/// Rapport « Comparaison de périodes » : dépenses (ou revenus) par catégorie principale,
/// d'une période à l'autre. La période se choisit dans le rapport lui-même ; le filtre
/// de compte de la barre d'outils s'applique.
struct PeriodComparisonChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    enum Unit: String, CaseIterable, Identifiable {
        case month = "Mois"
        case quarter = "Trimestre"
        case year = "Année"

        var id: String { rawValue }
        var months: Int {
            switch self {
            case .month: return 1
            case .quarter: return 3
            case .year: return 12
            }
        }
    }

    enum Reference: String, CaseIterable, Identifiable {
        case previous = "Période précédente"
        case lastYear = "Même période, un an avant"

        var id: String { rawValue }
    }

    struct Line: Identifiable {
        let id: String
        let name: String
        let current: Decimal
        let reference: Decimal

        var gap: Decimal { current - reference }
    }

    @State private var unit: Unit = .month
    @State private var reference: Reference = .previous
    @State private var flow: ReportFlow = .expense
    /// Décalage de la période étudiée, en nombre de périodes (0 = période en cours)
    @State private var offset = 0

    var body: some View {
        let current = period(offset: offset)
        let compared = referencePeriod(for: current)
        let lines = self.lines(current: current, reference: compared)

        ScrollView {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                controls(current: current, compared: compared)

                if lines.isEmpty {
                    ReportEmptyState(
                        systemImage: "arrow.left.arrow.right",
                        message: "Aucune transaction en \(flow.plural) sur ces deux périodes."
                    )
                    .frame(minHeight: 320)
                } else {
                    tiles(lines, current: current, compared: compared)
                    chartBlock(lines, current: current, compared: compared)
                    tableBlock(lines, current: current, compared: compared)
                }
            }
        }
    }

    // MARK: - Réglages du rapport

    /// Réglages sur deux lignes : la zone du rapport (fenêtre moins la liste) peut être étroite
    private func controls(current: DateInterval, compared: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Sens", selection: $flow) {
                    Text("Dépenses").tag(ReportFlow.expense)
                    Text("Revenus").tag(ReportFlow.income)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Picker("Durée", selection: $unit) {
                    ForEach(Unit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: unit) { _, _ in offset = 0 }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                navigation(current)

                Spacer(minLength: 0)

                Picker("Comparer à", selection: $reference) {
                    ForEach(Reference.allCases) { reference in
                        Text(reference.rawValue).tag(reference)
                    }
                }
                .fixedSize()
                // Sur une année, « un an avant » et « période précédente » désignent la même chose
                .disabled(unit == .year)
            }
        }
    }

    private func navigation(_ current: DateInterval) -> some View {
        HStack(spacing: 4) {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Période précédente")

            Text(label(current))
                .fontWeight(.semibold)
                .frame(minWidth: 130)

            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(offset >= 0)
            .help("Période suivante")
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ lines: [Line], current: DateInterval, compared: DateInterval) -> some View {
        let totalCurrent = lines.reduce(Decimal(0)) { $0 + $1.current }
        let totalReference = lines.reduce(Decimal(0)) { $0 + $1.reference }
        let gap = totalCurrent - totalReference
        let rise = lines.max { $0.gap < $1.gap }
        let drop = lines.min { $0.gap < $1.gap }
        // Une hausse des dépenses est défavorable, une hausse des revenus favorable
        let gapColor: Color = gap == 0 ? .primary : ((gap > 0) == (flow == .income) ? .green : .red)

        return ReportTiles {
            StatTile(title: "\(flow.title), \(label(current))", value: money(totalCurrent), detail: "période étudiée")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "\(flow.title), \(label(compared))", value: money(totalReference), detail: "période de référence")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "Écart", value: signed(gap), valueColor: gapColor, detail: percentChange(from: totalReference, to: totalCurrent))
                .privacyBlur(hidden: appSettings.hideAmounts)

            if let rise, rise.gap > 0 {
                StatTile(title: "Plus forte hausse", value: rise.name, detail: signed(rise.gap))
            } else if let drop, drop.gap < 0 {
                StatTile(title: "Plus forte baisse", value: drop.name, detail: signed(drop.gap))
            } else {
                StatTile(title: "Plus forte hausse", value: "—", detail: "aucun écart")
            }
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ lines: [Line], current: DateInterval, compared: DateInterval) -> some View {
        let currentLabel = label(current)
        let referenceLabel = label(compared)
        let shown = Array(lines.prefix(12))

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("\(flow.title) par catégorie, d'une période à l'autre")

            Chart {
                ForEach(shown) { line in
                    BarMark(
                        x: .value("Montant", double(line.current)),
                        y: .value("Catégorie", line.name)
                    )
                    .foregroundStyle(by: .value("Période", currentLabel))
                    .position(by: .value("Période", currentLabel))

                    BarMark(
                        x: .value("Montant", double(line.reference)),
                        y: .value("Catégorie", line.name)
                    )
                    .foregroundStyle(by: .value("Période", referenceLabel))
                    .position(by: .value("Période", referenceLabel))
                }
            }
            .chartForegroundStyleScale([
                currentLabel: Color.accentColor,
                referenceLabel: Color.secondary.opacity(0.45)
            ])
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(shown.count) * 38 + 50)
            .privacyBlur(hidden: appSettings.hideAmounts)

            if lines.count > shown.count {
                Text("Les \(shown.count) premières catégories sont affichées ; le tableau les liste toutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    // MARK: - Tableau

    private func tableBlock(_ lines: [Line], current: DateInterval, compared: DateInterval) -> some View {
        ReportTable(
            columns: ["Catégorie", label(current), label(compared), "Écart", "Écart %"],
            rows: lines.map { line in
                let color: Color = line.gap == 0 ? .secondary : ((line.gap > 0) == (flow == .income) ? .green : .red)
                return ReportRow(id: line.id, cells: [
                    ReportCell(text: line.name),
                    ReportCell(text: money(line.current)),
                    ReportCell(text: money(line.reference), color: .secondary),
                    ReportCell(text: signed(line.gap), color: color),
                    ReportCell(text: percentChange(from: line.reference, to: line.current) ?? "nouveau", color: color)
                ])
            },
            footnote: "Les sous-catégories sont regroupées dans leur catégorie principale. Comme dans les rapports par catégorie, les transactions sans catégorie et les transferts entre comptes ne sont pas comptés."
        )
    }

    // MARK: - Périodes

    /// Période de `unit.months` mois, décalée de `offset` périodes par rapport à la période en cours
    private func period(offset: Int) -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month], from: now)

        switch unit {
        case .month:
            break
        case .quarter:
            let month = components.month ?? 1
            components.month = ((month - 1) / 3) * 3 + 1
        case .year:
            components.month = 1
        }

        let currentStart = calendar.date(from: components) ?? now
        let start = calendar.date(byAdding: .month, value: offset * unit.months, to: currentStart) ?? currentStart
        let end = calendar.date(byAdding: .month, value: unit.months, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func referencePeriod(for current: DateInterval) -> DateInterval {
        let calendar = Calendar.current
        let shift = (reference == .lastYear || unit == .year) ? -12 : -unit.months
        let start = calendar.date(byAdding: .month, value: shift, to: current.start) ?? current.start
        let end = calendar.date(byAdding: .month, value: unit.months, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func label(_ period: DateInterval) -> String {
        let calendar = Calendar.current
        switch unit {
        case .month:
            return period.start.formatted(.dateTime.month(.abbreviated).year())
        case .quarter:
            let quarter = (calendar.component(.month, from: period.start) - 1) / 3 + 1
            return "T\(quarter) \(calendar.component(.year, from: period.start))"
        case .year:
            return "\(calendar.component(.year, from: period.start))"
        }
    }

    // MARK: - Données

    private func lines(current: DateInterval, reference: DateInterval) -> [Line] {
        let accountIDs: Set<UUID>
        if let accountID = transactionsController.filters.accountID {
            accountIDs = [accountID]
        } else {
            accountIDs = Set(accountsController.activeAccounts.filter { $0.countsInCashFlow }.map { $0.id })
        }

        let type = flow.transactionType
        var currentTotals: [String: Decimal] = [:]
        var referenceTotals: [String: Decimal] = [:]
        var names: [String: String] = [:]

        for transaction in transactionsController.allTransactions {
            // Même périmètre que « Dépenses par catégorie » : transactions catégorisées seulement
            guard transaction.type == type,
                  transaction.status != .skipped,
                  transaction.categoryID != nil,
                  accountIDs.contains(transaction.accountID) else { continue }

            let inCurrent = transaction.date >= current.start && transaction.date < current.end
            let inReference = transaction.date >= reference.start && transaction.date < reference.end
            guard inCurrent || inReference else { continue }

            guard let root = rootCategory(of: transaction.categoryID) else { continue }
            let key = root.id.uuidString
            names[key] = root.name

            if inCurrent { currentTotals[key, default: 0] += abs(transaction.amount) }
            if inReference { referenceTotals[key, default: 0] += abs(transaction.amount) }
        }

        return names
            .map { key, name in
                Line(id: key, name: name, current: currentTotals[key] ?? 0, reference: referenceTotals[key] ?? 0)
            }
            .sorted { max($0.current, $0.reference) > max($1.current, $1.reference) }
    }

    /// Catégorie principale d'une catégorie (elle-même si elle n'a pas de parent)
    private func rootCategory(of categoryID: UUID?) -> Category? {
        guard let categoryID, var category = categoriesController.getCategory(id: categoryID) else { return nil }
        var depth = 0
        while let parentID = category.parentID, let parent = categoriesController.getCategory(id: parentID), depth < 10 {
            category = parent
            depth += 1
        }
        return category
    }

    // MARK: - Format

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func signed(_ amount: Decimal) -> String {
        (amount > 0 ? "+" : "") + money(amount)
    }

    private func double(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    private func percentChange(from start: Decimal, to end: Decimal) -> String? {
        guard start > 0 else { return nil }
        let ratio = double(end - start) / double(start)
        return (ratio > 0 ? "+" : "") + ratio.formatted(.percent.precision(.fractionLength(0)))
    }
}
