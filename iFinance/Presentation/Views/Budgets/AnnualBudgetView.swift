import SwiftUI

/// Budget annuel : une ligne par catégorie, une colonne par mois, avec le réel et le prévu.
/// Les montants prévus sont saisis dans la grille (clic sur une case).
struct AnnualBudgetView: View {
    @EnvironmentObject var annualBudgetController: AnnualBudgetController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var appSettings: AppSettings

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var expanded: Set<UUID> = []
    @State private var editing: AnnualBudgetKey?
    @State private var editAmount: Decimal = 0

    // MARK: - Modèle d'affichage

    enum Kind {
        case income, expense, balance
    }

    /// Ligne de la grille : douze valeurs prévues et douze valeurs réelles
    struct Line: Identifiable {
        let id: String
        let name: String
        let kind: Kind
        var categoryID: UUID? = nil
        var isChild = false
        var hasChildren = false
        var isBold = false
        /// Vrai si le prévu se saisit sur cette ligne (catégorie sans sous-catégorie)
        var isEditable = false
        var planned: [Decimal]
        var actual: [Decimal]
    }

    private static let zeros = [Decimal](repeating: 0, count: 12)
    private static let labelWidth: CGFloat = 170
    private static let yearWidth: CGFloat = 104
    private static let monthMinWidth: CGFloat = 58

    var body: some View {
        let actuals = actualsByCategory
        let incomeLines = lines(for: categoriesController.incomeCategories, kind: .income, actuals: actuals)
        let expenseLines = lines(for: categoriesController.expenseCategories, kind: .expense, actuals: actuals)
        let summary = summaryLines(income: incomeLines, expense: expenseLines)

        VStack(spacing: 0) {
            summaryHeader(summary)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        sectionTitle("Synthèse")
                        ForEach(summary) { row($0) }

                        sectionTitle("Catégories de revenus")
                        if incomeLines.isEmpty { emptyRow("Aucune catégorie de revenus") }
                        ForEach(incomeLines) { row($0) }

                        sectionTitle("Catégories de dépenses")
                        if expenseLines.isEmpty { emptyRow("Aucune catégorie de dépenses") }
                        ForEach(expenseLines) { row($0) }
                    } header: {
                        monthsHeader
                    }
                }
                .padding(.bottom, 12)
            }

            TableStatusBar(items: [
                "Cliquez sur une case pour saisir le montant prévu",
                "Réel sur les comptes inclus dans les rapports, hors transferts"
            ])
        }
        .frame(minWidth: Self.labelWidth + Self.yearWidth + 12 * Self.monthMinWidth)
        .navigationTitle("Budget annuel")
        .navigationSubtitle(String(year))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    year -= 1
                } label: {
                    Label("Année précédente", systemImage: "chevron.left")
                }
                .help("Année précédente")

                Button {
                    year = Calendar.current.component(.year, from: Date())
                } label: {
                    Text(String(year))
                        .monospacedDigit()
                }
                .help("Revenir à l'année en cours")

                Button {
                    year += 1
                } label: {
                    Label("Année suivante", systemImage: "chevron.right")
                }
                .help("Année suivante")
            }
        }
        .task(id: loadKey) {
            if let bookID = booksController.currentBook?.id {
                await annualBudgetController.load(bookID: bookID, year: year)
            }
        }
    }

    private var loadKey: String {
        "\(booksController.currentBook?.id.uuidString ?? "-")-\(year)"
    }

    // MARK: - En-tête : grands chiffres

    private func summaryHeader(_ summary: [Line]) -> some View {
        let months = elapsedMonths
        let income = summary[0], expense = summary[1], balance = summary[2]
        // Écart sur les mois écoulés : économies sur les dépenses + surplus de revenus
        let gap = months.reduce(Decimal(0)) { total, index in
            total + (expense.planned[index] - expense.actual[index]) + (income.actual[index] - income.planned[index])
        }

        return HStack(alignment: .top, spacing: 40) {
            figure("Revenus", actual: sum(income.actual), planned: sum(income.planned))
            figure("Dépenses", actual: sum(expense.actual), planned: sum(expense.planned))
            figure("Solde", actual: sum(balance.actual), planned: sum(balance.planned))

            VStack(alignment: .leading, spacing: 2) {
                Text("Écart au budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text((gap >= 0 ? "+" : "") + formatted(gap))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(gap >= 0 ? Color.green : Color.red)
                    .privacyBlur(hidden: appSettings.hideAmounts)
                Text(months.isEmpty ? "Aucun mois écoulé" : "Sur les mois écoulés")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func figure(_ title: String, actual: Decimal, planned: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatted(actual))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .privacyBlur(hidden: appSettings.hideAmounts)
            Text("Prévu \(formatted(planned))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Grille

    private var monthsHeader: some View {
        let symbols = Calendar.current.shortStandaloneMonthSymbols

        return HStack(spacing: 0) {
            Text("Catégorie")
                .frame(width: Self.labelWidth, alignment: .leading)
                .padding(.leading, 16)
            Text("Année")
                .frame(width: Self.yearWidth)
            ForEach(0..<12, id: \.self) { index in
                Text(symbols[index].capitalized)
                    .fontWeight(index == currentMonthIndex ? .semibold : .regular)
                    .foregroundStyle(index == currentMonthIndex ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.trailing, 12)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.vertical, 8)
    }

    private func row(_ line: Line) -> some View {
        HStack(spacing: 0) {
            label(line)
                .frame(width: Self.labelWidth, alignment: .leading)
                .padding(.leading, 16)

            // Total de l'année : le prévu couvre les douze mois, le réel les mois écoulés
            cell(
                actual: sum(line.actual),
                planned: sum(line.planned),
                plannedSoFar: elapsedMonths.reduce(Decimal(0)) { $0 + line.planned[$1] },
                kind: line.kind,
                isFuture: elapsedMonths.isEmpty,
                isBold: true
            )
            .frame(width: Self.yearWidth)

            ForEach(0..<12, id: \.self) { index in
                monthCell(line, index: index)
                    .frame(maxWidth: .infinity)
                    .background(index == currentMonthIndex ? Color.primary.opacity(0.04) : Color.clear)
            }
        }
        .padding(.trailing, 12)
        .privacyBlur(hidden: appSettings.hideAmounts)
    }

    @ViewBuilder
    private func label(_ line: Line) -> some View {
        if line.hasChildren, let id = line.categoryID {
            Button {
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded.contains(id) ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(line.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(line.name)
                .fontWeight(line.isBold ? .semibold : .regular)
                .lineLimit(1)
                .padding(.leading, line.isChild ? 30 : 15)
        }
    }

    @ViewBuilder
    private func monthCell(_ line: Line, index: Int) -> some View {
        let content = cell(
            actual: line.actual[index],
            planned: line.planned[index],
            plannedSoFar: line.planned[index],
            kind: line.kind,
            isFuture: !elapsedMonths.contains(index),
            isBold: line.isBold
        )

        if line.isEditable, let categoryID = line.categoryID {
            let key = AnnualBudgetKey(categoryID: categoryID, month: index + 1)
            Button {
                editAmount = line.planned[index]
                editing = key
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Modifier le montant prévu")
            .popover(isPresented: Binding(
                get: { editing == key },
                set: { if !$0, editing == key { editing = nil } }
            ), arrowEdge: .bottom) {
                editor(for: key, name: line.name)
            }
        } else {
            content
        }
    }

    /// Case « réel / prévu » avec sa barre de progression
    private func cell(actual: Decimal, planned: Decimal, plannedSoFar: Decimal, kind: Kind, isFuture: Bool, isBold: Bool) -> some View {
        let hasPlan = planned != 0
        let isOnTrack = kind == .expense ? actual <= plannedSoFar : actual >= plannedSoFar
        let color: Color = isFuture || !hasPlan ? .clear : (isOnTrack ? .green : .red)
        let ratio: Double = {
            guard !isFuture, hasPlan else { return 0 }
            // Dépenses : part du budget consommée. Revenus et solde : barre pleine, colorée selon l'atteinte.
            guard kind == .expense else { return 1 }
            let value = NSDecimalNumber(decimal: actual / planned).doubleValue
            return min(max(value, 0), 1)
        }()

        return VStack(spacing: 2) {
            Text(isFuture ? "—" : formatted(actual))
                .font(.callout)
                .fontWeight(isBold ? .semibold : .regular)
                .foregroundStyle(isFuture ? Color.secondary : (hasPlan && !isOnTrack ? Color.red : Color.primary))

            Text(hasPlan ? formatted(planned) : "·")
                .font(.caption)
                .foregroundStyle(.secondary)

            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * ratio)
                    }
                }
                .padding(.horizontal, 5)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.vertical, 5)
    }

    // MARK: - Saisie du prévu

    private func editor(for key: AnnualBudgetKey, name: String) -> some View {
        let monthName = Calendar.current.standaloneMonthSymbols[key.month - 1]

        return VStack(alignment: .leading, spacing: 10) {
            Text("\(name) · \(monthName) \(String(year))")
                .font(.headline)

            TextField("Montant prévu", value: $editAmount, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { save(key, allMonths: false) }

            HStack {
                Button("Tous les mois") { save(key, allMonths: true) }
                    .help("Appliquer ce montant aux douze mois de l'année")
                Spacer()
                Button("OK") { save(key, allMonths: false) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private func save(_ key: AnnualBudgetKey, allMonths: Bool) {
        let amount = editAmount
        editing = nil
        Task {
            if allMonths {
                await annualBudgetController.setPlannedForAllMonths(amount, for: key.categoryID)
            } else {
                await annualBudgetController.setPlanned(amount, for: key.categoryID, month: key.month)
            }
        }
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    /// Index (0 à 11) du mois en cours, si l'année affichée est l'année en cours
    private var currentMonthIndex: Int? {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return now.year == year ? (now.month ?? 1) - 1 : nil
    }

    /// Index des mois écoulés ou en cours de l'année affichée
    private var elapsedMonths: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        if year < currentYear { return Array(0..<12) }
        if year > currentYear { return [] }
        return Array(0...(currentMonthIndex ?? 11))
    }

    /// Réel de l'année par catégorie et par mois, signé selon le sens de la catégorie
    /// (dépenses nettes des remboursements, revenus nets). La clé nil regroupe le non catégorisé.
    private var actualsByCategory: [UUID?: [Decimal]] {
        let calendar = Calendar.current
        let accountIDs = accountsController.cashFlowAccountIDs
        var result: [UUID?: [Decimal]] = [:]

        for transaction in transactionsController.allTransactions {
            guard transaction.type != .transfer,
                  transaction.status != .skipped,
                  accountIDs.contains(transaction.accountID) else { continue }

            let components = calendar.dateComponents([.year, .month], from: transaction.date)
            guard components.year == year, let month = components.month else { continue }

            let category = transaction.categoryID.flatMap { categoriesController.getCategory(id: $0) }
            let isIncome = category?.isIncome ?? (transaction.type == .credit)
            let value = isIncome ? transaction.signedAmount : -transaction.signedAmount
            // Le non catégorisé est séparé entre revenus et dépenses par deux clés distinctes
            let key: UUID? = category?.id ?? (isIncome ? Self.uncategorizedIncomeID : nil)

            result[key, default: Self.zeros][month - 1] += value
        }
        return result
    }

    /// Identifiant fictif pour regrouper les revenus sans catégorie
    private static let uncategorizedIncomeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")

    private func plannedValues(for categoryID: UUID) -> [Decimal] {
        (1...12).map { annualBudgetController.amount(for: categoryID, month: $0) }
    }

    /// Lignes d'une section : catégories racines (somme de leurs sous-catégories),
    /// sous-catégories si dépliées, puis le non catégorisé s'il y en a.
    private func lines(for roots: [Category], kind: Kind, actuals: [UUID?: [Decimal]]) -> [Line] {
        var result: [Line] = []
        let sortedRoots = roots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        for root in sortedRoots {
            let children = categoriesController.getSubcategories(for: root.id)
            var planned = plannedValues(for: root.id)
            var actual = actuals[root.id] ?? Self.zeros
            var childLines: [Line] = []

            for child in children {
                let childPlanned = plannedValues(for: child.id)
                let childActual = actuals[child.id] ?? Self.zeros
                planned = add(planned, childPlanned)
                actual = add(actual, childActual)
                childLines.append(Line(
                    id: child.id.uuidString,
                    name: child.name,
                    kind: kind,
                    categoryID: child.id,
                    isChild: true,
                    isEditable: true,
                    planned: childPlanned,
                    actual: childActual
                ))
            }

            result.append(Line(
                id: root.id.uuidString,
                name: root.name,
                kind: kind,
                categoryID: root.id,
                hasChildren: !children.isEmpty,
                isEditable: children.isEmpty,
                planned: planned,
                actual: actual
            ))
            if expanded.contains(root.id) {
                result.append(contentsOf: childLines)
            }
        }

        let uncategorizedKey: UUID? = kind == .income ? Self.uncategorizedIncomeID : nil
        if let uncategorized = actuals[uncategorizedKey], uncategorized.contains(where: { $0 != 0 }) {
            result.append(Line(
                id: "uncategorized-\(kind)",
                name: "Sans catégorie",
                kind: kind,
                planned: Self.zeros,
                actual: uncategorized
            ))
        }
        return result
    }

    /// Revenus, Dépenses et Solde : sommes des lignes de premier niveau
    private func summaryLines(income: [Line], expense: [Line]) -> [Line] {
        func total(_ lines: [Line], _ values: (Line) -> [Decimal]) -> [Decimal] {
            lines.filter { !$0.isChild }.reduce(Self.zeros) { add($0, values($1)) }
        }
        let incomePlanned = total(income) { $0.planned }
        let incomeActual = total(income) { $0.actual }
        let expensePlanned = total(expense) { $0.planned }
        let expenseActual = total(expense) { $0.actual }

        return [
            Line(id: "summary-income", name: "Revenus", kind: .income, isBold: true, planned: incomePlanned, actual: incomeActual),
            Line(id: "summary-expense", name: "Dépenses", kind: .expense, isBold: true, planned: expensePlanned, actual: expenseActual),
            Line(
                id: "summary-balance",
                name: "Solde",
                kind: .balance,
                isBold: true,
                planned: zip(incomePlanned, expensePlanned).map { $0 - $1 },
                actual: zip(incomeActual, expenseActual).map { $0 - $1 }
            )
        ]
    }

    // MARK: - Helpers

    private func add(_ lhs: [Decimal], _ rhs: [Decimal]) -> [Decimal] {
        zip(lhs, rhs).map { $0 + $1 }
    }

    private func sum(_ values: [Decimal]) -> Decimal {
        values.reduce(Decimal(0), +)
    }

    /// Montant sans décimales, pour tenir dans les colonnes des mois
    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}
