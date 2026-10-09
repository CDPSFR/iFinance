import Foundation
import SwiftUI
import Combine

@MainActor
class PayeesController: ObservableObject {
    @Published var payees: [Payee] = []
    @Published var selectedPayee: Payee?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository: PayeeRepositoryProtocol
    private var currentBookID: UUID?
    
    init(repository: PayeeRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Load Payees
    
    func loadPayees(for bookID: UUID) async {
        currentBookID = bookID
        isLoading = true
        defer { isLoading = false }
        
        do {
            payees = try await repository.fetchAll(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur chargement bénéficiaires: \(error)")
        }
    }
    
    // MARK: - Search Payees
    
    func searchPayees(query: String) async -> [Payee] {
        guard let bookID = currentBookID, !query.isEmpty else {
            return payees
        }
        
        do {
            return try await repository.search(for: bookID, query: query)
        } catch {
            print("❌ Erreur recherche bénéficiaires: \(error)")
            return []
        }
    }
    
    // MARK: - Get Payee by ID
    
    func getPayee(id: UUID) -> Payee? {
        return payees.first { $0.id == id }
    }
    
    // MARK: - Create Payee
    
    func createPayee(
        bookID: UUID,
        name: String,
        city: String? = nil,
        postalCode: String? = nil,
        notes: String? = nil,
        defaultCategoryID: UUID? = nil
    ) async {
        let payee = Payee(
            bookID: bookID,
            name: name,
            city: city,
            postalCode: postalCode,
            notes: notes,
            defaultCategoryID: defaultCategoryID
        )
        
        do {
            try await repository.create(payee)
            await loadPayees(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur création bénéficiaire: \(error)")
        }
    }
    
    // MARK: - Update Payee
    
    func updatePayee(_ payee: Payee) async {
        do {
            try await repository.update(payee)
            if let bookID = currentBookID {
                await loadPayees(for: bookID)
            }
        } catch {
            self.error = error
            print("❌ Erreur mise à jour bénéficiaire: \(error)")
        }
    }
    
    /// Catégorie par défaut de plusieurs bénéficiaires, puis un seul rechargement
    func setDefaultCategory(_ categoryID: UUID?, for payeeIDs: Set<UUID>) async {
        do {
            for var payee in payees where payeeIDs.contains(payee.id) && payee.defaultCategoryID != categoryID {
                payee.defaultCategoryID = categoryID
                try await repository.update(payee)
            }
        } catch {
            self.error = error
            print("❌ Erreur catégorisation bénéficiaires: \(error)")
        }
        if let bookID = currentBookID {
            await loadPayees(for: bookID)
        }
    }

    /// Regroupe plusieurs bénéficiaires sous `target` (renommé `name`). Renvoie le bénéficiaire conservé,
    /// ou nil en cas d'échec. Les transactions et récurrences sont à recharger par l'appelant.
    @discardableResult
    func merge(_ payeeIDs: Set<UUID>, into targetID: UUID, name: String, defaultCategoryID: UUID?) async -> Payee? {
        guard var target = getPayee(id: targetID) else { return nil }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.defaultCategoryID = defaultCategoryID
        do {
            try await repository.merge(Array(payeeIDs), into: target)
        } catch {
            self.error = error
            print("❌ Erreur regroupement bénéficiaires: \(error)")
            return nil
        }
        if let bookID = currentBookID {
            await loadPayees(for: bookID)
        }
        return target
    }

    // MARK: - Delete Payee
    
    /// Crée plusieurs bénéficiaires en une seule écriture, puis recharge la liste une fois.
    /// Renvoie les bénéficiaires créés.
    func createPayees(bookID: UUID, names: [String]) async throws -> [Payee] {
        let created = names.map { Payee(bookID: bookID, name: $0) }
        guard !created.isEmpty else { return [] }
        try await repository.createBatch(created)
        await loadPayees(for: bookID)
        return created
    }

    func deletePayee(id: UUID) async {
        do {
            try await repository.delete(id: id)
            if let bookID = currentBookID {
                await loadPayees(for: bookID)
            }
        } catch {
            self.error = error
            print("❌ Erreur suppression bénéficiaire: \(error)")
        }
    }
    
    // MARK: - Get Default Category
    
    func getDefaultCategory(for payeeID: UUID) -> UUID? {
        return getPayee(id: payeeID)?.defaultCategoryID
    }
}
