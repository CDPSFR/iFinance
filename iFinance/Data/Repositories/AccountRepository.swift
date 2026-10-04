import Foundation

class AccountRepository: AccountRepositoryProtocol {
    private let db: SQLiteManager
    
    init(db: SQLiteManager) {
        self.db = db
    }
    
    // MARK: - Fetch All
    
    func fetchAll(for bookID: UUID) async throws -> [Account] {
        let sql = """
        SELECT id, book_id, name, bank, type, initial_balance, currency, iban, bic, is_excluded_from_reports, initial_balance_date, is_hidden_from_sidebar, is_excluded_from_budgets, is_closed, created_at
        FROM accounts
        WHERE book_id = ?
        ORDER BY created_at DESC;
        """
        
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { AccountMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Active
    
    func fetchActive(for bookID: UUID) async throws -> [Account] {
        let sql = """
        SELECT id, book_id, name, bank, type, initial_balance, currency, iban, bic, is_excluded_from_reports, initial_balance_date, is_hidden_from_sidebar, is_excluded_from_budgets, is_closed, created_at
        FROM accounts
        WHERE book_id = ? AND is_closed = 0
        ORDER BY created_at DESC;
        """
        
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { AccountMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Closed
    
    func fetchClosed(for bookID: UUID) async throws -> [Account] {
        let sql = """
        SELECT id, book_id, name, bank, type, initial_balance, currency, iban, bic, is_excluded_from_reports, initial_balance_date, is_hidden_from_sidebar, is_excluded_from_budgets, is_closed, created_at
        FROM accounts
        WHERE book_id = ? AND is_closed = 1
        ORDER BY created_at DESC;
        """
        
        let rows = try db.query(sql: sql, parameters: [bookID.uuidString])
        return rows.compactMap { AccountMapper.fromRow($0) }
    }
    
    // MARK: - Fetch by ID
    
    func fetch(id: UUID) async throws -> Account? {
        let sql = """
        SELECT id, book_id, name, bank, type, initial_balance, currency, iban, bic, is_excluded_from_reports, initial_balance_date, is_hidden_from_sidebar, is_excluded_from_budgets, is_closed, created_at
        FROM accounts
        WHERE id = ?;
        """
        
        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        return rows.first.flatMap { AccountMapper.fromRow($0) }
    }
    
    // MARK: - Create
    
    func create(_ account: Account) async throws {
        let dto = AccountMapper.toDTO(account)
        
        let sql = """
        INSERT INTO accounts (id, book_id, name, bank, type, initial_balance, currency, iban, bic, is_excluded_from_reports, initial_balance_date, is_hidden_from_sidebar, is_excluded_from_budgets, is_closed, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.bookID,
            dto.name,
            dto.bank ?? NSNull(),
            dto.type,
            dto.initialBalance,
            dto.currency,
            dto.iban ?? NSNull(),
            dto.bic ?? NSNull(),
            dto.isExcludedFromReports ? 1 : 0,
            dto.initialBalanceDate ?? NSNull(),
            dto.isHiddenFromSidebar ? 1 : 0,
            dto.isExcludedFromBudgets ? 1 : 0,
            dto.isClosed ? 1 : 0,
            dto.createdAt
        ])
    }
    
    // MARK: - Update
    
    func update(_ account: Account) async throws {
        let dto = AccountMapper.toDTO(account)
        
        let sql = """
        UPDATE accounts
        SET name = ?, bank = ?, type = ?, initial_balance = ?, currency = ?, iban = ?, bic = ?, is_excluded_from_reports = ?, initial_balance_date = ?, is_hidden_from_sidebar = ?, is_excluded_from_budgets = ?, is_closed = ?
        WHERE id = ?;
        """

        try db.execute(sql: sql, parameters: [
            dto.name,
            dto.bank ?? NSNull(),
            dto.type,
            dto.initialBalance,
            dto.currency,
            dto.iban ?? NSNull(),
            dto.bic ?? NSNull(),
            dto.isExcludedFromReports ? 1 : 0,
            dto.initialBalanceDate ?? NSNull(),
            dto.isHiddenFromSidebar ? 1 : 0,
            dto.isExcludedFromBudgets ? 1 : 0,
            dto.isClosed ? 1 : 0,
            dto.id
        ])
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) async throws {
        let sql = "DELETE FROM accounts WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
    
    // MARK: - Close Account
    
    func close(id: UUID) async throws {
        let sql = "UPDATE accounts SET is_closed = 1 WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
    
    // MARK: - Reopen Account
    
    func reopen(id: UUID) async throws {
        let sql = "UPDATE accounts SET is_closed = 0 WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
}
