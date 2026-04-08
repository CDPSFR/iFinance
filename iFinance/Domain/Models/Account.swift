import Foundation

enum AccountType: String, Codable, CaseIterable {
    case checking = "checking"           // Compte courant
    case savings = "savings"             // Épargne
    case creditCard = "credit_card"      // Carte de crédit
    case investment = "investment"       // Compte titre
    case retirement = "retirement"       // PER, assurance vie
    case crypto = "crypto"               // Cryptomonnaies
    case loan = "loan"                   // Prêt
    case other = "other"                 // Autre
    
    var displayName: String {
        switch self {
        case .checking: return "Compte courant"
        case .savings: return "Épargne"
        case .creditCard: return "Carte de crédit"
        case .investment: return "Compte titre"
        case .retirement: return "Retraite / Assurance vie"
        case .crypto: return "Cryptomonnaies"
        case .loan: return "Prêt"
        case .other: return "Autre"
        }
    }
    
    var icon: String {
        switch self {
        case .checking: return "creditcard.fill"
        case .savings: return "banknote.fill"
        case .creditCard: return "creditcard.trianglebadge.exclamationmark"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .retirement: return "calendar"
        case .crypto: return "bitcoinsign.circle.fill"
        case .loan: return "house.fill"
        case .other: return "folder.fill"
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
    var isClosed: Bool = false
    var createdAt: Date = Date()
    
    // Calculé côté application (pas en base)
    var currentBalance: Decimal = 0
    
    enum CodingKeys: String, CodingKey {
        case id, bookID, name, bank, type, initialBalance, currency, isClosed, createdAt
        // currentBalance n'est pas sérialisé
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

enum AssetType: String, Codable {
    case stock
    case bond
    case etf
    case mutualFund
    case crypto
    case other
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
    var amount: Decimal         // Montant total
    var fees: Decimal = 0
    var memo: String?
}

enum InvestmentTransactionType: String, Codable {
    case buy
    case sell
    case dividend
    case interest
    case fee
    case split          // Division d'actions
    case transfer       // Transfert de titres
}
