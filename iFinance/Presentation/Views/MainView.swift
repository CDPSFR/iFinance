import SwiftUI

struct MainView: View {

    // MARK: - Environment
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
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
        .onChange(of: booksController.currentBook?.id) { _, newValue in
            guard let bookID = newValue else { return }
            Task {
                await accountsController.loadAccounts(for: bookID)
                await categoriesController.loadCategories(for: bookID)
                await payeesController.loadPayees(for: bookID)
                await transactionsController.loadAllTransactions(
                    for: accountsController.activeAccounts
                )
                await budgetsController.loadBudgets(for: bookID)
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTab) {

                // Vue d'ensemble
                Section {
                    NavigationLink(value: SidebarItem.dashboard) {
                        Label("Vue d'ensemble", systemImage: "chart.pie")
                    }

                    NavigationLink(value: SidebarItem.wealth) {
                        Label("Patrimoine", systemImage: "building.columns")
                    }

                    NavigationLink(value: SidebarItem.allTransactions) {
                        Label("Toutes les transactions", systemImage: "list.bullet.rectangle")
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
                
                // Comptes clos
                Section("Comptes clos") {
                    ForEach(accountsController.closedAccounts) { account in
                        NavigationLink(value: SidebarItem.account(account.id)) {
                            AccountSidebarRow(
                                account: account,
                                balance: valuation.value(of: account),
                                isClosed: true
                            )
                        }
                    }
                }

                // Organisation
                Section("Organisation") {
                    NavigationLink(value: SidebarItem.categories) {
                        Label("Catégories", systemImage: "folder.fill")
                    }

                    NavigationLink(value: SidebarItem.payees) {
                        Label("Bénéficiaires", systemImage: "person.crop.circle.fill")
                    }

                    NavigationLink(value: SidebarItem.budgets) {
                        Label("Budgets", systemImage: "target")
                    }

                    NavigationLink(value: SidebarItem.reports) {
                        Label("Rapports", systemImage: "chart.line.uptrend.xyaxis")
                    }

                    NavigationLink(value: SidebarItem.settings) {
                        Label("Paramètres", systemImage: "gear")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("iFinance")

            // Sélecteur de livre
            BookSelectorButton(
                showBookSelector: $showBookSelector,
                showBookForm: $showBookForm
            )
            .padding(8)
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
                case .account(_):
                    TransactionListView()
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

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        
        ToolbarItem(placement: .automatic) {
            HStack {
                if shouldShowFilters {
                    Button {
                        showFilterForm = true
                    } label: {
                        Label("Filtres", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .background(transactionsController.filters.isActive ? Color.blue.opacity(0.2) : Color.clear)
                    .foregroundColor(transactionsController.filters.isActive ? .blue : .primary)
                    .cornerRadius(6)
                }

                // Menu dropdown pour créer différents éléments
                Menu {
                    Button {
                        showTransactionForm = true
                    } label: {
                        Label("Nouvelle transaction", systemImage: "plus.circle")
                    }
                    
                    Divider()
                    
                    Button {
                        showAccountForm = true
                    } label: {
                        Label("Nouveau compte", systemImage: "creditcard")
                    }
                    
                    Button {
                        showCategoryForm = true
                    } label: {
                        Label("Nouvelle catégorie", systemImage: "folder")
                    }
                    
                    Button {
                        showPayeeForm = true
                    } label: {
                        Label("Nouveau bénéficiaire", systemImage: "person.crop.circle")
                    }

                    Button {
                        showBudgetForm = true
                    } label: {
                        Label("Nouveau budget", systemImage: "target")
                    }
                } label: {
                    Image(systemName: "plus")
                } primaryAction: {
                    // Action par défaut quand on clique directement (sans ouvrir le menu)
                    showTransactionForm = true
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Créer un nouvel élément (⌘N pour transaction)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Helpers
    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController)
    }

    private var activeAccountGroups: [(group: AccountGroup, accounts: [Account])] {
        Dictionary(grouping: accountsController.activeAccounts) { $0.type.group }
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
