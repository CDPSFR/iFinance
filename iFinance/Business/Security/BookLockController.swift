import Foundation
import AppKit
import SwiftUI
import Combine
import LocalAuthentication
import Security

/// Verrouillage des livres protégés : ouverture avec le mot de passe, Touch ID ou la clé de secours,
/// délai après plusieurs échecs, et verrouillage automatique (inactivité, veille, ⌘L, changement de livre).
/// Un livre verrouillé a sa base fermée : rien n'en est lisible, même par l'app.
@MainActor
final class BookLockController: ObservableObject {
    enum Keys {
        static let autoLockMinutes = "autoLockMinutes"
        static func biometricDomain(_ id: UUID) -> String { "biometricDomainState.\(id.uuidString)" }
    }

    /// Délais de verrouillage proposés, en minutes (0 = jamais)
    static let autoLockChoices = [0, 1, 5, 15, 30, 60]
    static let defaultAutoLockMinutes = 15

    @Published private(set) var isLocked = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// Prochain essai possible après plusieurs échecs
    @Published private(set) var retryAfter: Date?
    @Published var autoLockMinutes: Int {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: Keys.autoLockMinutes) }
    }

    private let library: LibraryStore
    private(set) var bookID: UUID?
    private var failures: [UUID: Int] = [:]
    private var lastActivity = Date()
    private var monitors: [Any] = []
    private var timer: Timer?

    init(library: LibraryStore) {
        self.library = library
        let stored = UserDefaults.standard.object(forKey: Keys.autoLockMinutes) as? Int
        self.autoLockMinutes = stored ?? Self.defaultAutoLockMinutes
        startMonitoring()
    }

    var isAvailable: Bool { library.mode == .split }

    func isProtected(_ bookID: UUID) -> Bool { library.isProtected(bookID) }

    // MARK: - Ouverture d'un livre

    /// Appelé au choix d'un livre : un livre protégé s'affiche verrouillé, sa base reste fermée.
    /// Changer de livre verrouille donc le précédent.
    func open(_ bookID: UUID?) throws {
        self.bookID = bookID
        errorMessage = nil
        retryAfter = nil
        if let bookID, library.isProtected(bookID) {
            try library.open(bookID: nil)
            isLocked = true
        } else {
            try library.open(bookID: bookID)
            isLocked = false
        }
    }

    // MARK: - Déverrouillage

    func unlock(password: String) async -> Bool {
        guard let bookID, let keys = try? library.keys(for: bookID), canTry else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let key = try await Task.detached(priority: .userInitiated) { try LibraryStore.dataKey(keys, password: password) }.value
            return finishUnlock(bookID, key: key)
        } catch {
            registerFailure(for: bookID, message: "Mot de passe incorrect.")
            return false
        }
    }

    /// Mot de passe oublié : la clé de secours ouvre le livre et définit un nouveau mot de passe.
    /// Renvoie la nouvelle clé de secours à noter.
    func unlock(recoveryCode: String, newPassword: String) async -> String? {
        guard let bookID, canTry else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await library.resetPassword(bookID: bookID, recoveryCode: recoveryCode, new: newPassword)
            removeBiometricKey(for: bookID)
            return finishUnlock(bookID, key: result.dataKey) ? result.recoveryCode : nil
        } catch {
            registerFailure(for: bookID, message: (error as? LocalizedError)?.errorDescription ?? "Clé de secours incorrecte.")
            return nil
        }
    }

    private func finishUnlock(_ bookID: UUID, key: Data) -> Bool {
        guard self.bookID == bookID else { return false }
        do {
            try library.open(bookID: bookID, key: key)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
        failures[bookID] = 0
        retryAfter = nil
        errorMessage = nil
        lastActivity = Date()
        isLocked = false
        return true
    }

    /// Ferme la base du livre affiché s'il est protégé
    func lock() {
        guard let bookID, !isLocked, library.isProtected(bookID) else { return }
        library.close()
        isLocked = true
    }

    // MARK: - Essais

    /// Après 3 échecs, attente de 5 s, puis doublée à chaque échec (5 minutes au plus)
    private var canTry: Bool {
        if let retryAfter, retryAfter > Date() {
            errorMessage = "Trop d'essais : réessayez dans \(Int(retryAfter.timeIntervalSinceNow.rounded(.up))) s."
            return false
        }
        return true
    }

    private func registerFailure(for bookID: UUID, message: String) {
        let count = (failures[bookID] ?? 0) + 1
        failures[bookID] = count
        errorMessage = message
        if count >= 3 {
            let delay = min(5 * pow(2, Double(count - 3)), 300)
            retryAfter = Date().addingTimeInterval(delay)
            errorMessage = "\(message) Prochain essai dans \(Int(delay)) s."
        }
    }

    // MARK: - Touch ID

    private static let keychainService = "iFinance.bookKeys"

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func isBiometricEnabled(for bookID: UUID) -> Bool {
        UserDefaults.standard.data(forKey: Keys.biometricDomain(bookID)) != nil
    }

    /// Active Touch ID pour le livre ouvert et déverrouillé : sa clé est rangée dans le trousseau.
    /// Elle ne sert que si les empreintes du Mac n'ont pas changé depuis.
    func enableBiometrics(for bookID: UUID) -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
              let domain = context.domainState.biometry.stateHash,
              library.openBookID == bookID, let key = library.openBookKey else { return false }
        removeBiometricKey(for: bookID)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: bookID.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key
        ]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { return false }
        UserDefaults.standard.set(domain, forKey: Keys.biometricDomain(bookID))
        objectWillChange.send()
        return true
    }

    func removeBiometricKey(for bookID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: bookID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: Keys.biometricDomain(bookID))
        objectWillChange.send()
    }

    /// Déverrouille avec Touch ID ; refuse si les empreintes ont changé depuis l'activation
    func unlockWithBiometrics(bookName: String) async -> Bool {
        guard let bookID, isBiometricEnabled(for: bookID), canTry else { return false }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        if context.domainState.biometry.stateHash != UserDefaults.standard.data(forKey: Keys.biometricDomain(bookID)) {
            removeBiometricKey(for: bookID)
            errorMessage = "Les empreintes de ce Mac ont changé : Touch ID est désactivé pour ce livre. Entrez le mot de passe."
            return false
        }
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                   localizedReason: "ouvrir le livre « \(bookName) »") else { return false }
        } catch {
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: bookID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let key = item as? Data else {
            errorMessage = "La clé enregistrée pour Touch ID est introuvable. Entrez le mot de passe."
            return false
        }
        return finishUnlock(bookID, key: key)
    }

    // MARK: - Gestion du mot de passe (Réglages › Livres)

    /// Chiffre le livre ; renvoie la clé de secours
    func protect(_ bookID: UUID, password: String) async throws -> String {
        isWorking = true
        defer { isWorking = false }
        let code = try await library.protect(bookID: bookID, password: password)
        objectWillChange.send()
        return code
    }

    func changePassword(_ bookID: UUID, current: String, new: String) async throws {
        isWorking = true
        defer { isWorking = false }
        try await library.changePassword(bookID: bookID, current: current, new: new)
    }

    func unprotect(_ bookID: UUID, password: String) async throws {
        isWorking = true
        defer { isWorking = false }
        try await library.unprotect(bookID: bookID, password: password)
        removeBiometricKey(for: bookID)
        // Livre affiché et verrouillé : il s'ouvre, puisqu'il n'a plus de mot de passe
        if self.bookID == bookID, isLocked {
            try library.open(bookID: bookID)
            isLocked = false
        }
    }

    func regenerateRecoveryCode(_ bookID: UUID, password: String) async throws -> String {
        isWorking = true
        defer { isWorking = false }
        return try await library.regenerateRecoveryCode(bookID: bookID, password: password)
    }

    /// Vérifie le mot de passe d'un livre protégé (suppression du livre)
    func verifyPassword(_ bookID: UUID, password: String) async -> Bool {
        guard let keys = try? library.keys(for: bookID) else { return true }
        isWorking = true
        defer { isWorking = false }
        return (try? await Task.detached(priority: .userInitiated) { try LibraryStore.dataKey(keys, password: password) }.value) != nil
    }

    /// Livre supprimé : sa clé Touch ID aussi
    func forget(_ bookID: UUID) {
        removeBiometricKey(for: bookID)
        failures[bookID] = nil
    }

    // MARK: - Verrouillage automatique

    private func startMonitoring() {
        // Activité dans l'app : clavier, souris, défilement
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel], handler: { [weak self] event in
            self?.lastActivity = Date()
            return event
        }) {
            monitors.append(monitor)
        }
        // Veille du Mac, mise en veille de l'écran, écran verrouillé, économiseur d'écran
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            monitors.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            monitors.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInactivity() }
        }
    }

    private func checkInactivity() {
        guard autoLockMinutes > 0, !isLocked else { return }
        if Date().timeIntervalSince(lastActivity) >= Double(autoLockMinutes) * 60 {
            lock()
        }
    }
}
