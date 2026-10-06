import SwiftUI

/// Page « Récurrent » : échéances à traiter et à venir, et liste des récurrences
struct RecurringView: View {
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    enum Tab: String, CaseIterable, Identifiable {
        case upcoming = "À venir"
        case templates = "Toutes les récurrences"

        var id: String { rawValue }
    }

    @State private var tab: Tab = .upcoming
    @State private var showForm = false
    @State private var templateToEdit: RecurringTemplate?
    @State private var templateToDelete: RecurringTemplate?
    @State private var showDeleteConfirmation = false
    @State private var occurrenceToValidate: RecurringOccurrence?

    var body: some View {
        VStack(spacing: 0) {
            if recurringController.templates.isEmpty {
                ContentUnavailableView {
                    Label("Aucune récurrence", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Loyer, salaire, abonnements : enregistrez-les une fois, leurs échéances vous sont proposées à chaque période.")
                } actions: {
                    Button("Nouvelle récurrence") { showForm = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                        tiles

                        Picker("Affichage", selection: $tab) {
                            ForEach(Tab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 320)

                        switch tab {
                        case .upcoming: upcomingList
                        case .templates: templateList
                        }
                    }
                    .padding(NativeMetrics.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showForm = true
                } label: {
                    Label("Nouvelle récurrence", systemImage: "plus.circle")
                }
                .help("Nouvelle récurrence")
            }
        }
        .sheet(isPresented: $showForm) {
            RecurringFormView(isPresented: $showForm)
        }
        .sheet(item: $templateToEdit) { template in
            RecurringFormView(
                isPresented: Binding(
                    get: { templateToEdit != nil },
                    set: { if !$0 { templateToEdit = nil } }
                ),
                templateToEdit: template
            )
        }
        .sheet(item: $occurrenceToValidate) { occurrence in
            RecurringValidateView(occurrence: occurrence)
        }
        .alert("Supprimer la récurrence ?", isPresented: $showDeleteConfirmation, presenting: templateToDelete) { template in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await recurringController.delete(id: template.id) }
            }
        } message: { _ in
            Text("Les transactions déjà validées sont conservées.")
        }
    }

    // MARK: - Chiffres clés

    private var tiles: some View {
        let charges = recurringController.monthlyCharges
        let income = recurringController.monthlyIncome
        let active = recurringController.templates.filter { $0.isActive }
        let due = recurringController.dueCount
        let late = recurringController.lateCount

        return ReportTiles {
            StatTile(
                title: "Charges récurrentes",
                value: money(charges),
                detail: "par mois, \(countText(active.filter { $0.type == .debit }.count))"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Revenus récurrents",
                value: money(income),
                valueColor: income > 0 ? .green : .primary,
                detail: "par mois, \(countText(active.filter { $0.type == .credit }.count))"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Reste après charges",
                value: money(income - charges),
                valueColor: income - charges < 0 ? .red : .primary,
                detail: "par mois"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "À traiter",
                value: "\(due)",
                valueColor: late > 0 ? .red : .primary,
                detail: late > 0 ? "dont \(late) en retard" : "échéances arrivées à terme"
            )
        }
    }

    private func countText(_ count: Int) -> String {
        count > 1 ? "\(count) récurrences" : "\(count) récurrence"
    }

    // MARK: - À venir

    private var upcomingList: some View {
        let occurrences = recurringController.occurrences()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("À traiter et à venir")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(RecurringController.horizonDays) prochains jours · une échéance ne compte dans les soldes qu'une fois validée")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if occurrences.isEmpty {
                Text("Aucune échéance dans les \(RecurringController.horizonDays) prochains jours.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .cardBackground()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
                        if index > 0 { Divider() }
                        occurrenceRow(occurrence)
                    }
                }
                .cardBackground()
            }
        }
    }

    private func occurrenceRow(_ occurrence: RecurringOccurrence) -> some View {
        let template = occurrence.template

        return HStack(spacing: 12) {
            Text(occurrence.dueLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(occurrence.isLate ? Color.red : (occurrence.daysFromToday() <= 3 ? Color.accentColor : Color.secondary))
                .frame(width: 96, alignment: .leading)

            Text(occurrence.date, format: .dateTime.day().month(.abbreviated))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(payeeName(template))
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(categoryName(template))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(accountName(template))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            Text(money(template.signedAmount))
                .monospacedDigit()
                .foregroundStyle(template.type == .credit ? Color.green : Color.primary)
                .frame(width: 100, alignment: .trailing)
                .privacyBlur(hidden: appSettings.hideAmounts)

            RecurringOccurrenceActions(
                occurrence: occurrence,
                onValidate: { validate(occurrence) },
                onEdit: { occurrenceToValidate = occurrence },
                onSkip: { Task { await recurringController.skip(occurrence) } }
            )
            .frame(width: 230, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
    }

    private func validate(_ occurrence: RecurringOccurrence) {
        // Montant variable : on demande le montant réel avant de créer la transaction
        if occurrence.template.isVariableAmount {
            occurrenceToValidate = occurrence
            return
        }
        Task {
            await recurringController.validate(occurrence)
            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
        }
    }

    // MARK: - Toutes les récurrences

    private var templateList: some View {
        let templates = recurringController.templates.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return abs($0.monthlyAmount) > abs($1.monthlyAmount)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Récurrences")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("double-clic pour modifier · clic droit pour suspendre ou supprimer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    if index > 0 { Divider() }
                    templateRow(template)
                }
            }
            .cardBackground()
        }
    }

    private func templateRow(_ template: RecurringTemplate) -> some View {
        HStack(spacing: 12) {
            Text(payeeName(template))
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(categoryName(template))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Text(accountName(template))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Text(template.isActive ? template.ruleText : "Suspendue")
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text(template.isActive ? template.nextDueDate.formatted(.dateTime.day().month(.abbreviated).year()) : "—")
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(template.autoPost ? "Automatique" : "À valider")
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Text(money(template.signedAmount))
                .monospacedDigit()
                .foregroundStyle(template.type == .credit ? Color.green : Color.primary)
                .frame(width: 96, alignment: .trailing)
                .privacyBlur(hidden: appSettings.hideAmounts)

            Text(template.isActive ? money(template.monthlyAmount) : "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)
                .privacyBlur(hidden: appSettings.hideAmounts)
                .help("Équivalent mensuel")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .opacity(template.isActive ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { templateToEdit = template }
        .contextMenu {
            Button("Modifier…") { templateToEdit = template }
            Button(template.isActive ? "Suspendre" : "Reprendre") {
                Task { await recurringController.setActive(!template.isActive, for: template) }
            }
            Divider()
            Button("Supprimer…", role: .destructive) {
                templateToDelete = template
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Libellés

    private func payeeName(_ template: RecurringTemplate) -> String {
        template.payeeID.flatMap { payeesController.getPayee(id: $0)?.name } ?? template.memo ?? "Sans bénéficiaire"
    }

    private func categoryName(_ template: RecurringTemplate) -> String {
        template.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "—"
    }

    private func accountName(_ template: RecurringTemplate) -> String {
        accountsController.getAccount(id: template.accountID)?.name ?? "—"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: booksController.currentBook?.currency ?? "EUR"))
    }
}
