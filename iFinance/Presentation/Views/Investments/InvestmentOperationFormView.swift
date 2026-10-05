import SwiftUI

struct InvestmentOperationFormView: View {
    let account: Account
    var operationToEdit: InvestmentTransaction?

    @EnvironmentObject var investmentsController: InvestmentsController
    @Environment(\.dismiss) private var dismiss

    @State private var type: InvestmentTransactionType
    @State private var positionChoice: PositionChoice
    @State private var date: Date
    @State private var quantity: String
    @State private var price: String
    @State private var amount: String
    @State private var fees: String
    @State private var memo: String
    @State private var isIncomingTransfer: Bool

    // Nouvelle position créée à la volée
    @State private var newPositionName = ""
    @State private var newPositionSymbol = ""
    @State private var newPositionAssetType: AssetType

    @State private var isSaving = false
    @State private var errorMessage: String?

    enum PositionChoice: Hashable {
        case none
        case existing(UUID)
        case new
    }

    init(account: Account, operationToEdit: InvestmentTransaction? = nil, preselectedPosition: InvestmentPosition? = nil) {
        self.account = account
        self.operationToEdit = operationToEdit

        let operation = operationToEdit
        _type = State(initialValue: operation?.type ?? .buy)
        if let positionID = operation?.positionID ?? preselectedPosition?.id {
            _positionChoice = State(initialValue: .existing(positionID))
        } else {
            _positionChoice = State(initialValue: operation == nil ? .new : .none)
        }
        _date = State(initialValue: operation?.date ?? Date())
        _quantity = State(initialValue: operation?.quantity.map { abs($0).userInputString } ?? "")
        _price = State(initialValue: operation?.price?.userInputString ?? "")
        _amount = State(initialValue: operation.map { $0.amount.userInputString } ?? "")
        _fees = State(initialValue: operation.map { $0.fees == 0 ? "" : $0.fees.userInputString } ?? "")
        _memo = State(initialValue: operation?.memo ?? "")
        _isIncomingTransfer = State(initialValue: (operation?.quantity ?? 1) >= 0)
        _newPositionAssetType = State(initialValue: InvestmentPositionFormView.defaultAssetType(for: account.type))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: operationToEdit == nil ? "Nouvelle opération" : "Modifier l'opération")

            Form {
                Section {
                    Picker("Opération", selection: $type) {
                        ForEach(InvestmentTransactionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Titre") {
                    Picker("Position", selection: $positionChoice) {
                        if !type.affectsQuantity {
                            Text("Aucune (compte)").tag(PositionChoice.none)
                        }
                        ForEach(positions) { position in
                            Text("\(position.name) (\(position.symbol))").tag(PositionChoice.existing(position.id))
                        }
                        Divider()
                        Text("Nouvelle position…").tag(PositionChoice.new)
                    }

                    if positionChoice == .new {
                        TextField("Nom (ex. Amundi MSCI World)", text: $newPositionName)
                        TextField("Symbole ou ISIN", text: $newPositionSymbol)
                        Picker("Type d'actif", selection: $newPositionAssetType) {
                            ForEach(AssetType.allCases, id: \.self) { assetType in
                                Text(assetType.displayName).tag(assetType)
                            }
                        }
                    }
                }

                Section("Montants") {
                    fields
                }

                Section {
                    TextField("Mémo (optionnel)", text: $memo)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil || isSaving)
            }
        }
        .frame(width: 520, height: 680)
        .sheetBackground()
        .onChange(of: type) { _, newType in
            // Une opération sur quantité exige une position
            if newType.affectsQuantity && positionChoice == .none {
                positionChoice = positions.first.map { .existing($0.id) } ?? .new
            }
            errorMessage = nil
        }
    }

    // MARK: - Fields

    @ViewBuilder
    private var fields: some View {
        switch type {
        case .buy, .sell:
            decimalField("Quantité", text: $quantity)
            decimalField("Prix unitaire (\(account.currency))", text: $price)
            decimalField("Frais (\(account.currency))", text: $fees)
            summary

        case .dividend, .interest:
            decimalField("Montant brut (\(account.currency))", text: $amount)
            decimalField("Prélèvements / frais (\(account.currency))", text: $fees)
            summary

        case .fee:
            decimalField("Montant (\(account.currency))", text: $amount)
            summary

        case .split:
            decimalField("Ratio (ex. 2 pour 1 → 2)", text: $quantity)
            Text("La quantité est multipliée et le PRU divisé par ce ratio.")
                .font(.caption)
                .foregroundColor(.secondary)

        case .transfer:
            Picker("Sens", selection: $isIncomingTransfer) {
                Text("Entrée de titres").tag(true)
                Text("Sortie de titres").tag(false)
            }
            .pickerStyle(.segmented)
            decimalField("Quantité", text: $quantity)
            if isIncomingTransfer {
                decimalField("Prix de revient unitaire (\(account.currency))", text: $price)
            }
            Text("Sans effet sur les espèces du compte.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let operation = draft {
            if type == .buy || type == .sell {
                LabeledContent("Montant") {
                    Text(operation.amount, format: .currency(code: account.currency))
                }
            }
            let impact = PositionCalculator.cashImpact(operation)
            LabeledContent("Effet sur les espèces") {
                Text(impact, format: .currency(code: account.currency))
                    .foregroundColor(impact >= 0 ? .green : .red)
            }
        }
    }

    private func decimalField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Draft

    private var positions: [InvestmentPosition] {
        investmentsController.positions[account.id] ?? []
    }

    /// Opération construite à partir de la saisie, nil si incomplète
    private var draft: InvestmentTransaction? {
        let feesValue = fees.isEmpty ? Decimal(0) : Decimal(userInput: fees)
        guard let feesValue, feesValue >= 0 else { return nil }

        var operation = InvestmentTransaction(
            id: operationToEdit?.id ?? UUID(),
            accountID: account.id,
            positionID: nil,
            date: date,
            type: type,
            amount: 0,
            fees: 0,
            memo: memo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : memo.trimmingCharacters(in: .whitespaces)
        )

        switch type {
        case .buy, .sell:
            guard let q = Decimal(userInput: quantity), q > 0,
                  let p = Decimal(userInput: price), p >= 0 else { return nil }
            operation.quantity = q
            operation.price = p
            operation.amount = q * p
            operation.fees = feesValue

        case .dividend, .interest:
            guard let a = Decimal(userInput: amount), a > 0 else { return nil }
            operation.amount = a
            operation.fees = feesValue

        case .fee:
            guard let a = Decimal(userInput: amount), a > 0 else { return nil }
            operation.amount = a

        case .split:
            guard let ratio = Decimal(userInput: quantity), ratio > 0 else { return nil }
            operation.quantity = ratio

        case .transfer:
            guard let q = Decimal(userInput: quantity), q > 0 else { return nil }
            operation.quantity = isIncomingTransfer ? q : -q
            if isIncomingTransfer {
                guard let p = Decimal(userInput: price), p >= 0 else { return nil }
                operation.price = p
            }
        }

        switch positionChoice {
        case .none:
            guard !type.affectsQuantity else { return nil }
        case .existing(let id):
            operation.positionID = id
            operation.symbol = positions.first { $0.id == id }?.symbol
        case .new:
            guard !newPositionName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        }

        return operation
    }

    // MARK: - Save

    private func save() {
        guard var operation = draft else { return }
        isSaving = true
        errorMessage = nil

        Task {
            var createdPosition: InvestmentPosition?
            if positionChoice == .new {
                let name = newPositionName.trimmingCharacters(in: .whitespaces)
                let symbol = newPositionSymbol.trimmingCharacters(in: .whitespaces).uppercased()
                let position = InvestmentPosition(
                    accountID: account.id,
                    symbol: symbol.isEmpty ? name : symbol,
                    name: name,
                    quantity: 0,
                    averageCost: 0,
                    currency: account.currency,
                    assetType: newPositionAssetType
                )
                await investmentsController.addPosition(position)
                createdPosition = position
                operation.positionID = position.id
                operation.symbol = position.symbol
            }

            do {
                if operationToEdit == nil {
                    try await investmentsController.recordOperation(operation)
                } else {
                    try await investmentsController.updateOperation(operation)
                }
                dismiss()
            } catch {
                // Ne pas laisser de position vide créée pour une opération refusée
                if let createdPosition {
                    await investmentsController.deletePosition(createdPosition)
                    positionChoice = .new
                }
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
