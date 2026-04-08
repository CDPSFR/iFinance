import Foundation

class TransactionRepository: TransactionRepositoryProtocol {
    private let db: SQLiteManager
    
    init(db: SQLiteManager) {
        self.db = db
    }
    
    // MARK: - Fetch All
    
    func fetchAll(for accountID: UUID) async throws -> [Transaction] {
        let sql = """
        SELECT id, date, amount, account_id, to_account_id, linked_transaction_id,
               payee_id, category_id, type, memo, is_reconciled, recurring_template_id, status
        FROM transactions
        WHERE account_id = ?
        ORDER BY date DESC, id DESC;
        """
        
        let rows = try db.query(sql: sql, parameters: [accountID.uuidString])
        return rows.compactMap { TransactionMapper.fromRow($0) }
    }
    
    // MARK: - Fetch Between Dates
    
    func fetchBetween(accountID: UUID, start: Date, end: Date) async throws -> [Transaction] {
        let dateFormatter = ISO8601DateFormatter()
        let startStr = dateFormatter.string(from: start)
        let endStr = dateFormatter.string(from: end)
        
        let sql = """
        SELECT id, date, amount, account_id, to_account_id, linked_transaction_id,
               payee_id, category_id, type, memo, is_reconciled, recurring_template_id, status
        FROM transactions
        WHERE account_id = ? AND date >= ? AND date <= ?
        ORDER BY date ASC, id ASC;
        """
        
        let rows = try db.query(sql: sql, parameters: [accountID.uuidString, startStr, endStr])
        return rows.compactMap { TransactionMapper.fromRow($0) }
    }
    
    // MARK: - Fetch by ID
    
    func fetch(id: UUID) async throws -> Transaction? {
        let sql = """
        SELECT id, date, amount, account_id, to_account_id, linked_transaction_id,
               payee_id, category_id, type, memo, is_reconciled, recurring_template_id, status
        FROM transactions
        WHERE id = ?;
        """
        
        let rows = try db.query(sql: sql, parameters: [id.uuidString])
        return rows.first.flatMap { TransactionMapper.fromRow($0) }
    }
    
    // MARK: - Create
    
    func create(_ transaction: Transaction) async throws {
        let dto = TransactionMapper.toDTO(transaction)
        
        let sql = """
        INSERT INTO transactions (
            id, date, amount, account_id, to_account_id, linked_transaction_id,
            payee_id, category_id, type, memo, is_reconciled, recurring_template_id, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        try db.execute(sql: sql, parameters: [
            dto.id,
            dto.date,
            dto.amount,
            dto.accountID,
            dto.toAccountID ?? NSNull(),
            dto.linkedTransactionID ?? NSNull(),
            dto.payeeID ?? NSNull(),
            dto.categoryID ?? NSNull(),
            dto.type,
            dto.memo ?? NSNull(),
            dto.isReconciled ? 1 : 0,
            dto.recurringTemplateID ?? NSNull(),
            dto.status
        ])
    }
    
    // MARK: - Update
    
    func update(_ transaction: Transaction) async throws {
        let dto = TransactionMapper.toDTO(transaction)
        
        let sql = """
        UPDATE transactions
        SET date = ?, amount = ?, account_id = ?, to_account_id = ?, linked_transaction_id = ?,
            payee_id = ?, category_id = ?, type = ?, memo = ?, is_reconciled = ?,
            recurring_template_id = ?, status = ?
        WHERE id = ?;
        """
        
        try db.execute(sql: sql, parameters: [
            dto.date,
            dto.amount,
            dto.accountID,
            dto.toAccountID ?? NSNull(),
            dto.linkedTransactionID ?? NSNull(),
            dto.payeeID ?? NSNull(),
            dto.categoryID ?? NSNull(),
            dto.type,
            dto.memo ?? NSNull(),
            dto.isReconciled ? 1 : 0,
            dto.recurringTemplateID ?? NSNull(),
            dto.status,
            dto.id
        ])
    }
    
    // MARK: - Delete
    
    func delete(id: UUID) async throws {
        let sql = "DELETE FROM transactions WHERE id = ?;"
        try db.execute(sql: sql, parameters: [id.uuidString])
    }
    
    // MARK: - Create Transfer
    // MARK: - Create Transfer (2 transactions liées)

    func createTransfer(
        from sourceAccountID: UUID,
        to destinationAccountID: UUID,
        amount: Decimal,
        date: Date,
        memo: String?
    ) async throws -> (Transaction, Transaction) {
        
        // 🔍 DEBUG: Vérifier que les comptes existent
        print("🔍 Creating transfer:")
        print("   Source account ID: \(sourceAccountID)")
        print("   Destination account ID: \(destinationAccountID)")
        
        let checkAccountSQL = "SELECT id FROM accounts WHERE id = ?;"
        let sourceExists = try db.query(sql: checkAccountSQL, parameters: [sourceAccountID.uuidString])
        let destExists = try db.query(sql: checkAccountSQL, parameters: [destinationAccountID.uuidString])
        
        print("   Source exists: \(sourceExists.count > 0)")
        print("   Dest exists: \(destExists.count > 0)")
        
        if sourceExists.isEmpty {
            throw NSError(domain: "TransactionRepository", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Source account does not exist"])
        }
        if destExists.isEmpty {
            throw NSError(domain: "TransactionRepository", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Destination account does not exist"])
        }
        
        // ✅ ÉTAPE 1: Créer la transaction source SANS linkedTransactionID
        var sourceTransaction = Transaction(
            date: date,
            amount: -abs(amount),
            accountID: sourceAccountID,
            toAccountID: destinationAccountID,
            linkedTransactionID: nil,  // ✅ nil pour l'instant
            payeeID: nil,
            categoryID: nil,
            type: .transfer,
            memo: memo,
            isReconciled: false,
            recurringTemplateID: nil,
            status: .cleared
        )
        
        // ✅ ÉTAPE 2: Créer la transaction destination SANS linkedTransactionID
        var destTransaction = Transaction(
            date: date,
            amount: abs(amount),
            accountID: destinationAccountID,
            toAccountID: sourceAccountID,
            linkedTransactionID: nil,  // ✅ nil pour l'instant aussi
            payeeID: nil,
            categoryID: nil,
            type: .transfer,
            memo: memo,
            isReconciled: false,
            recurringTemplateID: nil,
            status: .cleared
        )
        
        // ✅ ÉTAPE 3: Insérer les deux transactions SANS liens
        print("🔍 Creating source transaction (no link yet): \(sourceTransaction.id)")
        try await create(sourceTransaction)
        print("✅ Source transaction created")
        
        print("🔍 Creating dest transaction (no link yet): \(destTransaction.id)")
        try await create(destTransaction)
        print("✅ Dest transaction created")
        
        // ✅ ÉTAPE 4: Maintenant mettre à jour les liens
        sourceTransaction.linkedTransactionID = destTransaction.id
        destTransaction.linkedTransactionID = sourceTransaction.id
        
        print("🔍 Updating source transaction with link to: \(destTransaction.id)")
        try await update(sourceTransaction)
        print("✅ Source transaction linked")
        
        print("🔍 Updating dest transaction with link to: \(sourceTransaction.id)")
        try await update(destTransaction)
        print("✅ Dest transaction linked")
        
        return (sourceTransaction, destTransaction)
    }
}
