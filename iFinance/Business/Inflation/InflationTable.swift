import Foundation

// MARK: - Postes de l'indice des prix

/// Postes de l'indice des prix à la consommation (INSEE, base 2025, ensemble des ménages, France)
/// suivis par le rapport « Inflation personnelle »
enum InflationPost: String, CaseIterable {
    case all = "all"
    case food = "food"
    case energy = "energy"
    case services = "services"
    case manufactured = "manufactured"
    case rent = "rent"
    case communications = "communications"
    case transport = "transport"
    case health = "health"
    case clothing = "clothing"

    /// Identifiant de la série « variation annuelle » dans la base de séries de l'INSEE (BDM)
    var idbank: String {
        switch self {
        case .all: return "011814640"
        case .food: return "011814163"
        case .energy: return "011814261"
        case .services: return "011814289"
        case .manufactured: return "011814205"
        case .rent: return "011814303"
        case .communications: return "011814439"
        case .transport: return "011814425"
        case .health: return "011814317"
        case .clothing: return "011814219"
        }
    }

    var displayName: String {
        switch self {
        case .all: return "Ensemble"
        case .food: return "Alimentation"
        case .energy: return "Énergie"
        case .services: return "Services"
        case .manufactured: return "Produits manufacturés"
        case .rent: return "Loyers et eau"
        case .communications: return "Communications"
        case .transport: return "Services de transport"
        case .health: return "Services de santé"
        case .clothing: return "Habillement"
        }
    }

    /// Mots-clés (sans accents, en minuscules) qui relient une catégorie à ce poste
    var keywords: [String] {
        switch self {
        case .all, .manufactured: return []
        case .food: return ["aliment", "course", "supermarche", "epicerie", "boulangerie"]
        case .energy: return ["energie", "electricite", "gaz", "carburant", "essence", "edf", "chauffage"]
        case .services: return ["service", "assurance", "banque", "abonnement"]
        case .rent: return ["loyer", "logement", "eau", "ordures"]
        case .communications: return ["telephone", "mobile", "internet", "box", "communication"]
        case .transport: return ["transport", "train", "sncf", "metro", "bus", "navigo", "avion"]
        case .health: return ["sante", "medecin", "dentiste", "kine", "pharmacie", "mutuelle"]
        case .clothing: return ["vetement", "habillement", "chaussure"]
        }
    }

    /// Poste le plus précis d'abord : « Charges logement » relève des loyers avant les services
    static let matchingOrder: [InflationPost] = [.energy, .food, .rent, .communications, .transport, .health, .clothing, .services]

    /// Poste INSEE probable d'une catégorie, d'après son nom
    static func post(forCategoryName name: String) -> InflationPost? {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        return matchingOrder.first { post in post.keywords.contains { folded.contains($0) } }
    }
}

// MARK: - Table des variations

/// Variations annuelles moyennes des prix (0,009 = +0,9 %), par poste et par année.
/// Les valeurs intégrées servent de secours ; celles téléchargées sur le site de l'INSEE les complètent.
struct InflationTable: Equatable {
    var values: [InflationPost: [Int: Double]]

    /// Valeurs intégrées à l'app (INSEE, base 2025, séries consultées en octobre 2026)
    nonisolated static let embedded = InflationTable(values: [
        .all: [2019: 0.011, 2020: 0.005, 2021: 0.016, 2022: 0.052, 2023: 0.049, 2024: 0.020, 2025: 0.009],
        .food: [2019: 0.025, 2020: 0.019, 2021: 0.006, 2022: 0.068, 2023: 0.118, 2024: 0.014, 2025: 0.012],
        .energy: [2019: 0.019, 2020: -0.061, 2021: 0.105, 2022: 0.231, 2023: 0.056, 2024: 0.023, 2025: -0.056],
        .services: [2019: 0.010, 2020: 0.009, 2021: 0.012, 2022: 0.030, 2023: 0.030, 2024: 0.027, 2025: 0.023],
        .manufactured: [2019: -0.006, 2020: -0.002, 2021: 0.003, 2022: 0.030, 2023: 0.035, 2024: 0.000, 2025: -0.003],
        .rent: [2019: 0.003, 2020: 0.003, 2021: 0.011, 2022: 0.020, 2023: 0.028, 2024: 0.028, 2025: 0.026],
        .communications: [2019: -0.011, 2020: 0.010, 2021: 0.029, 2022: 0.006, 2023: -0.036, 2024: -0.081, 2025: -0.087],
        .transport: [2019: 0.007, 2020: -0.017, 2021: 0.038, 2022: 0.104, 2023: 0.063, 2024: 0.025, 2025: 0.005],
        .health: [2019: -0.001, 2020: 0.003, 2021: -0.005, 2022: -0.001, 2023: -0.002, 2024: 0.006, 2025: 0.017],
        .clothing: [2019: -0.003, 2020: -0.005, 2021: 0.001, 2022: 0.027, 2023: 0.025, 2024: 0.004, 2025: 0.007]
    ])

    /// Dernière année connue pour l'ensemble des prix
    var lastYear: Int { values[.all]?.keys.max() ?? 2025 }
    /// Inflation de la dernière année connue
    var last: Double { values[.all]?[lastYear] ?? 0 }

    /// Inflation d'une année, ou celle de la dernière année connue
    func yearly(_ year: Int) -> Double { values[.all]?[year] ?? last }

    /// Variation d'un poste pour la dernière année connue
    func change(for post: InflationPost) -> Double? { values[post]?[lastYear] }

    /// Valeurs complétées et remplacées par `other` (les données téléchargées priment)
    func merging(_ other: [InflationPost: [Int: Double]]) -> InflationTable {
        var merged = values
        for (post, years) in other {
            merged[post, default: [:]].merge(years) { _, new in new }
        }
        return InflationTable(values: merged)
    }
}
