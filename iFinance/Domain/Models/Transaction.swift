import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case debit = "debit"       // Dépense
    case credit = "credit"     // Revenu
    case transfer = "transfer" // Transfert entre comptes
    
    var displayName: String {
        switch self {
        case .debit: return "Dépense"
        case .credit: return "Revenu"
        case .transfer: return "Transfert"
        }
    }
    
    var icon: String {
        switch self {
        case .debit: return "arrow.down.circle.fill"
        case .credit: return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .debit: return "red"
        case .credit: return "green"
        case .transfer: return "blue"
        }
    }
}

// Template pour définir la récurrence
struct RecurringTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var accountID: UUID
    var toAccountID: UUID?  // Pour transferts récurrents
    var payeeID: UUID?
    var categoryID: UUID?
    var amount: Decimal
    var type: TransactionType
    var memo: String?
    
    // Configuration de la récurrence
    var frequency: RecurrenceFrequency
    var startDate: Date
    var endDate: Date?  // nil = indéfini
    var dayOfMonth: Int?  // Pour monthly: 1-31, -1 = dernier jour
    var dayOfWeek: Int?   // Pour weekly: 1=lundi, 7=dimanche
    
    var isActive: Bool = true
    var createdAt: Date = Date()
}

enum RecurrenceFrequency: String, Codable {
    case daily
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly
}

// Transaction normale avec lien optionnel vers le template
/*struct Transaction: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Decimal = 0
    var accountID: UUID
    var toAccountID: UUID?
    var linkedTransactionID: UUID?  // Pour transferts
    var payeeID: UUID?
    var categoryID: UUID?
    var type: TransactionType = .debit
    var memo: String?
    var isReconciled: Bool = false
    
    // 🆕 Lien vers le template (si générée depuis récurrence)
    var recurringTemplateID: UUID?
    
    // 🆕 État de validation pour les transactions récurrentes
    var status: TransactionStatus = .cleared
} */


enum TransactionStatus: String, Codable {
    case pending = "pending"       // En attente de validation (récurrentes)
    case cleared = "cleared"       // Validée/exécutée
    case reconciled = "reconciled" // Rapprochée avec relevé bancaire
    case skipped = "skipped"       // Occurrence sautée (récurrentes)
    
    var displayName: String {
        switch self {
        case .pending: return "En attente"
        case .cleared: return "Validée"
        case .reconciled: return "Rapprochée"
        case .skipped: return "Ignorée"
        }
    }
}

struct Transaction: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Decimal = 0
    var accountID: UUID
    var toAccountID: UUID?           // Pour les transferts
    var linkedTransactionID: UUID?   // Transaction miroir (transferts)
    var payeeID: UUID?
    var categoryID: UUID?
    var type: TransactionType = .debit
    var memo: String?
    var isReconciled: Bool = false
    var recurringTemplateID: UUID?   // Lien vers template récurrent
    var status: TransactionStatus = .cleared
    var projectID: UUID?             // Projet auquel la transaction est rattachée
    
    // Helper pour savoir si c'est un transfert
    var isTransfer: Bool {
        return type == .transfer && toAccountID != nil
    }
    
    // Montant signé selon le type
    var signedAmount: Decimal {
        switch type {
        case .debit:
            return -abs(amount)
        case .credit:
            return abs(amount)
        case .transfer:
            return amount  // Le signe dépend du contexte (compte source vs destination)
        }
    }
}
