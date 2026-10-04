import SwiftUI

struct InvestmentAccountView: View {
    let accountID: UUID

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedTab: Tab = .positions
    @State private var activeSheet: InvestmentSheet?

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
        VStack(spacing: 0) {
            header(for: account)
                .padding()

            Picker("Vue", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case .positions:
                    PositionListView(account: account, activeSheet: $activeSheet)
                case .operations:
                    InvestmentOperationListView(account: account, activeSheet: $activeSheet)
                case .cash:
                    TransactionListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
    }

    private func header(for account: Account) -> some View {
        let valuation = AccountValuation(
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController
        )
        let cost = investmentsController.costBasis(for: account.id)
        let gain = investmentsController.unrealizedGain(for: account.id)
        let gainRatio: Double? = cost > 0 ? Double(truncating: NSDecimalNumber(decimal: gain / cost)) : nil
        let year = Calendar.current.component(.year, from: Date())
        let realized = investmentsController.realizedGain(for: account.id, year: year)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(account.bank.map { "\(account.type.displayName) · \($0)" } ?? account.type.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

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
                    Label("Ajouter", systemImage: "plus")
                } primaryAction: {
                    activeSheet = .newOperation
                }
                .fixedSize()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                InvestmentStatCard(
                    title: "Valeur totale",
                    value: valuation.value(of: account),
                    currency: account.currency,
                    color: .primary
                )
                InvestmentStatCard(
                    title: "Titres",
                    value: investmentsController.marketValue(for: account.id),
                    currency: account.currency,
                    color: .primary
                )
                InvestmentStatCard(
                    title: "Espèces",
                    value: valuation.cash(of: account),
                    currency: account.currency,
                    color: .primary
                )
                InvestmentStatCard(
                    title: "Plus-value latente",
                    value: gain,
                    currency: account.currency,
                    color: gain >= 0 ? .green : .red,
                    detail: gainRatio.map { $0.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())) }
                )
            }

            if realized != 0 {
                HStack {
                    Text("Plus-values réalisées \(String(year))")
                        .foregroundColor(.secondary)
                    Text(realized, format: .currency(code: account.currency))
                        .foregroundColor(realized >= 0 ? .green : .red)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .font(.caption)
            }
        }
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
                .privacyBlur(hidden: appSettings.hideAmounts)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(color)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 12)
    }
}
