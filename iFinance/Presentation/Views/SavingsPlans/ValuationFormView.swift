import SwiftUI

struct ValuationFormView: View {
    let account: Account
    var snapshotToEdit: ValuationSnapshot?

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var value: String
    @State private var note: String

    init(account: Account, snapshotToEdit: ValuationSnapshot? = nil) {
        self.account = account
        self.snapshotToEdit = snapshotToEdit
        _date = State(initialValue: snapshotToEdit?.date ?? Date())
        _value = State(initialValue: snapshotToEdit?.value.userInputString ?? "")
        _note = State(initialValue: snapshotToEdit?.note ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshotToEdit == nil ? "Mettre à jour la valeur" : "Modifier la valeur")
                        .font(.title)
                        .fontWeight(.bold)
                    Text(account.name)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            Form {
                Section {
                    DatePicker("Date du relevé", selection: $date, displayedComponents: .date)

                    HStack {
                        Text("Valeur totale (\(account.currency))")
                        Spacer()
                        TextField("0,00", text: $value)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .multilineTextAlignment(.trailing)
                    }

                    TextField("Note (optionnel, ex. relevé semestriel)", text: $note)
                } footer: {
                    Text("Reportez la valeur totale de votre relevé ou de l'espace en ligne de votre gestionnaire, tous supports confondus.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("À cette date") {
                    LabeledContent("Versements nets") {
                        Text(investedAtDate, format: .currency(code: account.currency))
                    }
                    if let parsed = Decimal(userInput: value) {
                        let gain = parsed - investedAtDate
                        LabeledContent("Plus-value") {
                            Text(gain, format: .currency(code: account.currency))
                                .foregroundColor(gain >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled((Decimal(userInput: value) ?? -1) < 0)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: 480)
    }

    private var investedAtDate: Decimal {
        let flows = savingsPlansController.flows(for: account, transactions: transactionsController.allTransactions)
        return SavingsPlanCalculator.invested(flows: flows, at: endOfDay(date))
    }

    /// Le relevé inclut les mouvements du jour
    private func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func save() {
        guard let parsed = Decimal(userInput: value) else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        Task {
            var snapshot = snapshotToEdit ?? ValuationSnapshot(accountID: account.id, date: date, value: parsed)
            snapshot.date = endOfDay(date)
            snapshot.value = parsed
            snapshot.note = trimmedNote.isEmpty ? nil : trimmedNote

            if snapshotToEdit == nil {
                await savingsPlansController.addValuation(snapshot)
            } else {
                await savingsPlansController.updateValuation(snapshot)
            }
            dismiss()
        }
    }
}
