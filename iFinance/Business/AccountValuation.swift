import Foundation

/// Valeur d'un compte telle qu'affichée partout (barre latérale, dashboard, patrimoine)
@MainActor
struct AccountValuation {
    let transactionsController: TransactionsController

    func value(of account: Account) -> Decimal {
        transactionsController.calculateBalance(
            for: account.id,
            initialBalance: account.initialBalance
        )
    }

    func total(of accounts: [Account]) -> Decimal {
        accounts.reduce(Decimal(0)) { $0 + value(of: $1) }
    }
}
