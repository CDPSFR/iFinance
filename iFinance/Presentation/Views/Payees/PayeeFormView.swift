import SwiftUI

struct PayeeFormView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    @Binding var isPresented: Bool
    
    var payeeToEdit: Payee?
    
    @State private var name: String
    @State private var city: String
    @State private var postalCode: String
    @State private var notes: String
    @State private var selectedCategory: UUID?
    @State private var isCreating = false
    
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
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(payeeToEdit == nil ? "Nouveau Bénéficiaire" : "Modifier le Bénéficiaire")
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
                    TextField("Nom du bénéficiaire", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Localisation") {
                    TextField("Ville (optionnel)", text: $city)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Code postal (optionnel)", text: $postalCode)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Catégorie par défaut") {
                    Picker("Catégorie", selection: $selectedCategory) {
                        Text("Aucune").tag(nil as UUID?)
                        
                        ForEach(categoriesController.rootCategories) { category in
                            Text(category.name).tag(category.id as UUID?)
                            
                            // Sous-catégories
                            ForEach(categoriesController.getSubcategories(for: category.id)) { sub in
                                Text("  \(sub.name)").tag(sub.id as UUID?)
                            }
                        }
                    }
                    
                    Text("Les transactions futures avec ce bénéficiaire utiliseront automatiquement cette catégorie")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Notes") {
                    TextField("Notes (optionnel)", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
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
                
                Button(payeeToEdit == nil ? "Créer" : "Modifier") {
                    savePayee()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 550)
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
                
                await payeesController.updatePayee(updated)
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
