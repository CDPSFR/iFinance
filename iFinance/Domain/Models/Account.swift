import Foundation

enum AccountGroup: String, CaseIterable {
    case liquidity
    case savings
    case investment
    case retirement
    case debt
    case other

    var displayName: String {
        switch self {
        case .liquidity: return "Liquidités"
        case .savings: return "Épargne"
        case .investment: return "Investissements"
        case .retirement: return "Retraite & épargne salariale"
        case .debt: return "Dettes"
        case .other: return "Autre"
        }
    }

    var sortOrder: Int {
        switch self {
        case .liquidity: return 0
        case .savings: return 1
        case .investment: return 2
        case .retirement: return 3
        case .debt: return 4
        case .other: return 5
        }
    }

    /// Seuls les comptes de liquidités alimentent les rapports de dépenses / cash-flow
    var includesCashFlow: Bool {
        self == .liquidity
    }

    var types: [AccountType] {
        AccountType.allCases.filter { $0.group == self }
    }
}

enum AccountType: String, Codable, CaseIterable {
    // Liquidités
    case checking = "checking"           // Compte courant
    case creditCard = "credit_card"      // Carte de crédit
    // Épargne
    case livretA = "livret_a"            // Livret A
    case ldds = "ldds"                   // LDDS
    case lep = "lep"                     // LEP
    case pel = "pel"                     // PEL
    case cel = "cel"                     // CEL
    case termDeposit = "term_deposit"    // Compte à terme
    case savings = "savings"             // Autre épargne
    // Investissements
    case investment = "investment"       // Compte-titres (CTO)
    case pea = "pea"                     // PEA
    case crypto = "crypto"               // Cryptomonnaies
    // Retraite & épargne salariale
    case retirement = "retirement"       // PER
    case lifeInsurance = "life_insurance" // Assurance vie
    case perco = "perco"                 // PERCO / PERECO
    case pee = "pee"                     // PEE
    // Dettes
    case loan = "loan"                   // Prêt
    // Autre
    case other = "other"                 // Autre

    var displayName: String {
        switch self {
        case .checking: return "Compte courant"
        case .creditCard: return "Carte de crédit"
        case .livretA: return "Livret A"
        case .ldds: return "LDDS"
        case .lep: return "LEP"
        case .pel: return "PEL"
        case .cel: return "CEL"
        case .termDeposit: return "Compte à terme"
        case .savings: return "Autre épargne"
        case .investment: return "Compte-titres (CTO)"
        case .pea: return "PEA"
        case .crypto: return "Cryptomonnaies"
        case .retirement: return "PER"
        case .lifeInsurance: return "Assurance vie"
        case .perco: return "PERCO / PERECO"
        case .pee: return "PEE"
        case .loan: return "Prêt"
        case .other: return "Autre"
        }
    }

    var icon: String {
        switch self {
        case .checking: return "creditcard.fill"
        case .creditCard: return "creditcard.trianglebadge.exclamationmark"
        case .livretA, .ldds, .lep: return "banknote.fill"
        case .pel, .cel: return "house.lodge.fill"
        case .termDeposit: return "lock.fill"
        case .savings: return "banknote.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .pea: return "chart.bar.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        case .retirement: return "calendar"
        case .lifeInsurance: return "umbrella.fill"
        case .perco, .pee: return "briefcase.fill"
        case .loan: return "house.fill"
        case .other: return "folder.fill"
        }
    }

    var group: AccountGroup {
        switch self {
        case .checking, .creditCard: return .liquidity
        case .livretA, .ldds, .lep, .pel, .cel, .termDeposit, .savings: return .savings
        case .investment, .pea, .crypto: return .investment
        case .retirement, .lifeInsurance, .perco, .pee: return .retirement
        case .loan: return .debt
        case .other: return .other
        }
    }

    /// Manière de suivre la valeur du compte
    var trackingMode: AccountTrackingMode {
        switch group {
        case .investment: return .positions
        case .retirement: return .valuations
        default: return .transactions
        }
    }

    /// Compte pouvant détenir des positions (titres, cryptos) gérées ligne par ligne
    var supportsPositions: Bool {
        trackingMode == .positions
    }

    /// Règle d'indisponibilité par défaut des sommes versées
    var availabilityRule: AvailabilityRule {
        switch self {
        case .pee: return .lockedYears(5)
        case .perco, .retirement: return .untilRetirement
        default: return .immediate
        }
    }
}

enum AccountTrackingMode {
    case transactions   // Solde = somme des transactions
    case positions      // Titres détaillés (CTO, PEA, crypto)
    case valuations     // Plan géré par un prestataire : versements + valeurs des relevés
}

enum AvailabilityRule: Equatable {
    case immediate
    case lockedYears(Int)
    case untilRetirement

    /// Date de disponibilité par défaut d'un versement (nil = jusqu'à la retraite)
    func defaultAvailability(for date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .immediate: return date
        case .lockedYears(let years): return calendar.date(byAdding: .year, value: years, to: date)
        case .untilRetirement: return nil
        }
    }
}

struct Account: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var name: String
    var bank: String?
    var type: AccountType
    var initialBalance: Decimal = 0
    var currency: String = "EUR"
    var iban: String? = nil
    var bic: String? = nil
    var isExcludedFromReports: Bool = false
    var isClosed: Bool = false
    var createdAt: Date = Date()

    // Calculé côté application (pas en base)
    var currentBalance: Decimal = 0

    enum CodingKeys: String, CodingKey {
        case id, bookID, name, bank, type, initialBalance, currency, iban, bic, isExcludedFromReports, isClosed, createdAt
        // currentBalance n'est pas sérialisé
    }

    /// Compte pris en compte dans les rapports de dépenses / cash-flow
    var countsInCashFlow: Bool {
        type.group.includesCashFlow && !isExcludedFromReports
    }
}

// Nouveau modèle pour les positions d'investissement
struct InvestmentPosition: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var accountID: UUID
    var symbol: String          // ex: "AAPL", "BTC", "FR0000120271"
    var name: String            // ex: "Apple Inc."
    var quantity: Decimal
    var averageCost: Decimal    // Prix moyen d'achat
    var currentPrice: Decimal?  // Prix actuel (màj via API)
    var currency: String = "EUR"
    var assetType: AssetType
    var lastUpdated: Date?
}

enum AssetType: String, Codable, CaseIterable {
    case stock = "stock"
    case bond = "bond"
    case etf = "etf"
    case mutualFund = "mutual_fund"   // OPCVM, FCPE, unités de compte
    case crypto = "crypto"
    case other = "other"

    var displayName: String {
        switch self {
        case .stock: return "Action"
        case .bond: return "Obligation"
        case .etf: return "ETF"
        case .mutualFund: return "Fonds (OPCVM, FCPE, UC)"
        case .crypto: return "Crypto"
        case .other: return "Autre"
        }
    }
}

// Pour tracer les opérations sur titres
struct InvestmentTransaction: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var accountID: UUID
    var positionID: UUID?
    var date: Date
    var type: InvestmentTransactionType
    var symbol: String?
    var quantity: Decimal?
    var price: Decimal?
    var amount: Decimal         // Montant brut, toujours positif (achat/vente : quantité × prix)
    var fees: Decimal = 0
    var memo: String?
}

enum InvestmentTransactionType: String, Codable, CaseIterable {
    case buy = "buy"
    case sell = "sell"
    case dividend = "dividend"
    case interest = "interest"
    case fee = "fee"
    case split = "split"            // Division d'actions (quantity = ratio)
    case transfer = "transfer"      // Transfert de titres (quantity > 0 entrée, < 0 sortie)

    var displayName: String {
        switch self {
        case .buy: return "Achat"
        case .sell: return "Vente"
        case .dividend: return "Dividende"
        case .interest: return "Intérêts"
        case .fee: return "Frais"
        case .split: return "Division"
        case .transfer: return "Transfert de titres"
        }
    }

    /// Opération qui modifie la quantité détenue (et nécessite donc une position)
    var affectsQuantity: Bool {
        switch self {
        case .buy, .sell, .split, .transfer: return true
        case .dividend, .interest, .fee: return false
        }
    }
}
