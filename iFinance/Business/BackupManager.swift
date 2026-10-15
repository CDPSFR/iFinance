import Foundation
import AppKit
import SwiftUI
import Combine
import Security

/// Copie de la base enregistrée dans le dossier de sauvegarde
struct BackupFile: Identifiable, Hashable {
    let url: URL
    let date: Date
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Description d'une sauvegarde chiffrée (backup.json) : clé de la sauvegarde chiffrée par le
/// mot de passe de sauvegarde, et protection de chaque livre
struct BackupManifest: Codable {
    struct StoredKey: Codable {
        let salt: Data
        let iterations: Int
        let sealed: Data

        init(_ key: WrappedKey) { salt = key.salt; iterations = key.iterations; sealed = key.sealed }
        var wrapped: WrappedKey { WrappedKey(salt: salt, iterations: iterations, sealed: sealed) }
    }

    static let fileName = "backup.json"
    var format = 2
    var createdAt: Date
    var backupKey: StoredKey?
    var books: [LibraryStore.BackupEntry]
}

/// Résultat de la préparation d'une restauration
enum RestorePreparation: Equatable {
    case ready
    /// Livres chiffrés avec un mot de passe de sauvegarde qui n'est pas (ou plus) le bon
    case needsPassword
    case failed
}

/// Fréquence des sauvegardes automatiques
enum BackupInterval: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Chaque jour"
        case .weekly: return "Chaque semaine"
        case .monthly: return "Chaque mois"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        case .monthly: return 30 * 24 * 3600
        }
    }
}

/// Sauvegardes de la base : copie à intervalle régulier dans un dossier choisi par l'utilisateur,
/// liste, suppression et restauration.
///
/// L'app est en bac à sable : le dossier (par défaut ~/Documents/iFinance) doit être choisi une fois
/// dans un panneau, puis il est mémorisé par un signet à portée de sécurité.
/// La restauration est appliquée au lancement suivant, avant l'ouverture de la base.
@MainActor
final class BackupManager: ObservableObject {

    enum Keys {
        static let enabled = "backupEnabled"
        static let interval = "backupInterval"
        static let keepCount = "backupKeepCount"
        static let folderBookmark = "backupFolderBookmark"
        static let lastBackup = "backupLastDate"
    }

    /// Mot de passe des sauvegardes, rangé dans le trousseau (sauvegardes automatiques sans saisie)
    private static let passwordService = "iFinance.backup"
    private static let passwordAccount = "password"

    private static let filePrefix = "iFinance-"
    /// Sauvegarde actuelle : un dossier avec le catalogue et un fichier par livre
    private static let fileExtension = "ifbackup"
    /// Anciennes sauvegardes : la base commune à tous les livres, toujours restaurables
    private static let legacyExtension = "sqlite"

    @Published private(set) var backups: [BackupFile] = []
    @Published private(set) var folderURL: URL?
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// Sauvegarde automatique impossible (mot de passe de sauvegarde manquant)
    @Published private(set) var blockedReason: String?

    private let library: LibraryStore
    private let defaults = UserDefaults.standard
    private var timer: Timer?

    init(library: LibraryStore) {
        self.library = library
        self.folderURL = resolveFolder()
        let last = defaults.double(forKey: Keys.lastBackup)
        self.lastBackupDate = last > 0 ? Date(timeIntervalSince1970: last) : nil

        refresh()
        // Vérification au lancement, puis toutes les heures tant que l'app est ouverte
        Task { await backupIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.backupIfDue() }
        }
    }

    // MARK: - Réglages

    var isEnabled: Bool { defaults.bool(forKey: Keys.enabled) }

    var interval: BackupInterval {
        BackupInterval(rawValue: defaults.string(forKey: Keys.interval) ?? "") ?? .weekly
    }

    /// Nombre de sauvegardes conservées ; 0 = toutes
    var keepCount: Int {
        defaults.object(forKey: Keys.keepCount) == nil ? 10 : defaults.integer(forKey: Keys.keepCount)
    }

    // MARK: - Dossier

    /// ~/Documents/iFinance dans le vrai dossier de l'utilisateur (hors conteneur du bac à sable)
    static var suggestedFolderURL: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("iFinance", isDirectory: true)
    }

    /// Demande le dossier de sauvegarde. Le panneau s'ouvre sur ~/Documents, où l'on peut créer « iFinance ».
    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Dossier des sauvegardes"
        panel.message = "Choisissez le dossier où enregistrer les sauvegardes. Dossier conseillé : Documents/iFinance."
        panel.prompt = "Choisir"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let suggested = Self.suggestedFolderURL
        panel.directoryURL = FileManager.default.fileExists(atPath: suggested.path)
            ? suggested
            : suggested.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Keys.folderBookmark)
            folderURL = url
            refresh()
            return true
        } catch {
            errorMessage = "Impossible de mémoriser ce dossier : \(error.localizedDescription)"
            return false
        }
    }

    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Keys.folderBookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Keys.folderBookmark)
            }
        }
        return url
    }

    /// Exécute une opération avec l'accès au dossier de sauvegarde ouvert
    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let folder = folderURL else { throw BackupError.noFolder }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    func revealFolder() {
        guard let folder = folderURL else { return }
        let accessing = folder.startAccessingSecurityScopedResource()
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        if accessing { folder.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Liste

    func refresh() {
        guard folderURL != nil else {
            backups = []
            return
        }
        do {
            backups = try withFolder { folder in
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                return urls
                    .filter { [Self.fileExtension, Self.legacyExtension].contains($0.pathExtension) && $0.lastPathComponent.hasPrefix(Self.filePrefix) }
                    .map { url in
                        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                        return BackupFile(
                            url: url,
                            date: values?.contentModificationDate ?? .distantPast,
                            size: Self.size(of: url) ?? Int64(values?.fileSize ?? 0)
                        )
                    }
                    .sorted { $0.date > $1.date }
            }
        } catch {
            backups = []
            errorMessage = "Impossible de lire le dossier des sauvegardes : \(error.localizedDescription)"
        }
    }

    // MARK: - Sauvegarde

    /// Sauvegarde automatique si elle est activée et que la dernière est plus ancienne que l'intervalle
    func backupIfDue() async {
        guard isEnabled, folderURL != nil else { return }
        if let last = lastBackupDate, Date().timeIntervalSince(last) < interval.seconds { return }
        await backupNow(automatic: true)
    }

    // MARK: - Mot de passe des sauvegardes

    var hasBackupPassword: Bool { backupPassword != nil }

    private var backupPassword: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.passwordService,
            kSecAttrAccount as String: Self.passwordAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Définit ou remplace le mot de passe (l'actuel est demandé pour le remplacer). nil le supprime.
    /// Les sauvegardes déjà faites gardent le mot de passe avec lequel elles ont été chiffrées.
    func setBackupPassword(_ new: String?, current: String?) throws {
        if let stored = backupPassword, stored != current { throw BookCryptoError.wrongSecret }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.passwordService,
            kSecAttrAccount as String: Self.passwordAccount
        ]
        SecItemDelete(base as CFDictionary)
        if let new, let data = new.data(using: .utf8) {
            var attributes = base
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw BackupError.keychain }
        }
        blockedReason = nil
        objectWillChange.send()
    }

    /// Taille d'une sauvegarde-dossier (somme de ses fichiers) ; nil pour un simple fichier
    private static func size(of url: URL) -> Int64? {
        guard url.pathExtension == fileExtension,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// Crée une copie chiffrée du catalogue et de chaque livre puis la dépose dans le dossier de
    /// sauvegarde. Les livres protégés gardent leur clé ; les autres sont chiffrés avec une clé
    /// propre à la sauvegarde, elle-même chiffrée par le mot de passe de sauvegarde.
    func backupNow(automatic: Bool = false) async {
        guard !isWorking else { return }
        let password = backupPassword
        if library.needsBackupPassword, password == nil {
            let message = "Définissez un mot de passe de sauvegarde : il chiffre les livres qui ne sont pas protégés par leur propre mot de passe."
            blockedReason = message
            if !automatic { errorMessage = message }
            return
        }
        blockedReason = nil
        isWorking = true
        defer { isWorking = false }

        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "\(Self.filePrefix)\(formatter.string(from: Date())).\(Self.fileExtension)"
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(name)

        do {
            var manifest = BackupManifest(createdAt: Date(), backupKey: nil, books: [])
            var backupKey: Data?
            if let password {
                let key = try BookCrypto.newDataKey()
                let wrapped = try await Task.detached(priority: .utility) { try BookCrypto.wrap(key, with: password) }.value
                backupKey = key
                manifest.backupKey = BackupManifest.StoredKey(wrapped)
            }
            manifest.books = try library.copyLibrary(to: temporary, backupKey: backupKey)
            defer { try? fileManager.removeItem(at: temporary) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: temporary.appendingPathComponent(BackupManifest.fileName))

            try withFolder { folder in
                try fileManager.copyItem(at: temporary, to: folder.appendingPathComponent(name))
            }

            let now = Date()
            lastBackupDate = now
            defaults.set(now.timeIntervalSince1970, forKey: Keys.lastBackup)
            refresh()
            prune()
        } catch {
            errorMessage = "La sauvegarde a échoué : \(error.localizedDescription)"
        }
    }

    /// Supprime les sauvegardes les plus anciennes au-delà du nombre conservé
    private func prune() {
        let keep = keepCount
        guard keep > 0, backups.count > keep else { return }
        delete(Array(backups.dropFirst(keep)))
    }

    // MARK: - Suppression

    /// Place les sauvegardes dans la Corbeille (ou les supprime si la Corbeille est indisponible)
    func delete(_ files: [BackupFile]) {
        guard !files.isEmpty else { return }
        do {
            try withFolder { _ in
                for file in files {
                    do {
                        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                    } catch {
                        try FileManager.default.removeItem(at: file.url)
                    }
                }
            }
        } catch {
            errorMessage = "La suppression a échoué : \(error.localizedDescription)"
        }
        refresh()
    }

    // MARK: - Restauration

    private static var databaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iFinance", isDirectory: true)
    }

    /// Sauvegarde à restaurer au prochain lancement (dossier .ifbackup, ou ancienne base .sqlite)
    private static var pendingRestoreURL: URL { databaseDirectory.appendingPathComponent("restauration-en-attente", isDirectory: true) }
    /// Bibliothèque remplacée par la dernière restauration, gardée par sécurité
    static var beforeRestoreURL: URL { databaseDirectory.appendingPathComponent("avant-restauration", isDirectory: true) }

    /// Prépare la restauration : la sauvegarde est copiée (et ses livres non protégés déchiffrés)
    /// à côté des bases, qu'elle remplacera au prochain lancement.
    /// Le mot de passe de sauvegarde du trousseau est essayé d'abord, puis `password`.
    func prepareRestore(from file: BackupFile, password: String? = nil) async -> RestorePreparation {
        let fileManager = FileManager.default
        let pending = Self.pendingRestoreURL
        do {
            // Sauvegarde chiffrée : clé de la sauvegarde à partir du mot de passe
            var manifest: BackupManifest?
            var backupKey: Data?
            let manifestURL = file.url.appendingPathComponent(BackupManifest.fileName)
            let manifestData = try withFolder { _ in try? Data(contentsOf: manifestURL) }
            if let manifestData {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(BackupManifest.self, from: manifestData)
                manifest = decoded
                if let stored = decoded.backupKey, decoded.books.contains(where: { $0.protection == .backup }) {
                    let candidates = [backupPassword, password].compactMap { $0 }
                    let wrapped = stored.wrapped
                    backupKey = await Task.detached(priority: .userInitiated) {
                        candidates.lazy.compactMap { try? BookCrypto.unwrap(wrapped, with: $0) }.first
                    }.value
                    guard backupKey != nil else { return .needsPassword }
                }
            }

            try withFolder { _ in
                try? fileManager.removeItem(at: pending)
                try fileManager.createDirectory(at: pending, withIntermediateDirectories: true)
                if file.url.pathExtension == Self.legacyExtension {
                    // Ancienne sauvegarde : la base commune sera découpée par livre au lancement
                    try fileManager.copyItem(at: file.url, to: LibraryStore.legacyURL(in: pending))
                } else if let manifest {
                    try LibraryStore.extractBackup(file.url, entries: manifest.books, backupKey: backupKey, to: pending)
                } else {
                    // Sauvegarde en clair, sans manifeste
                    for item in try fileManager.contentsOfDirectory(at: file.url, includingPropertiesForKeys: nil) {
                        try fileManager.copyItem(at: item, to: pending.appendingPathComponent(item.lastPathComponent))
                    }
                }
            }
            return .ready
        } catch {
            try? fileManager.removeItem(at: pending)
            errorMessage = "La restauration a échoué : \(error.localizedDescription)"
            return .failed
        }
    }

    /// Relance l'app pour appliquer la restauration préparée
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// À appeler au lancement, AVANT l'ouverture des bases : remplace la bibliothèque (catalogue,
    /// livres, ancienne base) par la sauvegarde préparée. L'ancienne bibliothèque est gardée
    /// dans « avant-restauration ».
    nonisolated static func applyPendingRestoreIfNeeded(in directory: URL = LibraryStore.defaultDirectory) {
        let fileManager = FileManager.default
        let pending = directory.appendingPathComponent("restauration-en-attente", isDirectory: true)
        let previous = directory.appendingPathComponent("avant-restauration", isDirectory: true)
        guard fileManager.fileExists(atPath: pending.path) else { return }

        // Fichiers de la bibliothèque, journaux SQLite compris
        let catalog = LibraryStore.catalogURL(in: directory)
        let legacy = LibraryStore.legacyURL(in: directory)
        let books = LibraryStore.booksDirectory(in: directory)
        let current = [catalog, legacy].flatMap { url in ["", "-wal", "-shm", "-journal"].map { URL(fileURLWithPath: url.path + $0) } } + [books]

        do {
            try? fileManager.removeItem(at: previous)
            try fileManager.createDirectory(at: previous, withIntermediateDirectories: true)
            for url in current where fileManager.fileExists(atPath: url.path) {
                try fileManager.moveItem(at: url, to: previous.appendingPathComponent(url.lastPathComponent))
            }
            for item in try fileManager.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil) {
                try fileManager.moveItem(at: item, to: directory.appendingPathComponent(item.lastPathComponent))
            }
            try fileManager.removeItem(at: pending)
            print("✅ Bibliothèque restaurée depuis une sauvegarde")
        } catch {
            print("❌ Restauration impossible : \(error)")
            // On remet l'ancienne bibliothèque en place
            for item in (try? fileManager.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil)) ?? [] {
                let target = directory.appendingPathComponent(item.lastPathComponent)
                if !fileManager.fileExists(atPath: target.path) { try? fileManager.moveItem(at: item, to: target) }
            }
        }
    }
}

enum BackupError: LocalizedError {
    case noFolder
    case copyFailed
    case keychain

    var errorDescription: String? {
        switch self {
        case .noFolder: return "Aucun dossier de sauvegarde n'est choisi."
        case .copyFailed: return "La copie de la base n'a pas pu être créée."
        case .keychain: return "Le mot de passe n'a pas pu être enregistré dans le trousseau."
        }
    }
}
