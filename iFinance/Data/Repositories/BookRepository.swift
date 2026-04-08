import Foundation

class BookRepository: BookRepositoryProtocol {
    private let db: SQLiteManager
    
    init(db: SQLiteManager) {
        self.db = db
    }
    
    // MARK: - Fetch All
    
    func fetchAll() async throws -> [Book] {
        let sql = """
        SELECT id, name, currency, created_at, updated_at, archived_at
        FROM books
        ORDER BY created_at DESC;
        """
        
        let rows = try db.query(sql: sql)
        return rows.compactMap { BookMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Active (non-archivés)
    
    func fetchActive() async throws -> [Book] {
        let sql = """
        SELECT id, name, currency, created_at, updated_at, archived_at
        FROM books
        WHERE archived_at IS NULL
        ORDER BY created_at DESC;
        """
        
        let rows = try db.query(sql: sql)
        return rows.compactMap { BookMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Archived
    
    func fetchArchived() async throws -> [Book] {
        let sql = """
        SELECT id, name, currency, created_at, updated_at, archived_at
        FROM books
        WHERE archived_at IS NOT NULL
        ORDER BY archived_at DESC;
        """
        
        let rows = try db.query(sql: sql)
        return rows.compactMap { BookMapper.fromRow($0) }
    }
    
    // MARK: - Fetch by ID
    
    func fetch(id: UUID) async throws -> Book? {
        let sql = """
        SELECT id, name, currency, created_at, updated_at, archived_at
        FROM books
        WHERE id = ?;
        """
        
        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        return rows.first.flatMap { BookMapper.fromRow($0) }
    }
    
    // MARK: - Create
    
    func create(_ book: Book) async throws {
        let dto = BookMapper.toDTO(book)
        
        let sql = """
        INSERT INTO books (id, name, currency, created_at, updated_at, archived_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        
        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.name,
            dto.currency,
            dto.createdAt,
            dto.updatedAt,
            dto.archivedAt ?? NSNull()
        ])
    }
    
    // MARK: - Update
    
    func update(_ book: Book) async throws {
        var updatedBook = book
        updatedBook.updatedAt = Date()  // Mise à jour automatique
        
        let dto = BookMapper.toDTO(updatedBook)
        
        let sql = """
        UPDATE books
        SET name = ?, currency = ?, updated_at = ?, archived_at = ?
        WHERE id = ?;
        """
        
        try db.execute(sql: sql, parameters: [
            dto.name,
            dto.currency,
            dto.updatedAt,
            dto.archivedAt ?? NSNull(),
            dto.id
        ])
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) async throws {
        let sql = "DELETE FROM books WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
    
    // MARK: - Archive
    
    func archive(id: UUID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
        UPDATE books
        SET archived_at = ?, updated_at = ?
        WHERE id = ?;
        """
        
        try db.execute(sql: sql, parameters: [now, now, id.uuidString])
    }
    
    // MARK: - Unarchive
    
    func unarchive(id: UUID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
        UPDATE books
        SET archived_at = NULL, updated_at = ?
        WHERE id = ?;
        """
        
        try db.execute(sql: sql, parameters: [now, id.uuidString])
    }
}
