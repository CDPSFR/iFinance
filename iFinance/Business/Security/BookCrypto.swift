import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Clé de données d'un livre chiffrée par une clé tirée d'un secret (mot de passe ou clé de secours)
struct WrappedKey: Equatable {
    let salt: Data
    let iterations: Int
    /// Clé de données scellée par AES-GCM (nonce, texte chiffré et étiquette)
    let sealed: Data
}

enum BookCryptoError: LocalizedError {
    case wrongSecret
    case randomFailure

    var errorDescription: String? {
        switch self {
        case .wrongSecret: return "Mot de passe incorrect."
        case .randomFailure: return "Impossible de générer une clé aléatoire."
        }
    }
}

/// Chiffrement des livres : une clé de données aléatoire (256 bits) chiffre la base avec SQLCipher ;
/// elle est elle-même chiffrée par une clé tirée du mot de passe (PBKDF2-SHA256) et par une clé
/// tirée de la clé de secours. Changer de mot de passe ne rechiffre donc que cette petite clé.
enum BookCrypto {
    /// Itérations PBKDF2 (recommandation OWASP 2023 pour SHA-256)
    nonisolated static let passwordIterations = 600_000
    nonisolated static let minimumPasswordLength = 8

    nonisolated static func randomBytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw BookCryptoError.randomFailure }
        return data
    }

    /// Nouvelle clé de données d'un livre
    nonisolated static func newDataKey() throws -> Data { try randomBytes(32) }

    /// Clé de chiffrement tirée d'un secret (PBKDF2-HMAC-SHA256)
    nonisolated static func deriveKey(from secret: String, salt: Data, iterations: Int) -> SymmetricKey {
        let password = Array(secret.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        _ = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBufferPointer { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) },
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    derived.count
                )
            }
        }
        return SymmetricKey(data: derived)
    }

    nonisolated static func wrap(_ dataKey: Data, with secret: String, iterations: Int = passwordIterations) throws -> WrappedKey {
        let salt = try randomBytes(16)
        let key = deriveKey(from: secret, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(dataKey, using: key)
        return WrappedKey(salt: salt, iterations: iterations, sealed: box.combined!)
    }

    /// Clé de données, ou `wrongSecret` si le secret ne correspond pas (l'étiquette AES-GCM échoue)
    nonisolated static func unwrap(_ wrapped: WrappedKey, with secret: String) throws -> Data {
        let key = deriveKey(from: secret, salt: wrapped.salt, iterations: wrapped.iterations)
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: wrapped.sealed), using: key)
        } catch {
            throw BookCryptoError.wrongSecret
        }
    }

    // MARK: - Clé de secours

    /// Alphabet sans caractères ambigus (ni 0/O, ni 1/I/L)
    nonisolated private static let recoveryAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// 24 caractères aléatoires en 6 groupes : « K7QF-3MXA-… » (environ 119 bits)
    nonisolated static func newRecoveryCode() throws -> String {
        let bytes = try randomBytes(24)
        let characters = bytes.map { recoveryAlphabet[Int($0) % recoveryAlphabet.count] }
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }

    /// Clé de secours telle que saisie : majuscules, sans tirets ni espaces
    nonisolated static func normalizedRecoveryCode(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Clé brute au format attendu par SQLCipher : x'…' (64 caractères hexadécimaux)
    nonisolated static func sqlcipherKey(_ dataKey: Data) -> String {
        "x'" + dataKey.map { String(format: "%02X", $0) }.joined() + "'"
    }
}
