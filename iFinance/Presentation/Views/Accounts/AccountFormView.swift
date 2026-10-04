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
    @State private var iban: String
    @State private var bic: String
    @State private var isExcludedFromReports: Bool
    @State private var initialBalanceDate: Date
    @State private var isHiddenFromSidebar: Bool
    @State private var isExcludedFromBudgets: Bool
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
        _iban = State(initialValue: accountToEdit?.iban ?? "")
        _bic = State(initialValue: accountToEdit?.bic ?? "")
        _isExcludedFromReports = State(initialValue: accountToEdit?.isExcludedFromReports ?? false)
        _initialBalanceDate = State(initialValue: accountToEdit?.initialBalanceDate ?? accountToEdit?.createdAt ?? Date())
        _isHiddenFromSidebar = State(initialValue: accountToEdit?.isHiddenFromSidebar ?? false)
        _isExcludedFromBudgets = State(initialValue: accountToEdit?.isExcludedFromBudgets ?? false)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête de feuille
            VStack(alignment: .leading, spacing: 2) {
                Text(accountToEdit == nil ? "Nouveau compte" : "Modifier le compte")
                    .font(.headline)

                if let book = bookController.currentBook {
                    Text("Ajouté au livre « \(book.name) ». Le solde est tenu à la main ou par import de fichier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Formulaire groupé : étiquettes à gauche, contrôles à droite
            Form {
                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(AccountGroup.allCases, id: \.self) { group in
                            Section(group.displayName) {
                                ForEach(group.types, id: \.self) { type in
                                    Label(type.displayName, systemImage: type.icon)
                                        .tag(type)
                                }
                            }
                        }
                    }

                    TextField("Nom", text: $name, prompt: Text("Nom du compte"))

                    TextField("Établissement", text: $bank, prompt: Text("Facultatif"))
                }

                Section {
                    Picker("Devise", selection: $currency) {
                        ForEach(availableCurrencies, id: \.self) { curr in
                            Text(curr).tag(curr)
                        }
                    }

                    TextField("Solde initial", text: $initialBalance, prompt: Text("0,00"))
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    DatePicker("Date du solde", selection: $initialBalanceDate, displayedComponents: .date)
                }

                Section("Coordonnées bancaires") {
                    TextField("IBAN", text: $iban, prompt: Text("Facultatif"))

                    TextField("BIC", text: $bic, prompt: Text("Facultatif"))
                }

                Section {
                    Toggle("Inclure dans le patrimoine net", isOn: inverted($isExcludedFromReports))

                    Toggle("Afficher dans la barre latérale", isOn: inverted($isHiddenFromSidebar))

                    Toggle(isOn: $isExcludedFromBudgets) {
                        Text("Compte hors budget")
                        Text("Ses dépenses ne consomment pas les budgets.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Boutons : action par défaut à droite
            HStack(spacing: 8) {
                Spacer()

                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(accountToEdit == nil ? "Créer" : "Enregistrer") {
                    saveAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 700)
    }

    /// Options affichées à l'endroit (« inclure », « afficher ») mais stockées à l'envers
    private func inverted(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { !binding.wrappedValue },
            set: { binding.wrappedValue = !$0 }
        )
    }

    private func saveAccount() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let bookID = bookController.currentBook?.id else { return }
        
        let balance = Decimal(string: initialBalance.replacingOccurrences(of: ",", with: ".")) ?? 0
        
        isCreating = true
        
        Task {
            if let existingAccount = accountToEdit {
                var updated = existingAccount
                updated.name = name
                updated.bank = bank.isEmpty ? nil : bank
                updated.type = selectedType
                updated.initialBalance = balance
                updated.currency = currency
                updated.iban = iban.isEmpty ? nil : iban
                updated.bic = bic.isEmpty ? nil : bic
                updated.isExcludedFromReports = isExcludedFromReports
                updated.initialBalanceDate = initialBalanceDate
                updated.isHiddenFromSidebar = isHiddenFromSidebar
                updated.isExcludedFromBudgets = isExcludedFromBudgets

                await accountsController.updateAccount(updated)
            } else {
                await accountsController.createAccount(
                    bookID: bookID,
                    name: name,
                    bank: bank.isEmpty ? nil : bank,
                    type: selectedType,
                    initialBalance: balance,
                    currency: currency,
                    iban: iban.isEmpty ? nil : iban,
                    bic: bic.isEmpty ? nil : bic,
                    isExcludedFromReports: isExcludedFromReports,
                    initialBalanceDate: initialBalanceDate,
                    isHiddenFromSidebar: isHiddenFromSidebar,
                    isExcludedFromBudgets: isExcludedFromBudgets
                )
            }
            
            isPresented = false
        }
    }
}
