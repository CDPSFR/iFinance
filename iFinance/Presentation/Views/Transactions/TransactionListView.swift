import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var projectsController: ProjectsController
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var appSettings: AppSettings
    
    @State private var showTransactionForm = false
    @State private var showFilters = false
    @State private var transactionToEdit: Transaction?
    @State private var transactionToDelete: Transaction?
    @State private var showDeleteConfirmation = false
    @State private var selectedTransactions: Set<Transaction.ID> = []
    @State private var showBulkDeleteConfirmation = false
    @State private var showBulkCategorize = false
    @State private var transactionToConvert: Transaction?
    @State private var transactionToRepeat: Transaction?
    @AppStorage("showTransactionInspector") private var showInspector = true
    @State private var sortOrder = [KeyPathComparator(\TransactionRow.date, order: .reverse)]
    
    var body: some View {
        VStack(spacing: 0) {
            // Bandeau du compte sélectionné (le titre est dans la barre d'outils)
            if let accountID = transactionsController.filters.accountID,
               let account = accountsController.getAccount(id: accountID) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headerSubtitle)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(headerBalanceLabel(for: account))
                        .foregroundStyle(.secondary)

                    let balance = AccountValuation(
                        transactionsController: transactionsController,
                        investmentsController: investmentsController,
                        savingsPlansController: savingsPlansController
                    ).cash(of: account)

                    Text(balance, format: .currency(code: account.currency))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(balance >= 0 ? Color.primary : Color.red)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

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
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                
                Divider()
            }
            
            // Échéances à venir des récurrences (du compte affiché, ou de tous les comptes)
            UpcomingOccurrencesBand(
                accountID: transactionsController.filters.accountID,
                currentBalance: upcomingBandBalance
            )

            // L'inspecteur se loge sous l'en-tête de la page
            SidePanelLayout(isPresented: $showInspector) {
                // Table des transactions
                if transactionsController.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if transactionsController.filteredTransactions.isEmpty {
                    emptyStateView
                } else {
                    transactionTable
                    TableStatusBar(items: statusItems)
                }
            } panel: {
                inspectorContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help("Afficher ou masquer l'inspecteur")
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
        .alert(
            "Supprimer \(selectedTransactions.count) transaction(s) ?",
            isPresented: $showBulkDeleteConfirmation
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                let ids = selectedTransactions
                Task {
                    for id in ids {
                        await transactionsController.deleteTransaction(id: id)
                    }
                    selectedTransactions.removeAll()
                    await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                }
            }
        } message: {
            Text("Cette action est irréversible.")
        }
        .sheet(item: $transactionToConvert) { transaction in
            ConvertToTransferView(
                transaction: transaction,
                isPresented: Binding(
                    get: { transactionToConvert != nil },
                    set: { if !$0 { transactionToConvert = nil } }
                ),
                onConfirm: { destinationAccountID in
                    Task {
                        // Conversion en une seule écriture : la dépense devient le côté source du transfert
                        await transactionsController.convertToTransfer(
                            transaction,
                            to: destinationAccountID,
                            payeeName: transaction.payeeID.flatMap { payeesController.getPayee(id: $0)?.name }
                        )
                        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                    }
                }
            )
        }
        .sheet(item: $transactionToRepeat) { transaction in
            RecurringFormView(
                isPresented: Binding(
                    get: { transactionToRepeat != nil },
                    set: { if !$0 { transactionToRepeat = nil } }
                ),
                prefill: transaction
            )
        }
        .sheet(isPresented: $showBulkCategorize) {
            BulkCategorizeView(
                subtitle: "\(selectedTransactions.count) transaction(s) sélectionnée(s)",
                isPresented: $showBulkCategorize,
                onApply: { categoryID, _ in
                    let ids = selectedTransactions
                    Task {
                        for id in ids {
                            if var tx = transactionsController.filteredTransactions.first(where: { $0.id == id }) {
                                tx.categoryID = categoryID
                                await transactionsController.updateTransaction(tx)
                            }
                        }
                        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                    }
                }
            )
        }
    }
    
    /// Solde de trésorerie du compte affiché, base du « solde prévu » du bandeau À venir
    private var upcomingBandBalance: Decimal? {
        guard let accountID = transactionsController.filters.accountID,
              let account = accountsController.getAccount(id: accountID) else { return nil }
        return AccountValuation(
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController
        ).cash(of: account)
    }

    // MARK: - Transaction Table
    
    private var transactionTable: some View {
        Table(tableRows, selection: $selectedTransactions, sortOrder: $sortOrder) {
            // Colonne Date
            TableColumn("Date", value: \.date) { row in
                Text(row.date, format: .dateTime.day().month(.abbreviated).year())
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)

            // Colonne Bénéficiaire
            TableColumn("Bénéficiaire", value: \.payeeNameForSort) { row in
                if let payeeName = row.payeeName {
                    HStack(spacing: 5) {
                        if row.isRecurring {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .help("Issue d'une récurrence")
                        }
                        Text(payeeName)
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 150, ideal: 220)

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
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 200)

            // Colonne Compte
            TableColumn("Compte", value: \.accountName) { row in
                Text(row.accountName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            
            // Colonne Montant
            TableColumn("Montant", value: \.amount) { row in
                Text(row.amount, format: .currency(code: row.currency))
                    .monospacedDigit()
                    .foregroundStyle(row.amount > 0 ? Color.green : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .width(min: 100, ideal: 120)
            
            // Colonne Solde (uniquement si un compte est sélectionné)
            if transactionsController.filters.accountID != nil {
                TableColumn("Solde", value: \.balance) { row in
                    Text(row.balance, format: .currency(code: row.currency))
                        .monospacedDigit()
                        .foregroundStyle(row.balance >= 0 ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .width(min: 100, ideal: 120)
            }
        }
        .contextMenu(forSelectionType: Transaction.ID.self) { items in
            if items.count == 1,
               let id = items.first,
               let transaction = transactionsController.filteredTransactions.first(where: { $0.id == id }) {
                Button {
                    transactionToEdit = transaction
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }

                if transaction.type == .debit {
                    Button {
                        transactionToConvert = transaction
                    } label: {
                        Label("Convertir en transfert", systemImage: "arrow.left.arrow.right")
                    }
                }

                if transaction.type != .transfer, transaction.recurringTemplateID == nil {
                    Button {
                        transactionToRepeat = transaction
                    } label: {
                        Label("Rendre récurrente…", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    transactionToDelete = transaction
                    showDeleteConfirmation = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } else if items.count > 1 {
                Button {
                    selectedTransactions = items
                    showBulkCategorize = true
                } label: {
                    Label("Catégoriser \(items.count) transactions", systemImage: "folder.badge.plus")
                }

                Divider()

                Button(role: .destructive) {
                    selectedTransactions = items
                    showBulkDeleteConfirmation = true
                } label: {
                    Label("Supprimer \(items.count) transactions", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Inspecteur

    private var selectedTransaction: Transaction? {
        guard selectedTransactions.count == 1, let id = selectedTransactions.first else { return nil }
        return transactionsController.filteredTransactions.first { $0.id == id }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let transaction = selectedTransaction {
            inspectorDetail(transaction)
        } else if selectedTransactions.count > 1 {
            ContentUnavailableView(
                "\(selectedTransactions.count) transactions sélectionnées",
                systemImage: "checklist",
                description: Text("Clic droit pour catégoriser ou supprimer la sélection.")
            )
        } else {
            ContentUnavailableView(
                "Aucune sélection",
                systemImage: "sidebar.right",
                description: Text("Sélectionnez une transaction pour afficher son détail.")
            )
        }
    }

    private func inspectorDetail(_ transaction: Transaction) -> some View {
        let account = accountsController.getAccount(id: transaction.accountID)
        let currency = account?.currency ?? "EUR"
        let payee = transaction.payeeID.flatMap { payeesController.getPayee(id: $0) }
        let categoryPath = transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "—"
        let amountText = appSettings.hideAmounts
            ? "•••"
            : transaction.signedAmount.formatted(.currency(code: currency))
        let memo = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return InspectorContainer {
            InspectorHeader(
                title: payee?.name ?? transaction.type.displayName,
                value: amountText,
                valueColor: transaction.type == .credit ? .green : .primary
            )

            InspectorSection {
                InspectorRow("Date", value: transaction.date.formatted(date: .long, time: .omitted))
                InspectorRow("Compte", value: account?.name ?? "Inconnu")
                InspectorRow("Catégorie", value: categoryPath)
                InspectorRow(label: "Projet") {
                    Picker("Projet", selection: projectBinding(for: transaction)) {
                        Text("Aucun").tag(UUID?.none)
                        Divider()
                        ForEach(projectsController.selectableProjects(including: transaction.projectID)) { project in
                            Text(project.name).tag(UUID?.some(project.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                InspectorRow("Type", value: transaction.type.displayName)
                InspectorRow(label: "Pointée") {
                    Toggle("Rapprochée avec le relevé", isOn: reconciledBinding(for: transaction))
                        .toggleStyle(.checkbox)
                }
            }

            InspectorSection(title: "Note") {
                Text(memo.isEmpty ? "Aucune note" : memo)
                    .foregroundStyle(memo.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            InspectorSection {
                HStack(spacing: 8) {
                    Button("Modifier…") {
                        transactionToEdit = transaction
                    }

                    if transaction.type == .debit {
                        Button("Convertir en transfert…") {
                            transactionToConvert = transaction
                        }
                    }
                }

                Button("Supprimer…", role: .destructive) {
                    transactionToDelete = transaction
                    showDeleteConfirmation = true
                }
            }
        }
    }

    private func projectBinding(for transaction: Transaction) -> Binding<UUID?> {
        Binding(
            get: { projectsController.project(id: transaction.projectID)?.id },
            set: { newValue in
                var updated = transaction
                updated.projectID = newValue
                Task {
                    await transactionsController.updateTransaction(updated)
                    await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                }
            }
        )
    }

    private func reconciledBinding(for transaction: Transaction) -> Binding<Bool> {
        Binding(
            get: { transaction.isReconciled },
            set: { newValue in
                var updated = transaction
                updated.isReconciled = newValue
                Task {
                    await transactionsController.updateTransaction(updated)
                    await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                }
            }
        )
    }

    // MARK: - Barre d'état

    private var statusItems: [String] {
        let transactions = transactionsController.filteredTransactions
        let count = transactions.count
        var items = ["\(count) transaction\(count > 1 ? "s" : "")"]

        guard !appSettings.hideAmounts else { return items }

        let currency = booksController.currentBook?.currency ?? "EUR"
        let credits = transactions.filter { $0.type == .credit }.reduce(Decimal(0)) { $0 + abs($1.amount) }
        let debits = transactions.filter { $0.type == .debit }.reduce(Decimal(0)) { $0 + abs($1.amount) }
        items.append("Entrées \(credits.formatted(.currency(code: currency)))")
        items.append("Sorties \(debits.formatted(.currency(code: currency)))")
        return items
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
                amount: transaction.signedAmount,
                balance: newBalance,
                currency: account?.currency ?? "EUR",
                isRecurring: transaction.recurringTemplateID != nil
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

extension TransactionListView {
    func headerBalanceLabel(for account: Account) -> String {
        switch account.type.trackingMode {
        case .transactions: return "Solde actuel"
        case .positions: return "Espèces"
        case .valuations: return "Versements nets"
        }
    }
}
