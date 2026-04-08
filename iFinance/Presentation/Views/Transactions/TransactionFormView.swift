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
                Text(transactionToEdit == nil ? "Nouvelle Transaction" : "Modifier la Transaction")
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
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Section Type
                    GroupBox {
                        VStack(spacing: 12) {
                            Picker("Type", selection: $selectedType) {
                                ForEach(TransactionType.allCases, id: \.self) { type in
                                    HStack {
                                        Text(type.displayName)
                                    }
                                    .tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedType) { oldValue, newValue in
                                // Réinitialiser certains champs selon le type
                                if newValue != .transfer {
                                    selectedToAccount = nil
                                }
                                
                                // Filtrer les catégories selon le type
                                if newValue == .transfer {
                                    selectedCategory = nil
                                } else {
                                    // Si la catégorie actuelle ne correspond pas au type, réinitialiser
                                    if let catID = selectedCategory,
                                       let category = categoriesController.getCategory(id: catID) {
                                        let shouldBeIncome = newValue == .credit
                                        if category.isIncome != shouldBeIncome {
                                            selectedCategory = nil
                                        }
                                    }
                                }
                            }
                            
                            // Comptes pour transfert
                            if selectedType == .transfer {
                                Picker("Compte source", selection: Binding(
                                    get: { selectedAccount ?? accountsController.activeAccounts.first?.id ?? UUID() },
                                    set: { selectedAccount = $0 }
                                )) {
                                    ForEach(accountsController.activeAccounts) { account in
                                        Text(account.name).tag(account.id)
                                    }
                                }
                                
                                Picker("Compte destination", selection: $selectedToAccount) {
                                    Text("Sélectionner...").tag(nil as UUID?)
                                    ForEach(accountsController.activeAccounts.filter { $0.id != selectedAccount }) { account in
                                        Text(account.name).tag(account.id as UUID?)
                                    }
                                }
                            }
                        }
                    }
                    
                        
                    // Section Date et Montant
                    GroupBox {
                        VStack(spacing: 12) {
                            
                            HStack {
                                Text("Date")
                                Spacer()
                                DatePicker("", selection: $date, displayedComponents: [.date])
                            }
                            
                            HStack {
                                Text("Montant")
                                Spacer()
                                TextField("0.00", text: $amount)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            if selectedType != .transfer {
                                Picker("Compte", selection: Binding(
                                    get: { selectedAccount ?? accountsController.activeAccounts.first?.id ?? UUID() },
                                    set: { selectedAccount = $0 }
                                )) {
                                    ForEach(accountsController.activeAccounts) { account in
                                        Text(account.name).tag(account.id)
                                    }
                                }
                            }
                        }
                    }
                    
                    
                    
                    // Section Bénéficiaire (sauf pour transferts)
                    if selectedType != .transfer {
                        GroupBox(label: Label("Bénéficiaire", systemImage: "person.crop.circle")) {
                            VStack(spacing: 12) {
                                HStack {
                                    Picker("", selection: $selectedPayee) {
                                        Text("Aucun").tag(nil as UUID?)
                                        
                                        ForEach(payeesController.payees) { payee in
                                            HStack {
                                                Text(payee.name)
                                                if let location = payee.locationDisplay {
                                                    Text("(\(location))")
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .tag(payee.id as UUID?)
                                        }
                                    }
                                    .labelsHidden()
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
                                   let payee = payeesController.getPayee(id: payeeID) {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let location = payee.locationDisplay {
                                                Text(location)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            if let catID = payee.defaultCategoryID,
                                               let category = categoriesController.getCategory(id: catID) {
                                                Text("Catégorie par défaut : \(categoriesController.getCategoryPath(for: catID))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(Color.blue.opacity(0.05))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Section Catégorie (sauf pour transferts)
                    if selectedType != .transfer {
                        GroupBox(label: Label("Catégorie", systemImage: "folder")) {
                            VStack(spacing: 8) {

                                let filteredCategories = categoriesController.rootCategories.filter {
                                    $0.isIncome == (selectedType == .credit)
                                }

                                Picker("", selection: $selectedCategory) {
                                    Text("Aucune").tag(nil as UUID?)

                                    ForEach(filteredCategories) { category in
                                        // Catégorie parent — label simple
                                        Label(category.name, systemImage: category.icon ?? "folder")
                                            .tag(category.id as UUID?)

                                        // Sous-catégories — préfixer le nom avec le chemin
                                        ForEach(categoriesController.getSubcategories(for: category.id)) { sub in
                                            Label(
                                                "   \(sub.name)",   // indentation visuelle dans la liste
                                                systemImage: sub.icon ?? "folder"
                                            )
                                            .tag(sub.id as UUID?)
                                        }
                                    }
                                }
                                .labelsHidden()
                                
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
                                    .padding(8)
                                    .background(Color(hex: category.displayColor).opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Section Mémo
                    GroupBox(label: Label("Mémo", systemImage: "note.text")) {
                        TextField("Ajouter une note (optionnel)", text: $memo, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }
                }
                .padding()
            }
            
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
            .padding()
        }
        .padding()
        .frame(width: 600, height: 700)
        .onAppear {
            // CORRECTION ICI : Prendre en compte le filtre actif
            if let transaction = transactionToEdit {
                // Mode édition : utiliser les données de la transaction
                date = transaction.date
                amount = "\(abs(transaction.amount))"
                selectedType = transaction.type
                memo = transaction.memo ?? ""
                selectedAccount = transaction.accountID
                selectedToAccount = transaction.toAccountID
                selectedPayee = transaction.payeeID
                selectedCategory = transaction.categoryID
            } else if selectedAccount == nil {
                // Mode création : utiliser le filtre actif s'il existe
                if let filteredAccountID = transactionsController.filters.accountID {
                    // Si un filtre de compte est actif, l'utiliser
                    selectedAccount = filteredAccountID
                } else if let defaultAccount = accountsController.selectedAccount?.id {
                    // Sinon utiliser le compte par défaut du controller
                    selectedAccount = defaultAccount
                } else if let firstAccount = accountsController.activeAccounts.first?.id {
                    // En dernier recours, prendre le premier compte actif
                    selectedAccount = firstAccount
                }
            }
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
                // Créer un transfert
                await transactionsController.createTransfer(
                    from: accountID,
                    to: toAccountID,
                    amount: amountDecimal,
                    date: date,
                    memo: memo.isEmpty ? nil : memo
                )
            } else {
                // Calculer le montant signé
                let signedAmount: Decimal
                switch selectedType {
                case .debit:
                    signedAmount = -abs(amountDecimal)
                case .credit:
                    signedAmount = abs(amountDecimal)
                case .transfer:
                    signedAmount = amountDecimal
                }
                
                if let existingTransaction = transactionToEdit {
                    // Modification
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
                    // Création
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
