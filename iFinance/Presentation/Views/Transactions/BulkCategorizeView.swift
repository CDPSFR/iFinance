import SwiftUI

struct BulkCategorizeView: View {
    let transactionIDs: Set<Transaction.ID>
    @Binding var isPresented: Bool
    let onApply: (UUID?) -> Void

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
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Catégoriser")
                        .font(.headline)
                    Text("\(transactionIDs.count) transaction(s) sélectionnée(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
            .padding(.horizontal)
            .padding(.vertical, 8)

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

            Divider()

            // Footer
            HStack {
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.bordered)

                Spacer()

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

                Button("Appliquer") {
                    onApply(selectedCategoryID)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCategoryID == nil && !canApplyNone)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
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
