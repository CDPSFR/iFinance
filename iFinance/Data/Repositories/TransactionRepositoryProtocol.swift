import Foundation

protocol TransactionRepositoryProtocol {
    func fetchAll(for accountID: UUID) async throws -> [Transaction]
    func fetchBetween(accountID: UUID, start: Date, end: Date) async throws -> [Transaction]
    func fetch(id: UUID) async throws -> Transaction?
    func create(_ transaction: Transaction) async throws
    /// Crée toutes les transactions ensemble : toutes ou aucune
    func createBatch(_ transactions: [Transaction]) async throws
    func update(_ transaction: Transaction) async throws
    func delete(id: UUID) async throws
    func createTransfer(from: UUID, to: UUID, amount: Decimal, date: Date, memo: String?, categoryID: UUID?) async throws -> (Transaction, Transaction)
    /// Transforme une dépense en transfert vers `destinationAccountID` : la transaction devient le côté
    /// source (mêmes identifiant, date, rapprochement, projet), le côté destination est créé
    /// Renvoie (source, destination)
    func convertToTransfer(_ transaction: Transaction, destinationAccountID: UUID, memo: String?) async throws -> (Transaction, Transaction)
}

extension TransactionRepositoryProtocol {
    /// Par défaut, en plusieurs écritures (l'implémentation SQLite les regroupe en une seule)
    func convertToTransfer(_ transaction: Transaction, destinationAccountID: UUID, memo: String?) async throws -> (Transaction, Transaction) {
        let (source, destination) = TransferConversion.legs(of: transaction, destinationAccountID: destinationAccountID, memo: memo)
        var unlinked = source
        unlinked.linkedTransactionID = nil
        try await update(unlinked)
        try await create(destination)
        try await update(source)
        return (source, destination)
    }

    /// Par défaut, une à une (les implémentations SQLite regroupent les écritures)
    func createBatch(_ transactions: [Transaction]) async throws {
        for transaction in transactions {
            try await create(transaction)
        }
    }
}

/// Construction des deux côtés d'un transfert issu d'une dépense
enum TransferConversion {
    static func legs(of transaction: Transaction, destinationAccountID: UUID, memo: String?) -> (source: Transaction, destination: Transaction) {
        let destinationID = UUID()
        var source = transaction
        source.type = .transfer
        source.amount = -abs(transaction.amount)
        source.toAccountID = destinationAccountID
        source.linkedTransactionID = destinationID
        // Un transfert n'a pas de bénéficiaire : la contrepartie est l'autre compte
        source.payeeID = nil
        source.memo = memo

        let destination = Transaction(
            id: destinationID,
            date: transaction.date,
            amount: abs(transaction.amount),
            accountID: destinationAccountID,
            toAccountID: transaction.accountID,
            linkedTransactionID: transaction.id,
            payeeID: nil,
            categoryID: transaction.categoryID,
            type: .transfer,
            memo: memo,
            isReconciled: false,
            recurringTemplateID: nil,
            status: transaction.status
        )
        return (source, destination)
    }
}
