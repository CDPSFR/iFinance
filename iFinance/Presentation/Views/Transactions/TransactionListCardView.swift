import SwiftUI

struct TransactionListCardView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    
    @State private var showTransactionForm = false
    @State private var showFilters = false
    @State private var transactionToEdit: Transaction?
    @State private var transactionToDelete: Transaction?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerTitle)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Solde (si compte spécifique)
                if let accountID = transactionsController.filters.accountID,
                   let account = accountsController.getAccount(id: accountID) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Solde actuel")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let balance = transactionsController.calculateBalance(
                            for: account.id,
                            initialBalance: account.initialBalance
                        )
                        
                        Text(balance, format: .currency(code: account.currency))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(balance >= 0 ? .green : .red)
                    }
                }
                
                // Bouton Filtres
                Button {
                    showFilters = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filtres")
                        
                        if transactionsController.filters.isActive {
                            Text("(\(transactionsController.filters.activeFiltersCount))")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .font(.headline)
                }
                .buttonStyle(.bordered)
                
                Button {
                    transactionToEdit = nil
                    showTransactionForm = true
                } label: {
                    Label("Nouvelle transaction", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Badges filtres actifs
            if transactionsController.filters.isActive {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Badge compte (si filtré)
                        if let accountID = transactionsController.filters.accountID,
                           let account = accountsController.getAccount(id: accountID) {
                            FilterBadge(
                                text: account.name,
                                icon: "creditcard",
                                onRemove: {
                                    transactionsController.filterByAccount(nil)
                                }
                            )
                        }
                        
                        if let type = transactionsController.filters.transactionType {
                            FilterBadge(
                                text: type.displayName,
                                icon: type.icon,
                                onRemove: {
                                    var newFilters = transactionsController.filters
                                    newFilters.transactionType = nil
                                    transactionsController.updateFilters(newFilters)
                                }
                            )
                        }
                        
                        if let categoryID = transactionsController.filters.categoryID {
                            FilterBadge(
                                text: categoriesController.getCategoryPath(for: categoryID),
                                icon: "folder",
                                onRemove: {
                                    var newFilters = transactionsController.filters
                                    newFilters.categoryID = nil
                                    transactionsController.updateFilters(newFilters)
                                }
                            )
                        }
                        
                        if let payeeID = transactionsController.filters.payeeID,
                           let payee = payeesController.getPayee(id: payeeID) {
                            FilterBadge(
                                text: payee.name,
                                icon: "person.crop.circle",
                                onRemove: {
                                    var newFilters = transactionsController.filters
                                    newFilters.payeeID = nil
                                    transactionsController.updateFilters(newFilters)
                                }
                            )
                        }
                        
                        if transactionsController.filters.dateRange != .all {
                            FilterBadge(
                                text: transactionsController.filters.dateRange.displayName,
                                icon: "calendar",
                                onRemove: {
                                    var newFilters = transactionsController.filters
                                    newFilters.dateRange = .all
                                    transactionsController.updateFilters(newFilters)
                                }
                            )
                        }
                        
                        Button {
                            transactionsController.resetFilters()
                        } label: {
                            Text("Tout effacer")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
            }
            
            // Liste des transactions (filtrées)
            if transactionsController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transactionsController.filteredTransactions.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(groupedTransactions.keys.sorted(by: >), id: \.self) { date in
                        Section {
                            ForEach(groupedTransactions[date] ?? []) { transaction in
                                TransactionRowView(
                                    transaction: transaction,
                                    onEdit: {
                                        transactionToEdit = transaction
                                        showTransactionForm = true
                                    },
                                    onDelete: {
                                        transactionToDelete = transaction
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        } header: {
                            Text(date, style: .date)
                                .font(.headline)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showTransactionForm) {
            if let transaction = transactionToEdit {
                TransactionFormView(isPresented: $showTransactionForm, transactionToEdit: transaction)
            } else {
                TransactionFormView(isPresented: $showTransactionForm)
            }
        }
        .sheet(isPresented: $showFilters) {
            TransactionFiltersView(
                filters: $transactionsController.filters,
                isPresented: $showFilters
            )
            .onDisappear {
                transactionsController.applyFilters()
            }
        }
        .alert("Supprimer la transaction ?", isPresented: $showDeleteConfirmation, presenting: transactionToDelete) { transaction in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await transactionsController.deleteTransaction(id: transaction.id)
                    await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                }
            }
        } message: { _ in
            Text("Cette action est irréversible.")
        }
    }
    
    private var headerTitle: String {
        if let accountID = transactionsController.filters.accountID,
           let account = accountsController.getAccount(id: accountID) {
            return account.name
        }
        return "Toutes les transactions"
    }
    
    private var headerSubtitle: String {
        if let accountID = transactionsController.filters.accountID,
           let account = accountsController.getAccount(id: accountID) {
            var parts: [String] = [account.type.displayName]
            if let bank = account.bank {
                parts.append(bank)
            }
            return parts.joined(separator: " • ")
        }
        
        let count = accountsController.activeAccounts.count
        return "\(count) compte\(count > 1 ? "s" : "")"
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: transactionsController.filters.isActive ? "line.3.horizontal.decrease.circle" : "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            if transactionsController.filters.isActive {
                Text("Aucun résultat")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Aucune transaction ne correspond aux filtres")
                    .foregroundColor(.secondary)
                
                Button {
                    transactionsController.resetFilters()
                } label: {
                    Label("Effacer les filtres", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Aucune transaction")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Créez votre première transaction")
                    .foregroundColor(.secondary)
                
                Button {
                    showTransactionForm = true
                } label: {
                    Label("Créer une transaction", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var groupedTransactions: [Date: [Transaction]] {
        let calendar = Calendar.current
        return Dictionary(grouping: transactionsController.filteredTransactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
    }
}
