import SwiftUI

struct InvestmentOperationListView: View {
    let account: Account
    @Binding var activeSheet: InvestmentSheet?

    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var appSettings: AppSettings

    @State private var selection: Set<InvestmentTransaction.ID> = []
    @State private var operationToDelete: InvestmentTransaction?
    @State private var deleteError: String?

    var body: some View {
        Group {
            if operations.isEmpty {
                ContentUnavailableView {
                    Label("Aucune opération", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Enregistrez vos achats, ventes, dividendes et frais.")
                } actions: {
                    Button("Nouvelle opération") {
                        activeSheet = .newOperation
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Supprimer cette opération ?",
            isPresented: Binding(
                get: { operationToDelete != nil },
                set: { if !$0 { operationToDelete = nil } }
            ),
            presenting: operationToDelete
        ) { operation in
            Button("Supprimer", role: .destructive) {
                Task {
                    do {
                        try await investmentsController.deleteOperation(operation)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
        } message: { operation in
            Text("\(operation.type.displayName) du \(operation.date.formatted(date: .abbreviated, time: .omitted)). Cette action est irréversible.")
        }
        .alert(
            "Suppression impossible",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(operations, selection: $selection) {
            TableColumn("Date") { operation in
                Text(operation.date, format: .dateTime.day().month().year())
            }
            .width(min: 80, ideal: 90)

            TableColumn("Opération") { operation in
                Label(operation.type.displayName, systemImage: icon(for: operation.type))
            }
            .width(min: 100, ideal: 130)

            TableColumn("Titre") { operation in
                Text(positionName(for: operation))
                    .foregroundColor(operation.positionID == nil ? .secondary : .primary)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Quantité") { operation in
                Group {
                    if let quantity = operation.quantity, operation.type.affectsQuantity {
                        Text(operation.type == .split
                             ? "×\(quantity.formatted())"
                             : quantity.formatted(.number.precision(.fractionLength(0...6))))
                    } else {
                        Text("")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            TableColumn("Prix") { operation in
                Group {
                    if let price = operation.price, operation.type != .split {
                        Text(price, format: .currency(code: account.currency))
                    } else {
                        Text("")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .privacyBlur(hidden: appSettings.hideAmounts)
            }

            TableColumn("Frais") { operation in
                Text(operation.fees == 0 ? "" : operation.fees.formatted(.currency(code: account.currency)))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }

            TableColumn("Espèces") { operation in
                let impact = PositionCalculator.cashImpact(operation)
                Text(impact == 0 ? "" : impact.formatted(.currency(code: account.currency)))
                    .foregroundColor(impact >= 0 ? .green : .red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }

            TableColumn("Mémo") { operation in
                Text(operation.memo ?? "")
                    .foregroundColor(.secondary)
            }
        }
        .contextMenu(forSelectionType: InvestmentTransaction.ID.self) { ids in
            if let id = ids.first, let operation = operation(id: id) {
                Button("Modifier…") { activeSheet = .editOperation(operation) }
                Divider()
                Button("Supprimer…", role: .destructive) { operationToDelete = operation }
            }
        } primaryAction: { ids in
            if let id = ids.first, let operation = operation(id: id) {
                activeSheet = .editOperation(operation)
            }
        }
    }

    // MARK: - Helpers

    /// Plus récentes en premier
    private var operations: [InvestmentTransaction] {
        (investmentsController.operations[account.id] ?? []).reversed()
    }

    private func operation(id: UUID) -> InvestmentTransaction? {
        investmentsController.operations[account.id]?.first { $0.id == id }
    }

    private func positionName(for operation: InvestmentTransaction) -> String {
        if let position = investmentsController.position(id: operation.positionID, in: account.id) {
            return position.name
        }
        return operation.symbol ?? "—"
    }

    private func icon(for type: InvestmentTransactionType) -> String {
        switch type {
        case .buy: return "arrow.down.circle"
        case .sell: return "arrow.up.circle"
        case .dividend: return "gift"
        case .interest: return "percent"
        case .fee: return "minus.circle"
        case .split: return "square.split.2x1"
        case .transfer: return "arrow.left.arrow.right"
        }
    }
}
