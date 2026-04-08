import SwiftUI

struct BookFormView: View {
    @EnvironmentObject var bookController: BooksController
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var currency: String = "EUR"
    @State private var isCreating = false
    
    let availableCurrencies = ["EUR", "USD", "GBP", "CHF", "CAD", "JPY", "AUD"]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Nouveau Livre")
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
                TextField("Nom du livre", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Devise", selection: $currency) {
                    ForEach(availableCurrencies, id: \.self) { curr in
                        Text(curr).tag(curr)
                    }
                }
                .pickerStyle(.menu)
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
                
                Button("Créer") {
                    createBook()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
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
