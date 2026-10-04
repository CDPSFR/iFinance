import Foundation

/// Projet : regroupe des transactions autour d'un même thème (voyage, achat, travaux),
/// indépendamment de leurs catégories. Une transaction appartient à un seul projet au plus.
struct Project: Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var name: String
    var color: String?        // Code couleur hex (#0A66D8)
    var startDate: Date?
    var endDate: Date?
    /// Enveloppe prévue, facultative : sans enveloppe, le projet sert seulement à regrouper
    var budget: Decimal?
    var isCompleted: Bool = false
    var note: String?
    var createdAt: Date = Date()

    var displayColor: String { color ?? "#0A66D8" }
}
