import SwiftUI
import Charts

/// Plan géré par un prestataire (PEE, PER, PERCO, article 83, assurance vie) :
/// valeur relevée, apports par origine, blocs propres au dispositif
struct SavingsPlanAccountView: View {
    let accountID: UUID

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedTab: Tab = .contributions
    @State private var activeSheet: PlanSheet?
    @State private var snapshotToDelete: ValuationSnapshot?
    @State private var selectedFlows: Set<PlanFlow.ID> = []
    @State private var selectedSnapshots: Set<ValuationSnapshot.ID> = []
    @AppStorage("savingsPlanShowBlocks") private var showBlocks = true
    /// Hauteur naturelle de la zone haute (tuiles et blocs), mesurée après rendu
    @State private var topHeight: CGFloat = 420

    enum Tab: String, CaseIterable, Identifiable {
        case contributions = "Apports"
        case valuations = "Relevés de valeur"
        case movements = "Mouvements"

        var id: String { rawValue }
    }

    enum PlanSheet: Identifiable {
        case newValuation
        case editValuation(ValuationSnapshot)
        case newContribution
        case editContribution(PlanFlow)
        case settings

        var id: String {
            switch self {
            case .newValuation: return "newValuation"
            case .editValuation(let snapshot): return "editValuation-\(snapshot.id)"
            case .newContribution: return "newContribution"
            case .editContribution(let flow): return "editContribution-\(flow.id)"
            case .settings: return "settings"
            }
        }
    }

    /// Données de la page, calculées une fois par rendu
    private struct PlanContext {
        let account: Account
        let kind: SavingsPlanPageKind
        let summary: SavingsPlanSummary
        let flows: [PlanFlow]
        let settings: SavingsPlanSettings
        let snapshots: [ValuationSnapshot]
        let year: Int

        var currency: String { account.currency }
        var type: AccountType { account.type }

        /// Total des apports (hors solde initial et retraits)
        var totalContributions: Decimal {
            summary.totalsByOrigin.values.reduce(0, +)
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
                    case .settings:
                        SavingsPlanSettingsFormView(account: account)
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
        let context = makeContext(for: account)

        GeometryReader { page in
            Group {
                if selectedTab == .movements {
                    // Les mouvements hébergent l'en-tête du plan : l'inspecteur occupe toute la hauteur de la page
                    TransactionListView(pageHeader: AnyView(planHeader(context, pageHeight: page.size.height)))
                } else {
                    VStack(spacing: 0) {
                        planHeader(context, pageHeight: page.size.height)

                        Group {
                            switch selectedTab {
                            case .contributions:
                                contributionsTab(context)
                            case .valuations, .movements:
                                valuationsTab(context)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                    }
                }
            }
            .frame(width: page.size.width, height: page.size.height, alignment: .top)
        }
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    activeSheet = .newValuation
                } label: {
                    Label("Mettre à jour la valeur", systemImage: "camera")
                        .labelStyle(.titleAndIcon)
                }
                .help("Reporter la valeur de votre dernier relevé")
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        activeSheet = .newContribution
                    } label: {
                        Label("Nouvel apport", systemImage: "plus.circle")
                    }

                    if hasSettings(context.kind) {
                        Divider()
                        Button {
                            activeSheet = .settings
                        } label: {
                            Label("Réglages du plan…", systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    Label("Apport", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                } primaryAction: {
                    activeSheet = .newContribution
                }
                .help("Nouvel apport. Maintenez le clic pour les réglages du plan.")
            }
        }
    }

    /// En-tête du plan : tuiles et blocs (zone qui défile si la place manque), puis barre d'onglets
    private func planHeader(_ context: PlanContext, pageHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Zone haute : elle garde sa hauteur naturelle tant qu'elle laisse de la place au tableau,
            // et défile au-delà, au lieu de comprimer les blocs les uns sur les autres
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    topBar(context)
                    tiles(context)

                    if showBlocks {
                        blocks(context)
                    }
                }
                .padding()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PlanTopHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: topAreaHeight(pageHeight: pageHeight))
            .clipped()
            .onPreferenceChange(PlanTopHeightKey.self) { height in
                if abs(height - topHeight) > 0.5 {
                    topHeight = height
                }
            }

            HStack(spacing: 12) {
                Picker("Vue", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                Text(tabNote(context))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    showBlocks.toggle()
                } label: {
                    Label(showBlocks ? "Masquer les graphiques" : "Afficher les graphiques",
                          systemImage: showBlocks ? "chevron.up" : "chart.xyaxis.line")
                }
                .controlSize(.regular)
                .help("Les graphiques masqués laissent plus de place au tableau")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()
        }
    }

    /// Hauteur réservée sous la zone haute : barre d'onglets et tableau
    private static let tabBarHeight: CGFloat = 46
    private static let minimumTableHeight: CGFloat = 260

    /// La zone haute garde sa hauteur naturelle si elle laisse au tableau sa hauteur minimale,
    /// sinon elle rétrécit et défile : le tableau ne peut plus déborder par-dessus les blocs
    private func topAreaHeight(pageHeight: CGFloat) -> CGFloat {
        let available = pageHeight - Self.tabBarHeight - Self.minimumTableHeight
        return max(min(topHeight, available), 120)
    }

    private func makeContext(for account: Account) -> PlanContext {
        let transactions = transactionsController.allTransactions
        return PlanContext(
            account: account,
            kind: SavingsPlanPageKind(account.type),
            summary: savingsPlansController.summary(for: account, transactions: transactions),
            flows: savingsPlansController.flows(for: account, transactions: transactions),
            settings: savingsPlansController.planSettings(for: account.id),
            snapshots: savingsPlansController.valuations[account.id] ?? [],
            year: Calendar.current.component(.year, from: Date())
        )
    }

    private func hasSettings(_ kind: SavingsPlanPageKind) -> Bool {
        kind == .pee || kind == .per
    }

    // MARK: - Barre du haut

    private func topBar(_ context: PlanContext) -> some View {
        let freshness = self.freshness(context.summary)

        return HStack(spacing: 12) {
            Text(context.account.bank.map { "\(context.type.displayName) · \($0)" } ?? context.type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(freshness.color)
                    .frame(width: 7, height: 7)
                Text(freshness.text)
                    .foregroundStyle(freshness.color == .orange ? Color.orange : Color.secondary)
            }
            .font(.caption)
        }
    }

    /// Fraîcheur du dernier relevé : rappel au-delà de 6 mois
    private func freshness(_ summary: SavingsPlanSummary) -> (text: String, color: Color) {
        guard let snapshot = summary.lastSnapshot else {
            return ("Aucune valeur relevée : la valeur affichée correspond aux versements", .gray)
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: snapshot.date), to: calendar.startOfDay(for: Date())).day ?? 0
        let months = calendar.dateComponents([.month], from: snapshot.date, to: Date()).month ?? 0

        if days <= 0 {
            return ("Dernier relevé aujourd’hui", .green)
        } else if months < 1 {
            return ("Dernier relevé il y a \(days) jour\(days > 1 ? "s" : "")", .green)
        } else if months < 6 {
            return ("Dernier relevé il y a \(months) mois", .green)
        } else {
            return ("Dernier relevé il y a \(months) mois : pensez à le mettre à jour", .orange)
        }
    }

    // MARK: - Chiffres clés

    @ViewBuilder
    private func tiles(_ context: PlanContext) -> some View {
        let summary = context.summary
        let currency = context.currency
        let gainRatio = summary.gainRatio.map { PlanFormat.percent($0, signed: true) }

        ReportTiles {
            StatTile(
                title: "Valeur estimée",
                value: PlanFormat.money(summary.value, currency),
                detail: valueDetail(summary, currency: currency)
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Disponible aujourd’hui",
                value: PlanFormat.money(summary.availableValue, currency),
                valueColor: summary.availableValue > 0 ? .green : .secondary,
                detail: availableDetail(context)
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: context.kind == .article83 ? "Cotisations nettes" : "Versements nets",
                value: PlanFormat.money(summary.invested, currency),
                detail: context.kind == .article83 && summary.employerContributions > 0
                    ? "dont \(PlanFormat.round(summary.employerContributions, currency)) par l’employeur"
                    : "apports moins retraits"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Plus-value",
                value: PlanFormat.signed(summary.gain, currency),
                valueColor: summary.gain >= 0 ? .green : .red,
                detail: gainDetail(context, ratio: gainRatio)
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            fifthTile(context)
        }
    }

    @ViewBuilder
    private func fifthTile(_ context: PlanContext) -> some View {
        let currency = context.currency

        switch context.kind {
        case .pee:
            let employer = context.summary.employerContributions
            StatTile(
                title: "Apporté par l’employeur",
                value: PlanFormat.money(employer, currency),
                detail: PlanFormat.ratio(employer, context.totalContributions).map { "\(PlanFormat.percent($0)) des apports" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .per:
            let deducted = RetirementPlanAnalytics.deductedContributions(flows: context.flows, year: context.year)
            let ceiling = RetirementPlanAnalytics.ceiling(for: context.year, settings: context.settings).value
            StatTile(
                title: "Versé en \(String(context.year))",
                value: PlanFormat.money(deducted, currency),
                detail: PlanFormat.ratio(deducted, ceiling).map { "\(PlanFormat.percent($0)) de votre plafond de déduction" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .article83:
            let mandatory = RetirementPlanAnalytics.contributions(
                flows: context.flows,
                year: context.year,
                origins: [.matching, .employeeMandatory]
            )
            StatTile(
                title: "Cotisations \(String(context.year))",
                value: PlanFormat.money(mandatory, currency),
                detail: "déjà déduites de votre salaire imposable"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .generic:
            EmptyView()
        }
    }

    private func valueDetail(_ summary: SavingsPlanSummary, currency: String) -> String {
        guard let snapshot = summary.lastSnapshot else {
            return "aucun relevé : versements nets"
        }
        let date = snapshot.date.formatted(.dateTime.day().month(.abbreviated).year())
        guard summary.flowsSinceSnapshot != 0 else {
            return "relevé du \(date)"
        }
        let flows = PlanFormat.round(abs(summary.flowsSinceSnapshot), currency)
        return summary.flowsSinceSnapshot > 0
            ? "relevé du \(date) + \(flows) versés depuis"
            : "relevé du \(date) − \(flows) retirés depuis"
    }

    private func availableDetail(_ context: PlanContext) -> String? {
        let summary = context.summary
        switch context.kind {
        case .article83:
            return "sortie en rente à la retraite"
        case .per where summary.availableValue == 0:
            return "bloqué jusqu’à la retraite"
        default:
            if summary.value > 0, summary.availableValue > 0, let ratio = PlanFormat.ratio(summary.availableValue, summary.value) {
                return "\(PlanFormat.percent(ratio)) du plan"
            }
            return summary.blockedValue > 0 ? "tout est encore bloqué" : nil
        }
    }

    private func gainDetail(_ context: PlanContext, ratio: String?) -> String? {
        guard let ratio else { return nil }
        switch context.kind {
        case .pee: return "\(ratio) · soumise aux prélèvements sociaux"
        case .article83: return "\(ratio) sur les cotisations"
        case .per, .generic: return "\(ratio) sur les versements"
        }
    }

    // MARK: - Blocs

    private enum Block: Hashable {
        case chart, availability, origins, matching, ceilings, pace, deduction
    }

    private func blockList(_ kind: SavingsPlanPageKind) -> [Block] {
        switch kind {
        case .pee: return [.chart, .availability, .origins, .matching]
        case .per: return [.chart, .ceilings, .pace, .deduction]
        case .article83: return [.chart, .availability, .origins]
        case .generic: return [.chart]
        }
    }

    @ViewBuilder
    private func blocks(_ context: PlanContext) -> some View {
        let list = blockList(context.kind)
        let rows = stride(from: 0, to: list.count, by: 2).map { Array(list[$0..<min($0 + 2, list.count)]) }

        Grid(alignment: .topLeading, horizontalSpacing: NativeMetrics.groupSpacing, verticalSpacing: NativeMetrics.groupSpacing) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    if list.count == 1, let only = row.first {
                        block(only, context)
                            .gridCellColumns(2)
                    } else {
                        ForEach(row, id: \.self) { item in
                            block(item, context)
                        }
                        if row.count == 1 {
                            // Case vide : ne fixe pas la hauteur de la ligne
                            Color.clear
                                .gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func block(_ block: Block, _ context: PlanContext) -> some View {
        let currency = context.currency

        switch block {
        case .chart:
            PlanValueChartBlock(
                history: context.summary.history,
                snapshotDates: Set(context.snapshots.map(\.date)),
                currency: currency,
                onAddValuation: { activeSheet = .newValuation }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .availability:
            AvailabilityCalendarBlock(
                buckets: RetirementPlanAnalytics.availabilityBuckets(summary: context.summary, kind: context.kind),
                subtitle: context.kind == .article83 ? "sortie en rente uniquement" : availabilitySubtitle(context.type),
                note: availabilityNote(context),
                currency: currency
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .origins:
            OriginsByYearBlock(
                yearly: RetirementPlanAnalytics.yearlyOrigins(flows: context.flows),
                totals: context.summary.totalsByOrigin,
                accountType: context.type,
                note: originsNote(context),
                currency: currency
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .matching:
            matchingBlock(context)
                .privacyBlur(hidden: appSettings.hideAmounts)

        case .ceilings:
            let status = RetirementPlanAnalytics.deductionStatus(flows: context.flows, settings: context.settings, year: context.year)
            DeductionCeilingsBlock(
                history: status.history,
                currentYear: context.year,
                note: ceilingsNote(status, currency: currency),
                currency: currency
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .pace:
            let pace = RetirementPlanAnalytics.pace(flows: context.flows)
            ContributionPaceBlock(
                pace: pace,
                note: paceNote(pace, context: context),
                currency: currency
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

        case .deduction:
            deductionBlock(context)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: Disponibilité

    private func availabilitySubtitle(_ type: AccountType) -> String {
        switch type.availabilityRule {
        case .lockedYears(let years): return "sommes bloquées \(years) ans"
        case .untilRetirement: return "bloqué jusqu’à la retraite"
        case .immediate: return "disponible à tout moment"
        }
    }

    private func availabilityNote(_ context: PlanContext) -> String {
        let summary = context.summary
        let currency = context.currency

        if context.kind == .article83 {
            let optional = summary.totalsByOrigin[.voluntary] ?? 0
            var note = "Les cotisations obligatoires ne sortent qu’en rente."
            if optional > 0 {
                note += " Vos \(PlanFormat.round(optional, currency)) de versements facultatifs deviendraient récupérables en capital après un transfert vers un PER."
            }
            return note + " Pas de déblocage anticipé pour l’achat de la résidence principale."
        }

        let earlyRelease = "Déblocage anticipé possible dans 11 cas (mariage ou Pacs, 3e enfant, résidence principale, fin du contrat de travail…), à demander dans les 6 mois suivant l’événement."
        let lockedInvested = summary.unlocks.reduce(Decimal(0)) { $0 + $1.amount }
        guard lockedInvested > 0 else {
            return "Toutes les sommes sont disponibles."
        }
        guard let next = summary.unlocks.first(where: { $0.date != nil }), let date = next.date else {
            return "Les sommes restantes sont bloquées jusqu’à la retraite. " + earlyRelease
        }

        let value = next.amount * summary.blockedValue / lockedInvested
        let months = Calendar.current.dateComponents([.month], from: Date(), to: date).month ?? 0
        let delay = months >= 1 ? "dans \(months) mois" : "dans moins d’un mois"
        return "Prochain déblocage : \(PlanFormat.round(value, currency)) le \(date.formatted(.dateTime.day().month(.wide).year())), \(delay). " + earlyRelease
    }

    // MARK: Origines

    private func originsNote(_ context: PlanContext) -> String {
        let summary = context.summary
        let currency = context.currency
        let total = context.totalContributions
        guard total > 0 else { return "Aucun apport enregistré." }

        if context.kind == .article83 {
            let employer = summary.totalsByOrigin[.matching] ?? 0
            let lastYear = context.year - 1
            let mandatoryLastYear = RetirementPlanAnalytics.contributions(
                flows: context.flows,
                year: lastYear,
                origins: [.matching, .employeeMandatory]
            )
            var note = "L’employeur a versé \(PlanFormat.percent(PlanFormat.ratio(employer, total) ?? 0)) des cotisations."
            if mandatoryLastYear > 0 {
                note += " Les cotisations obligatoires de \(String(lastYear)) (\(PlanFormat.round(mandatoryLastYear, currency)), part employeur comprise) réduisent d’autant votre plafond de déduction PER \(String(context.year))."
            }
            return note
        }

        let personal = summary.totalsByOrigin[.voluntary] ?? 0
        return "Votre effort personnel : \(PlanFormat.round(personal, currency)), soit \(PlanFormat.percent(PlanFormat.ratio(personal, total) ?? 0)) des apports. Abondement, participation et intéressement font le reste."
    }

    // MARK: Abondement (PEE)

    private func matchingBlock(_ context: PlanContext) -> some View {
        let currency = context.currency
        let matching = RetirementPlanAnalytics.matchingYear(
            flows: context.flows,
            settings: context.settings,
            accountType: context.type,
            year: context.year
        )
        let openSettings = { activeSheet = .settings }

        var rows: [PlanFactRow] = [
            PlanFactRow(label: "Vos versements volontaires", value: PlanFormat.round(matching.voluntary, currency)),
            PlanFactRow(
                label: "Abondement reçu",
                detail: matching.rate.map { "taux constaté : \(PlanFormat.percent($0))" },
                value: (matching.matching > 0 ? "+" : "") + PlanFormat.round(matching.matching, currency),
                color: matching.matching > 0 ? .green : .primary
            )
        ]

        if let cap = matching.accordCap {
            rows.append(PlanFactRow(label: "Plafond de votre accord", detail: "saisi dans les réglages du plan", value: PlanFormat.round(cap, currency)))
        } else {
            rows.append(PlanFactRow(label: "Plafond de votre accord", detail: "indiqué dans l’accord d’entreprise", value: "À saisir", action: openSettings))
        }

        rows.append(PlanFactRow(
            label: "Plafond légal",
            detail: "8 % du PASS \(String(context.year))",
            value: PlanFormat.money(matching.legalCap, currency),
            color: .secondary
        ))
        rows.append(PlanFactRow(
            label: "Abondement restant à capter",
            detail: matching.accordCap != nil ? "plafond de l’accord − reçu" : "plafond légal − reçu",
            value: PlanFormat.round(matching.remaining, currency),
            color: .accentColor
        ))

        var footnote: String
        if matching.remaining == 0 {
            footnote = "Vous avez capté tout l’abondement de l’année."
        } else if let needed = matching.additionalVoluntaryNeeded, let rate = matching.rate {
            footnote = "Pour capter les \(PlanFormat.round(matching.remaining, currency)) restants au taux de \(PlanFormat.percent(rate)), il faudrait verser environ \(PlanFormat.round(needed, currency)) de plus."
        } else {
            footnote = "Aucun abondement reçu cette année : il se déclenche avec vos versements volontaires."
        }
        if matching.voluntary > 0 {
            footnote += " Règle du triple : l’abondement ne peut dépasser 3 × vos versements (\(PlanFormat.round(matching.tripleCap, currency)) ici)"
            footnote += matching.tripleCap >= matching.effectiveCap
                ? ", elle ne vous limite donc pas."
                : ", elle le plafonne donc à ce montant."
        }

        return PlanFactsBlock(
            title: "Abondement de l’année",
            subtitle: String(context.year),
            rows: rows,
            footnote: footnote,
            onEdit: openSettings
        )
    }

    // MARK: Déduction (PER)

    private func ceilingsNote(_ status: DeductionStatus, currency: String) -> String {
        var note = "Le plafond non utilisé se reporte sur les 3 années suivantes, et sur 5 ans pour les plafonds nés à partir de 2026."
        let currentLeft = max(status.ceiling - status.deducted, 0)
        let carriedLeft = max(status.remaining - currentLeft, 0)
        if carriedLeft > 0, let first = status.carriedOverFirstYear, let last = status.carriedOverLastYear {
            let years = first == last ? "de \(String(first))" : "de \(String(first)) à \(String(last))"
            note += " \(PlanFormat.round(carriedLeft, currency)) \(years) restent utilisables"
            if status.expiringThisYear > 0 {
                note += ", dont \(PlanFormat.round(status.expiringThisYear, currency)) perdus fin \(String(status.year))"
            }
            note += "."
        }
        if status.history.contains(where: \.isFloorCeiling) {
            note += " * Plancher légal : saisissez le plafond de votre avis d’impôt dans les réglages du plan."
        }
        return note
    }

    private func paceNote(_ pace: ContributionPace, context: PlanContext) -> String {
        guard pace.paidMonths > 0 else {
            return "Aucun versement volontaire sur les 12 derniers mois."
        }

        let missed = pace.missedMonths
        var note: String
        if missed.isEmpty {
            note = "Un versement chaque mois depuis un an."
        } else if missed.count <= 3 {
            let names = missed.map { $0.start.formatted(.dateTime.month(.wide)) }
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " et " + names.last!
            note = "\(missed.count == 1 ? "Un mois" : "\(missed.count) mois") sans versement (\(list))."
        } else {
            note = "\(missed.count) mois sans versement sur les 12 derniers."
        }

        if pace.usualAmount != nil {
            let deducted = RetirementPlanAnalytics.deductedContributions(flows: context.flows, year: context.year)
            let projected = RetirementPlanAnalytics.projectedYearEnd(deducted: deducted, pace: pace)
            let ceiling = RetirementPlanAnalytics.ceiling(for: context.year, settings: context.settings).value
            note += " À ce rythme, vous aurez versé \(PlanFormat.round(projected, context.currency)) fin décembre"
            if let ratio = PlanFormat.ratio(projected, ceiling) {
                note += ", soit \(PlanFormat.percent(ratio)) de votre plafond de l’année"
            }
            note += "."
        }
        return note
    }

    private func deductionBlock(_ context: PlanContext) -> some View {
        let currency = context.currency
        let status = RetirementPlanAnalytics.deductionStatus(flows: context.flows, settings: context.settings, year: context.year)
        let year = String(context.year)
        let previousYear = String(context.year - 1)
        let openSettings = { activeSheet = .settings }

        var carriedDetail = "aucun plafond non utilisé"
        if status.carriedOver > 0, let first = status.carriedOverFirstYear, let last = status.carriedOverLastYear {
            carriedDetail = first == last
                ? "non utilisé en \(String(first))"
                : "non utilisés de \(String(first)) à \(String(last))"
        }

        var remainingDetail: String? = nil
        if status.expiringThisYear > 0, let expiringYear = status.expiringYear {
            remainingDetail = "dont \(PlanFormat.round(status.expiringThisYear, currency)) de \(String(expiringYear)), perdus fin \(year)"
        }

        var rows: [PlanFactRow] = [
            PlanFactRow(label: "Versé en \(year)", detail: "versements volontaires déduits", value: PlanFormat.round(status.deducted, currency)),
            PlanFactRow(
                label: "Plafond de l’année",
                detail: status.isFloorCeiling
                    ? "plancher légal (10 % du PASS \(previousYear)) : saisissez celui de votre avis d’impôt"
                    : "10 % des revenus \(previousYear), sur l’avis d’impôt",
                value: PlanFormat.round(status.ceiling, currency),
                action: status.isFloorCeiling ? openSettings : nil
            ),
            PlanFactRow(label: "Plafonds reportés", detail: carriedDetail, value: PlanFormat.round(status.carriedOver, currency)),
            PlanFactRow(
                label: "Restant à déduire en \(year)",
                detail: remainingDetail,
                value: PlanFormat.round(status.remaining, currency),
                color: .accentColor
            )
        ]

        if let saving = status.taxSaving, let rate = status.marginalTaxRate {
            rows.append(PlanFactRow(
                label: "Économie d’impôt estimée",
                detail: "tranche marginale à \(PlanFormat.percent(rate))",
                value: "≈ \(PlanFormat.round(saving, currency))",
                color: .green
            ))
        } else {
            rows.append(PlanFactRow(
                label: "Économie d’impôt estimée",
                detail: "selon votre tranche marginale d’imposition",
                value: "À saisir",
                action: openSettings
            ))
        }

        return PlanFactsBlock(
            title: "Déduction fiscale de l’année",
            subtitle: year,
            rows: rows,
            footnote: "Les versements consomment d’abord le plafond de l’année, puis les reports les plus anciens. Report sur 5 ans pour les plafonds nés à partir de 2026. En couple, mutualisation possible avec le plafond du conjoint (case 6QR de la déclaration). Seuls les versements de ce plan sont pris en compte.",
            onEdit: openSettings
        )
    }

    // MARK: - Onglets

    private func tabNote(_ context: PlanContext) -> String {
        switch selectedTab {
        case .contributions:
            switch context.kind {
            case .pee: return "chaque apport porte son origine et sa date de disponibilité"
            case .per: return "compartiment et déduction décident de la fiscalité à la sortie"
            case .article83: return "cotisations prélevées sur la fiche de paie"
            case .generic: return "chaque apport porte son origine"
            }
        case .valuations:
            switch context.type {
            case .pee, .perco: return "une ligne par relevé du teneur de compte"
            case .retirement, .article83, .lifeInsurance: return "une ligne par relevé de l’assureur"
            default: return "une ligne par relevé"
            }
        case .movements:
            return "apports, retraits et déblocages, comme dans un compte classique"
        }
    }

    // MARK: Apports

    @ViewBuilder
    private func contributionsTab(_ context: PlanContext) -> some View {
        let flows = Array(context.flows.reversed())

        if flows.isEmpty {
            TopEmptyState(
                systemImage: "tray",
                title: "Aucun apport",
                message: context.kind == .article83
                    ? "Ajoutez les cotisations de votre fiche de paie et vos versements facultatifs."
                    : "Ajoutez vos versements et les apports de votre entreprise.",
                actionTitle: "Nouvel apport",
                action: { activeSheet = .newContribution }
            )
        } else if context.kind == .per {
            perContributionsTable(flows, context: context)
        } else {
            contributionsTable(flows, context: context)
        }
    }

    private func contributionsTable(_ flows: [PlanFlow], context: PlanContext) -> some View {
        Table(flows, selection: $selectedFlows) {
            TableColumn("Date") { flow in
                Text(flow.date, format: .dateTime.day().month(.abbreviated).year())
                    .fontWeight(.medium)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Origine") { flow in
                originCell(flow, type: context.type)
            }
            .width(min: 150, ideal: 190)

            TableColumn("Montant") { flow in
                amountCell(flow, currency: context.currency)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Disponible le") { flow in
                Text(availabilityText(flow, kind: context.kind))
                    .foregroundStyle(flow.isContribution ? Color.primary : Color.secondary)
            }
            .width(min: 120, ideal: 200)

            TableColumn("État") { flow in
                stateCell(flow)
            }
            .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: PlanFlow.ID.self) { ids in
            contributionMenu(ids, flows: flows)
        } primaryAction: { ids in
            editContribution(ids, flows: flows)
        }
    }

    private func perContributionsTable(_ flows: [PlanFlow], context: PlanContext) -> some View {
        Table(flows, selection: $selectedFlows) {
            TableColumn("Date") { flow in
                Text(flow.date, format: .dateTime.day().month(.abbreviated).year())
                    .fontWeight(.medium)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Origine") { flow in
                originCell(flow, type: context.type)
            }
            .width(min: 150, ideal: 190)

            TableColumn("Montant") { flow in
                amountCell(flow, currency: context.currency)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Compartiment") { flow in
                Text(flow.isContribution ? (flow.origin?.perCompartment.displayName ?? "—") : "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Déduit") { flow in
                if flow.isContribution, flow.origin == .voluntary {
                    Text(flow.isDeducted ? "Oui" : "Non")
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 50, ideal: 70)

            TableColumn("Sortie") { flow in
                Text(flow.isContribution ? (flow.origin?.perCompartment.exitMode ?? "Capital ou rente") : "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: PlanFlow.ID.self) { ids in
            contributionMenu(ids, flows: flows)
        } primaryAction: { ids in
            editContribution(ids, flows: flows)
        }
    }

    @ViewBuilder
    private func originCell(_ flow: PlanFlow, type: AccountType) -> some View {
        if flow.isInitialBalance {
            Label("Solde initial", systemImage: "flag")
                .foregroundStyle(.secondary)
        } else if let origin = flow.origin {
            Label(origin.displayName(for: type), systemImage: origin.icon)
                .foregroundStyle(flow.hasDetail ? Color.primary : Color.secondary)
                .help(flow.hasDetail ? "" : "Origine déduite automatiquement : double-cliquez pour la préciser")
        } else {
            Label("Retrait / déblocage", systemImage: "arrow.up.right")
        }
    }

    private func amountCell(_ flow: PlanFlow, currency: String) -> some View {
        Text(PlanFormat.signed(flow.amount, currency))
            .monospacedDigit()
            .foregroundStyle(flow.amount >= 0 ? Color.primary : Color.red)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .privacyBlur(hidden: appSettings.hideAmounts)
    }

    @ViewBuilder
    private func stateCell(_ flow: PlanFlow) -> some View {
        if flow.isContribution {
            if let date = flow.availableOn, date <= Date() {
                Text("Disponible").foregroundStyle(.green)
            } else {
                Text("Bloqué").foregroundStyle(.secondary)
            }
        }
    }

    private func availabilityText(_ flow: PlanFlow, kind: SavingsPlanPageKind) -> String {
        guard flow.isContribution else { return "—" }
        if kind == .article83 {
            return flow.origin == .voluntary ? "Retraite, capital après transfert" : "Retraite, en rente"
        }
        guard let date = flow.availableOn else { return "Retraite" }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    @ViewBuilder
    private func contributionMenu(_ ids: Set<PlanFlow.ID>, flows: [PlanFlow]) -> some View {
        if let id = ids.first,
           let flow = flows.first(where: { $0.id == id }),
           flow.isContribution, flow.transactionID != nil {
            Button("Modifier l’apport…") {
                activeSheet = .editContribution(flow)
            }
        }
    }

    private func editContribution(_ ids: Set<PlanFlow.ID>, flows: [PlanFlow]) {
        if let id = ids.first,
           let flow = flows.first(where: { $0.id == id }),
           flow.isContribution, flow.transactionID != nil {
            activeSheet = .editContribution(flow)
        }
    }

    // MARK: Relevés de valeur

    private struct ValuationLine: Identifiable {
        var id: UUID { snapshot.id }
        let snapshot: ValuationSnapshot
        let invested: Decimal
        let change: String?

        var gain: Decimal { snapshot.value - invested }
    }

    private func valuationLines(_ context: PlanContext) -> [ValuationLine] {
        let sorted = context.snapshots.sorted { $0.date < $1.date }
        let suffix = context.kind == .article83 ? "hors cotisations" : "hors apports"

        var lines: [ValuationLine] = []
        for index in sorted.indices {
            let snapshot = sorted[index]
            var change: String? = nil
            if index > 0, let performance = RetirementPlanAnalytics.performance(from: sorted[index - 1], to: snapshot, flows: context.flows) {
                change = PlanFormat.percent(performance.ratio, signed: true) + (performance.hasFlows ? " \(suffix)" : "")
            }
            lines.append(ValuationLine(
                snapshot: snapshot,
                invested: SavingsPlanCalculator.invested(flows: context.flows, at: snapshot.date),
                change: change
            ))
        }
        return lines.reversed()
    }

    @ViewBuilder
    private func valuationsTab(_ context: PlanContext) -> some View {
        let lines = valuationLines(context)
        let currency = context.currency
        let investedTitle: String = context.kind == .article83 ? "Cotisations nettes" : "Versements nets"

        if lines.isEmpty {
            TopEmptyState(
                systemImage: "camera",
                title: "Aucune valeur relevée",
                message: "Reportez la valeur de votre dernier relevé pour suivre la performance du plan. En attendant, la valeur affichée correspond aux versements.",
                actionTitle: "Mettre à jour la valeur",
                action: { activeSheet = .newValuation }
            )
        } else {
            Table(lines, selection: $selectedSnapshots) {
                TableColumn("Date du relevé") { line in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.snapshot.date, format: .dateTime.day().month(.abbreviated).year())
                            .fontWeight(.medium)
                        if let note = line.snapshot.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 110, ideal: 140)

                TableColumn("Valeur") { line in
                    Text(PlanFormat.money(line.snapshot.value, currency))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }

                TableColumn(investedTitle) { line in
                    Text(PlanFormat.money(line.invested, currency))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }

                TableColumn("Plus-value") { line in
                    Text(PlanFormat.signed(line.gain, currency))
                        .monospacedDigit()
                        .foregroundStyle(line.gain >= 0 ? Color.green : Color.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }

                TableColumn("Depuis le relevé précédent") { line in
                    Text(line.change ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(line.change.map { $0.hasPrefix("-") || $0.hasPrefix("−") ? Color.red : Color.green } ?? .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .contextMenu(forSelectionType: ValuationSnapshot.ID.self) { ids in
                if let id = ids.first, let line = lines.first(where: { $0.id == id }) {
                    Button("Modifier…") { activeSheet = .editValuation(line.snapshot) }
                    Button("Supprimer…", role: .destructive) { snapshotToDelete = line.snapshot }
                }
            } primaryAction: { ids in
                if let id = ids.first, let line = lines.first(where: { $0.id == id }) {
                    activeSheet = .editValuation(line.snapshot)
                }
            }
        }
    }
}

/// Hauteur naturelle de la zone haute de la page d'un plan
private struct PlanTopHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
