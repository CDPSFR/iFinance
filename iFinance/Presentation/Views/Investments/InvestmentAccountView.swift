import SwiftUI

struct InvestmentAccountView: View {
    let accountID: UUID

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var quoteService: QuoteService
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedTab: Tab = .positions
    @State private var activeSheet: InvestmentSheet?
    @State private var chartRange: InvestmentValueChart.Range = .oneYear
    @State private var allocationMode: InvestmentAllocationChart.Mode = .position
    @State private var priceHistory: [UUID: [PositionPrice]] = [:]
    @AppStorage("showInvestmentCharts") private var showCharts = true

    enum Tab: String, CaseIterable, Identifiable {
        case positions = "Positions"
        case operations = "Opérations"
        case cash = "Mouvements d'espèces"

        var id: String { rawValue }
    }

    var body: some View {
        if let account = accountsController.getAccount(id: accountID) {
            content(for: account)
                .task(id: accountID) {
                    await investmentsController.reload(accountID: accountID)
                }
                .sheet(item: $activeSheet) { sheet in
                    sheetView(sheet, account: account)
                }
        } else {
            ContentUnavailableView("Compte introuvable", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for account: Account) -> some View {
        let summary = self.summary(for: account)

        Group {
            if selectedTab == .cash {
                // Les espèces hébergent l'en-tête du compte : l'inspecteur occupe toute la hauteur de la page
                TransactionListView(pageHeader: AnyView(accountHeader(for: account, summary: summary)))
            } else {
                VStack(spacing: 0) {
                    accountHeader(for: account, summary: summary)

                    Group {
                        switch selectedTab {
                        case .positions:
                            PositionListView(account: account, activeSheet: $activeSheet)
                        case .operations:
                            InvestmentOperationListView(account: account, activeSheet: $activeSheet)
                        case .cash:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
        .task(id: historyKey) {
            loadPriceHistory()
        }
        .toolbar {
            // Mise à jour des cours en ligne, seulement si elle est activée dans les réglages
            if quoteService.isEnabled {
                ToolbarItem(placement: .automatic) {
                    QuoteUpdateToolbarButton(accountID: account.id)
                }
            }

            // Ajout d'une opération ou d'une position, dans l'en-tête de la fenêtre
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        activeSheet = .newOperation
                    } label: {
                        Label("Nouvelle opération", systemImage: "plus.circle")
                    }

                    Button {
                        activeSheet = .newPosition
                    } label: {
                        Label("Nouvelle position", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } label: {
                    Label("Opération", systemImage: "chart.line.uptrend.xyaxis")
                        .labelStyle(.titleAndIcon)
                } primaryAction: {
                    activeSheet = .newOperation
                }
                .help("Nouvelle opération sur titres. Maintenez le clic pour créer une position.")
            }
        }
    }

    /// En-tête du compte : chiffres clés, graphiques, puis barre d'onglets
    private func accountHeader(for account: Account, summary: Summary) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                topBar(for: account)
                tiles(summary, account: account)

                if showCharts {
                    HStack(alignment: .top, spacing: NativeMetrics.groupSpacing) {
                        InvestmentValueChart(
                            points: series(for: account, summary: summary),
                            currency: account.currency,
                            range: $chartRange
                        )
                        .layoutPriority(1)

                        InvestmentAllocationChart(
                            positions: investmentsController.positions[account.id] ?? [],
                            cash: summary.cash,
                            currency: account.currency,
                            mode: $allocationMode
                        )
                        .frame(width: 380)
                    }
                    .frame(height: 230)
                }
            }
            .padding()

            HStack(spacing: 12) {
                Picker("Vue", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)

                Spacer()

                Button {
                    showCharts.toggle()
                } label: {
                    Label(showCharts ? "Masquer les graphiques" : "Afficher les graphiques",
                          systemImage: showCharts ? "chevron.up" : "chart.xyaxis.line")
                }
                // Même taille de contrôle que le sélecteur d'onglets voisin
                .controlSize(.regular)
                .help("Les graphiques masqués laissent plus de place au tableau")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()
        }
    }

    // MARK: - Barre du haut

    private func topBar(for account: Account) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(account.bank.map { "\(account.type.displayName) · \($0)" } ?? account.type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Fraîcheur des cours et mise à jour en ligne (si activée dans les réglages)
            QuoteUpdateBar(accountID: account.id)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Chiffres clés

    private struct Summary {
        var value: Decimal = 0
        var cash: Decimal = 0
        var invested: Decimal = 0
        var gain: Decimal = 0
        var gainRatio: Double?
        var totalGain: Decimal = 0
        var annualized: Double?
        var income: Decimal = 0
        var realized: Decimal = 0
        var firstDate: Date?
    }

    private func tiles(_ summary: Summary, account: Account) -> some View {
        let year = Calendar.current.component(.year, from: Date())

        return ReportTiles {
            StatTile(
                title: "Valeur du compte",
                value: money(summary.value, account),
                detail: "dont \(money(summary.cash, account)) d'espèces"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Plus-value latente",
                value: signed(summary.gain, account),
                valueColor: summary.gain >= 0 ? .green : .red,
                detail: summary.gainRatio.map { "\(percent($0)) sur le prix de revient" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Versé net",
                value: money(summary.invested, account),
                detail: "versements moins retraits"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: summary.annualized == nil ? "Gain total" : "Performance annualisée",
                value: summary.annualized.map(percent) ?? signed(summary.totalGain, account),
                valueColor: summary.totalGain >= 0 ? .green : .red,
                detail: summary.annualized == nil
                    ? "valeur moins versé net"
                    : "\(signed(summary.totalGain, account)) depuis l'ouverture"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Dividendes, 12 mois",
                value: money(summary.income, account),
                detail: summary.realized != 0
                    ? "plus-values réalisées \(String(year)) : \(signed(summary.realized, account))"
                    : "intérêts compris"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Données

    /// Mouvements d'espèces du compte (versements, retraits), hors occurrences ignorées
    private func cashTransactions(for account: Account) -> [Transaction] {
        transactionsController.allTransactions.filter { $0.accountID == account.id && $0.status != .skipped }
    }

    private func summary(for account: Account) -> Summary {
        let valuation = AccountValuation(
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController
        )
        let calendar = Calendar.current
        let now = Date()
        let cashTransactions = self.cashTransactions(for: account)
        let operations = investmentsController.operations[account.id] ?? []

        var summary = Summary()
        summary.value = valuation.value(of: account)
        summary.cash = valuation.cash(of: account)
        summary.invested = transactionsController.calculateBalance(for: account.id, initialBalance: account.initialBalance)
        summary.gain = investmentsController.unrealizedGain(for: account.id)
        let cost = investmentsController.costBasis(for: account.id)
        summary.gainRatio = cost > 0 ? NSDecimalNumber(decimal: summary.gain / cost).doubleValue : nil
        summary.totalGain = summary.value - summary.invested
        summary.income = InvestmentAnalytics.income(operations, since: calendar.date(byAdding: .year, value: -1, to: now) ?? now)
        summary.realized = investmentsController.realizedGain(for: account.id, year: calendar.component(.year, from: now))

        let dates = cashTransactions.map { $0.date } + operations.map { $0.date }
        summary.firstDate = dates.min()

        // Flux de l'épargnant : solde initial puis chaque versement ou retrait
        var flows: [(date: Date, amount: Decimal)] = cashTransactions.map { ($0.date, $0.signedAmount) }
        if account.initialBalance != 0 {
            flows.append((account.initialBalanceDate ?? summary.firstDate ?? account.createdAt, account.initialBalance))
        }
        summary.annualized = InvestmentAnalytics.annualizedReturn(flows: flows, finalValue: summary.value, at: now)
        return summary
    }

    private func series(for account: Account, summary: Summary) -> [InvestmentSeriesPoint] {
        let now = Date()
        guard let first = summary.firstDate else { return [] }
        let start = max(first, chartRange.start(from: now) ?? first)

        return InvestmentAnalytics.series(
            account: account,
            cashTransactions: cashTransactions(for: account),
            operations: investmentsController.operations[account.id] ?? [],
            positions: investmentsController.positions[account.id] ?? [],
            priceHistory: priceHistory,
            from: start,
            to: now
        )
    }

    /// Recharge l'historique des cours quand le compte, ses positions ou leurs cours changent
    private var historyKey: String {
        let positions = investmentsController.positions[accountID] ?? []
        let stamp = positions.map { "\($0.id.uuidString)-\($0.lastUpdated?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
        return "\(accountID.uuidString)#\(stamp)"
    }

    private func loadPriceHistory() {
        var history: [UUID: [PositionPrice]] = [:]
        for position in investmentsController.positions[accountID] ?? [] {
            history[position.id] = quoteService.history(for: position)
        }
        priceHistory = history
    }

    // MARK: - Format

    private func money(_ amount: Decimal, _ account: Account) -> String {
        amount.formatted(.currency(code: account.currency))
    }

    private func signed(_ amount: Decimal, _ account: Account) -> String {
        (amount > 0 ? "+" : "") + money(amount, account)
    }

    private func percent(_ ratio: Double) -> String {
        ratio.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(_ sheet: InvestmentSheet, account: Account) -> some View {
        switch sheet {
        case .newOperation:
            InvestmentOperationFormView(account: account)
        case .newOperationFor(let position):
            InvestmentOperationFormView(account: account, preselectedPosition: position)
        case .editOperation(let operation):
            InvestmentOperationFormView(account: account, operationToEdit: operation)
        case .newPosition:
            InvestmentPositionFormView(account: account)
        case .editPosition(let position):
            InvestmentPositionFormView(account: account, positionToEdit: position)
        case .price(let position):
            PositionPriceFormView(position: position)
        }
    }
}

// MARK: - Sheet routing

enum InvestmentSheet: Identifiable {
    case newOperation
    case newOperationFor(InvestmentPosition)
    case editOperation(InvestmentTransaction)
    case newPosition
    case editPosition(InvestmentPosition)
    case price(InvestmentPosition)

    var id: String {
        switch self {
        case .newOperation: return "newOperation"
        case .newOperationFor(let position): return "newOperationFor-\(position.id)"
        case .editOperation(let operation): return "editOperation-\(operation.id)"
        case .newPosition: return "newPosition"
        case .editPosition(let position): return "editPosition-\(position.id)"
        case .price(let position): return "price-\(position.id)"
        }
    }
}

// MARK: - Supporting Views

struct InvestmentStatCard: View {
    let title: String
    let value: Decimal
    let currency: String
    let color: Color
    var detail: String? = nil
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value, format: .currency(code: currency))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacyBlur(hidden: appSettings.hideAmounts)

            // La ligne de complément est toujours réservée : toutes les tuiles ont la même hauteur
            Text(detail ?? " ")
                .font(.caption)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .privacyBlur(hidden: detail != nil && appSettings.hideAmounts)
                .accessibilityHidden(detail == nil)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 12)
    }
}
