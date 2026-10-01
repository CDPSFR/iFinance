import Foundation

/// Origine d'un apport sur un plan d'épargne salariale ou retraite
enum ContributionOrigin: String, Codable, CaseIterable {
    case voluntary = "voluntary"            // Versement volontaire
    case matching = "matching"              // Abondement
    case profitSharing = "profit_sharing"   // Intéressement
    case participation = "participation"    // Participation

    var displayName: String {
        switch self {
        case .voluntary: return "Versement volontaire"
        case .matching: return "Abondement"
        case .profitSharing: return "Intéressement"
        case .participation: return "Participation"
        }
    }

    var icon: String {
        switch self {
        case .voluntary: return "person.fill"
        case .matching: return "building.2.fill"
        case .profitSharing: return "chart.pie.fill"
        case .participation: return "person.3.fill"
        }
    }

    /// Apport payé par l'entreprise
    var isEmployerFunded: Bool {
        self != .voluntary
    }
}

/// Informations propres aux plans, rattachées à une transaction du compte
struct ContributionDetail: Codable, Equatable, Hashable {
    var transactionID: UUID
    var origin: ContributionOrigin
    var availableOn: Date?          // nil = bloqué jusqu'à la retraite
}

/// Valeur d'un compte relevée à une date (relevé du prestataire)
struct ValuationSnapshot: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var accountID: UUID
    var date: Date
    var value: Decimal
    var note: String?
}
