import Foundation

protocol BookRepositoryProtocol {
    func fetchAll() async throws -> [Book]
    func fetchActive() async throws -> [Book]
    func fetchArchived() async throws -> [Book]
    func fetch(id: UUID) async throws -> Book?
    func create(_ book: Book) async throws
    func update(_ book: Book) async throws
    func delete(id: UUID) async throws
    func archive(id: UUID) async throws
    func unarchive(id: UUID) async throws
}
