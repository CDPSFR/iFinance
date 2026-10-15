import Foundation
import SwiftUI
import Combine

/// Indices des prix de l'INSEE. Désactivé par défaut : l'app utilise alors les valeurs intégrées
/// et ne contacte aucun service. Activé dans Réglages › Confidentialité, il télécharge les nouvelles
/// valeurs au plus une fois par mois, ou à la demande.
@MainActor
class InflationService: ObservableObject {
    enum Keys {
        static let enabled = "inflationOnlineEnabled"
        static let lastUpdate = "inflationLastUpdate"
    }

    /// Délai entre deux mises à jour automatiques (l'INSEE publie les moyennes annuelles mi-janvier)
    static let refreshInterval: TimeInterval = 30 * 24 * 3600

    @Published private(set) var table = InflationTable.embedded
    @Published private(set) var isUpdating = false
    @Published private(set) var lastUpdate: Date?
    /// Résultat de la dernière mise à jour : (réussite, message)
    @Published private(set) var lastResult: (success: Bool, message: String)?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled { lastResult = nil }
        }
    }

    private let repository: PriceIndexRepository

    init(repository: PriceIndexRepository) {
        self.repository = repository
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        self.lastUpdate = UserDefaults.standard.object(forKey: Keys.lastUpdate) as? Date
    }

    /// Valeurs intégrées, complétées par celles déjà téléchargées
    func load() {
        do {
            table = InflationTable.embedded.merging(try repository.fetchAll())
        } catch {
            table = .embedded
            print("❌ Erreur chargement des indices de prix: \(error)")
        }
    }

    /// Met à jour si l'option est active et que la dernière mise à jour date de plus d'un mois
    func updateIfStale() async {
        guard isEnabled, !isUpdating else { return }
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < Self.refreshInterval { return }
        await update()
    }

    /// Télécharge les variations annuelles de tous les postes suivis
    func update() async {
        guard isEnabled, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            let values = try await InseeIndexClient.fetch()
            try repository.save(values)
            load()
            let now = Date()
            lastUpdate = now
            UserDefaults.standard.set(now, forKey: Keys.lastUpdate)
            lastResult = (true, "Indices à jour : inflation \(String(table.lastYear)) de \(table.last.formatted(.percent.precision(.fractionLength(1)))).")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastResult = (false, "Mise à jour impossible : \(message) Les dernières valeurs connues restent utilisées.")
        }
    }
}
