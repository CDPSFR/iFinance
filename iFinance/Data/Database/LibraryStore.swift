import Foundation

/// Fichiers de l'app : un catalogue des livres et une base par livre.
///
/// ```
/// Application Support/iFinance/
/// ├── catalog.sqlite      liste des livres, indices des prix
/// └── Books/<id>.ifbook   données d'un livre
/// ```
///
/// La base du livre courant est ouverte dans `bookDB`, une instance unique partagée par les
/// repositories : changer de livre ferme un fichier et en ouvre un autre.
/// Au premier lancement, l'ancienne base commune (iFinance.sqlite) est découpée en un fichier
/// par livre ; elle est gardée intacte sous « iFinance.sqlite.avant-separation ».
@MainActor
final class LibraryStore {
    enum Mode {
        /// Un fichier par livre
        case split
        /// La séparation a échoué : l'ancienne base commune reste utilisée pour tout
        case legacy
    }

    let catalogDB: SQLiteManager
    let bookDB: SQLiteManager
    let mode: Mode
    let directory: URL

    private(set) var openBookID: UUID?

    // MARK: - Emplacements

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iFinance", isDirectory: true)
    }

    nonisolated static func catalogURL(in directory: URL) -> URL { directory.appendingPathComponent("catalog.sqlite") }
    nonisolated static func booksDirectory(in directory: URL) -> URL { directory.appendingPathComponent("Books", isDirectory: true) }
    nonisolated static func legacyURL(in directory: URL) -> URL { directory.appendingPathComponent("iFinance.sqlite") }
    nonisolated static func bookURL(_ id: UUID, in directory: URL) -> URL {
        booksDirectory(in: directory).appendingPathComponent("\(id.uuidString).ifbook")
    }
    nonisolated static let bookExtension = "ifbook"

    var catalogURL: URL { Self.catalogURL(in: directory) }
    var booksDirectory: URL { Self.booksDirectory(in: directory) }
    func bookURL(_ id: UUID) -> URL { Self.bookURL(id, in: directory) }

    // MARK: - Ouverture

    init(directory: URL = LibraryStore.defaultDirectory) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        switch Self.prepareLibrary(in: directory) {
        case .split:
            try FileManager.default.createDirectory(at: Self.booksDirectory(in: directory), withIntermediateDirectories: true)
            mode = .split
            catalogDB = try SQLiteManager(path: Self.catalogURL(in: directory).path, schema: .catalog)
            // Aucun livre ouvert : base vide en mémoire jusqu'au choix d'un livre
            bookDB = try SQLiteManager(path: ":memory:", schema: .book)
        case .legacy:
            mode = .legacy
            let legacy = try SQLiteManager(path: Self.legacyURL(in: directory).path, schema: .book)
            catalogDB = legacy
            bookDB = legacy
        }
    }

    /// Ouvre la base du livre ; elle est créée si elle n'existe pas encore (nouveau livre).
    /// Un livre protégé ne s'ouvre qu'avec sa clé de données. La ligne du livre y est recopiée
    /// depuis le catalogue (clés étrangères book_id).
    func open(bookID: UUID?, key: Data? = nil) throws {
        guard mode == .split else { openBookID = bookID; return }
        guard let bookID else {
            try bookDB.reopen(path: ":memory:")
            openBookID = nil
            return
        }
        if isProtected(bookID), key == nil { throw LibraryError.locked }
        do {
            try bookDB.reopen(path: bookURL(bookID).path, key: key)
        } catch {
            openBookID = nil
            throw key == nil ? error : LibraryError.wrongKey
        }
        openBookID = bookID
        let rows = try catalogDB.query(
            sql: "SELECT id, name, currency, created_at, updated_at, archived_at, color FROM books WHERE id = ?;",
            parameters: [bookID.uuidString]
        )
        if let row = rows.first {
            // Jamais de INSERT OR REPLACE : remplacer la ligne la supprimerait d'abord, et la
            // suppression en cascade effacerait tout le contenu du livre
            let columns = ["id", "name", "currency", "created_at", "updated_at", "archived_at", "color"]
            try bookDB.execute(
                sql: "INSERT OR IGNORE INTO books (\(columns.joined(separator: ", "))) VALUES (?, ?, ?, ?, ?, ?, ?);",
                parameters: columns.map { row[$0] ?? NSNull() }
            )
            let updated = columns.dropFirst()
            try bookDB.execute(
                sql: "UPDATE books SET \(updated.map { "\($0) = ?" }.joined(separator: ", ")) WHERE id = ?;",
                parameters: updated.map { row[$0] ?? NSNull() } + [bookID.uuidString]
            )
        }
    }

    /// Ferme la base du livre ouvert : plus rien n'est lisible sans sa clé
    func close() {
        try? open(bookID: nil)
    }

    /// Supprime le fichier d'un livre et ses clés (après sa suppression du catalogue)
    func deleteBookFile(_ bookID: UUID) throws {
        guard mode == .split else { return }
        if openBookID == bookID { try open(bookID: nil) }
        try catalogDB.execute(sql: "DELETE FROM book_keys WHERE book_id = ?;", parameters: [bookID.uuidString])
        let url = bookURL(bookID)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    // MARK: - Copies

    /// Copie cohérente de toute la bibliothèque (catalogue et livres) dans `destination`, un dossier
    func copyLibrary(to destination: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        let books = Self.booksDirectory(in: destination)
        try fileManager.createDirectory(at: books, withIntermediateDirectories: true)

        switch mode {
        case .legacy:
            try bookDB.copy(to: Self.legacyURL(in: destination))
        case .split:
            try catalogDB.copy(to: Self.catalogURL(in: destination))
            for id in try bookIDs() {
                let target = Self.bookURL(id, in: destination)
                if id == openBookID {
                    // Livre ouvert : copie cohérente, chiffrée avec sa clé s'il est protégé
                    try bookDB.copy(to: target)
                } else if fileManager.fileExists(atPath: bookURL(id).path) {
                    // Livre fermé : le fichier est stable, copié tel quel (chiffré s'il est protégé)
                    try fileManager.copyItem(at: bookURL(id), to: target)
                }
            }
        }
    }

    /// Copie de la base du livre ouvert, toujours en clair (export)
    func copyOpenBook(to destination: URL) throws {
        try bookDB.export(to: destination, key: nil)
    }

    /// Nombre de comptes ouverts de chaque livre. Un livre protégé et fermé n'est pas lu.
    func activeAccountCounts(for ids: [UUID]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        let sql = "SELECT COUNT(*) AS n FROM accounts WHERE book_id = ? AND is_closed = 0;"
        for id in ids {
            let db: SQLiteManager?
            if id == openBookID || mode == .legacy {
                db = bookDB
            } else if !isProtected(id), FileManager.default.fileExists(atPath: bookURL(id).path) {
                db = try? SQLiteManager(path: bookURL(id).path, schema: .none)
            } else {
                db = nil
            }
            if let n = (try? db?.query(sql: sql, parameters: [id.uuidString]))?.first?["n"] as? Int64 {
                counts[id] = Int(n)
            }
        }
        return counts
    }

    // MARK: - Protection par mot de passe

    enum LibraryError: LocalizedError {
        case locked
        case wrongKey
        case notProtected
        case alreadyProtected
        case unsupported
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .locked: return "Ce livre est verrouillé."
            case .wrongKey: return "Mot de passe incorrect."
            case .notProtected: return "Ce livre n'est pas protégé."
            case .alreadyProtected: return "Ce livre est déjà protégé."
            case .unsupported: return "La protection n'est pas disponible : l'ancienne base commune est encore utilisée."
            case .verificationFailed: return "La copie chiffrée ne correspond pas au livre : rien n'a été modifié."
            }
        }
    }

    /// Clés d'un livre protégé : clé de données chiffrée par le mot de passe et par la clé de secours
    struct BookKeys {
        var password: WrappedKey
        var recovery: WrappedKey
    }

    func isProtected(_ bookID: UUID) -> Bool {
        (try? keys(for: bookID)) != nil
    }

    func keys(for bookID: UUID) throws -> BookKeys? {
        guard let row = try catalogDB.query(sql: "SELECT * FROM book_keys WHERE book_id = ?;", parameters: [bookID.uuidString]).first,
              let passwordSalt = row["password_salt"] as? Data, let passwordIterations = row["password_iterations"] as? Int64,
              let passwordKey = row["password_wrapped_key"] as? Data,
              let recoverySalt = row["recovery_salt"] as? Data, let recoveryIterations = row["recovery_iterations"] as? Int64,
              let recoveryKey = row["recovery_wrapped_key"] as? Data else { return nil }
        return BookKeys(
            password: WrappedKey(salt: passwordSalt, iterations: Int(passwordIterations), sealed: passwordKey),
            recovery: WrappedKey(salt: recoverySalt, iterations: Int(recoveryIterations), sealed: recoveryKey)
        )
    }

    private func saveKeys(_ keys: BookKeys, for bookID: UUID) throws {
        try catalogDB.execute(
            sql: """
            INSERT OR REPLACE INTO book_keys (book_id, password_salt, password_iterations, password_wrapped_key,
                                              recovery_salt, recovery_iterations, recovery_wrapped_key, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [bookID.uuidString, keys.password.salt, keys.password.iterations, keys.password.sealed,
                         keys.recovery.salt, keys.recovery.iterations, keys.recovery.sealed, Date()]
        )
    }

    /// Clé de données d'un livre à partir de son mot de passe (calcul long : hors du fil principal)
    nonisolated static func dataKey(_ keys: BookKeys, password: String) throws -> Data {
        try BookCrypto.unwrap(keys.password, with: password)
    }

    nonisolated static func dataKey(_ keys: BookKeys, recoveryCode: String) throws -> Data {
        do {
            return try BookCrypto.unwrap(keys.recovery, with: BookCrypto.normalizedRecoveryCode(recoveryCode))
        } catch {
            throw RecoveryError.wrongCode
        }
    }

    enum RecoveryError: LocalizedError {
        case wrongCode
        var errorDescription: String? { "Clé de secours incorrecte." }
    }

    /// Chiffre la base d'un livre en clair. Renvoie la clé de secours, à montrer une seule fois.
    func protect(bookID: UUID, password: String) async throws -> String {
        guard mode == .split else { throw LibraryError.unsupported }
        guard !isProtected(bookID) else { throw LibraryError.alreadyProtected }
        let dataKey = try BookCrypto.newDataKey()
        let recoveryCode = try BookCrypto.newRecoveryCode()
        let keys = try await Task.detached(priority: .userInitiated) {
            BookKeys(
                password: try BookCrypto.wrap(dataKey, with: password),
                recovery: try BookCrypto.wrap(dataKey, with: BookCrypto.normalizedRecoveryCode(recoveryCode))
            )
        }.value
        try rewrite(bookID: bookID, from: nil, to: dataKey) {
            try saveKeys(keys, for: bookID)
        }
        return recoveryCode
    }

    /// Déchiffre la base d'un livre protégé et retire ses clés
    func unprotect(bookID: UUID, password: String) async throws {
        guard let keys = try keys(for: bookID) else { throw LibraryError.notProtected }
        let dataKey = try await Task.detached(priority: .userInitiated) { try Self.dataKey(keys, password: password) }.value
        try rewrite(bookID: bookID, from: dataKey, to: nil) {
            try catalogDB.execute(sql: "DELETE FROM book_keys WHERE book_id = ?;", parameters: [bookID.uuidString])
        }
    }

    /// Nouveau mot de passe : seule la clé de données est rechiffrée, la base ne change pas
    func changePassword(bookID: UUID, current: String, new: String) async throws {
        guard var keys = try keys(for: bookID) else { throw LibraryError.notProtected }
        let snapshot = keys
        keys.password = try await Task.detached(priority: .userInitiated) {
            let dataKey = try Self.dataKey(snapshot, password: current)
            return try BookCrypto.wrap(dataKey, with: new)
        }.value
        try saveKeys(keys, for: bookID)
    }

    /// Mot de passe oublié : la clé de secours permet d'en définir un nouveau.
    /// Renvoie une nouvelle clé de secours (l'ancienne ne sert plus).
    func resetPassword(bookID: UUID, recoveryCode: String, new: String) async throws -> (dataKey: Data, recoveryCode: String) {
        guard let keys = try keys(for: bookID) else { throw LibraryError.notProtected }
        let newCode = try BookCrypto.newRecoveryCode()
        let result = try await Task.detached(priority: .userInitiated) {
            let dataKey = try Self.dataKey(keys, recoveryCode: recoveryCode)
            let updated = BookKeys(
                password: try BookCrypto.wrap(dataKey, with: new),
                recovery: try BookCrypto.wrap(dataKey, with: BookCrypto.normalizedRecoveryCode(newCode))
            )
            return (dataKey, updated)
        }.value
        try saveKeys(result.1, for: bookID)
        return (result.0, newCode)
    }

    /// Nouvelle clé de secours (mot de passe requis)
    func regenerateRecoveryCode(bookID: UUID, password: String) async throws -> String {
        guard var keys = try keys(for: bookID) else { throw LibraryError.notProtected }
        let snapshot = keys
        let newCode = try BookCrypto.newRecoveryCode()
        keys.recovery = try await Task.detached(priority: .userInitiated) {
            let dataKey = try Self.dataKey(snapshot, password: password)
            return try BookCrypto.wrap(dataKey, with: BookCrypto.normalizedRecoveryCode(newCode))
        }.value
        try saveKeys(keys, for: bookID)
        return newCode
    }

    /// Clé du livre ouvert, s'il est protégé (activation de Touch ID sans redemander le mot de passe)
    var openBookKey: Data? { openBookID == nil ? nil : bookDB.currentKey }

    /// Recopie la base d'un livre avec une autre clé (chiffrement ou déchiffrement), vérifie la copie,
    /// enregistre les clés (`commit`) puis remplace le fichier. Le livre ouvert est rouvert ensuite.
    private func rewrite(bookID: UUID, from oldKey: Data?, to newKey: Data?, commit: () throws -> Void) throws {
        let fileManager = FileManager.default
        let url = bookURL(bookID)
        let staging = URL(fileURLWithPath: url.path + ".nouveau")
        try? fileManager.removeItem(at: staging)
        defer { try? fileManager.removeItem(at: staging) }

        let wasOpen = openBookID == bookID
        func count(_ db: SQLiteManager) throws -> [Int64] {
            try ["accounts", "transactions", "categories", "payees"].map { table in
                try db.query(sql: "SELECT COUNT(*) AS n FROM \(table);").first?["n"] as? Int64 ?? -1
            }
        }

        // Copie avec la nouvelle clé, depuis la base ouverte ou une connexion dédiée
        let expected: [Int64]
        do {
            let source = wasOpen ? bookDB : try SQLiteManager(path: url.path, schema: .none, key: oldKey)
            expected = try count(source)
            try source.export(to: staging, key: newKey)
        }
        // La copie doit s'ouvrir avec la nouvelle clé et contenir les mêmes données
        do {
            let copy = try SQLiteManager(path: staging.path, schema: .none, key: newKey)
            guard try count(copy) == expected else { throw LibraryError.verificationFailed }
        }

        if wasOpen { try open(bookID: nil) }
        try commit()
        for suffix in ["-wal", "-shm", "-journal"] { try? fileManager.removeItem(atPath: url.path + suffix) }
        _ = try fileManager.replaceItemAt(url, withItemAt: staging)
        if wasOpen { try open(bookID: bookID, key: newKey) }
    }

    func bookIDs() throws -> [UUID] {
        try catalogDB.query(sql: "SELECT id FROM books;").compactMap { ($0["id"] as? String).flatMap(UUID.init) }
    }

    /// Taille totale des fichiers de la bibliothèque
    var totalSize: Int64 {
        let fileManager = FileManager.default
        var urls = [catalogURL, Self.legacyURL(in: directory)]
        urls += (try? fileManager.contentsOfDirectory(at: booksDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.reduce(Int64(0)) { total, url in
            total + ((try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }
    }

    // MARK: - Séparation de l'ancienne base

    /// Tables comparées après la séparation : la somme des lignes des livres doit égaler l'ancienne base
    nonisolated private static let ignoredTables: Set<String> = ["schema_version", "price_indices"]

    /// Prépare le dossier : catalogue existant, installation neuve, ou ancienne base à découper.
    /// En cas d'échec de la séparation, rien n'est modifié et l'ancienne base reste utilisée.
    static func prepareLibrary(in directory: URL) -> Mode {
        let fileManager = FileManager.default
        let catalog = catalogURL(in: directory)
        let legacy = legacyURL(in: directory)
        if fileManager.fileExists(atPath: catalog.path) || !fileManager.fileExists(atPath: legacy.path) {
            return .split
        }
        do {
            try splitLegacyDatabase(in: directory)
            return .split
        } catch {
            print("❌ Séparation des livres impossible, l'ancienne base reste utilisée : \(error)")
            return .legacy
        }
    }

    enum SplitError: LocalizedError {
        case countMismatch(table: String, expected: Int, found: Int)

        var errorDescription: String? {
            switch self {
            case .countMismatch(let table, let expected, let found):
                return "Table \(table) : \(expected) ligne(s) attendue(s), \(found) trouvée(s)"
            }
        }
    }

    /// Découpe iFinance.sqlite en un fichier par livre et crée le catalogue.
    /// Tout est préparé dans des fichiers temporaires, vérifié, puis mis en place.
    static func splitLegacyDatabase(in directory: URL) throws {
        let fileManager = FileManager.default
        let legacyFile = legacyURL(in: directory)
        let staging = directory.appendingPathComponent("separation-en-cours", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: booksDirectory(in: staging), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        do {
            // Ancienne base mise au dernier schéma, puis copiée telle quelle pour chaque livre
            let legacy = try SQLiteManager(path: legacyFile.path, schema: .book)
            let tables = try legacy.query(sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';")
                .compactMap { $0["name"] as? String }
                .filter { !ignoredTables.contains($0) }
            func count(_ db: SQLiteManager, _ table: String) throws -> Int {
                Int(try db.query(sql: "SELECT COUNT(*) AS n FROM \"\(table)\";").first?["n"] as? Int64 ?? 0)
            }
            var expected: [String: Int] = [:]
            for table in tables { expected[table] = try count(legacy, table) }

            let ids = try legacy.query(sql: "SELECT id FROM books;").compactMap { $0["id"] as? String }
            var found: [String: Int] = [:]
            for id in ids {
                let target = booksDirectory(in: staging).appendingPathComponent("\(id).\(bookExtension)")
                try legacy.copy(to: target)
                let book = try SQLiteManager(path: target.path, schema: .none)
                guard book.execute(sql: "PRAGMA foreign_keys = ON;") else { throw SQLiteError.executeQuery(message: "foreign_keys") }
                // Les autres livres et tout ce qui en dépend disparaissent par les suppressions en cascade
                try book.execute(sql: "DELETE FROM books WHERE id <> ?;", parameters: [id])
                book.execute(sql: "DELETE FROM price_indices;")
                book.execute(sql: "VACUUM;")
                for table in tables { found[table, default: 0] += try count(book, table) }
            }
            for table in tables where expected[table] != found[table, default: 0] {
                throw SplitError.countMismatch(table: table, expected: expected[table] ?? 0, found: found[table, default: 0])
            }

            // Catalogue : les livres et les indices des prix
            let catalog = try SQLiteManager(path: catalogURL(in: staging).path, schema: .catalog)
            let escaped = legacyFile.path.replacingOccurrences(of: "'", with: "''")
            guard catalog.execute(sql: "ATTACH DATABASE '\(escaped)' AS legacy;"),
                  catalog.execute(sql: "INSERT INTO books (id, name, currency, created_at, updated_at, archived_at, color) SELECT id, name, currency, created_at, updated_at, archived_at, color FROM legacy.books;"),
                  catalog.execute(sql: "INSERT OR REPLACE INTO price_indices SELECT * FROM legacy.price_indices;"),
                  catalog.execute(sql: "DETACH DATABASE legacy;") else {
                throw SQLiteError.executeQuery(message: "Création du catalogue impossible")
            }
            guard try count(catalog, "books") == ids.count else {
                throw SplitError.countMismatch(table: "catalogue", expected: ids.count, found: try count(catalog, "books"))
            }
        }

        // Mise en place : livres, puis catalogue (sa présence marque la séparation comme faite)
        let books = booksDirectory(in: directory)
        try? fileManager.removeItem(at: books)
        try fileManager.moveItem(at: booksDirectory(in: staging), to: books)
        try fileManager.moveItem(at: catalogURL(in: staging), to: catalogURL(in: directory))

        // L'ancienne base est gardée intacte, à côté
        let kept = directory.appendingPathComponent("iFinance.sqlite.avant-separation")
        try? fileManager.removeItem(at: kept)
        try? fileManager.moveItem(at: legacyFile, to: kept)
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fileManager.removeItem(atPath: legacyFile.path + suffix)
        }
        print("✅ Livres séparés : \((try? fileManager.contentsOfDirectory(atPath: books.path))?.count ?? 0) fichier(s)")
    }
}
