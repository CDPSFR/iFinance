import SwiftUI
import Charts

/// Plan géré par un prestataire (PEE, PERCO, PER, assurance vie) :
/// apports par origine, valeurs relevées, disponibilité
struct SavingsPlanAccountView: View {
    let accountID: UUID

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedTab: Tab = .evolution
    @State private var activeSheet: PlanSheet?
    @State private var snapshotToDelete: ValuationSnapshot?
    @State private var selectedFlows: Set<PlanFlow.ID> = []

    enum Tab: String, CaseIterable, Identifiable {
        case evolution = "Évolution"
        case contributions = "Apports"
        case availability = "Disponibilité"
        case movements = "Mouvements"

        var id: String { rawValue }
    }

    enum PlanSheet: Identifiable {
        case newValuation
        case editValuation(ValuationSnapshot)
        case newContribution
        case editContribution(PlanFlow)

        var id: String {
            switch self {
            case .newValuation: return "newValuation"
            case .editValuation(let snapshot): return "editValuation-\(snapshot.id)"
            case .newContribution: return "newContribution"
            case .editContribution(let flow): return "editContribution-\(flow.id)"
            }
        }
    }

    var body: some View {
        if let account = accountsController.getAccount(id: accountID) {
            content(for: account)
                .task(id: accountID) {
                    await savingsPlansController.reload(accountID: accountID)
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .newValuation:
                        ValuationFormView(account: account)
                    case .editValuation(let snapshot):
                        ValuationFormView(account: account, snapshotToEdit: snapshot)
                    case .newContribution:
                        ContributionFormView(account: account)
                    case .editContribution(let flow):
                        ContributionDetailFormView(account: account, flow: flow)
                    }
                }
                .confirmationDialog(
                    "Supprimer cette valeur ?",
                    isPresented: Binding(
                        get: { snapshotToDelete != nil },
                        set: { if !$0 { snapshotToDelete = nil } }
                    ),
                    presenting: snapshotToDelete
                ) { snapshot in
                    Button("Supprimer", role: .destructive) {
                        Task { await savingsPlansController.deleteValuation(snapshot) }
                    }
                } message: { snapshot in
                    Text("Valeur du \(snapshot.date.formatted(date: .abbreviated, time: .omitted)). Cette action est irréversible.")
                }
        } else {
            ContentUnavailableView("Compte introuvable", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for account: Account) -> some View {
        let summary = savingsPlansController.summary(for: account, transactions: transactionsController.allTransactions)

        VStack(spacing: 0) {
            header(for: account, summary: summary)
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
                case .evolution:
                    evolutionTab(account: account, summary: summary)
                case .contributions:
                    contributionsTab(account: account, summary: summary)
                case .availability:
                    availabilityTab(account: account, summary: summary)
                case .movements:
                    TransactionListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
    }

    private func header(for account: Account, summary: SavingsPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        activeSheet = .newValuation
                    } label: {
                        Label("Mettre à jour la valeur", systemImage: "camera")
                    }

                    Button {
                        activeSheet = .newContribution
                    } label: {
                        Label("Nouvel apport", systemImage: "plus.circle")
                    }
                } label: {
                    Label("Mettre à jour la valeur", systemImage: "camera")
                } primaryAction: {
                    activeSheet = .newValuation
                }
                .fixedSize()
            }

            if let reminder = valuationReminder(summary) {
                Label(reminder, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundColor(.orange)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                InvestmentStatCard(
                    title: "Valeur estimée",
                    value: summary.value,
                    currency: account.currency,
                    color: .primary,
                    detail: valueDetail(summary, currency: account.currency)
                )
                InvestmentStatCard(
                    title: "Versements nets",
                    value: summary.invested,
                    currency: account.currency,
                    color: .primary,
                    detail: summary.employerContributions > 0
                        ? "dont entreprise \(summary.employerContributions.formatted(.currency(code: account.currency)))"
                        : nil
                )
                InvestmentStatCard(
                    title: "Plus-value",
                    value: summary.gain,
                    currency: account.currency,
                    color: summary.gain >= 0 ? .green : .red,
                    detail: summary.gainRatio.map { $0.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())) }
                )
                InvestmentStatCard(
                    title: "Disponible",
                    value: summary.availableValue,
                    currency: account.currency,
                    color: .primary,
                    detail: summary.blockedValue > 0
                        ? "bloqué \(summary.blockedValue.formatted(.currency(code: account.currency)))"
                        : nil
                )
            }
        }
    }

    // MARK: - Évolution

    @ViewBuilder
    private func evolutionTab(account: Account, summary: SavingsPlanSummary) -> some View {
        let snapshots = (savingsPlansController.valuations[account.id] ?? []).reversed()
        let flows = savingsPlansController.flows(for: account, transactions: transactionsController.allTransactions)

        if snapshots.isEmpty {
            ContentUnavailableView {
                Label("Aucune valeur relevée", systemImage: "camera")
            } description: {
                Text("Reportez la valeur de votre dernier relevé (tous les 6 mois par exemple) pour suivre la performance du plan. En attendant, la valeur affichée correspond aux versements.")
            } actions: {
                Button("Mettre à jour la valeur") {
                    activeSheet = .newValuation
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if summary.history.count >= 2 {
                        PlanEvolutionChart(history: summary.history, currency: account.currency)
                            .frame(height: 240)
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(snapshots)) { snapshot in
                            let invested = SavingsPlanCalculator.invested(flows: flows, at: snapshot.date)
                            ValuationRow(
                                snapshot: snapshot,
                                invested: invested,
                                currency: account.currency
                            )
                            .contextMenu {
                                Button("Modifier…") { activeSheet = .editValuation(snapshot) }
                                Button("Supprimer…", role: .destructive) { snapshotToDelete = snapshot }
                            }
                            Divider()
                        }
                    }
                    .cardBackground(cornerRadius: 12)
                }
                .padding()
            }
        }
    }

    // MARK: - Apports

    @ViewBuilder
    private func contributionsTab(account: Account, summary: SavingsPlanSummary) -> some View {
        let flows = savingsPlansController.flows(for: account, transactions: transactionsController.allTransactions).reversed()

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(ContributionOrigin.allCases, id: \.self) { origin in
                    OriginTotalCard(
                        origin: origin,
                        amount: summary.totalsByOrigin[origin] ?? 0,
                        currency: account.currency
                    )
                }
            }
            .padding()

            if flows.isEmpty {
                ContentUnavailableView {
                    Label("Aucun apport", systemImage: "tray")
                } description: {
                    Text("Ajoutez vos versements et les abondements de votre entreprise.")
                } actions: {
                    Button("Nouvel apport") {
                        activeSheet = .newContribution
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(Array(flows), selection: $selectedFlows) {
                    TableColumn("Date") { flow in
                        Text(flow.date, format: .dateTime.day().month().year())
                    }
                    .width(min: 80, ideal: 90)

                    TableColumn("Origine") { flow in
                        if flow.isInitialBalance {
                            Label("Solde initial", systemImage: "flag")
                        } else if let origin = flow.origin {
                            Label(origin.displayName, systemImage: origin.icon)
                                .foregroundColor(flow.hasDetail ? .primary : .secondary)
                                .help(flow.hasDetail ? "" : "Origine déduite automatiquement : clic droit pour la préciser")
                        } else {
                            Label("Retrait / déblocage", systemImage: "arrow.up.right")
                        }
                    }
                    .width(min: 150, ideal: 180)

                    TableColumn("Montant") { flow in
                        Text(flow.amount, format: .currency(code: account.currency))
                            .foregroundColor(flow.amount >= 0 ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    }

                    TableColumn("Disponibilité") { flow in
                        if flow.isContribution {
                            AvailabilityBadge(availableOn: flow.availableOn)
                        }
                    }
                }
                .contextMenu(forSelectionType: PlanFlow.ID.self) { ids in
                    if let id = ids.first,
                       let flow = flows.first(where: { $0.id == id }),
                       flow.isContribution, flow.transactionID != nil {
                        Button("Modifier l'origine et la disponibilité…") {
                            activeSheet = .editContribution(flow)
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first,
                       let flow = flows.first(where: { $0.id == id }),
                       flow.isContribution, flow.transactionID != nil {
                        activeSheet = .editContribution(flow)
                    }
                }
            }
        }
    }

    // MARK: - Disponibilité

    private func availabilityTab(account: Account, summary: SavingsPlanSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    InvestmentStatCard(
                        title: "Disponible aujourd'hui",
                        value: summary.availableValue,
                        currency: account.currency,
                        color: .green
                    )
                    InvestmentStatCard(
                        title: "Bloqué",
                        value: summary.blockedValue,
                        currency: account.currency,
                        color: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Échéancier")
                        .font(.headline)

                    if summary.unlocks.isEmpty {
                        Text("Aucune somme bloquée.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(summary.unlocks) { unlock in
                            HStack {
                                Image(systemName: unlock.date == nil ? "figure.walk" : "lock.open")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(unlock.date.map { "Le \($0.formatted(date: .long, time: .omitted))" } ?? "À la retraite")
                                Spacer()
                                Text(unlock.amount, format: .currency(code: account.currency))
                                    .fontWeight(.semibold)
                                    .privacyBlur(hidden: appSettings.hideAmounts)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Text("Montants versés qui se débloquent à chaque date (hors plus-values). La valeur disponible répartit la valeur estimée au prorata de ces montants. Les cas de déblocage anticipé ne sont pas pris en compte.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .cardBackground(cornerRadius: 12)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func valueDetail(_ summary: SavingsPlanSummary, currency: String) -> String {
        guard let snapshot = summary.lastSnapshot else {
            return "aucune valeur relevée"
        }
        let date = snapshot.date.formatted(date: .abbreviated, time: .omitted)
        guard summary.flowsSinceSnapshot != 0 else {
            return "relevé du \(date)"
        }
        let sign = summary.flowsSinceSnapshot > 0 ? "+" : ""
        return "relevé du \(date) \(sign)\(summary.flowsSinceSnapshot.formatted(.currency(code: currency)))"
    }

    /// Rappel si aucune valeur n'a été relevée depuis plus de 6 mois
    private func valuationReminder(_ summary: SavingsPlanSummary) -> String? {
        guard let snapshot = summary.lastSnapshot else { return nil }
        let months = Calendar.current.dateComponents([.month], from: snapshot.date, to: Date()).month ?? 0
        guard months >= 6 else { return nil }
        return "Dernière valeur relevée il y a \(months) mois : pensez à la mettre à jour avec votre dernier relevé."
    }
}

// MARK: - Supporting Views

struct PlanEvolutionChart: View {
    let history: [SavingsPlanHistoryPoint]
    let currency: String

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", double(point.value)),
                    series: .value("Série", "Valeur")
                )
                .foregroundStyle(by: .value("Série", "Valeur"))
                .symbol(.circle)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", double(point.invested)),
                    series: .value("Série", "Versements nets")
                )
                .foregroundStyle(by: .value("Série", "Versements nets"))
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartForegroundStyleScale([
            "Valeur": Color.indigo,
            "Versements nets": Color.gray
        ])
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: currency).precision(.fractionLength(0)))
                    }
                }
            }
        }
        .padding()
        .cardBackground(cornerRadius: 12)
    }

    private func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

struct ValuationRow: View {
    let snapshot: ValuationSnapshot
    let invested: Decimal
    let currency: String
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        let gain = snapshot.value - invested

        HStack(spacing: 12) {
            Image(systemName: "camera")
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.date, format: .dateTime.day().month(.wide).year())
                if let note = snapshot.note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot.value, format: .currency(code: currency))
                    .fontWeight(.semibold)
                Text("versé \(invested.formatted(.currency(code: currency))) · \(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: currency)))")
                    .font(.caption)
                    .foregroundColor(gain >= 0 ? .green : .red)
            }
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct OriginTotalCard: View {
    let origin: ContributionOrigin
    let amount: Decimal
    let currency: String
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(origin.displayName, systemImage: origin.icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(amount, format: .currency(code: currency))
                .font(.headline)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 10)
    }
}

struct AvailabilityBadge: View {
    let availableOn: Date?

    var body: some View {
        if let availableOn {
            if availableOn <= Date() {
                Label("Disponible", systemImage: "lock.open")
                    .foregroundColor(.green)
            } else {
                Label(availableOn.formatted(date: .abbreviated, time: .omitted), systemImage: "lock")
                    .foregroundColor(.orange)
            }
        } else {
            Label("Retraite", systemImage: "lock")
                .foregroundColor(.secondary)
        }
    }
}
