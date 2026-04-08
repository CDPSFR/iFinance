import Foundation

protocol TransactionRepositoryProtocol {
    func fetchAll(for accountID: UUID) async throws -> [Transaction]
    func fetchBetween(accountID: UUID, start: Date, end: Date) async throws -> [Transaction]
    func fetch(id: UUID) async throws -> Transaction?
    func create(_ transaction: Transaction) async throws
    func update(_ transaction: Transaction) async throws
    func delete(id: UUID) async throws
    func createTransfer(from: UUID, to: UUID, amount: Decimal, date: Date, memo: String?) async throws -> (Transaction, Transaction)
}
