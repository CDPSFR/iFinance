import SwiftUI

/// Choix d'une catégorie, identique dans toute l'app : catégories puis sous-catégories indentées,
/// avec leurs icônes, et bouton « + » qui crée une catégorie et la sélectionne aussitôt.
struct CategoryPicker: View {
    /// Catégories proposées
    enum Kind: Equatable {
        /// Dépenses et revenus (transfert, filtre)
        case all
        case expenses
        case income

        init(isIncome: Bool) { self = isIncome ? .income : .expenses }
    }

    @Binding var selection: UUID?
    var kind: Kind = .all
    /// Libellé de l'absence de catégorie (« Aucune », « Tout » dans un filtre)
    var noneTitle: String = "Aucune"
    /// Bouton « + » de création (absent dans un filtre)
    var allowsAdd = true
    /// Largeur du contrôle, bouton « + » compris ; nil = largeur disponible
    var width: CGFloat? = 260
    /// Appelé avec la catégorie créée par le bouton « + »
    var onCreate: ((UUID) -> Void)? = nil

    @EnvironmentObject var categoriesController: CategoriesController

    @State private var showForm = false
    @State private var knownIDs: Set<UUID> = []

    var body: some View {
        HStack(spacing: 6) {
            FillPopUpPicker(items: Self.items(categoriesController, kind: kind, noneTitle: noneTitle), selection: $selection)
                .frame(maxWidth: .infinity)

            if allowsAdd {
                Button {
                    knownIDs = Set(categoriesController.categories.map { $0.id })
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Nouvelle catégorie")
                .accessibilityLabel("Nouvelle catégorie")
            }
        }
        .frame(width: width)
        .sheet(isPresented: $showForm, onDismiss: {
            // La catégorie créée est sélectionnée
            if let created = categoriesController.categories.first(where: { !knownIDs.contains($0.id) }) {
                selection = created.id
                onCreate?(created.id)
            }
        }) {
            CategoryFormView(isPresented: $showForm, initialIsIncome: kind == .all ? nil : kind == .income)
        }
    }

    /// Lignes du menu : l'absence de catégorie, puis chaque catégorie suivie de ses sous-catégories
    static func items(_ controller: CategoriesController, kind: Kind, noneTitle: String) -> [FillPopUpItem<UUID>] {
        let roots = controller.rootCategories.filter { category in
            switch kind {
            case .all: return true
            case .expenses: return !category.isIncome
            case .income: return category.isIncome
            }
        }
        var items = [FillPopUpItem<UUID>(id: nil, title: noneTitle)]
        for category in roots {
            items.append(FillPopUpItem(id: category.id, title: category.name, systemImage: category.icon ?? "folder"))
            for sub in controller.getSubcategories(for: category.id) {
                items.append(FillPopUpItem(id: sub.id, title: sub.name, systemImage: sub.icon ?? "folder", indentationLevel: 1))
            }
        }
        return items
    }
}
