import SwiftUI

struct TransactionListView: View {
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
    @State private var selectedTransaction: Transaction.ID?
    @State private var sortOrder = [KeyPathComparator(\TransactionRow.date, order: .reverse)]
    
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
            }
            .padding()
            
            Divider()
            
            // Badges filtres actifs
            if transactionsController.filters.isActive {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
            
            // Table des transactions
            if transactionsController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transactionsController.filteredTransactions.isEmpty {
                emptyStateView
            } else {
                transactionTable
            }
        }
        .sheet(item: $transactionToEdit) { transaction in
            TransactionFormView(
                isPresented: Binding(
                    get: { transactionToEdit != nil },
                    set: { if !$0 { transactionToEdit = nil } }
                ),
                transactionToEdit: transaction
            )
        }
        .sheet(isPresented: $showTransactionForm) {
            TransactionFormView(isPresented: $showTransactionForm)
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
    
    // MARK: - Transaction Table
    
    private var transactionTable: some View {
        Table(tableRows, selection: $selectedTransaction, sortOrder: $sortOrder) {
            // Colonne Type (icône)
            TableColumn("") { row in
                Image(systemName: row.typeIcon)
                    .foregroundColor(row.typeColor)
                    .frame(width: 20)
            }
            .width(30)
            
            // Colonne Date
            TableColumn("Date", value: \.date) { row in
                Text(row.date, style: .date)
                    .font(.body)
            }
            .width(min: 100, ideal: 120)
            
            // Colonne Compte
            TableColumn("Compte", value: \.accountName) { row in
                HStack(spacing: 6) {
                    Image(systemName: row.accountIcon)
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(row.accountName)
                        .font(.body)
                }
            }
            .width(min: 120, ideal: 150)
            
            // Colonne Bénéficiaire
            TableColumn("Bénéficiaire", value: \.payeeNameForSort) { row in
                if let payeeName = row.payeeName {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(payeeName)
                            .font(.body)
                    }
                } else {
                    Text(row.memo ?? "—")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 150, ideal: 200)
            
            // Colonne Catégorie
            TableColumn("Catégorie", value: \.categoryNameForSort) { row in
                if let categoryName = row.categoryName {
                    HStack(spacing: 6) {
                        if let categoryColor = row.categoryColor {
                            Circle()
                                .fill(categoryColor)
                                .frame(width: 8, height: 8)
                        }
                        Text(categoryName)
                            .font(.body)
                    }
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 120, ideal: 180)
            
            // Colonne Montant
            TableColumn("Montant", value: \.amount) { row in
                 Text((row.amount >= 0 ? "+" : "") + row.amount.formatted(.currency(code: row.currency)))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(row.typeColor)
            }
            .width(min: 100, ideal: 120)
            
            // Colonne Solde (uniquement si un compte est sélectionné)
            if transactionsController.filters.accountID != nil {
                TableColumn("Solde", value: \.balance) { row in
                    Text(row.balance, format: .currency(code: row.currency))
                        .font(.body)
                        .foregroundColor(row.balance >= 0 ? .green : .red)
                }
                .width(min: 100, ideal: 120)
            }
        }
        .contextMenu(forSelectionType: Transaction.ID.self) { items in
            if items.count == 1, let id = items.first,
               let transaction = transactionsController.filteredTransactions.first(where: { $0.id == id }) {
                Button {
                    transactionToEdit = transaction  // Ceci déclenchera automatiquement le sheet
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    transactionToDelete = transaction
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Table Rows
    
    private var tableRows: [TransactionRow] {
        var runningBalances: [UUID: Decimal] = [:]
        
        // Initialiser avec les soldes initiaux
        for account in accountsController.activeAccounts {
            runningBalances[account.id] = account.initialBalance
        }
        
        // Trier par date croissante pour calculer les soldes
        let sortedTransactions = transactionsController.filteredTransactions
            .sorted { $0.date < $1.date }
        
        // Calculer les soldes cumulés
        var rows: [TransactionRow] = []
        for transaction in sortedTransactions {
            // Mettre à jour le solde
            let previousBalance = runningBalances[transaction.accountID] ?? 0
            let newBalance = previousBalance + transaction.signedAmount
            runningBalances[transaction.accountID] = newBalance
            
            // Créer la row
            let account = accountsController.getAccount(id: transaction.accountID)
            let payee = transaction.payeeID.flatMap { payeesController.getPayee(id: $0) }
            let category = transaction.categoryID.flatMap { categoriesController.getCategory(id: $0) }
            
            let row = TransactionRow(
                id: transaction.id,
                date: transaction.date,
                typeIcon: transaction.type.icon,
                typeColor: colorForType(transaction.type),
                accountName: account?.name ?? "Inconnu",
                accountIcon: account?.type.icon ?? "questionmark.circle",
                payeeName: payee?.name,
                memo: transaction.memo,
                categoryName: category.map { categoriesController.getCategoryPath(for: $0.id) },
                categoryColor: category.map { Color(hex: $0.displayColor) },
                amount: transaction.amount,
                balance: newBalance,
                currency: account?.currency ?? "EUR"
            )
            
            rows.append(row)
        }
        
        // Appliquer le tri
        return rows.sorted(using: sortOrder)
    }
    
    // MARK: - Helpers
    
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
    
    private func colorForType(_ type: TransactionType) -> Color {
        switch type {
        case .debit: return .red
        case .credit: return .green
        case .transfer: return .blue
        }
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
}
