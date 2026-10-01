import Foundation

/// Valeur d'un compte telle qu'affichée partout (barre latérale, dashboard, patrimoine)
@MainActor
struct AccountValuation {
    let transactionsController: TransactionsController
    let investmentsController: InvestmentsController

    /// Espèces : solde initial + versements / retraits + effet des opérations sur titres
    func cash(of account: Account) -> Decimal {
        let balance = transactionsController.calculateBalance(
            for: account.id,
            initialBalance: account.initialBalance
        )
        guard account.type.supportsPositions else { return balance }
        return balance + investmentsController.cashImpact(for: account.id)
    }

    /// Valeur totale : espèces + valeur de marché des titres
    func value(of account: Account) -> Decimal {
        guard account.type.supportsPositions else { return cash(of: account) }
        return cash(of: account) + investmentsController.marketValue(for: account.id)
    }

    func total(of accounts: [Account]) -> Decimal {
        accounts.reduce(Decimal(0)) { $0 + value(of: $1) }
    }
}
