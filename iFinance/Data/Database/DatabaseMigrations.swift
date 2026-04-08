import Foundation

struct DatabaseMigrations {
    
    private let db: SQLiteManager
    
    init(db: SQLiteManager) {
        self.db = db
    }
    
    /// Exécute toutes les migrations nécessaires
    func runMigrations() {
        createVersionTable()
        
        let currentVersion = getCurrentVersion()
        print("📊 Version actuelle de la base: \(currentVersion)")
        
        // Liste de toutes les migrations
        let migrations: [(version: Int, migration: () -> Bool)] = [
            (1, migration_v1_initial),
            // Ajoutez vos futures migrations ici
            // (2, migration_v2_add_column),
        ]
        
        for (version, migration) in migrations where version > currentVersion {
            print("🔄 Migration vers version \(version)...")
            if migration() {
                updateVersion(to: version)
                print("✅ Migration v\(version) réussie")
            } else {
                print("❌ Migration v\(version) échouée")
                break
            }
        }
    }
    
    // MARK: - Version Management
    
    private func createVersionTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        );
        """
        db.execute(sql: sql)
    }
    
    private func getCurrentVersion() -> Int {
        do {
            let results = try db.query(sql: "SELECT MAX(version) as version FROM schema_version;")
            if let row = results.first, let version = row["version"] as? Int64 {
                return Int(version)
            }
        } catch {
            print("⚠️ Erreur lecture version: \(error)")
        }
        return 0
    }
    
    private func updateVersion(to version: Int) {
        let sql = "INSERT INTO schema_version (version, applied_at) VALUES (?, ?);"
        try? db.execute(sql: sql, parameters: [version, ISO8601DateFormatter().string(from: Date())])
    }
    
    // MARK: - Migrations
    
    private func migration_v1_initial() -> Bool {
        // La v1 est déjà créée par DatabaseSchema
        return true
    }
    
    // Exemple de migration future
    /*
    private func migration_v2_add_column() -> Bool {
        let sql = "ALTER TABLE transactions ADD COLUMN tags TEXT;"
        return db.execute(sql: sql)
    }
    */
}
