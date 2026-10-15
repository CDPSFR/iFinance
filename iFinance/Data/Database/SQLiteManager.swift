import Foundation
import SQLCipher

class SQLiteManager {
    /// Demande à SQLite de copier le texte lié. Sans cela (destructeur nil = SQLITE_STATIC),
    /// SQLite garde un pointeur vers une chaîne temporaire déjà libérée au moment du step :
    /// une valeur liée peut alors être lue corrompue, par exemple l'id d'un WHERE, et la
    /// requête ne modifie aucune ligne sans signaler d'erreur.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Tables créées à l'ouverture : celles d'un livre, ou celles du catalogue des livres
    enum Schema {
        case book
        case catalog
        /// Aucune création : fichier ouvert tel quel (copie, vérification)
        case none
    }

    private var db: OpaquePointer?
    private(set) var dbPath: String
    private let schema: Schema
    /// Clé SQLCipher de la base ouverte (nil : base en clair)
    private var key: Data?

    var isEncrypted: Bool { key != nil }
    /// Clé de la base ouverte (nil : base en clair)
    var currentKey: Data? { key }

    /// Ouvre (ou crée) la base `path` ; ":memory:" pour une base vide en mémoire.
    /// Avec `key`, la base est chiffrée par SQLCipher : une mauvaise clé lève une erreur.
    init(path: String, schema: Schema = .book, key: Data? = nil) throws {
        self.dbPath = path
        self.schema = schema
        self.key = key
        print("📁 Database path: \(dbPath)")
        try openDatabase()
        createTables()
    }

    /// Ferme la base courante et en ouvre une autre (changement de livre, verrouillage).
    /// Les repositories gardent la même instance : ils lisent aussitôt la nouvelle base.
    func reopen(path: String, key: Data? = nil) throws {
        guard path != dbPath || key != self.key else { return }
        closeDatabase()
        dbPath = path
        self.key = key
        do {
            try openDatabase()
        } catch {
            // Base vide en mémoire plutôt qu'un handle fermé
            self.key = nil
            dbPath = ":memory:"
            try? openDatabase()
            createTables()
            throw error
        }
        createTables()
    }

    /// Version de SQLCipher liée à l'app (vide si le SQLite du système était utilisé par erreur)
    var cipherVersion: String {
        ((try? query(sql: "PRAGMA cipher_version;"))?.first?["cipher_version"] as? String) ?? ""
    }

    /// Copie cohérente de la base ouverte dans `destination`, chiffrée avec `key` (nil : en clair).
    /// Sert à chiffrer, déchiffrer ou recopier une base (sqlcipher_export).
    func export(to destination: URL, key destinationKey: Data?) throws {
        try? FileManager.default.removeItem(at: destination)
        let escaped = destination.path.replacingOccurrences(of: "'", with: "''")
        // KEY '' : copie en clair ; KEY "x'…'" : copie chiffrée avec cette clé brute
        let keyClause = destinationKey.map { "\"\(BookCrypto.sqlcipherKey($0))\"" } ?? "''"
        guard execute(sql: "ATTACH DATABASE '\(escaped)' AS exported KEY \(keyClause);") else {
            throw SQLiteError.executeQuery(message: "Copie impossible vers \(destination.lastPathComponent)")
        }
        defer { execute(sql: "DETACH DATABASE exported;") }
        guard (try? query(sql: "SELECT sqlcipher_export('exported');")) != nil else {
            throw SQLiteError.executeQuery(message: "Copie impossible vers \(destination.lastPathComponent)")
        }
    }

    /// Copie cohérente de la base ouverte dans `destination`, avec la même clé
    func copy(to destination: URL) throws {
        if isEncrypted {
            try export(to: destination, key: key)
            return
        }
        try? FileManager.default.removeItem(at: destination)
        let escaped = destination.path.replacingOccurrences(of: "'", with: "''")
        guard execute(sql: "VACUUM INTO '\(escaped)';") else {
            throw SQLiteError.executeQuery(message: "Copie impossible vers \(destination.lastPathComponent)")
        }
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Connection Management
    
    private func openDatabase() throws {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) } ?? "handle SQLite non alloué"
            // sqlite3_open alloue un handle même en cas d'échec : il faut le libérer
            sqlite3_close(db)
            db = nil
            throw SQLiteError.openDatabase(message: "\(errorMessage) (\(dbPath))")
        }
        if let key {
            // La clé doit être donnée avant toute lecture ; une mauvaise clé fait échouer la première requête
            // PRAGMA key renvoie une ligne « ok » : lue comme une requête
            guard (try? query(sql: "PRAGMA key = \"\(BookCrypto.sqlcipherKey(key))\";")) != nil,
                  (try? query(sql: "SELECT count(*) FROM sqlite_master;")) != nil else {
                sqlite3_close(db)
                db = nil
                throw SQLiteError.openDatabase(message: "Clé du livre incorrecte (\(dbPath))")
            }
        }
        print("✅ Base de données ouverte avec succès")
        
        // Activer les clés étrangères
        execute(sql: "PRAGMA foreign_keys = ON;")
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            print("❌ Erreur lors de la fermeture de la base de données")
            return
        }
        print("✅ Base de données fermée")
        db = nil
    }
    
    // MARK: - Execute (CREATE, INSERT, UPDATE, DELETE)
    
    @discardableResult
    func execute(sql: String) -> Bool {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Erreur prepare: \(errorMessage)")
            print("SQL: \(sql)")
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Erreur step: \(errorMessage)")
            print("SQL: \(sql)")
            return false
        }
        
        return true
    }
    
    // MARK: - Execute with Parameters
    
    @discardableResult
    func execute(sql: String, parameters: [Any]) throws -> Bool {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: errorMessage)
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind parameters
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            
            switch parameter {
            case let value as String:
                sqlite3_bind_text(statement, bindIndex, value, -1, SQLiteManager.transient)
            case let value as Int:
                sqlite3_bind_int64(statement, bindIndex, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, bindIndex, value)
            case let value as Double:
                sqlite3_bind_double(statement, bindIndex, value)
            case let value as Decimal:
                sqlite3_bind_double(statement, bindIndex, NSDecimalNumber(decimal: value).doubleValue)
            case let value as Bool:
                sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
            case let value as Date:
                let iso8601 = ISO8601DateFormatter().string(from: value)
                sqlite3_bind_text(statement, bindIndex, iso8601, -1, SQLiteManager.transient)
            case let value as Data:
                _ = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, bindIndex, bytes.baseAddress, Int32(value.count), SQLiteManager.transient)
                }
            case is NSNull:
                sqlite3_bind_null(statement, bindIndex)
            case Optional<Any>.none:
                sqlite3_bind_null(statement, bindIndex)
            default:
                throw SQLiteError.bind(message: "Type non supporté: \(type(of: parameter))")
            }
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.step(message: errorMessage)
        }
        
        return true
    }
    
    // MARK: - Transaction

    /// Exécute `body` dans une transaction SQL : tout est validé ensemble sur le disque,
    /// ou rien en cas d'erreur. Beaucoup plus rapide que des écritures validées une à une.
    func inTransaction<T>(_ body: () throws -> T) throws -> T {
        guard execute(sql: "BEGIN IMMEDIATE;") else {
            throw SQLiteError.executeQuery(message: "Impossible d'ouvrir une transaction")
        }
        do {
            let result = try body()
            guard execute(sql: "COMMIT;") else {
                throw SQLiteError.executeQuery(message: "Impossible de valider la transaction")
            }
            return result
        } catch {
            execute(sql: "ROLLBACK;")
            throw error
        }
    }

    // MARK: - Query (SELECT)
    
    func query(sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(message: errorMessage)
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind parameters
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            
            switch parameter {
            case let value as String:
                sqlite3_bind_text(statement, bindIndex, value, -1, SQLiteManager.transient)
            case let value as Int:
                sqlite3_bind_int64(statement, bindIndex, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, bindIndex, value)
            case let value as Double:
                sqlite3_bind_double(statement, bindIndex, value)
            case let value as Decimal:
                sqlite3_bind_double(statement, bindIndex, NSDecimalNumber(decimal: value).doubleValue)
            case let value as Bool:
                sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
            case let value as Date:
                let iso8601 = ISO8601DateFormatter().string(from: value)
                sqlite3_bind_text(statement, bindIndex, iso8601, -1, SQLiteManager.transient)
            case let value as Data:
                _ = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, bindIndex, bytes.baseAddress, Int32(value.count), SQLiteManager.transient)
                }
            case is NSNull:
                sqlite3_bind_null(statement, bindIndex)
            case Optional<Any>.none:
                sqlite3_bind_null(statement, bindIndex)
            default:
                throw SQLiteError.bind(message: "Type non supporté: \(type(of: parameter))")
            }
        }
        
        // Fetch results
        var results: [[String: Any]] = []
        let columnCount = sqlite3_column_count(statement)
        
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnType = sqlite3_column_type(statement, i)
                
                switch columnType {
                case SQLITE_INTEGER:
                    row[columnName] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: cString)
                    }
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, i))
                    if let bytes = sqlite3_column_blob(statement, i) {
                        row[columnName] = Data(bytes: bytes, count: count)
                    } else {
                        row[columnName] = Data()
                    }
                case SQLITE_NULL:
                    row[columnName] = NSNull()
                default:
                    break
                }
            }
            
            results.append(row)
        }
        
        return results
    }
    
    // MARK: - Helper: Last Insert Row ID
    
    func lastInsertRowId() -> Int64 {
        return sqlite3_last_insert_rowid(db)
    }
    
    // MARK: - Table Creation
    
    private func createTables() {
        switch schema {
        case .none:
            return
        case .catalog:
            for sql in DatabaseSchema.catalogStatements { execute(sql: sql) }
            for sql in DatabaseSchema.catalogMigrationStatements { execute(sql: sql) }
            return
        case .book:
            break
        }
        print("📊 Création des tables...")
        
        for sql in DatabaseSchema.createTableStatements {
            if execute(sql: sql) {
                print("✅ Table créée avec succès")
            } else {
                print("⚠️ Table déjà existante ou erreur")
            }
        }
        
        print("📊 Création des index...")
        for sql in DatabaseSchema.createIndexStatements {
            execute(sql: sql)
        }
        
        runMigrations()
        // Migrations numérotées (anciens schémas de budgets, plans d'épargne…)
        DatabaseMigrations(db: self).runMigrations()

        print("✅ Base de données initialisée")
    }

    private func runMigrations() {
        for sql in DatabaseSchema.migrationStatements where !isAppliedColumn(sql) {
            execute(sql: sql)
        }
    }

    /// « ALTER TABLE t ADD COLUMN c » déjà appliqué : la colonne existe (évite une erreur à chaque ouverture)
    private func isAppliedColumn(_ sql: String) -> Bool {
        let words = sql.replacingOccurrences(of: ";", with: "").split(separator: " ").map(String.init)
        guard words.count >= 6, words[0].uppercased() == "ALTER", words[3].uppercased() == "ADD", words[4].uppercased() == "COLUMN" else { return false }
        let columns = (try? query(sql: "SELECT name FROM pragma_table_info(?);", parameters: [words[2]])) ?? []
        return columns.contains { ($0["name"] as? String) == words[5] }
    }
}
