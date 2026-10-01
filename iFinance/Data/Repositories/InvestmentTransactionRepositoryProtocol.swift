import Foundation

protocol InvestmentTransactionRepositoryProtocol {
    func fetchAll(for accountID: UUID) async throws -> [InvestmentTransaction]
    func fetchAll(forPosition positionID: UUID) async throws -> [InvestmentTransaction]
    func create(_ operation: InvestmentTransaction) async throws
    func update(_ operation: InvestmentTransaction) async throws
    func delete(id: UUID) async throws
    func deleteAll(forPosition positionID: UUID) async throws
}
