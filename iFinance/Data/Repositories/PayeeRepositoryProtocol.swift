import Foundation

protocol PayeeRepositoryProtocol {
    func fetchAll(for bookID: UUID) async throws -> [Payee]
    func fetch(id: UUID) async throws -> Payee?
    func search(for bookID: UUID, query: String) async throws -> [Payee]
    func create(_ payee: Payee) async throws
    /// Crée tous les bénéficiaires ensemble : tous ou aucun
    func createBatch(_ payees: [Payee]) async throws
    func update(_ payee: Payee) async throws
    func delete(id: UUID) async throws
}

extension PayeeRepositoryProtocol {
    /// Par défaut, un à un (les implémentations SQLite regroupent les écritures)
    func createBatch(_ payees: [Payee]) async throws {
        for payee in payees {
            try await create(payee)
        }
    }
}
