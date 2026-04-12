import SwiftUI

struct BudgetFormView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var booksController: BooksController

    // Editing mode
    var budgetToEdit: Budget? = nil

    // Form state
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var period: BudgetPeriod = .monthly
    @State private var selectedCategoryIDs: Set<UUID> = []
    @State private var amount: String = ""
    @State private var anchorDate: Date = Date()

    private var isEditing: Bool { budgetToEdit != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "Modifier le budget" : "Nouveau budget")
                    .font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                // Name
                Section("Informations") {
                    TextField("Nom du budget", text: $name)
                    TextField("Note (optionnel)", text: $note)
                }

                // Period & Amount
                Section("Montant et période") {
                    Picker("Période", selection: $period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    HStack {
                        Text("Montant")
                        Spacer()
                        TextField("0,00", text: $amount)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    DatePicker(
                        "Date de début",
                        selection: $anchorDate,
                        displayedComponents: .date
                    )
                }

                // Categories
                Section("Catégories") {
                    if categoriesController.expenseCategories.isEmpty {
                        Text("Aucune catégorie de dépense disponible")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(categoriesController.expenseCategories) { parent in
                            categoryToggleRow(parent)
                            ForEach(categoriesController.getSubcategories(for: parent.id)) { sub in
                                categoryToggleRow(sub, indent: true)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(isEditing ? "Enregistrer" : "Créer") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 620)
        .onAppear { populateIfEditing() }
    }

    // MARK: - Category row

    @ViewBuilder
    private func categoryToggleRow(_ category: Category, indent: Bool = false) -> some View {
        HStack {
            if indent {
                Spacer().frame(width: 20)
            }
            if let icon = category.icon {
                Image(systemName: icon)
                    .foregroundColor(Color(hex: category.color ?? "#888888"))
                    .frame(width: 20)
            }
            Text(category.name)
            Spacer()
            if selectedCategoryIDs.contains(category.id) {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedCategoryIDs.contains(category.id) {
                selectedCategoryIDs.remove(category.id)
            } else {
                selectedCategoryIDs.insert(category.id)
            }
        }
    }

    // MARK: - Helpers

    private func populateIfEditing() {
        guard let b = budgetToEdit else { return }
        name = b.name
        note = b.note ?? ""
        period = b.period
        selectedCategoryIDs = Set(b.categoryIDs)
        anchorDate = b.anchorDate
        if let v = b.currentVersion {
            amount = "\(v.amount)"
        }
    }

    private func save() {
        guard let bookID = booksController.currentBook?.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let decimalAmount = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0

        Task {
            if let existing = budgetToEdit {
                var updated = existing
                updated.name = trimmedName
                updated.note = trimmedNote.isEmpty ? nil : trimmedNote
                updated.period = period
                updated.categoryIDs = Array(selectedCategoryIDs)
                updated.anchorDate = anchorDate
                await budgetsController.updateBudget(updated)
            } else {
                await budgetsController.createBudget(
                    bookID: bookID,
                    name: trimmedName,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    period: period,
                    categoryIDs: Array(selectedCategoryIDs),
                    anchorDate: anchorDate,
                    amount: decimalAmount
                )
            }
            isPresented = false
        }
    }
}
