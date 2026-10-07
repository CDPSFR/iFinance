import Foundation

// Cours en ligne : contrat commun à tous les fournisseurs.
//
// Pour ajouter ou remplacer un fournisseur :
//   1. créer un type conforme à `QuoteProvider` (voir TwelveDataQuoteProvider) ;
//   2. l'ajouter à `QuoteProviderRegistry.all`.
// Rien d'autre dans l'app ne connaît le fournisseur : QuoteService, les réglages et les vues
// passent uniquement par ce protocole.

/// Ce que l'app envoie au fournisseur : l'identifiant du titre, jamais de quantité ni de montant
struct QuoteRequest: Hashable {
    /// Symbole ou code ISIN tel que saisi sur la position (ex. « AI », « AI:EPA », « FR0000120073 »)
    let symbol: String
    /// Devise attendue de la position, pour repérer un cours rendu dans une autre devise
    let currency: String
    let assetType: AssetType

    /// Vrai si le symbole a la forme d'un code ISIN (2 lettres, 9 caractères, 1 chiffre de contrôle)
    var looksLikeISIN: Bool {
        let value = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard value.count == 12 else { return false }
        let scalars = Array(value.unicodeScalars)
        let letters = CharacterSet.uppercaseLetters
        let alphanumerics = CharacterSet.uppercaseLetters.union(.decimalDigits)
        return scalars.prefix(2).allSatisfy(letters.contains)
            && scalars.dropFirst(2).allSatisfy(alphanumerics.contains)
            && CharacterSet.decimalDigits.contains(scalars[11])
    }
}

/// Cours rendu par un fournisseur
struct Quote: Equatable {
    let price: Decimal
    /// Devise du cours, si le fournisseur la précise
    let currency: String?
    /// Date de cotation (clôture ou dernier échange)
    let date: Date
    /// Variation du jour en pourcentage, si disponible
    let dayChangePercent: Double?
}

enum QuoteError: LocalizedError, Equatable {
    case disabled
    case missingAPIKey
    case invalidAPIKey
    case symbolNotFound(String)
    /// Le titre existe mais l'offre souscrite ne le couvre pas (place étrangère, identifiant ISIN…)
    case notInPlan(String)
    case rateLimited
    case currencyMismatch(expected: String, received: String)
    case network(String)
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "La mise à jour des cours en ligne est désactivée dans Réglages › Confidentialité."
        case .missingAPIKey:
            return "Aucune clé d'API n'est enregistrée pour ce fournisseur."
        case .invalidAPIKey:
            return "La clé d'API est refusée par le fournisseur."
        case .symbolNotFound(let symbol):
            return "Titre introuvable : « \(symbol) ». Vérifiez le symbole de la position."
        case .notInPlan(let message):
            return message
        case .rateLimited:
            return "Quota du fournisseur atteint. Réessayez plus tard."
        case .currencyMismatch(let expected, let received):
            return "Cours rendu en \(received) alors que la position est en \(expected) : cours ignoré."
        case .network(let message):
            return "Connexion impossible : \(message)"
        case .provider(let message):
            return message
        }
    }
}

/// Fournisseur de cours. Les implémentations ne stockent rien et ne touchent pas à la base.
protocol QuoteProvider {
    /// Identifiant stable, enregistré dans les réglages et dans l'historique des cours
    var id: String { get }
    var displayName: String { get }
    /// Adresse où créer une clé, affichée dans les réglages
    var signupURL: URL? { get }
    var requiresAPIKey: Bool { get }
    /// Délai minimal entre deux requêtes, pour respecter le quota de l'offre gratuite
    var minimumInterval: TimeInterval { get }
    /// Ce que l'offre permet, en une phrase, pour les réglages (fraîcheur, quota)
    var summary: String { get }

    func quote(for request: QuoteRequest, apiKey: String?) async throws -> Quote
}

/// Fournisseurs disponibles dans l'app
enum QuoteProviderRegistry {
    static let all: [QuoteProvider] = [
        TwelveDataQuoteProvider()
    ]

    static let defaultID = "twelvedata"

    static func provider(id: String?) -> QuoteProvider {
        all.first { $0.id == id } ?? all.first { $0.id == defaultID } ?? all[0]
    }
}
