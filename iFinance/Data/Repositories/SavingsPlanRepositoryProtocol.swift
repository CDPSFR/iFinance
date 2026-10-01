import Foundation

protocol SavingsPlanRepositoryProtocol {
    // Valorisations
    func fetchValuations(for accountID: UUID) async throws -> [ValuationSnapshot]
    func createValuation(_ snapshot: ValuationSnapshot) async throws
    func updateValuation(_ snapshot: ValuationSnapshot) async throws
    func deleteValuation(id: UUID) async throws

    // Détails des apports
    func fetchContributionDetails(for accountID: UUID) async throws -> [ContributionDetail]
    func saveContributionDetail(_ detail: ContributionDetail) async throws
    func deleteContributionDetail(transactionID: UUID) async throws
}
