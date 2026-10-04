import Foundation
import SwiftUI
import Combine

/// Budget annuel : montants prévus par catégorie et par mois, pour une année d'un livre.
@MainActor
class AnnualBudgetController: ObservableObject {
    @Published private(set) var planned: [AnnualBudgetKey: Decimal] = [:]
    @Published var error: Error?

    private let repository: AnnualBudgetRepositoryProtocol
    private var bookID: UUID?
    private var year: Int = Calendar.current.component(.year, from: Date())

    init(repository: AnnualBudgetRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load

    func load(bookID: UUID, year: Int) async {
        self.bookID = bookID
        self.year = year
        do {
            let entries = try await repository.fetchAll(for: bookID, year: year)
            var values: [AnnualBudgetKey: Decimal] = [:]
            for entry in entries {
                values[AnnualBudgetKey(categoryID: entry.categoryID, month: entry.month)] = entry.amount
            }
            planned = values
        } catch {
            self.error = error
            print("❌ Erreur chargement budget annuel: \(error)")
        }
    }

    // MARK: - Lecture

    /// Montant prévu pour la catégorie sur le mois (1 à 12) de l'année chargée
    func amount(for categoryID: UUID, month: Int) -> Decimal {
        planned[AnnualBudgetKey(categoryID: categoryID, month: month)] ?? 0
    }

    // MARK: - Saisie

    /// Enregistre le montant prévu d'un mois. Un montant nul supprime l'entrée.
    func setPlanned(_ amount: Decimal, for categoryID: UUID, month: Int) async {
        await write(amount, categoryID: categoryID, months: [month])
    }

    /// Applique le même montant prévu aux douze mois de l'année
    func setPlannedForAllMonths(_ amount: Decimal, for categoryID: UUID) async {
        await write(amount, categoryID: categoryID, months: Array(1...12))
    }

    private func write(_ amount: Decimal, categoryID: UUID, months: [Int]) async {
        guard let bookID else { return }
        let value = max(amount, 0)
        do {
            for month in months {
                let key = AnnualBudgetKey(categoryID: categoryID, month: month)
                if value == 0 {
                    try await repository.delete(bookID: bookID, categoryID: categoryID, year: year, month: month)
                    planned[key] = nil
                } else {
                    try await repository.save(
                        AnnualBudgetEntry(bookID: bookID, categoryID: categoryID, year: year, month: month, amount: value)
                    )
                    planned[key] = value
                }
            }
        } catch {
            self.error = error
            print("❌ Erreur enregistrement budget annuel: \(error)")
        }
    }
}
