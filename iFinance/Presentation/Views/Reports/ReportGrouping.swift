import Foundation

// Outils communs aux rapports « Tendances des dépenses / des revenus », « Flux de trésorerie » et « Taux d'épargne »

extension CategoriesController {
    /// Catégorie principale d'une catégorie (elle-même si elle n'a pas de parent)
    func topLevelCategory(of categoryID: UUID?) -> Category? {
        guard let categoryID, var category = getCategory(id: categoryID) else { return nil }
        var depth = 0
        while let parentID = category.parentID, let parent = getCategory(id: parentID), depth < 10 {
            category = parent
            depth += 1
        }
        return category
    }
}

/// Total d'un poste (catégorie principale, ou regroupement « Autres »)
struct ReportPost: Identifiable, Hashable {
    let id: String
    let name: String
    let amount: Decimal

    var doubleAmount: Double { NSDecimalNumber(decimal: amount).doubleValue }

    static let uncategorizedID = "none"
    static let othersID = "others"
}

extension Array where Element == ReportPost {
    /// Garde les `limit` premiers postes et regroupe le reste dans « Autres »
    func grouped(limit: Int, othersName: String = "Autres") -> [ReportPost] {
        let sorted = self.sorted { $0.amount > $1.amount }
        guard sorted.count > limit else { return sorted }
        let rest = sorted.dropFirst(limit).reduce(Decimal(0)) { $0 + $1.amount }
        return Array(sorted.prefix(limit)) + [ReportPost(id: ReportPost.othersID, name: othersName, amount: rest)]
    }
}
