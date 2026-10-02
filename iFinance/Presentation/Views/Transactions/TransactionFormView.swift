import SwiftUI

struct TransactionFormView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
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
    @State private var isCreating = false
    
    // Pour la création rapide de payee
    @State private var showQuickPayeeCreate = false
    @State private var quickPayeeName = ""
    
    init(isPresented: Binding<Bool>, transactionToEdit: Transaction? = nil) {
        self._isPresented = isPresented
        self.transactionToEdit = transactionToEdit
        
        // Initialisation des valeurs
        if let transaction = transactionToEdit {
            _date = State(initialValue: transaction.date)
            _amount = State(initialValue: "\(abs(transaction.amount))")
            _selectedType = State(initialValue: transaction.type)
            _memo = State(initialValue: transaction.memo ?? "")
            _selectedAccount = State(initialValue: transaction.accountID)
            _selectedToAccount = State(initialValue: transaction.toAccountID)
            _selectedPayee = State(initialValue: transaction.payeeID)
            _selectedCategory = State(initialValue: transaction.categoryID)
        } else {
            _date = State(initialValue: Date())
            _amount = State(initialValue: "")
            _selectedType = State(initialValue: .debit)
            _memo = State(initialValue: "")
            _selectedAccount = State(initialValue: nil)
            _selectedToAccount = State(initialValue: nil)
            _selectedPayee = State(initialValue: nil)
            _selectedCategory = State(initialValue: nil)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(transactionToEdit == nil ? "Nouvelle transaction" : "Modifier la transaction")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Formulaire
            Form {
                // Type, date, montant, comptes
                Section {
                    FillSegmentedPicker(
                        options: TransactionType.allCases.map { ($0, $0.displayName) },
                        selection: $selectedType
                    )
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedType) { oldValue, newValue in
                        // Réinitialiser certains champs selon le type
                        if newValue != .transfer {
                            selectedToAccount = nil
                        }

                        // Pour debit/credit, réinitialiser la catégorie si elle ne correspond pas au type
                        if newValue != .transfer {
                            if let catID = selectedCategory,
                               let category = categoriesController.getCategory(id: catID) {
                                let shouldBeIncome = newValue == .credit
                                if category.isIncome != shouldBeIncome {
                                    selectedCategory = nil
                                }
                            }
                        }
                    }

                    formRow("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                        Spacer()
                    }

                    formRow("Montant") {
                        TextField("Montant", text: $amount, prompt: Text("0,00"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }

                    if selectedType == .transfer {
                        accountPicker("Compte source", selection: $selectedAccount, accounts: accountsController.activeAccounts)

                        accountPicker(
                            "Compte destination",
                            selection: $selectedToAccount,
                            accounts: accountsController.activeAccounts.filter { $0.id != selectedAccount }
                        )
                    } else {
                        accountPicker("Compte", selection: $selectedAccount, accounts: accountsController.activeAccounts)
                    }
                }

                // Bénéficiaire (sauf pour transferts)
                if selectedType != .transfer {
                    Section("Bénéficiaire") {
                        HStack {
                            FillPopUpPicker(items: payeeItems, selection: $selectedPayee)
                                .frame(maxWidth: .infinity)
                            .onChange(of: selectedPayee) { oldValue, newValue in
                                // Auto-suggérer la catégorie si le payee en a une par défaut
                                if let payeeID = newValue,
                                   let defaultCat = payeesController.getDefaultCategory(for: payeeID) {
                                    selectedCategory = defaultCat
                                }
                            }

                            // Bouton création rapide
                            Button {
                                showQuickPayeeCreate.toggle()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Créer un nouveau bénéficiaire rapidement")
                        }

                        // Création rapide de payee
                        if showQuickPayeeCreate {
                            HStack {
                                TextField("Nom du bénéficiaire", text: $quickPayeeName)
                                    .textFieldStyle(.roundedBorder)

                                Button("Créer") {
                                    createQuickPayee()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(quickPayeeName.trimmingCharacters(in: .whitespaces).isEmpty)

                                Button("Annuler") {
                                    showQuickPayeeCreate = false
                                    quickPayeeName = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Info si payee sélectionné
                        if let payeeID = selectedPayee,
                           let payee = payeesController.getPayee(id: payeeID),
                           payee.locationDisplay != nil || payee.defaultCategoryID != nil {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.caption)

                                VStack(alignment: .leading, spacing: 2) {
                                    if let location = payee.locationDisplay {
                                        Text(location)
                                    }

                                    if let catID = payee.defaultCategoryID,
                                       categoriesController.getCategory(id: catID) != nil {
                                        Text("Catégorie par défaut : \(categoriesController.getCategoryPath(for: catID))")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)

                                Spacer()
                            }
                        }
                    }
                }

                // Catégorie (y compris pour transferts)
                Section("Catégorie") {
                    let filteredCategories: [Category] = selectedType == .transfer
                        ? categoriesController.rootCategories
                        : categoriesController.rootCategories.filter {
                            $0.isIncome == (selectedType == .credit)
                        }

                    FillPopUpPicker(items: categoryItems(filteredCategories), selection: $selectedCategory)
                        .frame(maxWidth: .infinity)

                    // Aperçu catégorie sélectionnée
                    if let catID = selectedCategory,
                       let category = categoriesController.getCategory(id: catID) {
                        HStack {
                            if let iconName = category.icon {
                                Image(systemName: iconName)
                                    .foregroundColor(Color(hex: category.displayColor))
                            }
                            Text(categoriesController.getCategoryPath(for: catID))
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }

                // Mémo
                Section("Mémo") {
                    TextField("Mémo", text: $memo, prompt: Text("Ajouter une note (optionnel)"), axis: .vertical)
                        .lineLimit(3...6)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)

            // Boutons
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(transactionToEdit == nil ? "Créer" : "Modifier") {
                    saveTransaction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 800)
        .onChange(of: selectedAccount) { _, newValue in
            // Source et destination d'un transfert doivent différer
            if selectedToAccount == newValue {
                selectedToAccount = nil
            }
        }
        .onAppear {
            // Mode création uniquement : sélectionner le compte par défaut
            guard transactionToEdit == nil, selectedAccount == nil else { return }
            if let filteredAccountID = transactionsController.filters.accountID {
                selectedAccount = filteredAccountID
            } else if let defaultAccount = accountsController.selectedAccount?.id {
                selectedAccount = defaultAccount
            } else if let firstAccount = accountsController.activeAccounts.first?.id {
                selectedAccount = firstAccount
            }
        }
    }

    /// Sélecteur de compte : propose « Sélectionner… » tant qu'aucun compte valide n'est choisi
    private func accountPicker(_ title: String, selection: Binding<UUID?>, accounts: [Account]) -> some View {
        let needsPlaceholder = selection.wrappedValue == nil || !accounts.contains { $0.id == selection.wrappedValue }
        let items = (needsPlaceholder ? [FillPopUpItem<UUID>(id: nil, title: "Sélectionner…")] : [])
            + accounts.map { FillPopUpItem(id: $0.id, title: $0.name, systemImage: $0.type.icon) }

        return formRow(title) {
            FillPopUpPicker(items: items, selection: selection)
                .frame(maxWidth: .infinity)
        }
    }

    private var payeeItems: [FillPopUpItem<UUID>] {
        [FillPopUpItem(id: nil, title: "Aucun")]
            + payeesController.payees.map { payee in
                FillPopUpItem(id: payee.id, title: payee.locationDisplay.map { "\(payee.name) (\($0))" } ?? payee.name)
            }
    }

    /// Catégories racines suivies de leurs sous-catégories, indentées
    private func categoryItems(_ roots: [Category]) -> [FillPopUpItem<UUID>] {
        var items = [FillPopUpItem<UUID>(id: nil, title: "Aucune")]
        for category in roots {
            items.append(FillPopUpItem(id: category.id, title: category.name, systemImage: category.icon ?? "folder"))
            for sub in categoriesController.getSubcategories(for: category.id) {
                items.append(FillPopUpItem(id: sub.id, title: sub.name, systemImage: sub.icon ?? "folder", indentationLevel: 1))
            }
        }
        return items
    }

    /// Ligne de formulaire : libellé en colonne fixe, contrôle sur toute la largeur restante
    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            content()
        }
    }

    private var isFormValid: Bool {
        guard !amount.isEmpty,
              Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) != nil else {
            return false
        }
        
        if selectedType == .transfer {
            return selectedAccount != nil && selectedToAccount != nil
        }
        
        return selectedAccount != nil
    }
    
    private func createQuickPayee() {
        guard !quickPayeeName.trimmingCharacters(in: .whitespaces).isEmpty,
              let bookID = accountsController.selectedAccount?.bookID else {
            return
        }
        
        Task {
            await payeesController.createPayee(
                bookID: bookID,
                name: quickPayeeName,
                defaultCategoryID: selectedCategory
            )
            
            // Sélectionner le nouveau payee
            if let newPayee = payeesController.payees.first(where: { $0.name == quickPayeeName }) {
                selectedPayee = newPayee.id
            }
            
            // Réinitialiser
            showQuickPayeeCreate = false
            quickPayeeName = ""
        }
    }
    
    private func saveTransaction() {
        guard let amountDecimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")),
              let accountID = selectedAccount else {
            return
        }
        
        isCreating = true
        
        Task {
            if selectedType == .transfer, let toAccountID = selectedToAccount {
                if let existingTransaction = transactionToEdit {
                    // Modification d'un transfert existant : mettre à jour la catégorie des deux transactions liées
                    await transactionsController.updateTransfer(existingTransaction, categoryID: selectedCategory)
                } else {
                    // Création d'un nouveau transfert
                    await transactionsController.createTransfer(
                        from: accountID,
                        to: toAccountID,
                        amount: amountDecimal,
                        date: date,
                        memo: memo.isEmpty ? nil : memo,
                        categoryID: selectedCategory
                    )
                }
            } else {
                if let existingTransaction = transactionToEdit {
                    // Modification d'une transaction non-transfert
                    var updated = existingTransaction
                    updated.date = date
                    updated.amount = abs(amountDecimal)
                    updated.type = selectedType
                    updated.memo = memo.isEmpty ? nil : memo
                    updated.accountID = accountID
                    updated.payeeID = selectedPayee
                    updated.categoryID = selectedCategory

                    await transactionsController.updateTransaction(updated)
                } else {
                    // Création d'une transaction non-transfert
                    await transactionsController.createTransaction(
                        accountID: accountID,
                        date: date,
                        amount: abs(amountDecimal),
                        type: selectedType,
                        payeeID: selectedPayee,
                        categoryID: selectedCategory,
                        memo: memo.isEmpty ? nil : memo
                    )
                }
            }
            
            // Recharger les transactions
            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
            
            isPresented = false
        }
    }
}
