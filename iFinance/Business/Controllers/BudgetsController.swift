import Foundation
import SwiftUI
import Combine

@MainActor
class BudgetsController: ObservableObject {
    @Published var budgets: [Budget] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let repository: BudgetRepositoryProtocol
    private var currentBookID: UUID?

    /// Comptes hors budget : leurs transactions ne sont pas comptées. Branché par AppState.
    var excludedAccountIDs: () -> Set<UUID> = { [] }

    init(repository: BudgetRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load

    func loadBudgets(for bookID: UUID) async {
        currentBookID = bookID
        isLoading = true
        defer { isLoading = false }
        do {
            budgets = try await repository.fetchAll(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur chargement budgets: \(error)")
        }
    }

    // MARK: - CRUD

    func createBudget(
        bookID: UUID,
        name: String,
        note: String? = nil,
        period: BudgetPeriod,
        categoryIDs: [UUID],
        anchorDate: Date,
        amount: Decimal
    ) async {
        let budget = Budget(
            bookID: bookID,
            name: name,
            note: note,
            period: period,
            categoryIDs: categoryIDs,
            anchorDate: anchorDate
        )
        let version = BudgetVersion(budgetID: budget.id, amount: amount, effectiveFrom: anchorDate)
        do {
            try await repository.create(budget)
            try await repository.createVersion(version)
            await loadBudgets(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur création budget: \(error)")
        }
    }

    func updateBudget(_ budget: Budget) async {
        do {
            try await repository.update(budget)
            if let bookID = currentBookID { await loadBudgets(for: bookID) }
        } catch {
            self.error = error
            print("❌ Erreur mise à jour budget: \(error)")
        }
    }

    func deleteBudget(id: UUID) async {
        do {
            try await repository.delete(id: id)
            if let bookID = currentBookID { await loadBudgets(for: bookID) }
        } catch {
            self.error = error
            print("❌ Erreur suppression budget: \(error)")
        }
    }

    // MARK: - Versions

    func fetchVersions(for budgetID: UUID) async -> [BudgetVersion] {
        do {
            return try await repository.fetchVersions(for: budgetID)
        } catch {
            print("❌ Erreur chargement versions: \(error)")
            return []
        }
    }

    /// Creates a new version for a budget (without losing history).
    func addVersion(to budgetID: UUID, amount: Decimal, effectiveFrom: Date, note: String? = nil) async {
        let version = BudgetVersion(budgetID: budgetID, amount: amount, effectiveFrom: effectiveFrom, note: note)
        do {
            try await repository.createVersion(version)
            if let bookID = currentBookID { await loadBudgets(for: bookID) }
        } catch {
            self.error = error
            print("❌ Erreur ajout version: \(error)")
        }
    }

    func deleteVersion(id: UUID) async {
        do {
            try await repository.deleteVersion(id: id)
            if let bookID = currentBookID { await loadBudgets(for: bookID) }
        } catch {
            self.error = error
            print("❌ Erreur suppression version: \(error)")
        }
    }

    // MARK: - Progress

    /// Amount spent in the current period for the given budget, from the transaction list.
    func spent(for budget: Budget, transactions: [Transaction]) -> Decimal {
        guard let version = budget.currentVersion else { return 0 }
        let window = budget.period.currentWindow(anchor: budget.anchorDate)
        let categorySet = Set(budget.categoryIDs)
        let excludedAccounts = excludedAccountIDs()

        return transactions
            .filter { tx in
                !excludedAccounts.contains(tx.accountID)
                && tx.date >= window.start
                && tx.date < window.end
                && tx.signedAmount < 0
                && tx.categoryID.map { categorySet.contains($0) } ?? false
                && tx.status != .skipped
            }
            .reduce(Decimal(0)) { $0 + abs($1.signedAmount) }
    }

    func progress(for budget: Budget, transactions: [Transaction]) -> Double {
        guard let version = budget.currentVersion, version.amount > 0 else { return 0 }
        let s = spent(for: budget, transactions: transactions)
        return Double(truncating: NSDecimalNumber(decimal: s / version.amount))
    }
}
