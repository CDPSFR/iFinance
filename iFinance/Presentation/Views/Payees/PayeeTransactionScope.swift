import SwiftUI

/// Ce que devient la catégorie des transactions existantes quand on change
/// la catégorie par défaut d'un ou plusieurs bénéficiaires
enum PayeeTransactionScope: Hashable {
    /// Les transactions gardent leur catégorie
    case none
    /// Seules les transactions sans catégorie reçoivent la nouvelle catégorie (choix par défaut)
    case uncategorized
    /// Toutes les transactions reçoivent la nouvelle catégorie, même celles déjà catégorisées
    case all
}

/// Nombre de transactions concernées par chaque option
struct PayeeTransactionCounts: Equatable {
    /// Transactions sans catégorie
    var uncategorized = 0
    /// Transactions qui ont déjà une autre catégorie (elles changeraient avec « toutes »)
    var recategorized = 0

    var total: Int { uncategorized + recategorized }
}

/// Calcul des transactions à recatégoriser. Les transferts ne sont jamais touchés.
enum PayeeCategoryPropagation {
    static func counts(in transactions: [Transaction], payeeIDs: Set<UUID>, categoryID: UUID?) -> PayeeTransactionCounts {
        var counts = PayeeTransactionCounts()
        for transaction in eligible(transactions, payeeIDs: payeeIDs) {
            if transaction.categoryID == nil {
                counts.uncategorized += 1
            } else if transaction.categoryID != categoryID {
                counts.recategorized += 1
            }
        }
        return counts
    }

    /// Transactions dont la catégorie doit devenir `categoryID`
    static func transactionsToUpdate(
        in transactions: [Transaction],
        payeeIDs: Set<UUID>,
        categoryID: UUID?,
        scope: PayeeTransactionScope
    ) -> [Transaction] {
        guard categoryID != nil else { return [] }
        return eligible(transactions, payeeIDs: payeeIDs).filter { transaction in
            switch scope {
            case .none: return false
            case .uncategorized: return transaction.categoryID == nil
            case .all: return transaction.categoryID != categoryID
            }
        }
    }

    private static func eligible(_ transactions: [Transaction], payeeIDs: Set<UUID>) -> [Transaction] {
        transactions.filter { transaction in
            transaction.type != .transfer && transaction.payeeID.map { payeeIDs.contains($0) } ?? false
        }
    }
}

/// Choix « Transactions existantes » : trois options avec leur nombre de transactions.
/// Une option sans effet reste visible, grisée, avec « aucune transaction concernée ».
struct PayeeTransactionScopePicker: View {
    let counts: PayeeTransactionCounts
    @Binding var scope: PayeeTransactionScope

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transactions existantes")
                .font(.subheadline.weight(.semibold))

            option(.none, title: "Ne pas modifier les transactions", detail: nil, enabled: true)
            option(
                .uncategorized,
                title: "Catégoriser les transactions sans catégorie",
                detail: counts.uncategorized == 0 ? "aucune transaction concernée" : count(counts.uncategorized),
                enabled: counts.uncategorized > 0
            )
            option(
                .all,
                title: "Appliquer à toutes les transactions",
                detail: allDetail,
                enabled: counts.total > 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allDetail: String {
        guard counts.total > 0 else { return "aucune transaction concernée" }
        guard counts.recategorized > 0 else { return count(counts.total) }
        return "\(count(counts.total)), dont \(counts.recategorized) déjà catégorisée\(counts.recategorized > 1 ? "s" : "") autrement"
    }

    private func count(_ value: Int) -> String {
        "\(value) transaction\(value > 1 ? "s" : "")"
    }

    private func option(_ value: PayeeTransactionScope, title: String, detail: String?, enabled: Bool) -> some View {
        Button {
            scope = value
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: scope == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(scope == value && enabled ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
