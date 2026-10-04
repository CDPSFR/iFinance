import SwiftUI

struct BookFormView: View {
    @EnvironmentObject var bookController: BooksController
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var currency: String = "EUR"
    @State private var isCreating = false
    
    let availableCurrencies = ["EUR", "USD", "GBP", "CHF", "CAD", "JPY", "AUD"]
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête de feuille
            VStack(alignment: .leading, spacing: 2) {
                Text("Nouveau livre de comptes")
                    .font(.headline)

                Text("Un livre regroupe ses propres comptes, catégories, budgets et bénéficiaires.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Form {
                Section {
                    TextField("Nom", text: $name, prompt: Text("Nom du livre"))

                    Picker("Devise principale", selection: $currency) {
                        ForEach(availableCurrencies, id: \.self) { curr in
                            Text(curr).tag(curr)
                        }
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

                Button("Créer") {
                    createBook()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 440, height: 260)
    }

    private func createBook() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isCreating = true
        
        Task {
            await bookController.createBook(name: name, currency: currency)
            isPresented = false
        }
    }
}
