import SwiftUI

struct PositionListView: View {
    let account: Account
    @Binding var activeSheet: InvestmentSheet?

    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var appSettings: AppSettings

    @State private var showClosedPositions = false
    @State private var positionToDelete: InvestmentPosition?
    @State private var selection: Set<InvestmentPosition.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            if allPositions.isEmpty {
                ContentUnavailableView {
                    Label("Aucune position", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Ajoutez une position puis enregistrez vos achats, ventes et dividendes.")
                } actions: {
                    Button("Nouvelle position") {
                        activeSheet = .newPosition
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table

                if hasClosedPositions {
                    HStack {
                        Toggle("Afficher les positions soldées", isOn: $showClosedPositions)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Supprimer cette position ?",
            isPresented: Binding(
                get: { positionToDelete != nil },
                set: { if !$0 { positionToDelete = nil } }
            ),
            presenting: positionToDelete
        ) { position in
            Button("Supprimer \(position.name) et ses opérations", role: .destructive) {
                Task { await investmentsController.deletePosition(position) }
            }
        } message: { _ in
            Text("Toutes les opérations de cette position seront supprimées. Cette action est irréversible.")
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(visiblePositions, selection: $selection) {
            TableColumn("Titre") { position in
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.name)
                    Text("\(position.symbol) · \(position.assetType.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(position.quantity == 0 ? .secondary : .primary)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Quantité") { position in
                Text(position.quantity, format: .number.precision(.fractionLength(0...6)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            TableColumn("PRU") { position in
                amount(position.averageCost, currency: position.currency)
            }

            TableColumn("Cours") { position in
                VStack(alignment: .trailing, spacing: 2) {
                    if let price = position.currentPrice {
                        amount(price, currency: position.currency)
                        if let date = position.lastUpdated {
                            Text(date, format: .dateTime.day().month().year())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                            .help("Cours non renseigné : valorisation au PRU")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            TableColumn("Valeur") { position in
                amount(PositionCalculator.marketValue(position), currency: position.currency)
                    .fontWeight(.semibold)
            }

            TableColumn("+/- value") { position in
                let gain = PositionCalculator.unrealizedGain(position)
                let cost = PositionCalculator.costBasis(position)
                VStack(alignment: .trailing, spacing: 2) {
                    amount(gain, currency: position.currency)
                        .foregroundColor(gain >= 0 ? .green : .red)
                    if cost > 0 {
                        Text(Double(truncating: NSDecimalNumber(decimal: gain / cost)),
                             format: .percent.precision(.fractionLength(2)).sign(strategy: .always()))
                            .font(.caption)
                            .foregroundColor(gain >= 0 ? .green : .red)
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            TableColumn("Poids") { position in
                Text(weight(of: position), format: .percent.precision(.fractionLength(1)))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(60)
        }
        .contextMenu(forSelectionType: InvestmentPosition.ID.self) { ids in
            if let id = ids.first, let position = investmentsController.position(id: id, in: account.id) {
                Button("Mettre à jour le cours…") { activeSheet = .price(position) }
                Button("Nouvelle opération…") { activeSheet = .newOperationFor(position) }
                Button("Modifier la position…") { activeSheet = .editPosition(position) }
                Divider()
                Button("Supprimer…", role: .destructive) { positionToDelete = position }
            }
        } primaryAction: { ids in
            if let id = ids.first, let position = investmentsController.position(id: id, in: account.id) {
                activeSheet = .price(position)
            }
        }
    }

    // MARK: - Helpers

    private var allPositions: [InvestmentPosition] {
        investmentsController.positions[account.id] ?? []
    }

    private var hasClosedPositions: Bool {
        allPositions.contains { $0.quantity == 0 }
    }

    private var visiblePositions: [InvestmentPosition] {
        allPositions
            .filter { showClosedPositions || $0.quantity != 0 }
            .sorted { PositionCalculator.marketValue($0) > PositionCalculator.marketValue($1) }
    }

    private func weight(of position: InvestmentPosition) -> Double {
        let total = investmentsController.marketValue(for: account.id)
        guard total > 0 else { return 0 }
        return Double(truncating: NSDecimalNumber(decimal: PositionCalculator.marketValue(position) / total))
    }

    private func amount(_ value: Decimal, currency: String) -> some View {
        Text(value, format: .currency(code: currency))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .privacyBlur(hidden: appSettings.hideAmounts)
    }
}
