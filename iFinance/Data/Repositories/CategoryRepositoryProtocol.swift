import Foundation

protocol CategoryRepositoryProtocol {
    func fetchAll(for bookID: UUID) async throws -> [Category]
    func fetchRootCategories(for bookID: UUID) async throws -> [Category]
    func fetchSubcategories(for parentID: UUID) async throws -> [Category]
    func fetch(id: UUID) async throws -> Category?
    func create(_ category: Category) async throws
    func update(_ category: Category) async throws
    func delete(id: UUID) async throws
}
