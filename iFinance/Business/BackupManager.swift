import Foundation
import AppKit
import SwiftUI
import Combine

/// Copie de la base enregistrée dans le dossier de sauvegarde
struct BackupFile: Identifiable, Hashable {
    let url: URL
    let date: Date
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
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
        await backupNow()
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

    /// Crée une copie cohérente du catalogue et de chaque livre (VACUUM INTO) puis la dépose
    /// dans le dossier de sauvegarde
    func backupNow() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "\(Self.filePrefix)\(formatter.string(from: Date())).\(Self.fileExtension)"
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(name)

        do {
            try library.copyLibrary(to: temporary)
            defer { try? fileManager.removeItem(at: temporary) }

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

    /// Prépare la restauration : la sauvegarde est copiée à côté des bases et les remplacera
    /// au prochain lancement. Renvoie vrai si la copie est prête.
    func prepareRestore(from file: BackupFile) -> Bool {
        do {
            try withFolder { _ in
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: Self.pendingRestoreURL)
                try fileManager.createDirectory(at: Self.pendingRestoreURL, withIntermediateDirectories: true)
                if file.url.pathExtension == Self.legacyExtension {
                    // Ancienne sauvegarde : la base commune sera découpée par livre au lancement
                    try fileManager.copyItem(at: file.url, to: LibraryStore.legacyURL(in: Self.pendingRestoreURL))
                } else {
                    for item in try fileManager.contentsOfDirectory(at: file.url, includingPropertiesForKeys: nil) {
                        try fileManager.copyItem(at: item, to: Self.pendingRestoreURL.appendingPathComponent(item.lastPathComponent))
                    }
                }
            }
            return true
        } catch {
            errorMessage = "La restauration a échoué : \(error.localizedDescription)"
            return false
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

    var errorDescription: String? {
        switch self {
        case .noFolder: return "Aucun dossier de sauvegarde n'est choisi."
        case .copyFailed: return "La copie de la base n'a pas pu être créée."
        }
    }
}
