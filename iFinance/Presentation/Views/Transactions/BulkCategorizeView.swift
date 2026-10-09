import SwiftUI

/// Choix d'une catégorie pour plusieurs éléments (transactions ou bénéficiaires).
/// `transactionCounts`, fourni pour des bénéficiaires, affiche le choix « Transactions existantes »
/// (compté pour la catégorie choisie) ; le choix est transmis à `onApply`.
struct BulkCategorizeView: View {
    let subtitle: String
    @Binding var isPresented: Bool
    var transactionCounts: ((UUID?) -> PayeeTransactionCounts)? = nil
    let onApply: (UUID?, PayeeTransactionScope) -> Void

    @State private var scope: PayeeTransactionScope = .uncategorized
    @State private var confirmOverwrite = false

    @EnvironmentObject var categoriesController: CategoriesController

    @State private var searchQuery = ""
    @State private var selectedCategoryID: UUID? = nil
    // Création d'une catégorie depuis la fenêtre (bouton « + »)
    @State private var showCategoryForm = false
    @State private var knownIDs: Set<UUID> = []

    /// Une catégorie et ses sous-catégories retenues par la recherche, comme dans le menu des formulaires
    private struct Group: Identifiable {
        let parent: Category
        let subcategories: [Category]
        var id: UUID { parent.id }
    }

    /// Catégories du sens demandé, chacune suivie de ses sous-catégories. Une recherche garde une
    /// catégorie si son nom correspond ou si l'une de ses sous-catégories correspond.
    private func groups(isIncome: Bool) -> [Group] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        func matches(_ category: Category) -> Bool {
            query.isEmpty || category.name.localizedCaseInsensitiveContains(query)
        }
        return categoriesController.rootCategories
            .filter { $0.isIncome == isIncome }
            .compactMap { parent in
                let subs = categoriesController.getSubcategories(for: parent.id)
                // Parent trouvé : toutes ses sous-catégories restent visibles
                let shownSubs = matches(parent) ? subs : subs.filter(matches)
                guard matches(parent) || !shownSubs.isEmpty else { return nil }
                return Group(parent: parent, subcategories: shownSubs)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Catégoriser",
                subtitle: subtitle
            )

            // Recherche, et création d'une catégorie
            HStack(spacing: 8) {
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

                Button {
                    knownIDs = Set(categoriesController.categories.map { $0.id })
                    showCategoryForm = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Nouvelle catégorie")
                .accessibilityLabel("Nouvelle catégorie")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            // Category list
            List(selection: $selectedCategoryID) {
                // "Aucune catégorie" option
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Aucune catégorie")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                .tag(nil as UUID?)

                ForEach([false, true], id: \.self) { isIncome in
                    let groups = groups(isIncome: isIncome)
                    if !groups.isEmpty {
                        Section(isIncome ? "Revenus" : "Dépenses") {
                            ForEach(groups) { group in
                                categoryRow(group.parent)
                                    .tag(group.parent.id as UUID?)
                                ForEach(group.subcategories) { sub in
                                    categoryRow(sub, indented: true)
                                        .tag(sub.id as UUID?)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            if let transactionCounts {
                Divider()
                PayeeTransactionScopePicker(counts: transactionCounts(selectedCategoryID), scope: $scope)
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
                    // Écraser des catégories déjà choisies demande une confirmation
                    if scope == .all, overwrittenCount > 0 {
                        confirmOverwrite = true
                    } else {
                        apply()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCategoryID == nil && !canApplyNone)
            }
        }
        .frame(width: 480, height: transactionCounts == nil ? 520 : 640)
        .sheetBackground()
        .sheet(isPresented: $showCategoryForm, onDismiss: {
            // La catégorie créée est sélectionnée
            if let created = categoriesController.categories.first(where: { !knownIDs.contains($0.id) }) {
                selectedCategoryID = created.id
            }
        }) {
            CategoryFormView(isPresented: $showCategoryForm)
        }
        .alert(
            "\(overwrittenCount) transaction\(overwrittenCount > 1 ? "s vont" : " va") changer de catégorie",
            isPresented: $confirmOverwrite
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Appliquer à toutes") { apply() }
        } message: {
            Text("Leur catégorie actuelle sera remplacée. Cette action ne peut pas être annulée.")
        }
    }

    /// Transactions déjà catégorisées autrement, que « toutes » remplacerait
    private var overwrittenCount: Int {
        transactionCounts?(selectedCategoryID).recategorized ?? 0
    }

    private func apply() {
        onApply(selectedCategoryID, transactionCounts == nil ? .none : scope)
        isPresented = false
    }

    // Allow applying "no category" only when explicitly selecting the nil row
    private var canApplyNone: Bool { false }

    /// Ligne de catégorie : icône et nom, sous-catégorie indentée (comme le menu des formulaires)
    private func categoryRow(_ category: Category, indented: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon ?? "folder")
                .foregroundStyle(Color(hex: categoriesController.displayColor(of: category)))
                .frame(width: 20)
            Text(category.name)
        }
        .padding(.leading, indented ? 24 : 0)
        .padding(.vertical, 2)
    }
}
