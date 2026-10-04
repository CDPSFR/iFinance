import SwiftUI

struct MainView: View {

    // MARK: - Environment
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var budgetsController: BudgetsController

    // MARK: - State
    @State private var showTransactionForm = false
    @State private var showAccountForm = false // NOUVEAU
    @State private var showCategoryForm = false // NOUVEAU
    @State private var showPayeeForm = false // NOUVEAU
    @State private var showBudgetForm = false
    @State private var showFilterForm = false
    @State private var showBookSelector = false
    @State private var showBookForm = false
    @State private var selectedTab: SidebarItem = .dashboard

    // MARK: - Sidebar enum
    enum SidebarItem: Hashable, Identifiable {
        case dashboard
        case wealth
        case allTransactions
        case account(UUID)
        case categories
        case payees
        case budgets
        case reports
        case settings

        var id: String {
            switch self {
            case .dashboard: return "dashboard"
            case .wealth: return "wealth"
            case .allTransactions: return "allTransactions"
            case .account(let id): return "account-\(id.uuidString)"
            case .categories: return "categories"
            case .payees: return "payees"
            case .budgets: return "budgets"
            case .reports: return "reports"
            case .settings: return "settings"
            }
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            contentView
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showBookSelector) {
            BookSelectorView(isPresented: $showBookSelector)
        }
        .sheet(isPresented: $showBookForm) {
            BookFormView(isPresented: $showBookForm)
        }
        .sheet(isPresented: $showTransactionForm) {
            TransactionFormView(isPresented: $showTransactionForm)
        }
        // NOUVEAU: Sheets pour les nouveaux formulaires
        .sheet(isPresented: $showAccountForm) {
            AccountFormView(isPresented: $showAccountForm)
        }
        .sheet(isPresented: $showCategoryForm) {
            CategoryFormView(isPresented: $showCategoryForm)
        }
        .sheet(isPresented: $showPayeeForm) {
            PayeeFormView(isPresented: $showPayeeForm)
        }
        .sheet(isPresented: $showBudgetForm) {
            BudgetFormView(isPresented: $showBudgetForm)
        }
        .sheet(isPresented: $showFilterForm) {
            TransactionFiltersView(filters: $transactionsController.filters, isPresented: $showFilterForm)
        }
        .task {
            await booksController.loadBooks()
        }
        .onReceive(NotificationCenter.default.publisher(for: CreationCommand.notification)) { notification in
            guard let command = notification.object as? CreationCommand else { return }
            handle(command)
        }
        .onChange(of: booksController.currentBook?.id) { _, newValue in
            guard let bookID = newValue else { return }
            Task {
                await accountsController.loadAccounts(for: bookID)
                await categoriesController.loadCategories(for: bookID)
                await payeesController.loadPayees(for: bookID)
                await transactionsController.loadAllTransactions(
                    for: accountsController.activeAccounts
                )
                await investmentsController.load(for: accountsController.activeAccounts)
                await savingsPlansController.load(for: accountsController.activeAccounts)
                await budgetsController.loadBudgets(for: bookID)
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Sélecteur de livre, en tête de barre latérale
            BookSelectorButton(
                showBookSelector: $showBookSelector,
                showBookForm: $showBookForm
            )
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)

            List(selection: $selectedTab) {

                // Vue d'ensemble
                Section {
                    NavigationLink(value: SidebarItem.dashboard) {
                        Label("Vue d'ensemble", systemImage: "square.grid.2x2")
                    }

                    NavigationLink(value: SidebarItem.wealth) {
                        Label("Patrimoine", systemImage: "building.columns")
                    }

                    NavigationLink(value: SidebarItem.allTransactions) {
                        Label("Toutes les transactions", systemImage: "list.bullet")
                    }
                }

                // Comptes ouverts, regroupés par type
                ForEach(activeAccountGroups, id: \.group) { item in
                    Section(item.group.displayName) {
                        ForEach(item.accounts) { account in
                            NavigationLink(value: SidebarItem.account(account.id)) {
                                AccountSidebarRow(
                                    account: account,
                                    balance: valuation.value(of: account),
                                    isClosed: false
                                )
                            }
                        }
                    }
                }
                
                // Comptes clos (hors comptes masqués de la barre latérale)
                if !sidebarClosedAccounts.isEmpty {
                    Section("Comptes clos") {
                        ForEach(sidebarClosedAccounts) { account in
                            NavigationLink(value: SidebarItem.account(account.id)) {
                                AccountSidebarRow(
                                    account: account,
                                    balance: valuation.value(of: account),
                                    isClosed: true
                                )
                            }
                        }
                    }
                }

                // Organisation
                Section("Organisation") {
                    NavigationLink(value: SidebarItem.categories) {
                        Label("Catégories", systemImage: "tag")
                    }

                    NavigationLink(value: SidebarItem.payees) {
                        Label("Bénéficiaires", systemImage: "person.2")
                    }

                    NavigationLink(value: SidebarItem.budgets) {
                        Label("Budgets", systemImage: "chart.pie")
                    }

                    NavigationLink(value: SidebarItem.reports) {
                        Label("Rapports", systemImage: "chart.bar")
                    }

                    NavigationLink(value: SidebarItem.settings) {
                        Label("Paramètres", systemImage: "gearshape")
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        if booksController.currentBook != nil {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                case .wealth:
                    WealthView()
                case .allTransactions:
                    TransactionListView()
                case .account(let accountID):
                    switch accountsController.getAccount(id: accountID)?.type.trackingMode {
                    case .positions:
                        InvestmentAccountView(accountID: accountID)
                            .id(accountID)
                    case .valuations:
                        SavingsPlanAccountView(accountID: accountID)
                            .id(accountID)
                    default:
                        TransactionListView()
                    }
                case .categories:
                    CategoryListView(selectedTab: $selectedTab)
                case .payees:
                    PayeeListView(selectedTab: $selectedTab)
                case .budgets:
                    NavigationStack {
                        BudgetsView()
                            .navigationDestination(for: SettingsView.Destination.self) { destination in
                                if case .budget(let budget) = destination {
                                    BudgetDetailView(budget: budget)
                                }
                            }
                    }
                case .reports:
                    ReportsView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(windowTitle)
            .navigationSubtitle(booksController.currentBook?.name ?? "")
            .onChange(of: selectedTab) { oldValue, newValue in
                // Gérer le filtrage selon le cas
                switch newValue {
                case .allTransactions:
                    transactionsController.filterByAccount(nil)
                case .account(let accountID):
                    transactionsController.filterByAccount(accountID)
                default:
                    break
                }
            }
        } else {
            NoBookSelectedView()
        }
    }

    // MARK: - Commandes de création (menu Fichier et raccourcis clavier)

    private func handle(_ command: CreationCommand) {
        // Sans livre ouvert, seule la création d'un livre a un sens
        guard command == .book || booksController.currentBook != nil else { return }
        // Une seule feuille à la fois
        let isPresenting = showTransactionForm || showAccountForm || showCategoryForm || showPayeeForm
            || showBudgetForm || showBookForm || showFilterForm || showBookSelector
        guard !isPresenting else { return }

        switch command {
        case .transaction: showTransactionForm = true
        case .account: showAccountForm = true
        case .category: showCategoryForm = true
        case .payee: showPayeeForm = true
        case .budget: showBudgetForm = true
        case .book: showBookForm = true
        }
    }

    private func creationButton(_ command: CreationCommand) -> some View {
        Button(command.title) {
            handle(command)
        }
        .keyboardShortcut(command.key, modifiers: command.modifiers)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        
        ToolbarItem(placement: .automatic) {
            HStack {
                if shouldShowFilters {
                    Button {
                        showFilterForm = true
                    } label: {
                        Label("Filtres", systemImage: transactionsController.filters.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .foregroundStyle(transactionsController.filters.isActive ? Color.accentColor : Color.primary)
                    .help("Filtrer les transactions")
                }

                // Menu « + » : un clic crée une transaction, un clic long ouvre le menu.
                // Les raccourcis sont affichés par macOS à droite de chaque entrée.
                Menu {
                    creationButton(.transaction)
                    Divider()
                    creationButton(.account)
                    creationButton(.category)
                    creationButton(.payee)
                    creationButton(.budget)
                    Divider()
                    creationButton(.book)
                } label: {
                    Label("Ajouter", systemImage: "plus")
                } primaryAction: {
                    handle(.transaction)
                }
                .help("Nouvelle transaction (⌘N). Maintenez le clic pour créer un autre élément.")
            }
        }
    }

    // MARK: - Helpers
    /// Titre affiché dans la barre d'outils unifiée
    private var windowTitle: String {
        switch selectedTab {
        case .dashboard: return "Vue d'ensemble"
        case .wealth: return "Patrimoine"
        case .allTransactions: return "Transactions"
        case .account(let id): return accountsController.getAccount(id: id)?.name ?? "Compte"
        case .categories: return "Catégories"
        case .payees: return "Bénéficiaires"
        case .budgets: return "Budgets"
        case .reports: return "Rapports"
        case .settings: return "Paramètres"
        }
    }

    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController, investmentsController: investmentsController, savingsPlansController: savingsPlansController)
    }

    private var sidebarClosedAccounts: [Account] {
        accountsController.closedAccounts.filter { !$0.isHiddenFromSidebar }
    }

    private var activeAccountGroups: [(group: AccountGroup, accounts: [Account])] {
        Dictionary(grouping: accountsController.activeAccounts.filter { !$0.isHiddenFromSidebar }) { $0.type.group }
            .map { ($0.key, $0.value) }
            .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }

    private var shouldShowFilters: Bool {
        switch selectedTab {
        case .allTransactions, .account(_), .reports:
            return true
        default:
            return false
        }
    }
}
