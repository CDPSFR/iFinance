import SwiftUI

struct BookFormView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var currency: String = "EUR"
    @State private var isCreating = false
    @State private var color: String = BookFormView.palette[0].hex
    @State private var startingPoint: StartingPoint = .defaultCategories

    /// Couleurs proposées pour un livre
    static let palette: [(name: String, hex: String)] = [
        ("Bleu", "#0A66D8"),
        ("Violet", "#7D3FB3"),
        ("Rose", "#D4568A"),
        ("Orange", "#E08A1E"),
        ("Vert", "#1A7F37"),
        ("Graphite", "#5B6470")
    ]

    /// Contenu initial du nouveau livre
    enum StartingPoint: String, CaseIterable, Identifiable {
        case empty
        case defaultCategories

        var id: String { rawValue }

        var title: String {
            switch self {
            case .empty: return "Livre vide"
            case .defaultCategories: return "Catégories courantes"
            }
        }

        var detail: String {
            switch self {
            case .empty: return "Aucun compte ni catégorie, tout est à créer."
            case .defaultCategories: return "Un jeu de catégories et sous-catégories prêt à modifier."
            }
        }
    }
    
    let availableCurrencies = ["EUR", "USD", "GBP", "CHF", "CAD", "JPY", "AUD"]
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête de feuille
            SheetHeader(
                title: "Nouveau livre de comptes",
                subtitle: "Un livre regroupe ses propres comptes, catégories, budgets et bénéficiaires."
            )

            Form {
                Section {
                    TextField("Nom", text: $name, prompt: Text("Nom du livre"))

                    Picker("Devise principale", selection: $currency) {
                        ForEach(availableCurrencies, id: \.self) { curr in
                            Text(curr).tag(curr)
                        }
                    }

                    LabeledContent("Couleur") {
                        HStack(spacing: 8) {
                            ForEach(BookFormView.palette, id: \.hex) { item in
                                Button {
                                    color = item.hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: item.hex))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: color == item.hex ? 2 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.name)
                                .accessibilityAddTraits(color == item.hex ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section("Point de départ") {
                    Picker("Point de départ", selection: $startingPoint) {
                        ForEach(StartingPoint.allCases) { option in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
            .formStyle(.grouped)

            // Boutons : action par défaut à droite
            SheetFooter {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Créer") {
                    createBook()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .frame(width: 520, height: 440)
        .sheetBackground()
    }

    private func createBook() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isCreating = true
        
        Task {
            await bookController.createBook(name: name, currency: currency, color: color)

            // Le livre créé devient le livre courant : on y ajoute les catégories demandées
            if startingPoint == .defaultCategories, let bookID = bookController.currentBook?.id {
                await categoriesController.createDefaultCategories(for: bookID)
            }
            isPresented = false
        }
    }
}
