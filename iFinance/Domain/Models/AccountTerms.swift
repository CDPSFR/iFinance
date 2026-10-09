import Foundation

/// Conditions d'un prêt, saisies par l'utilisateur (offre de prêt)
struct LoanTerms: Codable, Equatable, Hashable {
    /// Montant emprunté
    var principal: Decimal
    /// Taux nominal annuel (0,0145 pour 1,45 %)
    var annualRate: Double
    /// Durée en mois
    var months: Int
    /// Date de la première échéance
    var firstPaymentDate: Date
    /// Assurance emprunteur, par mois
    var monthlyInsurance: Decimal = 0
    /// Crédit immobilier (indemnités de remboursement anticipé propres à l'immobilier)
    var isMortgage: Bool = true
}

/// Informations complémentaires d'un compte, utilisées par les rapports patrimoniaux
struct AccountTerms: Codable, Equatable, Hashable {
    var accountID: UUID
    /// Conditions du prêt (comptes de type Prêt)
    var loan: LoanTerms? = nil
    /// Frais annuels en pourcentage de l'encours (0,0085 pour 0,85 %), comptes de placement
    var annualFeeRate: Double? = nil
}
