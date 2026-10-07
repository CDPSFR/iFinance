import Foundation
import SwiftUI
import Combine

/// Mise à jour des cours en ligne. Désactivée par défaut : rien ne part sur le réseau tant que
/// l'utilisateur n'a pas activé l'option dans Réglages › Confidentialité.
/// Ne connaît les fournisseurs que par le protocole `QuoteProvider`.
@MainActor
class QuoteService: ObservableObject {
    enum Keys {
        static let enabled = "quotesEnabled"
        static let providerID = "quotesProviderID"
        static let lastUpdate = "quotesLastUpdate"
    }

    struct Failure: Identifiable, Equatable {
        let positionID: UUID
        let name: String
        let message: String

        var id: UUID { positionID }
    }

    struct Outcome: Equatable {
        var updated = 0
        var failures: [Failure] = []
    }

    @Published private(set) var isUpdating = false
    /// Avancement de la mise à jour en cours : (positions traitées, total)
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)
    @Published private(set) var lastOutcome: Outcome?
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published var providerID: String {
        didSet { UserDefaults.standard.set(providerID, forKey: Keys.providerID) }
    }
    @Published private(set) var lastUpdate: Date?

    private let investmentsController: InvestmentsController
    private let priceRepository: PositionPriceRepository

    init(investmentsController: InvestmentsController, priceRepository: PositionPriceRepository) {
        self.investmentsController = investmentsController
        self.priceRepository = priceRepository
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        self.providerID = UserDefaults.standard.string(forKey: Keys.providerID) ?? QuoteProviderRegistry.defaultID
        self.lastUpdate = UserDefaults.standard.object(forKey: Keys.lastUpdate) as? Date
    }

    // MARK: - Fournisseur et clé

    var provider: QuoteProvider {
        QuoteProviderRegistry.provider(id: providerID)
    }

    /// Clé d'API du fournisseur courant, lue dans le trousseau
    var apiKey: String? {
        get { KeychainStore.string(for: provider.id) }
        set {
            KeychainStore.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.id)
            objectWillChange.send()
        }
    }

    var isConfigured: Bool {
        isEnabled && (!provider.requiresAPIKey || !(apiKey ?? "").isEmpty)
    }

    // MARK: - Mise à jour

    /// Met à jour le cours des positions détenues. Une requête par titre distinct, espacées
    /// selon le quota du fournisseur. Seul le symbole part sur le réseau.
    @discardableResult
    func update(_ positions: [InvestmentPosition]) async -> Outcome {
        var outcome = Outcome()
        guard isEnabled else {
            lastOutcome = Outcome(updated: 0, failures: [])
            return outcome
        }
        guard !isUpdating else { return outcome }

        let provider = self.provider
        let key = apiKey
        let held = positions.filter { $0.quantity > 0 && !$0.symbol.trimmingCharacters(in: .whitespaces).isEmpty }
        // Positions regroupées par titre : un même titre détenu sur deux comptes ne coûte qu'une requête
        let groups = Dictionary(grouping: held) {
            QuoteRequest(symbol: $0.symbol, currency: $0.currency, assetType: $0.assetType)
        }

        isUpdating = true
        progress = (0, groups.count)
        defer { isUpdating = false }

        var isFirst = true
        for (request, members) in groups.sorted(by: { $0.key.symbol < $1.key.symbol }) {
            if !isFirst, provider.minimumInterval > 0 {
                try? await Task.sleep(nanoseconds: UInt64(provider.minimumInterval * 1_000_000_000))
            }
            isFirst = false
            if Task.isCancelled { break }

            do {
                let quote = try await provider.quote(for: request, apiKey: key)
                for position in members {
                    await investmentsController.updatePrice(for: position, price: quote.price, date: quote.date)
                    try? priceRepository.record(positionID: position.id, price: quote.price, date: quote.date, source: provider.id)
                    outcome.updated += 1
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                for position in members {
                    outcome.failures.append(Failure(positionID: position.id, name: position.name, message: message))
                }
                // Clé refusée ou quota atteint : inutile d'insister sur les titres suivants
                if let quoteError = error as? QuoteError,
                   quoteError == .invalidAPIKey || quoteError == .missingAPIKey || quoteError == .rateLimited {
                    progress.done += 1
                    break
                }
            }
            progress.done += 1
        }

        if outcome.updated > 0 {
            let now = Date()
            lastUpdate = now
            UserDefaults.standard.set(now, forKey: Keys.lastUpdate)
        }
        lastOutcome = outcome
        return outcome
    }

    /// Vérifie la clé et le fournisseur sur un titre connu. Renvoie un message à afficher.
    func testConnection() async -> (success: Bool, message: String) {
        let request = QuoteRequest(symbol: "AAPL", currency: "USD", assetType: .stock)
        do {
            let quote = try await provider.quote(for: request, apiKey: apiKey)
            return (true, "Connexion réussie : cours reçu (\(quote.price) \(quote.currency ?? "")).")
        } catch {
            return (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Enregistre dans l'historique un cours saisi à la main
    func recordManualPrice(for position: InvestmentPosition, price: Decimal, date: Date) {
        try? priceRepository.record(positionID: position.id, price: price, date: date, source: "manual")
    }

    func history(for position: InvestmentPosition) -> [PositionPrice] {
        (try? priceRepository.fetchAll(for: position.id)) ?? []
    }
}
