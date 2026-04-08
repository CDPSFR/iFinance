import Foundation

protocol AccountRepositoryProtocol {
    func fetchAll(for bookID: UUID) async throws -> [Account]
    func fetchActive(for bookID: UUID) async throws -> [Account]
    func fetchClosed(for bookID: UUID) async throws -> [Account]
    func fetch(id: UUID) async throws -> Account?
    func create(_ account: Account) async throws
    func update(_ account: Account) async throws
    func delete(id: UUID) async throws
    func close(id: UUID) async throws
    func reopen(id: UUID) async throws
}
