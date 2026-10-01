import Foundation

protocol InvestmentPositionRepositoryProtocol {
    func fetchAll(for accountID: UUID) async throws -> [InvestmentPosition]
    func fetch(id: UUID) async throws -> InvestmentPosition?
    func create(_ position: InvestmentPosition) async throws
    func update(_ position: InvestmentPosition) async throws
    func updatePrice(id: UUID, price: Decimal, date: Date) async throws
    func delete(id: UUID) async throws
}
