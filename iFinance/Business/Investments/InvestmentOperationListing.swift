import Foundation

/// Opérations sur titres affichées, en lecture seule, parmi les transactions.
/// Elles ne sont pas des transactions : elles restent hors des rapports, budgets et récurrences ;
/// la liste montre seulement leur effet sur les espèces du compte.
enum InvestmentOperationListing {
    /// Opérations qui passent les filtres de la liste des transactions.
    /// Un filtre de type, de catégorie ou de bénéficiaire les écarte : elles n'en ont pas.
    static func visible(
        _ operations: [UUID: [InvestmentTransaction]],
        filters: TransactionFilters,
        accountIDs: Set<UUID>
    ) -> [InvestmentTransaction] {
        guard filters.showInvestmentOperations,
              filters.transactionType == nil,
              filters.categoryID == nil,
              filters.payeeID == nil else { return [] }

        let range = filters.dateRange.dates()
        return operations.values.joined().filter { operation in
            guard accountIDs.contains(operation.accountID) else { return false }
            if let accountID = filters.accountID, operation.accountID != accountID { return false }
            if let (start, end) = range, operation.date < start || operation.date >= end { return false }
            return true
        }
    }

    /// Libellé de l'opération : « Achat 10 × Amundi MSCI World », « Dividende · Air Liquide »
    static func label(_ operation: InvestmentTransaction, positionName: String?) -> String {
        let name = positionName ?? operation.symbol ?? ""
        let quantity = operation.quantity.map { abs($0).formatted(.number.precision(.fractionLength(0...4))) }

        switch operation.type {
        case .buy, .sell, .transfer:
            guard let quantity else { return join(operation.type.displayName, name) }
            return "\(operation.type.displayName) \(quantity) × \(name)".trimmingCharacters(in: .whitespaces)
        case .split:
            guard let quantity else { return join(operation.type.displayName, name) }
            return join("\(operation.type.displayName) ×\(quantity)", name)
        case .dividend, .interest, .fee:
            return join(operation.type.displayName, name)
        }
    }

    private static func join(_ title: String, _ name: String) -> String {
        name.isEmpty ? title : "\(title) · \(name)"
    }
}
