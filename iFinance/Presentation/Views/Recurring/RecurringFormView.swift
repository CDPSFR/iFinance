import SwiftUI

/// Création ou modification d'une récurrence.
/// `prefill` préremplit le formulaire depuis une transaction (« Rendre récurrente… »).
struct RecurringFormView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
    @Binding var isPresented: Bool

    var templateToEdit: RecurringTemplate?

    @State private var type: TransactionType
    @State private var amount: String
    @State private var accountID: UUID?
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

    private static let controlWidth: CGFloat = 260

    init(isPresented: Binding<Bool>, templateToEdit: RecurringTemplate? = nil, prefill: Transaction? = nil) {
        self._isPresented = isPresented
        self.templateToEdit = templateToEdit

        if let template = templateToEdit {
            _type = State(initialValue: template.type)
            _amount = State(initialValue: Self.text(template.amount))
            _accountID = State(initialValue: template.accountID)
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
            let sourceType: TransactionType = source?.type == .credit ? .credit : .debit
            _type = State(initialValue: sourceType)
            _amount = State(initialValue: source.map { Self.text(abs($0.amount)) } ?? "")
            _accountID = State(initialValue: source?.accountID)
            _payeeID = State(initialValue: source?.payeeID)
            _categoryID = State(initialValue: source?.categoryID)
            _memo = State(initialValue: source?.memo ?? "")
            _frequency = State(initialValue: .monthly)
            // Depuis une transaction : la prochaine échéance est un mois après celle-ci
            let first = source.map { RecurrenceFrequency.monthly.next(after: $0.date) } ?? Date()
            _nextDueDate = State(initialValue: first)
            _hasEndDate = State(initialValue: false)
            _endDate = State(initialValue: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
            _autoPost = State(initialValue: false)
            _isVariableAmount = State(initialValue: false)
        }
    }

    private var isEditing: Bool { templateToEdit != nil }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isEditing ? "Modifier la récurrence" : "Nouvelle récurrence",
                subtitle: "Chaque échéance devient une transaction une fois validée."
            )

            Form {
                Section {
                    Picker("Type", selection: $type) {
                        Text("Dépense").tag(TransactionType.debit)
                        Text("Revenu").tag(TransactionType.credit)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent(isVariableAmount ? "Montant estimé" : "Montant") {
                        TextField("Montant", text: $amount, prompt: Text("0,00"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: Self.controlWidth)
                    }

                    Toggle("Montant variable", isOn: $isVariableAmount)
                }

                Section {
                    LabeledContent("Compte") {
                        Picker("Compte", selection: $accountID) {
                            Text("Choisir…").tag(UUID?.none)
                            ForEach(accountsController.activeAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: Self.controlWidth)
                    }

                    LabeledContent("Bénéficiaire") {
                        Picker("Bénéficiaire", selection: $payeeID) {
                            Text("Aucun").tag(UUID?.none)
                            ForEach(payeesController.payees.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { payee in
                                Text(payee.name).tag(Optional(payee.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: Self.controlWidth)
                    }
                    .onChange(of: payeeID) { _, newValue in
                        // Proposer la catégorie par défaut du bénéficiaire
                        if categoryID == nil, let newValue,
                           let suggestion = payeesController.getDefaultCategory(for: newValue) {
                            categoryID = suggestion
                        }
                    }

                    LabeledContent("Catégorie") {
                        Picker("Catégorie", selection: $categoryID) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(categoryChoices, id: \.id) { choice in
                                Text(choice.path).tag(Optional(choice.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: Self.controlWidth)
                    }

                    LabeledContent("Note") {
                        TextField("Note", text: $memo, prompt: Text("Facultatif"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: Self.controlWidth)
                    }
                }

                Section {
                    LabeledContent("Répéter") {
                        Picker("Répéter", selection: $frequency) {
                            ForEach(frequencyChoices, id: \.self) { choice in
                                Text(choice.displayName).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .frame(width: Self.controlWidth)
                    }

                    LabeledContent("Prochaine échéance") {
                        DatePicker("Prochaine échéance", selection: $nextDueDate, displayedComponents: [.date])
                            .labelsHidden()
                            .frame(width: Self.controlWidth, alignment: .leading)
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
                } footer: {
                    Text(autoPost
                         ? "La transaction est créée automatiquement le jour de l'échéance."
                         : "L'échéance apparaît dans « À venir » et reste affichée jusqu'à ce que vous la validiez ou la passiez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                if isEditing {
                    Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                }
            } actions: {
                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Enregistrer" : "Créer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
        }
        .frame(width: 520, height: 640)
        .sheetBackground()
        .onAppear {
            if accountID == nil {
                accountID = accountsController.selectedAccount?.id ?? accountsController.activeAccounts.first?.id
            }
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

    // MARK: - Choix

    private var frequencyChoices: [RecurrenceFrequency] {
        var choices = RecurrenceFrequency.offered
        if !choices.contains(frequency) { choices.insert(frequency, at: 0) }
        return choices
    }

    private var categoryChoices: [(id: UUID, path: String)] {
        let pool = type == .credit ? categoriesController.incomeCategories : categoriesController.expenseCategories
        var ids = pool.map { $0.id }
        if let categoryID, !ids.contains(categoryID) { ids.append(categoryID) }
        return ids
            .map { (id: $0, path: categoriesController.getCategoryPath(for: $0)) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
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
        template.payeeID = payeeID
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
