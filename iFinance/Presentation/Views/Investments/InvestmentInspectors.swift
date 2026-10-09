import SwiftUI
import Charts

// Inspecteurs des onglets Positions et Opérations d'un compte d'investissement

// MARK: - Position

/// Ligne d'inspecteur avec une colonne de libellés assez large pour « Montant brut »
private func row(_ label: String, _ value: String) -> some View {
    InspectorRow(label: label, labelWidth: 96) { Text(value) }
}


struct PositionInspector: View {
    let position: InvestmentPosition
    /// Part de la position dans la valeur des titres du compte (0 à 1)
    let weight: Double
    /// Cours enregistrés, du plus ancien au plus récent
    let history: [PositionPrice]
    let onUpdatePrice: () -> Void
    let onNewOperation: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var appSettings: AppSettings

    /// Cours listés sous la courbe (la courbe montre tout l'historique)
    private static let historyCount = 3

    var body: some View {
        let value = PositionCalculator.marketValue(position)
        let gain = PositionCalculator.unrealizedGain(position)
        let cost = PositionCalculator.costBasis(position)

        InspectorContainer {
            InspectorHeader(
                title: position.name,
                value: money(value),
                caption: "\(position.symbol) · \(position.assetType.displayName)"
            )

            InspectorSection {
                row("Quantité", position.quantity.formatted(.number.precision(.fractionLength(0...6))))
                row("PRU", money(position.averageCost))
                row("Investi", money(cost))
                row("Cours", position.currentPrice.map(money) ?? "non renseigné")
                row("Cours du", priceDateText)
                row("+/- value", gainText(gain, cost: cost))
                row("Poids", weight.formatted(.percent.precision(.fractionLength(1))))
            }

            if history.count >= 2 {
                InspectorSection(title: "Évolution du cours") {
                    priceChart
                }
            }

            if !history.isEmpty {
                InspectorSection(title: "Derniers cours") {
                    ForEach(history.suffix(Self.historyCount).reversed()) { price in
                        HStack {
                            Text(price.date, format: .dateTime.day().month(.abbreviated).year())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(money(price.price))
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }

            InspectorSection {
                Button("Mettre à jour le cours…", action: onUpdatePrice)
                Button("Nouvelle opération…", action: onNewOperation)
                HStack(spacing: 8) {
                    Button("Modifier…", action: onEdit)
                    Button("Supprimer…", role: .destructive, action: onDelete)
                }
            }
        }
    }

    /// Cours enregistrés dans le temps, et prix de revient en pointillés (au-dessus : en gain)
    private var priceChart: some View {
        let prices = history.map { NSDecimalNumber(decimal: $0.price).doubleValue }
        let pru = NSDecimalNumber(decimal: position.averageCost).doubleValue
        let values = prices + (pru > 0 ? [pru] : [])
        let low = values.min() ?? 0, high = values.max() ?? 1
        let margin = max((high - low) * 0.15, high * 0.01)
        let lastPrice = prices.last ?? 0
        let color: Color = pru == 0 || lastPrice >= pru ? .green : .red

        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(history) { price in
                    AreaMark(
                        x: .value("Date", price.date),
                        yStart: .value("Bas", low - margin),
                        yEnd: .value("Cours", NSDecimalNumber(decimal: price.price).doubleValue)
                    )
                    .foregroundStyle(color.opacity(0.12))

                    LineMark(
                        x: .value("Date", price.date),
                        y: .value("Cours", NSDecimalNumber(decimal: price.price).doubleValue)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                if pru > 0 {
                    RuleMark(y: .value("PRU", pru))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: (low - margin)...(high + margin))
            // Axes masqués : la largeur de l'inspecteur tronquerait les dates ; la période est indiquée dessous
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
            .privacyBlur(hidden: appSettings.hideAmounts)

            if let first = history.first?.date, let last = history.last?.date {
                Text("Du \(first.formatted(.dateTime.day().month(.abbreviated).year())) au \(last.formatted(.dateTime.day().month(.abbreviated).year())) · \(history.count) cours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if pru > 0 {
                HStack(spacing: 5) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: 14, y: 0.5))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 14, height: 1)
                    Text("prix de revient")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Date du dernier cours, avec sa provenance (saisie ou service en ligne)
    private var priceDateText: String {
        guard let date = position.lastUpdated else { return "—" }
        let text = date.formatted(date: .abbreviated, time: .omitted)
        guard let source = history.last?.source else { return text }
        let origin = source == "manual" ? "saisi" : QuoteProviderRegistry.provider(id: source).displayName
        return "\(text) (\(origin))"
    }

    private func gainText(_ gain: Decimal, cost: Decimal) -> String {
        guard !appSettings.hideAmounts else { return "•••" }
        let amount = (gain > 0 ? "+" : "") + gain.formatted(.currency(code: position.currency))
        guard cost > 0 else { return amount }
        let ratio = NSDecimalNumber(decimal: gain / cost).doubleValue
        return "\(amount) (\(ratio.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))))"
    }

    private func money(_ value: Decimal) -> String {
        appSettings.hideAmounts ? "•••" : value.formatted(.currency(code: position.currency))
    }
}

// MARK: - Opération

struct OperationInspector: View {
    let operation: InvestmentTransaction
    let positionName: String?
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        let impact = PositionCalculator.cashImpact(operation)
        let memo = operation.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        InspectorContainer {
            InspectorHeader(
                title: InvestmentOperationListing.label(operation, positionName: positionName),
                value: impact == 0 ? "—" : money(impact),
                valueColor: impact > 0 ? .green : .primary,
                caption: operation.date.formatted(date: .long, time: .omitted)
            )

            InspectorSection {
                row("Type", operation.type.displayName)
                row("Titre", positionName ?? operation.symbol ?? "—")
                if let quantity = operation.quantity, operation.type.affectsQuantity {
                    row(operation.type == .split ? "Ratio" : "Quantité",
                                 operation.type == .split ? "×\(quantity.formatted())" : quantity.formatted(.number.precision(.fractionLength(0...6))))
                }
                if let price = operation.price, operation.type != .split {
                    row("Prix", money(price))
                }
                if operation.amount != 0 {
                    row("Montant brut", money(operation.amount))
                }
                if operation.fees != 0 {
                    row("Frais", money(operation.fees))
                }
                row("Espèces", impact == 0 ? "sans effet" : money(impact))
            }

            if !memo.isEmpty {
                InspectorSection(title: "Note") {
                    Text(memo)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            InspectorSection {
                HStack(spacing: 8) {
                    Button("Modifier…", action: onEdit)
                    Button("Supprimer…", role: .destructive, action: onDelete)
                }
            }
        }
    }

    private func money(_ value: Decimal) -> String {
        appSettings.hideAmounts ? "•••" : value.formatted(.currency(code: currency))
    }
}
