import Foundation

/// Valeur d'un compte telle qu'affichée partout (barre latérale, dashboard, patrimoine)
@MainActor
struct AccountValuation {
    let transactionsController: TransactionsController
    let investmentsController: InvestmentsController
    let savingsPlansController: SavingsPlansController

    /// Espèces : solde initial + versements / retraits (+ effet des opérations sur titres).
    /// Pour un plan valorisé, c'est le montant net versé.
    func cash(of account: Account) -> Decimal {
        let balance = transactionsController.calculateBalance(
            for: account.id,
            initialBalance: account.initialBalance
        )
        guard account.type.supportsPositions else { return balance }
        return balance + investmentsController.cashImpact(for: account.id)
    }

    /// Valeur totale du compte
    func value(of account: Account) -> Decimal {
        switch account.type.trackingMode {
        case .transactions:
            return cash(of: account)
        case .positions:
            return cash(of: account) + investmentsController.marketValue(for: account.id)
        case .valuations:
            return planSummary(of: account).value
        }
    }

    /// Plus-value latente (titres ou plan valorisé), 0 pour un compte classique
    func unrealizedGain(of account: Account) -> Decimal {
        switch account.type.trackingMode {
        case .transactions:
            return 0
        case .positions:
            return investmentsController.unrealizedGain(for: account.id)
        case .valuations:
            return planSummary(of: account).gain
        }
    }

    func planSummary(of account: Account) -> SavingsPlanSummary {
        savingsPlansController.summary(for: account, transactions: transactionsController.allTransactions)
    }

    func total(of accounts: [Account]) -> Decimal {
        accounts.reduce(Decimal(0)) { $0 + value(of: $1) }
    }
}
