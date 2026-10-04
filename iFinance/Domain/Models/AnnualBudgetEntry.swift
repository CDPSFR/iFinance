import Foundation

/// Montant prévu pour une catégorie sur un mois donné (budget annuel).
/// Indépendant des budgets par période (Budget / BudgetVersion).
struct AnnualBudgetEntry: Equatable, Hashable {
    var bookID: UUID
    var categoryID: UUID
    var year: Int
    /// Mois de 1 (janvier) à 12 (décembre)
    var month: Int
    var amount: Decimal
}

/// Clé d'accès à un montant prévu dans l'année chargée
struct AnnualBudgetKey: Hashable {
    let categoryID: UUID
    let month: Int
}
