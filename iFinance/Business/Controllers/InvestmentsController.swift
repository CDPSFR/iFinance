import Foundation
import SwiftUI
import Combine

enum InvestmentError: LocalizedError {
    case missingPosition
    case invalidQuantity
    case insufficientQuantity(available: Decimal)

    var errorDescription: String? {
        switch self {
        case .missingPosition:
            return "Cette opération doit être rattachée à une position."
        case .invalidQuantity:
            return "La quantité doit être supérieure à zéro."
        case .insufficientQuantity(let available):
            return "Quantité insuffisante : \(available.formatted()) titre(s) détenu(s) à cette date."
        }
    }
}

@MainActor
class InvestmentsController: ObservableObject {
    /// Positions par compte
    @Published var positions: [UUID: [InvestmentPosition]] = [:]
    /// Opérations par compte, dans l'ordre chronologique
    @Published var operations: [UUID: [InvestmentTransaction]] = [:]
    @Published var isLoading = false
    @Published var error: Error?

    private let positionRepository: InvestmentPositionRepositoryProtocol
    private let transactionRepository: InvestmentTransactionRepositoryProtocol

    init(
        positionRepository: InvestmentPositionRepositoryProtocol,
        transactionRepository: InvestmentTransactionRepositoryProtocol
    ) {
        self.positionRepository = positionRepository
        self.transactionRepository = transactionRepository
    }

    // MARK: - Load

    func load(for accounts: [Account]) async {
        isLoading = true
        defer { isLoading = false }

        positions = [:]
        operations = [:]
        for account in accounts where account.type.supportsPositions {
            await reload(accountID: account.id)
        }
    }

    func reload(accountID: UUID) async {
        do {
            positions[accountID] = try await positionRepository.fetchAll(for: accountID)
            operations[accountID] = try await transactionRepository.fetchAll(for: accountID)
        } catch {
            self.error = error
            print("❌ Erreur chargement investissements: \(error)")
        }
    }

    // MARK: - Positions

    func addPosition(_ position: InvestmentPosition) async {
        do {
            try await positionRepository.create(position)
            await reload(accountID: position.accountID)
        } catch {
            self.error = error
            print("❌ Erreur création position: \(error)")
        }
    }

    /// Modifie les informations descriptives (symbole, nom, type d'actif)
    func updatePosition(_ position: InvestmentPosition) async {
        do {
            try await positionRepository.update(position)
            await reload(accountID: position.accountID)
        } catch {
            self.error = error
            print("❌ Erreur mise à jour position: \(error)")
        }
    }

    func updatePrice(for position: InvestmentPosition, price: Decimal, date: Date = Date()) async {
        do {
            try await positionRepository.updatePrice(id: position.id, price: price, date: date)
            await reload(accountID: position.accountID)
        } catch {
            self.error = error
            print("❌ Erreur mise à jour cours: \(error)")
        }
    }

    /// Supprime la position et toutes ses opérations
    func deletePosition(_ position: InvestmentPosition) async {
        do {
            try await transactionRepository.deleteAll(forPosition: position.id)
            try await positionRepository.delete(id: position.id)
            await reload(accountID: position.accountID)
        } catch {
            self.error = error
            print("❌ Erreur suppression position: \(error)")
        }
    }

    // MARK: - Operations

    func recordOperation(_ operation: InvestmentTransaction) async throws {
        let previous = operationsOfPosition(operation.positionID, excluding: operation.id)
        try validate(operation, against: previous)
        try await transactionRepository.create(operation)
        try await recalculatePosition(operation.positionID)
        await reload(accountID: operation.accountID)
    }

    func updateOperation(_ operation: InvestmentTransaction) async throws {
        let original = operations[operation.accountID]?.first { $0.id == operation.id }
        let previous = operationsOfPosition(operation.positionID, excluding: operation.id)
        try validate(operation, against: previous)
        try await transactionRepository.update(operation)
        try await recalculatePosition(operation.positionID)
        if let originalPositionID = original?.positionID, originalPositionID != operation.positionID {
            try await recalculatePosition(originalPositionID)
        }
        await reload(accountID: operation.accountID)
    }

    func deleteOperation(_ operation: InvestmentTransaction) async throws {
        let remaining = operationsOfPosition(operation.positionID, excluding: operation.id)
        try validateHistory(remaining)
        try await transactionRepository.delete(id: operation.id)
        try await recalculatePosition(operation.positionID)
        await reload(accountID: operation.accountID)
    }

    // MARK: - Valuation

    /// Effet cumulé des opérations sur les espèces du compte
    func cashImpact(for accountID: UUID) -> Decimal {
        (operations[accountID] ?? []).reduce(Decimal(0)) { $0 + PositionCalculator.cashImpact($1) }
    }

    /// Valeur de marché des titres détenus
    func marketValue(for accountID: UUID) -> Decimal {
        (positions[accountID] ?? []).reduce(Decimal(0)) { $0 + PositionCalculator.marketValue($1) }
    }

    func costBasis(for accountID: UUID) -> Decimal {
        (positions[accountID] ?? []).reduce(Decimal(0)) { $0 + PositionCalculator.costBasis($1) }
    }

    func unrealizedGain(for accountID: UUID) -> Decimal {
        (positions[accountID] ?? []).reduce(Decimal(0)) { $0 + PositionCalculator.unrealizedGain($1) }
    }

    func realizedGain(for accountID: UUID, year: Int) -> Decimal {
        let byPosition = Dictionary(grouping: operations[accountID] ?? []) { $0.positionID }
        return byPosition.reduce(Decimal(0)) { sum, entry in
            guard entry.key != nil else { return sum }
            return sum + PositionCalculator.realizedGain(entry.value, year: year)
        }
    }

    func position(id: UUID?, in accountID: UUID) -> InvestmentPosition? {
        guard let id else { return nil }
        return positions[accountID]?.first { $0.id == id }
    }

    // MARK: - Helpers

    private func operationsOfPosition(_ positionID: UUID?, excluding operationID: UUID) -> [InvestmentTransaction] {
        guard let positionID else { return [] }
        return operations.values.joined().filter { $0.positionID == positionID && $0.id != operationID }
    }

    private func validate(_ operation: InvestmentTransaction, against others: [InvestmentTransaction]) throws {
        if operation.type.affectsQuantity {
            guard operation.positionID != nil else { throw InvestmentError.missingPosition }
            guard let quantity = operation.quantity, quantity != 0,
                  operation.type == .transfer || quantity > 0 else {
                throw InvestmentError.invalidQuantity
            }
        }
        try validateHistory(others + [operation])
    }

    /// Vérifie qu'aucune vente ne dépasse la quantité détenue au fil du temps
    private func validateHistory(_ history: [InvestmentTransaction]) throws {
        let sorted = history.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map { $0.element }
        var state = PositionState()
        for operation in sorted {
            let next = PositionCalculator.apply(operation, to: state)
            if next.quantity < 0 {
                throw InvestmentError.insufficientQuantity(available: state.quantity)
            }
            state = next
        }
    }

    /// Rejoue les opérations de la position et met à jour le cache quantité / PRU en base
    private func recalculatePosition(_ positionID: UUID?) async throws {
        guard let positionID,
              var position = try await positionRepository.fetch(id: positionID) else { return }
        let history = try await transactionRepository.fetchAll(forPosition: positionID)
        let state = PositionCalculator.replay(history)
        position.quantity = state.quantity
        position.averageCost = state.averageCost
        try await positionRepository.update(position)
    }
}
