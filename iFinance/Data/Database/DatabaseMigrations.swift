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
            (2, migration_v2_budgets_new_schema),
            (3, migration_v3_fix_budget_versions_fk),
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
    
    /// Recrée la table budgets avec le nouveau schéma (name, note, category_ids, anchor_date, created_at)
    /// et crée la table budget_versions.
    private func migration_v2_budgets_new_schema() -> Bool {
        // Cleanup any remnant from a previous partial attempt
        db.execute(sql: "DROP TABLE IF EXISTS budgets_old;")

        // Check if the current budgets table still has the old schema (category_id column)
        let hasOldSchema: Bool
        if let columns = try? db.query(sql: "PRAGMA table_info(budgets);") {
            hasOldSchema = columns.contains { ($0["name"] as? String) == "category_id" }
        } else {
            hasOldSchema = false
        }

        if hasOldSchema {
            // No useful data in the old schema (was broken by NOT NULL constraint) — drop it
            guard db.execute(sql: "DROP TABLE IF EXISTS budgets;") else { return false }
        }

        // Create budgets with new schema if it doesn't exist yet
        guard db.execute(sql: """
            CREATE TABLE IF NOT EXISTS budgets (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                name TEXT NOT NULL DEFAULT '',
                note TEXT,
                period TEXT NOT NULL,
                category_ids TEXT NOT NULL DEFAULT '[]',
                anchor_date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
            );
            """) else { return false }

        // Create budget_versions if it doesn't exist yet
        guard db.execute(sql: DatabaseSchema.createBudgetVersionsTable) else { return false }

        return true
    }

    /// Recrée budget_versions pour corriger la FK corrompue.
    ///
    /// Quand l'ancienne migration a fait ALTER TABLE budgets RENAME TO budgets_old,
    /// SQLite a mis à jour les références internes dans budget_versions :
    /// sa FK pointe désormais sur "budgets_old" au lieu de "budgets".
    /// Chaque INSERT dans budget_versions échoue avec "no such table: main.budgets_old".
    /// La seule solution est de supprimer et recréer budget_versions.
    private func migration_v3_fix_budget_versions_fk() -> Bool {
        guard db.execute(sql: "DROP TABLE IF EXISTS budget_versions;") else { return false }
        guard db.execute(sql: DatabaseSchema.createBudgetVersionsTable) else { return false }
        return true
    }
}
