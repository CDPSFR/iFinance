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
        VStack(spacing: 0) {
            SheetHeader(title: "Cours", subtitle: "\(position.name) · \(position.symbol)")

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

            SheetFooter {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    guard let parsed = Decimal(userInput: price) else { return }
                    Task {
                        await investmentsController.updatePrice(for: position, price: parsed, date: date)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled((Decimal(userInput: price) ?? -1) < 0)
            }
        }
        .frame(width: 520, height: 320)
        .sheetBackground()
    }
}
