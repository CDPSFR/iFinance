import Foundation
import SwiftUI
import Combine

@MainActor
class AccountsController: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var activeAccounts: [Account] = []
    @Published var closedAccounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository: AccountRepositoryProtocol
    private var currentBookID: UUID?
    
    init(repository: AccountRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Load Accounts
    
    func loadAccounts(for bookID: UUID) async {
        currentBookID = bookID
        isLoading = true
        defer { isLoading = false }
        
        do {
            accounts = try await repository.fetchAll(for: bookID)
            activeAccounts = accounts.filter { !$0.isClosed }
            closedAccounts = accounts.filter { $0.isClosed }
            
            // Sélectionner le premier compte actif par défaut
            if selectedAccount == nil, let first = activeAccounts.first {
                selectedAccount = first
            }
            
        } catch {
            self.error = error
            print("❌ Erreur chargement comptes: \(error)")
        }
    }
    
    func loadActiveAccounts(for bookID: UUID) async {
        currentBookID = bookID
        isLoading = true
        defer { isLoading = false }
        
        do {
            activeAccounts = try await repository.fetchActive(for: bookID)
            
            if selectedAccount == nil, let first = activeAccounts.first {
                selectedAccount = first
            }
            
        } catch {
            self.error = error
            print("❌ Erreur chargement comptes actifs: \(error)")
        }
    }
    
    // MARK: - Create Account
    
    func createAccount(
        bookID: UUID,
        name: String,
        bank: String?,
        type: AccountType,
        initialBalance: Decimal,
        currency: String,
        iban: String? = nil,
        bic: String? = nil,
        isExcludedFromReports: Bool = false,
        initialBalanceDate: Date? = nil,
        isHiddenFromSidebar: Bool = false,
        isExcludedFromBudgets: Bool = false
    ) async {
        let account = Account(
            bookID: bookID,
            name: name,
            bank: bank,
            type: type,
            initialBalance: initialBalance,
            currency: currency,
            iban: iban,
            bic: bic,
            isExcludedFromReports: isExcludedFromReports,
            initialBalanceDate: initialBalanceDate,
            isHiddenFromSidebar: isHiddenFromSidebar,
            isExcludedFromBudgets: isExcludedFromBudgets
        )
        
        do {
            try await repository.create(account)
            await loadAccounts(for: bookID)
            selectedAccount = account
        } catch {
            self.error = error
            print("❌ Erreur création compte: \(error)")
        }
    }
    
    // MARK: - Update Account
    
    func updateAccount(_ account: Account) async {
        do {
            try await repository.update(account)
            if let bookID = currentBookID {
                await loadAccounts(for: bookID)
            }
            
            if selectedAccount?.id == account.id {
                selectedAccount = account
            }
        } catch {
            self.error = error
            print("❌ Erreur mise à jour compte: \(error)")
        }
    }
    
    // MARK: - Delete Account
    
    func deleteAccount(id: UUID) async {
        do {
            try await repository.delete(id: id)
            if let bookID = currentBookID {
                await loadAccounts(for: bookID)
            }
            
            if selectedAccount?.id == id {
                selectedAccount = activeAccounts.first
            }
        } catch {
            self.error = error
            print("❌ Erreur suppression compte: \(error)")
        }
    }
    
    // MARK: - Close/Reopen Account
    
    func closeAccount(id: UUID) async {
        do {
            try await repository.close(id: id)
            if let bookID = currentBookID {
                await loadAccounts(for: bookID)
            }
            
            if selectedAccount?.id == id {
                selectedAccount = activeAccounts.first
            }
        } catch {
            self.error = error
            print("❌ Erreur fermeture compte: \(error)")
        }
    }
    
    func reopenAccount(id: UUID) async {
        do {
            try await repository.reopen(id: id)
            if let bookID = currentBookID {
                await loadAccounts(for: bookID)
            }
        } catch {
            self.error = error
            print("❌ Erreur réouverture compte: \(error)")
        }
    }
    
    // MARK: - Select Account
    
    func selectAccount(_ account: Account) {
        selectedAccount = account
    }
    
    // MARK: - Get Account by ID
    
    func getAccount(id: UUID) -> Account? {
        return accounts.first { $0.id == id }
    }

    // MARK: - Reports

    /// IDs des comptes dont les dépenses ne consomment pas les budgets
    var budgetExcludedAccountIDs: Set<UUID> {
        Set((activeAccounts + closedAccounts).filter { $0.isExcludedFromBudgets }.map { $0.id })
    }

    /// IDs des comptes actifs inclus dans les rapports de dépenses / cash-flow
    var cashFlowAccountIDs: Set<UUID> {
        Set(activeAccounts.filter { $0.countsInCashFlow }.map { $0.id })
    }

    /// Un filtre explicite sur un compte l'emporte sur l'exclusion des rapports
    func isReported(_ transaction: Transaction, accountFilter: UUID?) -> Bool {
        accountFilter != nil || cashFlowAccountIDs.contains(transaction.accountID)
    }
}
