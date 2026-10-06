import Foundation

class PayeeRepository: PayeeRepositoryProtocol {
    private let db: SQLiteManager
    
    init(db: SQLiteManager) {
        self.db = db
    }
    
    // MARK: - Fetch All
    
    func fetchAll(for bookID: UUID) async throws -> [Payee] {
        let sql = """
        SELECT id, book_id, name, city, postal_code, notes, default_category_id
        FROM payees
        WHERE book_id = ?
        ORDER BY name ASC;
        """
        
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { PayeeMapper.fromRow($0) }
    }
    
    // MARK: - Fetch by ID
    
    func fetch(id: UUID) async throws -> Payee? {
        let sql = """
        SELECT id, book_id, name, city, postal_code, notes, default_category_id
        FROM payees
        WHERE id = ?;
        """
        
        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        return rows.first.flatMap { PayeeMapper.fromRow($0) }
    }
    
    // MARK: - Search
    
    func search(for bookID: UUID, query: String) async throws -> [Payee] {
        let sql = """
        SELECT id, book_id, name, city, postal_code, notes, default_category_id
        FROM payees
        WHERE book_id = ? AND (name LIKE ? OR city LIKE ?)
        ORDER BY name ASC
        LIMIT 20;
        """
        
        let searchPattern = "%\(query)%"
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString, searchPattern, searchPattern])
        return rows.compactMap { PayeeMapper.fromRow($0) }
    }
    
    // MARK: - Create
    
    func create(_ payee: Payee) async throws {
        try insert(payee)
    }

    /// Une seule transaction SQL pour tout le lot (import QIF)
    func createBatch(_ payees: [Payee]) async throws {
        try db.inTransaction {
            for payee in payees {
                try insert(payee)
            }
        }
    }

    private func insert(_ payee: Payee) throws {
        let dto = PayeeMapper.toDTO(payee)
        
        let sql = """
        INSERT INTO payees (id, book_id, name, city, postal_code, notes, default_category_id)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        
        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.bookID,
            dto.name,
            dto.city ?? NSNull(),
            dto.postalCode ?? NSNull(),
            dto.notes ?? NSNull(),
            dto.defaultCategoryID ?? NSNull()
        ])
    }
    
    // MARK: - Update
    
    func update(_ payee: Payee) async throws {
        let dto = PayeeMapper.toDTO(payee)
        
        let sql = """
        UPDATE payees
        SET name = ?, city = ?, postal_code = ?, notes = ?, default_category_id = ?
        WHERE id = ?;
        """
        
        try db.execute(sql: sql, parameters: [
            dto.name,
            dto.city ?? NSNull(),
            dto.postalCode ?? NSNull(),
            dto.notes ?? NSNull(),
            dto.defaultCategoryID ?? NSNull(),
            dto.id
        ])
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) async throws {
        let sql = "DELETE FROM payees WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
}
