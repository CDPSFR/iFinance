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

    private var currencySymbol: String {
        let code = booksController.currentBook?.currency ?? "EUR"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    /// Montant en grand, centré, avec la devise : même présentation que dans la fenêtre de transaction
    private var amountField: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("Montant", text: $amount, prompt: Text("0,00"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 210)

                Text(currencySymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Montant du budget · \(period.displayName.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            // En-tête de feuille
            SheetHeader(
                title: isEditing ? "Modifier le budget" : "Nouveau budget",
                subtitle: budgetToEdit?.name
            )

            amountField
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            Form {
                // Name
                Section("Informations") {
                    // Champs visibles, sur la même colonne de 260 points que les autres feuilles
                    LabeledContent("Nom du budget") {
                        TextField("Nom du budget", text: $name, prompt: Text("Alimentation"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                    }

                    LabeledContent("Note (optionnel)") {
                        TextField("Note", text: $note, prompt: Text("Facultatif"), axis: .vertical)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2...4)
                            .frame(width: 260)
                    }
                }

                // Period & Amount
                Section("Montant et période") {
                    Picker("Période", selection: $period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
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

            // Actions
            SheetFooter {
                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Enregistrer" : "Créer") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty)
            }
        }
        .frame(width: 520, height: 620)
        .sheetBackground()
        .onAppear { populateIfEditing() }
    }

    // MARK: - Category row

    @ViewBuilder
    private func categoryToggleRow(_ category: Category, indent: Bool = false) -> some View {
        // Même présentation que le choix de catégorie des formulaires : icône, nom, sous-catégorie indentée
        HStack(spacing: 8) {
            if indent {
                Spacer().frame(width: 16)
            }
            Image(systemName: category.icon ?? "folder")
                .foregroundColor(Color(hex: categoriesController.displayColor(of: category)))
                .frame(width: 20)
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
