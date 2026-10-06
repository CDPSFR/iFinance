import SwiftUI

/// Choix d'une catégorie pour plusieurs éléments (transactions ou bénéficiaires).
/// `optionTitle` affiche une case à cocher dont l'état est transmis à `onApply`.
struct BulkCategorizeView: View {
    let subtitle: String
    @Binding var isPresented: Bool
    var optionTitle: String? = nil
    let onApply: (UUID?, Bool) -> Void

    @State private var isOptionOn = true

    @EnvironmentObject var categoriesController: CategoriesController

    @State private var searchQuery = ""
    @State private var selectedCategoryID: UUID? = nil

    private var allCategories: [Category] {
        categoriesController.categories.sorted {
            categoriesController.getCategoryPath(for: $0.id) <
            categoriesController.getCategoryPath(for: $1.id)
        }
    }

    private var filtered: [Category] {
        guard !searchQuery.isEmpty else { return allCategories }
        return allCategories.filter {
            categoriesController.getCategoryPath(for: $0.id)
                .localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var expenses: [Category] { filtered.filter { !$0.isIncome } }
    private var incomes: [Category]  { filtered.filter {  $0.isIncome } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Catégoriser",
                subtitle: subtitle
            )

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Rechercher…", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            // Category list
            List(selection: $selectedCategoryID) {
                // "Aucune catégorie" option
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray))
                    Text("Aucune catégorie")
                        .foregroundColor(.secondary)
                }
                .tag(nil as UUID?)

                if !expenses.isEmpty {
                    Section("Dépenses") {
                        ForEach(expenses) { category in
                            categoryRow(category)
                                .tag(category.id as UUID?)
                        }
                    }
                }

                if !incomes.isEmpty {
                    Section("Revenus") {
                        ForEach(incomes) { category in
                            categoryRow(category)
                                .tag(category.id as UUID?)
                        }
                    }
                }
            }
            .listStyle(.inset)

            if let optionTitle {
                Divider()
                Toggle(optionTitle, isOn: $isOptionOn)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }

            // Pied : rappel de la catégorie choisie à gauche
            SheetFooter {
                if let id = selectedCategoryID,
                   let category = categoriesController.getCategory(id: id) {
                    HStack(spacing: 6) {
                        Image(systemName: category.displayIcon)
                            .foregroundColor(Color(hex: category.displayColor))
                        Text(categoriesController.getCategoryPath(for: id))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } actions: {
                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("Appliquer") {
                    onApply(selectedCategoryID, optionTitle != nil && isOptionOn)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCategoryID == nil && !canApplyNone)
            }
        }
        .frame(width: 480, height: 520)
        .sheetBackground()
    }

    // Allow applying "no category" only when explicitly selecting the nil row
    private var canApplyNone: Bool { false }

    @ViewBuilder
    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.displayIcon)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: category.displayColor))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.body)
                if let parentID = category.parentID,
                   let parent = categoriesController.getCategory(id: parentID) {
                    Text(parent.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
