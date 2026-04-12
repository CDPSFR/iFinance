import SwiftUI

struct AccountFormView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @Binding var isPresented: Bool
    
    var accountToEdit: Account?
    
    @State private var name: String
    @State private var bank: String
    @State private var selectedType: AccountType
    @State private var initialBalance: String
    @State private var currency: String
    @State private var isCreating = false
    
    let availableCurrencies = ["EUR", "USD", "GBP", "CHF", "CAD", "JPY", "AUD"]
    
    init(isPresented: Binding<Bool>, accountToEdit: Account? = nil) {
        self._isPresented = isPresented
        self.accountToEdit = accountToEdit
        
        // Initialiser les states
        _name = State(initialValue: accountToEdit?.name ?? "")
        _bank = State(initialValue: accountToEdit?.bank ?? "")
        _selectedType = State(initialValue: accountToEdit?.type ?? .checking)
        _initialBalance = State(initialValue: accountToEdit != nil ? "\(accountToEdit!.initialBalance)" : "0")
        _currency = State(initialValue: accountToEdit?.currency ?? "EUR")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(accountToEdit == nil ? "Nouveau Compte" : "Modifier le compte")
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
                Section {
                    TextField("Nom du compte", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Banque (optionnel)", text: $bank)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section {
                    Picker("Type de compte", selection: $selectedType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section {
                    HStack {
                        Text("Solde initial")
                        Spacer()
                        TextField("0.00", text: $initialBalance)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Devise", selection: $currency) {
                        ForEach(availableCurrencies, id: \.self) { curr in
                            Text(curr).tag(curr)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            // Boutons
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(accountToEdit == nil ? "Créer" : "Modifier") {
                    saveAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private func saveAccount() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let bookID = bookController.currentBook?.id else { return }
        
        let balance = Decimal(string: initialBalance.replacingOccurrences(of: ",", with: ".")) ?? 0
        
        isCreating = true
        
        Task {
            if let existingAccount = accountToEdit {
                // Modification
                var updated = existingAccount
                updated.name = name
                updated.bank = bank.isEmpty ? nil : bank
                updated.type = selectedType
                updated.initialBalance = balance
                updated.currency = currency
                
                await accountsController.updateAccount(updated)
            } else {
                // Création
                await accountsController.createAccount(
                    bookID: bookID,
                    name: name,
                    bank: bank.isEmpty ? nil : bank,
                    type: selectedType,
                    initialBalance: balance,
                    currency: currency
                )
            }
            
            isPresented = false
        }
    }
}
