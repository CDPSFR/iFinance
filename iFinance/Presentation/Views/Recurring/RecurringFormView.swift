import SwiftUI

/// Création ou modification d'une récurrence.
/// `prefill` préremplit le formulaire depuis une transaction (« Rendre récurrente… »).
/// Même présentation que TransactionFormView : type, montant en grand, colonne de 260 points.
struct RecurringFormView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var transactionsController: TransactionsController
    @Binding var isPresented: Bool

    var templateToEdit: RecurringTemplate?

    @State private var type: TransactionType
    @State private var amount: String
    @State private var accountID: UUID?
    /// Compte de destination d'un virement
    @State private var toAccountID: UUID?
    @State private var payeeID: UUID?
    @State private var categoryID: UUID?
    @State private var memo: String
    @State private var frequency: RecurrenceFrequency
    @State private var nextDueDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var autoPost: Bool
    @State private var isVariableAmount: Bool
    @State private var showDeleteConfirmation = false
    /// Vrai quand la catégorie vient d'être proposée d'après le bénéficiaire
    @State private var categoryWasSuggested = false

    // Création à la volée : on retient les identifiants existants pour repérer le nouvel élément
    @State private var showPayeeForm = false
    @State private var showCategoryForm = false
    @State private var knownIDs: Set<UUID> = []

    private static let controlWidth: CGFloat = 260

    init(isPresented: Binding<Bool>, templateToEdit: RecurringTemplate? = nil, prefill: Transaction? = nil) {
        self._isPresented = isPresented
        self.templateToEdit = templateToEdit

        if let template = templateToEdit {
            _type = State(initialValue: template.type)
            _amount = State(initialValue: Self.text(template.amount))
            _accountID = State(initialValue: template.accountID)
            _toAccountID = State(initialValue: template.toAccountID)
            _payeeID = State(initialValue: template.payeeID)
            _categoryID = State(initialValue: template.categoryID)
            _memo = State(initialValue: template.memo ?? "")
            _frequency = State(initialValue: template.frequency)
            _nextDueDate = State(initialValue: template.nextDueDate)
            _hasEndDate = State(initialValue: template.endDate != nil)
            _endDate = State(initialValue: template.endDate ?? Date())
            _autoPost = State(initialValue: template.autoPost)
            _isVariableAmount = State(initialValue: template.isVariableAmount)
        } else {
            let source = prefill
            _type = State(initialValue: source?.type ?? .debit)
            _amount = State(initialValue: source.map { Self.text(abs($0.amount)) } ?? "")
            if let source, source.isTransfer {
                // Depuis l'un ou l'autre côté d'un virement : l'origine est le côté débité
                let isSourceSide = source.amount < 0
                _accountID = State(initialValue: isSourceSide ? source.accountID : source.toAccountID)
                _toAccountID = State(initialValue: isSourceSide ? source.toAccountID : source.accountID)
            } else {
                _accountID = State(initialValue: source?.accountID)
                _toAccountID = State(initialValue: nil)
            }
            _payeeID = State(initialValue: source?.payeeID)
            _categoryID = State(initialValue: source?.categoryID)
            _memo = State(initialValue: source?.memo ?? "")
            _frequency = State(initialValue: .monthly)
            // Depuis une transaction : la prochaine échéance est un mois après celle-ci
            let first = Calendar.current.startOfDay(for: source.map { RecurrenceFrequency.monthly.next(after: $0.date) } ?? Date())
            _nextDueDate = State(initialValue: first)
            _hasEndDate = State(initialValue: false)
            _endDate = State(initialValue: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
            _autoPost = State(initialValue: false)
            _isVariableAmount = State(initialValue: false)
        }
    }

    private var isEditing: Bool { templateToEdit != nil }
    private var isTransfer: Bool { type == .transfer }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Modifier la récurrence" : "Nouvelle récurrence")
                        .font(.headline)
                    Text("Livre « \(booksController.currentBook?.name ?? "") » · chaque échéance devient une transaction une fois validée")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                FillSegmentedPicker(
                    options: [(TransactionType.debit, TransactionType.debit.displayName),
                              (TransactionType.credit, TransactionType.credit.displayName),
                              (TransactionType.transfer, TransactionType.transfer.displayName)],
                    selection: $type
                )
                .frame(maxWidth: .infinity)
                .onChange(of: type) { _, newValue in
                    typeChanged(to: newValue)
                }

                amountField
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Form {
                Section {
                    LabeledContent("Prochaine échéance") {
                        DatePicker("Prochaine échéance", selection: $nextDueDate, displayedComponents: [.date])
                            .labelsHidden()
                            .frame(width: Self.controlWidth, alignment: .leading)
                    }

                    accountPicker(
                        isTransfer ? "Depuis le compte" : "Compte",
                        selection: $accountID,
                        accounts: accountsController.activeAccounts
                    )

                    if isTransfer {
                        accountPicker(
                            "Vers le compte",
                            selection: $toAccountID,
                            accounts: accountsController.activeAccounts.filter { $0.id != accountID }
                        )
                    }
                }

                Section {
                    if !isTransfer {
                        LabeledContent("Bénéficiaire") {
                            control(addHelp: "Nouveau bénéficiaire") {
                                FillPopUpPicker(items: payeeItems, selection: $payeeID)
                            } add: {
                                knownIDs = Set(payeesController.payees.map { $0.id })
                                showPayeeForm = true
                            }
                        }
                        .onChange(of: payeeID) { _, newValue in
                            // Proposer la catégorie par défaut du bénéficiaire
                            if let newValue, let suggestion = payeesController.getDefaultCategory(for: newValue) {
                                categoryID = suggestion
                                categoryWasSuggested = true
                            }
                        }
                    }

                    LabeledContent {
                        control(addHelp: "Nouvelle catégorie") {
                            FillPopUpPicker(items: categoryItems, selection: $categoryID)
                        } add: {
                            knownIDs = Set(categoriesController.categories.map { $0.id })
                            showCategoryForm = true
                        }
                    } label: {
                        Text("Catégorie")
                        if categoryWasSuggested, categoryID != nil {
                            Text("Proposée d'après le bénéficiaire")
                        }
                    }
                }

                Section {
                    LabeledContent("Note") {
                        TextField("Note", text: $memo, prompt: Text("Facultatif"), axis: .vertical)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2...4)
                            .frame(width: Self.controlWidth)
                    }
                }

                Section {
                    LabeledContent("Répéter") {
                        FillPopUpPicker(
                            items: frequencyChoices.map { FillPopUpItem<RecurrenceFrequency>(id: $0, title: $0.displayName) },
                            selection: Binding(get: { frequency }, set: { if let value = $0 { frequency = value } })
                        )
                        .frame(width: Self.controlWidth)
                    }

                    Toggle("Date de fin", isOn: $hasEndDate)

                    if hasEndDate {
                        LabeledContent("Se termine le") {
                            DatePicker("Se termine le", selection: $endDate, in: nextDueDate..., displayedComponents: [.date])
                                .labelsHidden()
                                .frame(width: Self.controlWidth, alignment: .leading)
                        }
                    }

                    Picker("À l'échéance", selection: $autoPost) {
                        Text("Me demander").tag(false)
                        Text("Saisir seule").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Montant variable", isOn: $isVariableAmount)
                } footer: {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 8) {
                if isEditing {
                    Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                }

                Spacer()

                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Enregistrer" : "Créer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
            .padding(12)
        }
        .frame(width: 520, height: 640)
        .sheetBackground()
        .onAppear {
            if accountID == nil {
                accountID = transactionsController.filters.accountID
                    ?? accountsController.selectedAccount?.id
                    ?? accountsController.activeAccounts.first?.id
            }
        }
        .onChange(of: categoryID) { oldValue, newValue in
            // Un choix manuel efface la mention « proposée »
            if oldValue != nil, newValue != oldValue, payeeID.flatMap({ payeesController.getDefaultCategory(for: $0) }) != newValue {
                categoryWasSuggested = false
            }
        }
        .sheet(isPresented: $showPayeeForm, onDismiss: {
            if let created = payeesController.payees.first(where: { !knownIDs.contains($0.id) }) {
                payeeID = created.id
            }
        }) {
            PayeeFormView(isPresented: $showPayeeForm)
        }
        .sheet(isPresented: $showCategoryForm, onDismiss: {
            if let created = categoriesController.categories.first(where: { !knownIDs.contains($0.id) }) {
                categoryID = created.id
                categoryWasSuggested = false
            }
        }) {
            CategoryFormView(isPresented: $showCategoryForm, initialIsIncome: type == .credit)
        }
        .alert("Supprimer la récurrence ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                guard let template = templateToEdit else { return }
                Task {
                    await recurringController.delete(id: template.id)
                    isPresented = false
                }
            }
        } message: {
            Text("Les transactions déjà validées sont conservées.")
        }
    }

    // MARK: - Montant

    private var currencySymbol: String {
        let code = accountID.flatMap { accountsController.getAccount(id: $0)?.currency }
            ?? booksController.currentBook?.currency ?? "EUR"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    /// Montant en grand, centré, avec le signe du type et la devise (comme une transaction)
    private var amountField: some View {
        let color: Color = type == .credit ? .green : .primary
        let sign: String
        switch type {
        case .credit: sign = "+"
        case .debit: sign = "−"
        case .transfer: sign = ""
        }

        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !sign.isEmpty {
                    Text(sign)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(color)
                }

                TextField("Montant", text: $amount, prompt: Text("0,00"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(width: 210)

                Text(currencySymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if isVariableAmount {
                Text("Montant estimé : le montant réel est demandé à chaque validation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - Lignes du formulaire

    /// Contrôle et son bouton « + », ensemble dans la colonne de 260 points
    private func control<Content: View>(
        addHelp: String,
        @ViewBuilder content: () -> Content,
        add: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            content()
                .frame(maxWidth: .infinity)

            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help(addHelp)
            .accessibilityLabel(addHelp)
        }
        .frame(width: Self.controlWidth)
    }

    /// Sélecteur de compte : « Sélectionner… » tant qu'aucun compte valide n'est choisi
    private func accountPicker(_ title: String, selection: Binding<UUID?>, accounts: [Account]) -> some View {
        let needsPlaceholder = selection.wrappedValue == nil || !accounts.contains { $0.id == selection.wrappedValue }
        let items = (needsPlaceholder ? [FillPopUpItem<UUID>(id: nil, title: "Sélectionner…")] : [])
            + accounts.map { FillPopUpItem(id: $0.id, title: $0.name, systemImage: $0.type.icon) }

        return LabeledContent(title) {
            FillPopUpPicker(items: items, selection: selection)
                .frame(width: Self.controlWidth)
        }
    }

    private var payeeItems: [FillPopUpItem<UUID>] {
        [FillPopUpItem(id: nil, title: "Aucun")]
            + payeesController.payees.map { payee in
                FillPopUpItem(id: payee.id, title: payee.locationDisplay.map { "\(payee.name) (\($0))" } ?? payee.name)
            }
    }

    /// Catégories du sens de la récurrence (toutes pour un virement), sous-catégories indentées
    private var categoryItems: [FillPopUpItem<UUID>] {
        let roots = isTransfer
            ? categoriesController.rootCategories
            : categoriesController.rootCategories.filter { $0.isIncome == (type == .credit) }
        var items = [FillPopUpItem<UUID>(id: nil, title: "Aucune")]
        for category in roots {
            items.append(FillPopUpItem(id: category.id, title: category.name, systemImage: category.icon ?? "folder"))
            for sub in categoriesController.getSubcategories(for: category.id) {
                items.append(FillPopUpItem(id: sub.id, title: sub.name, systemImage: sub.icon ?? "folder", indentationLevel: 1))
            }
        }
        return items
    }

    // MARK: - Logique

    /// La catégorie doit correspondre au sens (dépense ou revenu) ; un virement accepte toutes les catégories
    private func typeChanged(to newValue: TransactionType) {
        if newValue != .transfer,
           let categoryID,
           let category = categoriesController.getCategory(id: categoryID),
           category.isIncome != (newValue == .credit) {
            self.categoryID = nil
            categoryWasSuggested = false
        }
    }

    /// Ce qui se passera à l'échéance
    private var hint: String {
        let day = nextDueDate.formatted(.dateTime.day().month(.wide).year())
        let what = isTransfer ? "Le virement" : "La transaction"
        return autoPost
            ? "\(what) sera saisi\(isTransfer ? "" : "e") automatiquement le \(day), puis à chaque échéance."
            : "L'échéance du \(day) apparaîtra dans « À venir » jusqu'à ce que vous la validiez ou la passiez."
    }

    // MARK: - Choix

    private var frequencyChoices: [RecurrenceFrequency] {
        var choices = RecurrenceFrequency.offered
        if !choices.contains(frequency) { choices.insert(frequency, at: 0) }
        return choices
    }

    // MARK: - Enregistrement

    private static func text(_ amount: Decimal) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
    }

    private var parsedAmount: Decimal? {
        let cleaned = amount
            .replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace && $0 != "\u{202F}" && $0 != "\u{00A0}" }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var isFormValid: Bool {
        guard let value = parsedAmount, value != 0 else { return false }
        if isTransfer, toAccountID == nil || toAccountID == accountID { return false }
        return accountID != nil && booksController.currentBook != nil
    }

    private func save() {
        guard let value = parsedAmount, let accountID, let bookID = booksController.currentBook?.id else { return }
        let note = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current

        var template = templateToEdit ?? RecurringTemplate(
            bookID: bookID,
            accountID: accountID,
            amount: abs(value),
            type: type,
            frequency: frequency,
            startDate: nextDueDate
        )
        template.accountID = accountID
        template.toAccountID = isTransfer ? toAccountID : nil
        // Un virement n'a pas de bénéficiaire, comme une transaction de transfert
        template.payeeID = isTransfer ? nil : payeeID
        template.categoryID = categoryID
        template.amount = abs(value)
        template.type = type
        template.memo = note.isEmpty ? nil : note
        template.frequency = frequency
        template.nextDueDate = nextDueDate
        template.endDate = hasEndDate ? endDate : nil
        template.dayOfMonth = calendar.component(.day, from: nextDueDate)
        template.dayOfWeek = calendar.component(.weekday, from: nextDueDate)
        template.autoPost = autoPost
        template.isVariableAmount = isVariableAmount
        template.isActive = true

        Task {
            if isEditing {
                await recurringController.update(template)
            } else {
                await recurringController.create(template)
            }
            isPresented = false
        }
    }
}
