import SwiftUI

struct InvestmentPositionFormView: View {
    let account: Account
    var positionToEdit: InvestmentPosition?

    @EnvironmentObject var investmentsController: InvestmentsController
    @Environment(\.dismiss) private var dismiss

    @State private var symbol: String
    @State private var name: String
    @State private var assetType: AssetType
    @State private var isSaving = false

    init(account: Account, positionToEdit: InvestmentPosition? = nil) {
        self.account = account
        self.positionToEdit = positionToEdit
        _symbol = State(initialValue: positionToEdit?.symbol ?? "")
        _name = State(initialValue: positionToEdit?.name ?? "")
        _assetType = State(initialValue: positionToEdit?.assetType ?? InvestmentPositionFormView.defaultAssetType(for: account.type))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: positionToEdit == nil ? "Nouvelle position" : "Modifier la position")

            Form {
                Section {
                    TextField("Nom (ex. Amundi MSCI World)", text: $name)
                    TextField("Symbole ou ISIN (ex. CW8, FR0010756098)", text: $symbol)
                    Picker("Type d'actif", selection: $assetType) {
                        ForEach(AssetType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } footer: {
                    if positionToEdit == nil {
                        Text("La quantité et le PRU se calculent à partir des opérations (achats, ventes…).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(positionToEdit == nil ? "Créer" : "Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
        }
        .frame(width: 520, height: 340)
        .sheetBackground()
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        isSaving = true

        Task {
            if var position = positionToEdit {
                position.name = trimmedName
                position.symbol = trimmedSymbol.isEmpty ? trimmedName : trimmedSymbol
                position.assetType = assetType
                await investmentsController.updatePosition(position)
            } else {
                await investmentsController.addPosition(InvestmentPosition(
                    accountID: account.id,
                    symbol: trimmedSymbol.isEmpty ? trimmedName : trimmedSymbol,
                    name: trimmedName,
                    quantity: 0,
                    averageCost: 0,
                    currency: account.currency,
                    assetType: assetType
                ))
            }
            dismiss()
        }
    }

    static func defaultAssetType(for accountType: AccountType) -> AssetType {
        switch accountType {
        case .crypto: return .crypto
        case .perco, .pee, .lifeInsurance, .retirement, .article83: return .mutualFund
        case .pea: return .etf
        default: return .stock
        }
    }
}
