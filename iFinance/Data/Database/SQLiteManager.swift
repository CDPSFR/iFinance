import Foundation
import SQLite3

class SQLiteManager {
    private var db: OpaquePointer?
    private let dbPath: String
    
    init(dbName: String = "iFinance.sqlite") throws {
        // Stockage dans Application Support
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("iFinance", isDirectory: true)
        
        // Créer le dossier s'il n'existe pas
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        self.dbPath = appDirectory.appendingPathComponent(dbName).path
        
        print("📁 Database path: \(dbPath)")
        
        try openDatabase()
        createTables()
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
                sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, nil)
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
                sqlite3_bind_text(statement, bindIndex, (iso8601 as NSString).utf8String, -1, nil)
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
                sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, nil)
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
                sqlite3_bind_text(statement, bindIndex, (iso8601 as NSString).utf8String, -1, nil)
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

        print("✅ Base de données initialisée")
    }

    private func runMigrations() {
        for sql in DatabaseSchema.migrationStatements {
            // Les ALTER TABLE échouent silencieusement si la colonne existe déjà
            execute(sql: sql)
        }
    }
}
