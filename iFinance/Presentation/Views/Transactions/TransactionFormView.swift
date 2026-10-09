import SwiftUI

/// Création ou modification d'une transaction.
/// Tous les contrôles partagent une colonne de 260 points, alignée à droite ; les lignes
/// Bénéficiaire, Catégorie et Projet ont un bouton « + » pour créer l'élément à la volée.
struct TransactionFormView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var projectsController: ProjectsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var recurringController: RecurringController
    @Binding var isPresented: Bool

    var transactionToEdit: Transaction?

    @State private var date: Date
    @State private var amount: String
    @State private var selectedType: TransactionType
    @State private var memo: String
    @State private var selectedAccount: UUID?
    @State private var selectedToAccount: UUID?
    @State private var selectedPayee: UUID?
    @State private var selectedCategory: UUID?
    @State private var selectedProject: UUID?
    @State private var isReconciled: Bool
    @State private var isCreating = false
    @State private var createAnother = false
    /// Répétition (création seulement) : nil = jamais
    @State private var repeatFrequency: RecurrenceFrequency?
    @State private var repeatAutoPost = false
    @State private var repeatIsVariable = false
    /// Vrai quand la catégorie vient d'être proposée d'après le bénéficiaire
    @State private var categoryWasSuggested = false
    @State private var showDeleteConfirmation = false

    // Création à la volée : on retient les identifiants existants pour repérer le nouvel élément
    @State private var showPayeeForm = false
    @State private var showProjectForm = false
    @State private var knownIDs: Set<UUID> = []

    private static let controlWidth: CGFloat = 260

    init(isPresented: Binding<Bool>, transactionToEdit: Transaction? = nil) {
        self._isPresented = isPresented
        self.transactionToEdit = transactionToEdit

        if let transaction = transactionToEdit {
            _date = State(initialValue: transaction.date)
            _amount = State(initialValue: "\(abs(transaction.amount))".replacingOccurrences(of: ".", with: ","))
            _selectedType = State(initialValue: transaction.type)
            _memo = State(initialValue: transaction.memo ?? "")
            _selectedAccount = State(initialValue: transaction.accountID)
            _selectedToAccount = State(initialValue: transaction.toAccountID)
            _selectedPayee = State(initialValue: transaction.payeeID)
            _selectedCategory = State(initialValue: transaction.categoryID)
            _selectedProject = State(initialValue: transaction.projectID)
            _isReconciled = State(initialValue: transaction.isReconciled)
        } else {
            _date = State(initialValue: Date())
            _amount = State(initialValue: "")
            _selectedType = State(initialValue: .debit)
            _memo = State(initialValue: "")
            _selectedAccount = State(initialValue: nil)
            _selectedToAccount = State(initialValue: nil)
            _selectedPayee = State(initialValue: nil)
            _selectedCategory = State(initialValue: nil)
            _selectedProject = State(initialValue: nil)
            _isReconciled = State(initialValue: false)
        }
    }

    private var isEditing: Bool { transactionToEdit != nil }
    private var isTransfer: Bool { selectedType == .transfer }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Modifier la transaction" : "Nouvelle transaction")
                        .font(.headline)
                    Text("Livre « \(booksController.currentBook?.name ?? "") »")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                FillSegmentedPicker(
                    options: TransactionType.allCases.map { ($0, $0.displayName) },
                    selection: $selectedType
                )
                .frame(maxWidth: .infinity)
                // Le type d'un transfert existant ne se change pas (deux transactions liées)
                .disabled(isEditing && transactionToEdit?.type == .transfer)
                .onChange(of: selectedType) { _, newValue in
                    typeChanged(to: newValue)
                }

                amountField
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Form {
                Section {
                    LabeledContent("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                            .frame(width: Self.controlWidth, alignment: .leading)
                    }

                    accountPicker(
                        isTransfer ? "Depuis le compte" : "Compte",
                        selection: $selectedAccount,
                        accounts: accountsController.activeAccounts
                    )

                    if isTransfer {
                        accountPicker(
                            "Vers le compte",
                            selection: $selectedToAccount,
                            accounts: accountsController.activeAccounts.filter { $0.id != selectedAccount }
                        )
                    }
                }

                Section {
                    if !isTransfer {
                        LabeledContent("Bénéficiaire") {
                            control(addHelp: "Nouveau bénéficiaire") {
                                FillPopUpPicker(items: payeeItems, selection: $selectedPayee)
                            } add: {
                                knownIDs = Set(payeesController.payees.map { $0.id })
                                showPayeeForm = true
                            }
                        }
                        .onChange(of: selectedPayee) { _, newValue in
                            // Proposer la catégorie par défaut du bénéficiaire
                            if let payeeID = newValue,
                               let defaultCategory = payeesController.getDefaultCategory(for: payeeID) {
                                selectedCategory = defaultCategory
                                categoryWasSuggested = true
                            }
                        }
                    }

                    LabeledContent {
                        CategoryPicker(
                            selection: $selectedCategory,
                            kind: isTransfer ? .all : CategoryPicker.Kind(isIncome: selectedType == .credit),
                            width: Self.controlWidth,
                            onCreate: { _ in categoryWasSuggested = false }
                        )
                    } label: {
                        Text("Catégorie")
                        if categoryWasSuggested, selectedCategory != nil {
                            Text("Proposée d'après le bénéficiaire")
                        }
                    }

                    if !isTransfer {
                        LabeledContent("Projet") {
                            control(addHelp: "Nouveau projet") {
                                FillPopUpPicker(items: projectItems, selection: $selectedProject)
                            } add: {
                                knownIDs = Set(projectsController.projects.map { $0.id })
                                showProjectForm = true
                            }
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

                    if !isTransfer {
                        Toggle("Rapprochée avec le relevé", isOn: $isReconciled)
                    }
                }

                // Répétition : proposée à la création, transferts compris
                if !isEditing {
                    Section {
                        LabeledContent("Répéter") {
                            Picker("Répéter", selection: $repeatFrequency) {
                                Text("Jamais").tag(RecurrenceFrequency?.none)
                                ForEach(RecurrenceFrequency.offered, id: \.self) { frequency in
                                    Text(frequency.displayName).tag(Optional(frequency))
                                }
                            }
                            .labelsHidden()
                            .frame(width: Self.controlWidth)
                        }

                        if repeatFrequency != nil {
                            Picker("À l'échéance", selection: $repeatAutoPost) {
                                Text("Me demander").tag(false)
                                Text("Saisir seule").tag(true)
                            }
                            .pickerStyle(.segmented)

                            Toggle("Montant variable", isOn: $repeatIsVariable)
                        }
                    } footer: {
                        if let repeatHint {
                            Text(repeatHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 8) {
                if isEditing {
                    Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                } else {
                    Toggle("Créer une autre ensuite", isOn: $createAnother)
                        .toggleStyle(.checkbox)
                }

                Spacer()

                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Enregistrer" : "Créer") {
                    saveTransaction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid || isCreating)
            }
            .padding(12)
        }
        .frame(width: 520, height: 640)
        .sheetBackground()
        .onChange(of: selectedAccount) { _, newValue in
            // Source et destination d'un transfert doivent différer
            if selectedToAccount == newValue {
                selectedToAccount = nil
            }
        }
        .onChange(of: selectedCategory) { oldValue, newValue in
            // Un choix manuel efface la mention « proposée »
            if oldValue != nil, newValue != oldValue, selectedPayee.flatMap({ payeesController.getDefaultCategory(for: $0) }) != newValue {
                categoryWasSuggested = false
            }
        }
        .onAppear(perform: selectDefaultAccount)
        .sheet(isPresented: $showPayeeForm, onDismiss: {
            if let created = payeesController.payees.first(where: { !knownIDs.contains($0.id) }) {
                selectedPayee = created.id
            }
        }) {
            PayeeFormView(isPresented: $showPayeeForm)
        }
        .sheet(isPresented: $showProjectForm, onDismiss: {
            if let created = projectsController.projects.first(where: { !knownIDs.contains($0.id) }) {
                selectedProject = created.id
            }
        }) {
            ProjectFormView(isPresented: $showProjectForm)
        }
        .alert("Supprimer la transaction ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                guard let id = transactionToEdit?.id else { return }
                Task {
                    await transactionsController.deleteTransaction(id: id)
                    await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                    isPresented = false
                }
            }
        } message: {
            Text(transactionToEdit?.type == .transfer
                 ? "Les deux côtés du transfert seront supprimés. Cette action est irréversible."
                 : "Cette action est irréversible.")
        }
    }

    // MARK: - Montant

    private var currencySymbol: String {
        let code = selectedAccount.flatMap { accountsController.getAccount(id: $0)?.currency }
            ?? booksController.currentBook?.currency ?? "EUR"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    /// Montant en grand, centré, avec le signe du type et la devise
    private var amountField: some View {
        let color: Color = selectedType == .credit ? .green : .primary
        let sign = selectedType == .credit ? "+" : (isTransfer ? "" : "−")

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sign)
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)

            TextField("Montant", text: $amount, prompt: Text("0,00"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 210)
                // Le montant d'un transfert existant ne se modifie pas ici
                .disabled(isEditing && transactionToEdit?.type == .transfer)

            Text(currencySymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
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

    /// Sélecteur de compte : propose « Sélectionner… » tant qu'aucun compte valide n'est choisi
    private func accountPicker(_ title: String, selection: Binding<UUID?>, accounts: [Account]) -> some View {
        let needsPlaceholder = selection.wrappedValue == nil || !accounts.contains { $0.id == selection.wrappedValue }
        let items = (needsPlaceholder ? [FillPopUpItem<UUID>(id: nil, title: "Sélectionner…")] : [])
            + accounts.map { FillPopUpItem(id: $0.id, title: $0.name, systemImage: $0.type.icon) }

        return LabeledContent(title) {
            FillPopUpPicker(items: items, selection: selection)
                .frame(width: Self.controlWidth)
                // Les comptes d'un transfert existant ne se modifient pas ici
                .disabled(isEditing && transactionToEdit?.type == .transfer)
        }
    }

    private var payeeItems: [FillPopUpItem<UUID>] {
        [FillPopUpItem(id: nil, title: "Aucun")]
            + payeesController.payees.map { payee in
                FillPopUpItem(id: payee.id, title: payee.locationDisplay.map { "\(payee.name) (\($0))" } ?? payee.name)
            }
    }

    private var projectItems: [FillPopUpItem<UUID>] {
        [FillPopUpItem<UUID>(id: nil, title: "Aucun")]
            + projectsController.selectableProjects(including: selectedProject).map {
                FillPopUpItem(id: $0.id, title: $0.name, systemImage: "folder")
            }
    }

    // MARK: - Logique

    private func typeChanged(to newValue: TransactionType) {
        if newValue != .transfer {
            selectedToAccount = nil
            // La catégorie doit correspondre au sens (dépense ou revenu)
            if let categoryID = selectedCategory,
               let category = categoriesController.getCategory(id: categoryID),
               category.isIncome != (newValue == .credit) {
                selectedCategory = nil
                categoryWasSuggested = false
            }
        } else {
            selectedPayee = nil
            selectedProject = nil
            categoryWasSuggested = false
        }
    }

    /// Mode création : compte filtré à l'écran, sinon compte courant, sinon premier compte
    private func selectDefaultAccount() {
        guard transactionToEdit == nil, selectedAccount == nil else { return }
        if let filteredAccountID = transactionsController.filters.accountID {
            selectedAccount = filteredAccountID
        } else if let defaultAccount = accountsController.selectedAccount?.id {
            selectedAccount = defaultAccount
        } else if let firstAccount = accountsController.activeAccounts.first?.id {
            selectedAccount = firstAccount
        }
    }

    /// Ce qui se passera à la prochaine échéance, quand une répétition est choisie
    private var repeatHint: String? {
        guard let frequency = repeatFrequency else { return nil }
        let next = frequency.next(after: date, anchorDay: Calendar.current.component(.day, from: date))
        let day = next.formatted(.dateTime.day().month(.wide).year())
        return repeatAutoPost
            ? "Cette transaction est enregistrée maintenant. La suivante sera saisie automatiquement le \(day)."
            : "Cette transaction est enregistrée maintenant. La suivante apparaîtra dans « À venir » le \(day), pour validation."
    }

    private var parsedAmount: Decimal? {
        let cleaned = amount
            .replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace && $0 != "\u{202F}" && $0 != "\u{00A0}" }
        return Decimal(string: cleaned)
    }

    private var isFormValid: Bool {
        guard let value = parsedAmount, value != 0 else { return false }
        if isTransfer {
            return selectedAccount != nil && selectedToAccount != nil
        }
        return selectedAccount != nil
    }

    private func saveTransaction() {
        guard let amountDecimal = parsedAmount, let accountID = selectedAccount else { return }
        let note = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = true

        Task {
            if isTransfer, let toAccountID = selectedToAccount {
                if let existing = transactionToEdit {
                    // Transfert existant : seule la catégorie des deux transactions liées est mise à jour
                    await transactionsController.updateTransfer(existing, categoryID: selectedCategory)
                } else if let (source, destination) = await transactionsController.createTransfer(
                    from: accountID,
                    to: toAccountID,
                    amount: amountDecimal,
                    date: date,
                    memo: note.isEmpty ? nil : note,
                    categoryID: selectedCategory
                ), let frequency = repeatFrequency, let bookID = booksController.currentBook?.id {
                    // Virement répété : ce virement est la première échéance, la récurrence part de la suivante
                    let calendar = Calendar.current
                    let anchorDay = calendar.component(.day, from: date)
                    let template = RecurringTemplate(
                        bookID: bookID,
                        accountID: accountID,
                        toAccountID: toAccountID,
                        categoryID: selectedCategory,
                        amount: abs(amountDecimal),
                        type: .transfer,
                        memo: note.isEmpty ? nil : note,
                        frequency: frequency,
                        startDate: date,
                        dayOfMonth: anchorDay,
                        dayOfWeek: calendar.component(.weekday, from: date),
                        nextDueDate: frequency.next(after: date, anchorDay: anchorDay),
                        autoPost: repeatAutoPost,
                        isVariableAmount: repeatIsVariable
                    )
                    await recurringController.create(template)
                    for var leg in [source, destination] {
                        leg.recurringTemplateID = template.id
                        await transactionsController.updateTransaction(leg)
                    }
                }
            } else if let existing = transactionToEdit {
                var updated = existing
                updated.date = date
                updated.amount = abs(amountDecimal)
                updated.type = selectedType
                updated.memo = note.isEmpty ? nil : note
                updated.accountID = accountID
                updated.payeeID = selectedPayee
                updated.categoryID = selectedCategory
                updated.projectID = selectedProject
                updated.isReconciled = isReconciled
                await transactionsController.updateTransaction(updated)
            } else if var created = await transactionsController.createTransaction(
                accountID: accountID,
                date: date,
                amount: abs(amountDecimal),
                type: selectedType,
                payeeID: selectedPayee,
                categoryID: selectedCategory,
                memo: note.isEmpty ? nil : note
            ) {
                // Répétition : cette transaction est la première échéance, la récurrence part de la suivante
                var recurringID: UUID?
                if let frequency = repeatFrequency, let bookID = booksController.currentBook?.id {
                    let calendar = Calendar.current
                    let anchorDay = calendar.component(.day, from: date)
                    let template = RecurringTemplate(
                        bookID: bookID,
                        accountID: accountID,
                        payeeID: selectedPayee,
                        categoryID: selectedCategory,
                        amount: abs(amountDecimal),
                        type: selectedType,
                        memo: note.isEmpty ? nil : note,
                        frequency: frequency,
                        startDate: date,
                        dayOfMonth: anchorDay,
                        dayOfWeek: calendar.component(.weekday, from: date),
                        nextDueDate: frequency.next(after: date, anchorDay: anchorDay),
                        autoPost: repeatAutoPost,
                        isVariableAmount: repeatIsVariable
                    )
                    await recurringController.create(template)
                    recurringID = template.id
                }

                // Projet, rapprochement et récurrence ne font pas partie de la création : on complète aussitôt
                if selectedProject != nil || isReconciled || recurringID != nil {
                    created.projectID = selectedProject
                    created.isReconciled = isReconciled
                    created.recurringTemplateID = recurringID
                    await transactionsController.updateTransaction(created)
                }
            }

            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
            isCreating = false

            if createAnother, !isEditing {
                // On garde le type, la date, le compte et le projet pour enchaîner les saisies
                amount = ""
                memo = ""
                selectedPayee = nil
                selectedCategory = nil
                categoryWasSuggested = false
                isReconciled = false
                repeatFrequency = nil
            } else {
                isPresented = false
            }
        }
    }
}
