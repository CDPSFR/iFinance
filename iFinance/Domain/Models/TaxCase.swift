import Foundation

/// Case de la déclaration de revenus alimentée par une catégorie de dépenses
/// (réductions et crédits d'impôt les plus courants). Règles des revenus 2025-2026.
enum TaxCase: String, Codable, CaseIterable, Identifiable {
    case homeEmployment = "7DB"        // Emploi d'un salarié à domicile
    case childcare = "7GA"             // Frais de garde des enfants de moins de 6 ans
    case donations = "7UF"             // Dons aux organismes d'intérêt général
    case donationsHelp = "7UD"         // Dons aux organismes d'aide aux personnes en difficulté
    case unionDues = "7AC"             // Cotisations syndicales

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homeEmployment: return "Emploi à domicile"
        case .childcare: return "Garde d’enfant de moins de 6 ans"
        case .donations: return "Dons aux associations"
        case .donationsHelp: return "Aide aux personnes en difficulté"
        case .unionDues: return "Cotisations syndicales"
        }
    }

    var examples: String {
        switch self {
        case .homeEmployment: return "ménage, jardinage, soutien scolaire, CESU"
        case .childcare: return "crèche, assistante maternelle, garderie"
        case .donations: return "associations, fondations, partis"
        case .donationsHelp: return "repas, soins, logement des personnes en difficulté"
        case .unionDues: return "syndicat professionnel"
        }
    }

    /// Part de la dépense rendue en impôt
    var rate: Decimal {
        switch self {
        case .homeEmployment, .childcare: return Decimal(string: "0.5")!
        case .donations, .unionDues: return Decimal(string: "0.66")!
        case .donationsHelp: return Decimal(string: "0.75")!
        }
    }

    /// Crédit d'impôt (remboursé même sans impôt à payer) ou réduction
    var isCredit: Bool {
        switch self {
        case .homeEmployment, .childcare, .unionDues: return true
        case .donations, .donationsHelp: return false
        }
    }

    /// Plafond simple de dépenses retenues (nil : plafond lié au revenu, non calculé ici)
    var spendingCap: Decimal? {
        switch self {
        case .homeEmployment: return 12_000        // majoré de 1 500 € par enfant ou personne de plus de 65 ans
        case .childcare: return 3_500              // par enfant
        case .donationsHelp: return 1_000          // au-delà : 66 % (case 7UF)
        case .donations, .unionDues: return nil    // 20 % ou 1 % du revenu
        }
    }

    var ruleText: String {
        let percent = NSDecimalNumber(decimal: rate * 100).intValue
        return "\(isCredit ? "crédit" : "réduction") d’impôt de \(percent) %"
    }

    /// Mots qui suggèrent qu'une catégorie relève de cette case
    var keywords: [String] {
        switch self {
        case .homeEmployment: return ["menage", "domicile", "cesu", "jardin", "aide a domicile", "soutien scolaire"]
        case .childcare: return ["creche", "garde", "nounou", "assistante maternelle", "garderie"]
        case .donations: return ["don", "dons", "association", "charite"]
        case .donationsHelp: return ["restos du coeur", "secours", "aide alimentaire"]
        case .unionDues: return ["syndic"]
        }
    }
}
