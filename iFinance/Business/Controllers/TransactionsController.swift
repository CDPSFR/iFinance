import Foundation
import SwiftUI
import Combine

@MainActor
class TransactionsController: ObservableObject {
    @Published var allTransactions: [Transaction] = [] {
        didSet { revision &+= 1 }
    }
    /// Incrémenté à chaque changement de allTransactions : clé de cache pour les calculs dérivés
    private(set) var revision = 0
    @Published var filteredTransactions: [Transaction] = []
    @Published var selectedTransaction: Transaction?
    @Published var filters = TransactionFilters.empty {
        didSet {
            // Appliquer automatiquement les filtres quand ils changent
            applyFilters()
        }
    }
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository: TransactionRepositoryProtocol
    
    init(repository: TransactionRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Load All Transactions (pour un book)
    
    func loadAllTransactions(for accounts: [Account]) async {
        isLoading = true
        defer { isLoading = false }
        
        var all: [Transaction] = []
        
        for account in accounts {
            do {
                let txs = try await repository.fetchAll(for: account.id)
                all.append(contentsOf: txs)
            } catch {
                print("❌ Erreur chargement transactions pour \(account.name): \(error)")
            }
        }
        
        allTransactions = all.sorted { $0.date > $1.date }
        applyFilters()
    }
    
    // MARK: - Apply Filters
    
    /// Sous-catégories d'une catégorie, fourni par CategoriesController (voir AppState)
    var subcategoryIDs: (UUID) -> [UUID] = { _ in [] }

    func applyFilters() {
        var result = allTransactions
        
        // Filtre par type
        if let type = filters.transactionType {
            result = result.filter { $0.type == type }
        }
        
        // Filtre par compte
        if let accountID = filters.accountID {
            result = result.filter { $0.accountID == accountID }
        }
        
        // Filtre par catégorie (une catégorie parente inclut ses sous-catégories)
        if let categoryID = filters.categoryID {
            let categoryIDs = Set([categoryID] + subcategoryIDs(categoryID))
            result = result.filter { $0.categoryID.map(categoryIDs.contains) ?? false }
        }
        
        // Filtre par bénéficiaire
        if let payeeID = filters.payeeID {
            result = result.filter { $0.payeeID == payeeID }
        }
        
        // Filtre par date
        if let (start, end) = filters.dateRange.dates() {
            result = result.filter { $0.date >= start && $0.date < end }
        }
        
        filteredTransactions = result
    }
    
    func updateFilters(_ newFilters: TransactionFilters) {
        filters = newFilters
        // applyFilters() sera appelé automatiquement par didSet
    }
    
    func resetFilters() {
        filters = .empty
        // applyFilters() sera appelé automatiquement par didSet
    }
    
    // MARK: - Quick Filter by Account
    
    func filterByAccount(_ accountID: UUID?) {
        filters.accountID = accountID
        // applyFilters() sera appelé automatiquement par didSet
    }
    
    // MARK: - Create Transaction
    
    @discardableResult
    func createTransaction(
        accountID: UUID,
        date: Date,
        amount: Decimal,
        type: TransactionType,
        payeeID: UUID? = nil,
        categoryID: UUID? = nil,
        memo: String? = nil
    ) async -> Transaction? {
        let transaction = Transaction(
            date: date,
            amount: amount,
            accountID: accountID,
            payeeID: payeeID,
            categoryID: categoryID,
            type: type,
            memo: memo,
            status: .cleared
        )
        
        do {
            try await repository.create(transaction)
            // Recharger toutes les transactions
            // (sera appelé depuis la vue avec accountsController.activeAccounts)
            return transaction
        } catch {
            self.error = error
            print("❌ Erreur création transaction: \(error)")
            return nil
        }
    }
    
    // MARK: - Create Transfer
    
    /// Retourne (transaction source, transaction destination)
    @discardableResult
    func createTransfer(
        from sourceAccountID: UUID,
        to destinationAccountID: UUID,
        amount: Decimal,
        date: Date,
        memo: String? = nil,
        categoryID: UUID? = nil
    ) async -> (source: Transaction, destination: Transaction)? {
        do {
            return try await repository.createTransfer(
                from: sourceAccountID,
                to: destinationAccountID,
                amount: amount,
                date: date,
                memo: memo,
                categoryID: categoryID
            )
        } catch {
            self.error = error
            print("❌ Erreur création transfert: \(error)")
            return nil
        }
    }

    // MARK: - Update Transfer (met à jour les deux transactions liées)

    func updateTransfer(_ transaction: Transaction, categoryID: UUID?) async {
        var updated = transaction
        updated.categoryID = categoryID

        do {
            try await repository.update(updated)

            // Mettre à jour la transaction liée avec la même catégorie
            if let linkedID = transaction.linkedTransactionID,
               let linked = try? await repository.fetch(id: linkedID) {
                var updatedLinked = linked
                updatedLinked.categoryID = categoryID
                try await repository.update(updatedLinked)
            }
        } catch {
            self.error = error
            print("❌ Erreur mise à jour transfert: \(error)")
        }
    }
    
    // MARK: - Update Transaction
    
    func updateTransaction(_ transaction: Transaction) async {
        do {
            try await repository.update(transaction)
        } catch {
            self.error = error
            print("❌ Erreur mise à jour transaction: \(error)")
        }
    }
    
    // MARK: - Delete Transaction
    
    func deleteTransaction(id: UUID) async {
        do {
            // Si c'est un transfert, supprimer aussi la transaction liée
            if let transaction = try await repository.fetch(id: id),
               let linkedID = transaction.linkedTransactionID {
                try await repository.delete(id: linkedID)
            }
            try await repository.delete(id: id)
        } catch {
            self.error = error
            print("❌ Erreur suppression transaction: \(error)")
        }
    }
    
    // MARK: - Calculate Balance
    
    func calculateBalance(for accountID: UUID, initialBalance: Decimal) -> Decimal {
        let total = allTransactions
            .filter { $0.accountID == accountID && $0.status != .skipped }
            .reduce(Decimal(0)) { $0 + $1.signedAmount }
        
        return initialBalance + total
    }
    
    // Helper pour charger les transactions d'un compte spécifique
    func fetchTransactions(for accountID: UUID) async throws -> [Transaction] {
        return try await repository.fetchAll(for: accountID)
    }

}
