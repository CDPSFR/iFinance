import Foundation

protocol BudgetRepositoryProtocol {
    func fetchAll(for bookID: UUID) async throws -> [Budget]
    func fetch(id: UUID) async throws -> Budget?
    func create(_ budget: Budget) async throws
    func update(_ budget: Budget) async throws
    func delete(id: UUID) async throws

    // Versions
    func fetchVersions(for budgetID: UUID) async throws -> [BudgetVersion]
    func createVersion(_ version: BudgetVersion) async throws
    func deleteVersion(id: UUID) async throws
    func currentVersion(for budgetID: UUID, at date: Date) async throws -> BudgetVersion?
}
