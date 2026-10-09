import SwiftUI

struct PayeeFormView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @Binding var isPresented: Bool
    
    var payeeToEdit: Payee?
    
    @State private var name: String
    @State private var city: String
    @State private var postalCode: String
    @State private var notes: String
    @State private var selectedCategory: UUID?
    @State private var isCreating = false
    /// Effet du changement de catégorie par défaut sur les transactions existantes
    @State private var scope: PayeeTransactionScope = .uncategorized
    @State private var confirmOverwrite = false
    
    init(isPresented: Binding<Bool>, payeeToEdit: Payee? = nil) {
        self._isPresented = isPresented
        self.payeeToEdit = payeeToEdit
        
        _name = State(initialValue: payeeToEdit?.name ?? "")
        _city = State(initialValue: payeeToEdit?.city ?? "")
        _postalCode = State(initialValue: payeeToEdit?.postalCode ?? "")
        _notes = State(initialValue: payeeToEdit?.notes ?? "")
        _selectedCategory = State(initialValue: payeeToEdit?.defaultCategoryID)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête de feuille
            SheetHeader(
                title: payeeToEdit == nil ? "Nouveau bénéficiaire" : "Modifier le bénéficiaire",
                subtitle: payeeToEdit?.name
            )

            // Formulaire
            Form {
                Section {
                    TextField("Nom du bénéficiaire", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
                
                Section("Localisation") {
                    TextField("Ville (optionnel)", text: $city)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    
                    TextField("Code postal (optionnel)", text: $postalCode)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                }
                
                Section("Catégorie par défaut") {
                    LabeledContent("Catégorie") {
                        CategoryPicker(selection: $selectedCategory, width: 260)
                    }
                    
                    Text("Les transactions futures avec ce bénéficiaire utiliseront automatiquement cette catégorie")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Catégorie modifiée : que faire des transactions déjà saisies ?
                    if showsScope {
                        PayeeTransactionScopePicker(counts: counts, scope: $scope)
                            .padding(.vertical, 4)
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (optionnel)", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)

            // Boutons
            SheetFooter {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(payeeToEdit == nil ? "Créer" : "Enregistrer") {
                    // Écraser des catégories déjà choisies demande une confirmation
                    if showsScope, scope == .all, counts.recategorized > 0 {
                        confirmOverwrite = true
                    } else {
                        savePayee()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .frame(width: 520, height: showsScope ? 680 : 550)
        .sheetBackground()
        .alert(
            "\(counts.recategorized) transaction\(counts.recategorized > 1 ? "s vont" : " va") changer de catégorie",
            isPresented: $confirmOverwrite
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Appliquer à toutes") { savePayee() }
        } message: {
            Text("Leur catégorie actuelle sera remplacée. Cette action ne peut pas être annulée.")
        }
    }

    /// Transactions existantes du bénéficiaire, comptées pour la catégorie choisie
    private var counts: PayeeTransactionCounts {
        guard let payee = payeeToEdit else { return PayeeTransactionCounts() }
        return PayeeCategoryPropagation.counts(in: transactionsController.allTransactions, payeeIDs: [payee.id], categoryID: selectedCategory)
    }

    /// Le choix n'apparaît que si la catégorie par défaut change et que des transactions existent
    private var showsScope: Bool {
        guard let payee = payeeToEdit, selectedCategory != nil, selectedCategory != payee.defaultCategoryID else { return false }
        return counts.total > 0
    }
    
    private func savePayee() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let bookID = bookController.currentBook?.id else {
            return
        }
        
        isCreating = true
        
        Task {
            if let existingPayee = payeeToEdit {
                // Modification
                var updated = existingPayee
                updated.name = name
                updated.city = city.isEmpty ? nil : city
                updated.postalCode = postalCode.isEmpty ? nil : postalCode
                updated.notes = notes.isEmpty ? nil : notes
                updated.defaultCategoryID = selectedCategory

                let toUpdate = showsScope
                    ? PayeeCategoryPropagation.transactionsToUpdate(
                        in: transactionsController.allTransactions, payeeIDs: [existingPayee.id],
                        categoryID: selectedCategory, scope: scope)
                    : []
                await payeesController.updatePayee(updated)
                if !toUpdate.isEmpty {
                    await transactionsController.setCategory(selectedCategory, for: toUpdate)
                    await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                }
            } else {
                // Création
                await payeesController.createPayee(
                    bookID: bookID,
                    name: name,
                    city: city.isEmpty ? nil : city,
                    postalCode: postalCode.isEmpty ? nil : postalCode,
                    notes: notes.isEmpty ? nil : notes,
                    defaultCategoryID: selectedCategory
                )
            }
            
            isPresented = false
        }
    }
}
