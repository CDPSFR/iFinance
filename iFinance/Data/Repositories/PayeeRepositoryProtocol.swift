import Foundation

protocol PayeeRepositoryProtocol {
    func fetchAll(for bookID: UUID) async throws -> [Payee]
    func fetch(id: UUID) async throws -> Payee?
    func search(for bookID: UUID, query: String) async throws -> [Payee]
    func create(_ payee: Payee) async throws
    func update(_ payee: Payee) async throws
    func delete(id: UUID) async throws
}
