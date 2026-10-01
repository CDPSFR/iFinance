import SwiftUI

struct PositionPriceFormView: View {
    let position: InvestmentPosition

    @EnvironmentObject var investmentsController: InvestmentsController
    @Environment(\.dismiss) private var dismiss

    @State private var price: String
    @State private var date = Date()

    init(position: InvestmentPosition) {
        self.position = position
        _price = State(initialValue: position.currentPrice?.userInputString ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cours")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("\(position.name) · \(position.symbol)")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            Form {
                HStack {
                    Text("Cours (\(position.currency))")
                    Spacer()
                    TextField("0,00", text: $price)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .multilineTextAlignment(.trailing)
                }

                DatePicker("Date du cours", selection: $date, displayedComponents: .date)

                if let parsed = Decimal(userInput: price) {
                    LabeledContent("Valeur de la position") {
                        Text(position.quantity * parsed, format: .currency(code: position.currency))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer") {
                    guard let parsed = Decimal(userInput: price) else { return }
                    Task {
                        await investmentsController.updatePrice(for: position, price: parsed, date: date)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled((Decimal(userInput: price) ?? -1) < 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 320)
    }
}
