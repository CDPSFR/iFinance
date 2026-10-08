import Foundation

/// Origine d'un apport sur un plan d'épargne salariale ou retraite
enum ContributionOrigin: String, Codable, CaseIterable {
    case voluntary = "voluntary"                    // Versement volontaire (facultatif pour l'article 83)
    case matching = "matching"                      // Abondement (cotisation employeur pour l'article 83)
    case profitSharing = "profit_sharing"           // Intéressement
    case participation = "participation"            // Participation
    case employeeMandatory = "employee_mandatory"   // Cotisation obligatoire du salarié (article 83, PER obligatoire)

    var displayName: String {
        switch self {
        case .voluntary: return "Versement volontaire"
        case .matching: return "Abondement"
        case .profitSharing: return "Intéressement"
        case .participation: return "Participation"
        case .employeeMandatory: return "Cotisation salarié"
        }
    }

    /// Libellé adapté au type de plan (l'article 83 parle de cotisations)
    func displayName(for type: AccountType) -> String {
        guard type == .article83 else { return displayName }
        switch self {
        case .matching: return "Cotisation employeur"
        case .employeeMandatory: return "Cotisation salarié"
        case .voluntary: return "Versement facultatif"
        default: return displayName
        }
    }

    var icon: String {
        switch self {
        case .voluntary: return "person.fill"
        case .matching: return "building.2.fill"
        case .profitSharing: return "chart.pie.fill"
        case .participation: return "person.3.fill"
        case .employeeMandatory: return "doc.text.fill"
        }
    }

    /// Apport payé par l'entreprise
    var isEmployerFunded: Bool {
        switch self {
        case .matching, .profitSharing, .participation: return true
        case .voluntary, .employeeMandatory: return false
        }
    }

    /// Origines proposées selon le type de plan, dans l'ordre d'affichage
    static func origins(for type: AccountType) -> [ContributionOrigin] {
        switch type {
        case .article83: return [.matching, .employeeMandatory, .voluntary]
        case .pee, .perco: return [.voluntary, .matching, .participation, .profitSharing]
        case .lifeInsurance: return [.voluntary]
        default: return [.voluntary, .matching, .participation, .profitSharing, .employeeMandatory]
        }
    }

    // MARK: - PER : compartiments

    /// Compartiment du PER (loi Pacte) : il décide de la fiscalité et des modes de sortie
    var perCompartment: PERCompartment {
        switch self {
        case .voluntary: return .voluntary
        case .matching, .profitSharing, .participation: return .employeeSavings
        case .employeeMandatory: return .mandatory
        }
    }
}

enum PERCompartment: Int {
    case voluntary = 1          // Versements volontaires
    case employeeSavings = 2    // Intéressement, participation, abondement
    case mandatory = 3          // Cotisations obligatoires

    var displayName: String {
        switch self {
        case .voluntary: return "1 · volontaire"
        case .employeeSavings: return "2 · épargne salariale"
        case .mandatory: return "3 · obligatoire"
        }
    }

    /// Mode de sortie à la retraite
    var exitMode: String {
        self == .mandatory ? "Rente" : "Capital ou rente"
    }
}

/// Informations propres aux plans, rattachées à une transaction du compte
struct ContributionDetail: Codable, Equatable, Hashable {
    var transactionID: UUID
    var origin: ContributionOrigin
    var availableOn: Date?          // nil = bloqué jusqu'à la retraite
    var isDeducted: Bool? = nil     // PER, versement volontaire : déduit du revenu imposable (nil = oui par défaut)
}

/// Valeur d'un compte relevée à une date (relevé du prestataire)
struct ValuationSnapshot: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var accountID: UUID
    var date: Date
    var value: Decimal
    var note: String?
}

/// Réglages propres à un plan, saisis par l'utilisateur
struct SavingsPlanSettings: Codable, Equatable, Hashable {
    var accountID: UUID
    /// Plafond annuel d'abondement prévu par l'accord d'entreprise (PEE, PERCO)
    var matchingCap: Decimal? = nil
    /// Plafond de déduction de l'avis d'impôt, par année de versement (PER) : part de l'année, hors reports
    var deductionCeilings: [Int: Decimal] = [:]
    /// Tranche marginale d'imposition (0,30 pour 30 %)
    var marginalTaxRate: Double? = nil
}

/// Plafond annuel de la sécurité sociale et règles qui en dépendent
enum PASS {
    /// PASS par année civile
    static let byYear: [Int: Decimal] = [
        2019: 40_524,
        2020: 41_136,
        2021: 41_136,
        2022: 41_136,
        2023: 43_992,
        2024: 46_368,
        2025: 47_100,
        2026: 48_060
    ]

    /// PASS de l'année, ou le dernier connu
    static func value(for year: Int) -> Decimal {
        if let value = byYear[year] { return value }
        let known = byYear.keys.sorted()
        if let last = known.last, year > last { return byYear[last]! }
        return byYear[known.first!]!
    }

    /// Plafond légal d'abondement PEE : 8 % du PASS
    static func peeMatchingCap(year: Int) -> Decimal {
        value(for: year) * 8 / 100
    }

    /// Plafond légal d'abondement PERCO / PERECO : 16 % du PASS
    static func percoMatchingCap(year: Int) -> Decimal {
        value(for: year) * 16 / 100
    }

    /// Plancher de déduction PER des versements de l'année : 10 % du PASS de l'année précédente
    static func perDeductionFloor(year: Int) -> Decimal {
        value(for: year - 1) * 10 / 100
    }

    /// Durée de report d'un plafond PER non utilisé : 3 ans, 5 ans pour les plafonds nés à partir de 2026
    static func perCarryOverYears(ceilingYear: Int) -> Int {
        ceilingYear >= 2026 ? 5 : 3
    }
}
