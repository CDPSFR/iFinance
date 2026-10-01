import Foundation

/// État d'une position obtenu en rejouant ses opérations
struct PositionState: Equatable {
    var quantity: Decimal = 0
    var averageCost: Decimal = 0      // PRU, frais d'achat inclus
    var realizedGain: Decimal = 0     // Plus-values réalisées cumulées
}

/// Calculs purs sur les positions d'investissement (sans accès base)
enum PositionCalculator {

    // MARK: - Positions

    /// Applique une opération à l'état d'une position
    static func apply(_ operation: InvestmentTransaction, to state: PositionState) -> PositionState {
        var next = state
        let quantity = operation.quantity ?? 0
        let price = operation.price ?? 0

        switch operation.type {
        case .buy:
            let newQuantity = state.quantity + quantity
            if newQuantity > 0 {
                next.averageCost = (state.quantity * state.averageCost + quantity * price + operation.fees) / newQuantity
            }
            next.quantity = newQuantity

        case .sell:
            next.realizedGain += quantity * (price - state.averageCost) - operation.fees
            next.quantity = state.quantity - quantity
            if next.quantity == 0 {
                next.averageCost = 0
            }

        case .split:
            guard quantity > 0 else { break }
            next.quantity = state.quantity * quantity
            next.averageCost = state.averageCost / quantity

        case .transfer:
            if quantity > 0 {
                // Entrée de titres : le prix renseigné sert de prix de revient
                let newQuantity = state.quantity + quantity
                next.averageCost = (state.quantity * state.averageCost + quantity * price) / newQuantity
                next.quantity = newQuantity
            } else {
                next.quantity = state.quantity + quantity
                if next.quantity == 0 {
                    next.averageCost = 0
                }
            }

        case .dividend, .interest, .fee:
            break
        }

        return next
    }

    /// Rejoue les opérations dans l'ordre chronologique
    static func replay(_ operations: [InvestmentTransaction]) -> PositionState {
        sortedChronologically(operations).reduce(PositionState()) { apply($1, to: $0) }
    }

    /// Plus-values réalisées par les ventes de l'année donnée
    static func realizedGain(_ operations: [InvestmentTransaction], year: Int, calendar: Calendar = .current) -> Decimal {
        var state = PositionState()
        var total: Decimal = 0
        for operation in sortedChronologically(operations) {
            let before = state.realizedGain
            state = apply(operation, to: state)
            if calendar.component(.year, from: operation.date) == year {
                total += state.realizedGain - before
            }
        }
        return total
    }

    // MARK: - Espèces

    /// Effet d'une opération sur les espèces du compte
    static func cashImpact(_ operation: InvestmentTransaction) -> Decimal {
        switch operation.type {
        case .buy:
            return -(operation.amount + operation.fees)
        case .sell:
            return operation.amount - operation.fees
        case .dividend, .interest:
            return operation.amount - operation.fees
        case .fee:
            return -operation.amount
        case .split, .transfer:
            return 0
        }
    }

    // MARK: - Valorisation

    static func marketValue(_ position: InvestmentPosition) -> Decimal {
        position.quantity * (position.currentPrice ?? position.averageCost)
    }

    static func costBasis(_ position: InvestmentPosition) -> Decimal {
        position.quantity * position.averageCost
    }

    static func unrealizedGain(_ position: InvestmentPosition) -> Decimal {
        marketValue(position) - costBasis(position)
    }

    // MARK: - Helpers

    private static func sortedChronologically(_ operations: [InvestmentTransaction]) -> [InvestmentTransaction] {
        operations.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map { $0.element }
    }
}
