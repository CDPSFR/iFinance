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
    /// La ligne du livre y est recopiée depuis le catalogue (clés étrangères book_id).
    func open(bookID: UUID?) throws {
        guard mode == .split else { openBookID = bookID; return }
        guard let bookID else {
            try bookDB.reopen(path: ":memory:")
            openBookID = nil
            return
        }
        try bookDB.reopen(path: bookURL(bookID).path)
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

    /// Supprime le fichier d'un livre (après sa suppression du catalogue)
    func deleteBookFile(_ bookID: UUID) throws {
        guard mode == .split else { return }
        if openBookID == bookID { try open(bookID: nil) }
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
                    try bookDB.copy(to: target)
                } else if fileManager.fileExists(atPath: bookURL(id).path) {
                    let source = try SQLiteManager(path: bookURL(id).path, schema: .none)
                    try source.copy(to: target)
                }
            }
        }
    }

    /// Copie cohérente de la base du livre ouvert
    func copyOpenBook(to destination: URL) throws {
        try bookDB.copy(to: destination)
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
