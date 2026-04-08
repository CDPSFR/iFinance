import Foundation

class CategoryRepository: CategoryRepositoryProtocol {
    private let db: SQLiteManager
    
    init(db: SQLiteManager) {
        self.db = db
    }
    
    // MARK: - Fetch All
    
    func fetchAll(for bookID: UUID) async throws -> [Category] {
        let sql = """
        SELECT id, book_id, name, description, parent_id, color, icon, is_income
        FROM categories
        WHERE book_id = ?
        ORDER BY name ASC;
        """
        
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { CategoryMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Root Categories (sans parent)
    
    func fetchRootCategories(for bookID: UUID) async throws -> [Category] {
        let sql = """
        SELECT id, book_id, name, description, parent_id, color, icon, is_income
        FROM categories
        WHERE book_id = ? AND parent_id IS NULL
        ORDER BY name ASC;
        """
        
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { CategoryMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Subcategories
    
    func fetchSubcategories(for parentID: UUID) async throws -> [Category] {
        let sql = """
        SELECT id, book_id, name, description, parent_id, color, icon, is_income
        FROM categories
        WHERE parent_id = ?
        ORDER BY name ASC;
        """
        
        let rows = try db.query(sql: sql, parameters: [parentID.uuidString])
        return rows.compactMap { CategoryMapper.fromRow($0) }
    }
    
    // MARK: - Fetch by ID
    
    func fetch(id: UUID) async throws -> Category? {
        let sql = """
        SELECT id, book_id, name, description, parent_id, color, icon, is_income
        FROM categories
        WHERE id = ?;
        """
        
        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        return rows.first.flatMap { CategoryMapper.fromRow($0) }
    }
    
    // MARK: - Create
    
    func create(_ category: Category) async throws {
        let dto = CategoryMapper.toDTO(category)
        
        let sql = """
        INSERT INTO categories (id, book_id, name, description, parent_id, color, icon, is_income)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.bookID,
            dto.name,
            dto.description ?? NSNull(),
            dto.parentID ?? NSNull(),
            dto.color ?? NSNull(),
            dto.icon ?? NSNull(),
            dto.isIncome ? 1 : 0
        ])
    }
    
    // MARK: - Update
    
    func update(_ category: Category) async throws {
        let dto = CategoryMapper.toDTO(category)
        
        let sql = """
        UPDATE categories
        SET name = ?, description = ?, parent_id = ?, color = ?, icon = ?, is_income = ?
        WHERE id = ?;
        """
        
        try db.execute(sql: sql, parameters: [
            dto.name,
            dto.description ?? NSNull(),
            dto.parentID ?? NSNull(),
            dto.color ?? NSNull(),
            dto.icon ?? NSNull(),
            dto.isIncome ? 1 : 0,
            dto.id
        ])
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) async throws {
        let sql = "DELETE FROM categories WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
}
