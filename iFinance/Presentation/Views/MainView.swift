import SwiftUI

struct MainView: View {

    // MARK: - Environment
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var projectsController: ProjectsController

    // MARK: - State
    @State private var showTransactionForm = false
    @State private var showAccountForm = false // NOUVEAU
    @State private var showCategoryForm = false // NOUVEAU
    @State private var showPayeeForm = false // NOUVEAU
    @State private var showBudgetForm = false
    @State private var showProjectForm = false
    @State private var showFilterForm = false
    @State private var showBookForm = false
    @State private var selectedTab: SidebarItem = MainView.startTab
    @AppStorage(SettingsKeys.showClosedAccountsInSidebar) private var showClosedAccounts = true

    /// Écran affiché au lancement, choisi dans Réglages › Général
    private static var startTab: SidebarItem {
        switch UserDefaults.standard.string(forKey: SettingsKeys.startScreen) {
        case "transactions": return .allTransactions
        case "budgets": return .budgets
        case "reports": return .reports
        default: return .dashboard
        }
    }

    // MARK: - Sidebar enum
    enum SidebarItem: Hashable, Identifiable {
        case dashboard
        case wealth
        case allTransactions
        case account(UUID)
        case categories
        case payees
        case budgets
        case projects
        case recurring
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
            case .projects: return "projects"
            case .recurring: return "recurring"
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
        .sheet(isPresented: $showProjectForm) {
            ProjectFormView(isPresented: $showProjectForm)
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
                // Avant les transactions : les échéances en saisie automatique y sont créées
                await recurringController.load(for: bookID)
                await transactionsController.loadAllTransactions(
                    for: accountsController.activeAccounts
                )
                await investmentsController.load(for: accountsController.activeAccounts)
                await savingsPlansController.load(for: accountsController.activeAccounts)
                await budgetsController.loadBudgets(for: bookID)
                await projectsController.loadProjects(for: bookID)
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Sélecteur de livre, en tête de barre latérale
            BookSelectorButton(
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

                    NavigationLink(value: SidebarItem.projects) {
                        Label("Projets", systemImage: "folder")
                    }

                    NavigationLink(value: SidebarItem.recurring) {
                        Label("Récurrent", systemImage: "arrow.triangle.2.circlepath")
                            // Échéances arrivées à terme, à valider ou à passer
                            .badge(recurringController.dueCount)
                    }

                    NavigationLink(value: SidebarItem.reports) {
                        Label("Rapports", systemImage: "chart.bar")
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Lien vers la fenêtre Réglages (⌘,), fixé en bas de la barre latérale
                VStack(spacing: 0) {
                    Divider()
                    SettingsLink {
                        Label("Réglages", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
            }
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
                case .projects:
                    NavigationStack {
                        ProjectsView()
                    }
                case .budgets:
                    NavigationStack {
                        BudgetsView()
                            .navigationDestination(for: SettingsView.Destination.self) { destination in
                                if case .budget(let budget) = destination {
                                    BudgetDetailView(budget: budget)
                                }
                            }
                    }
                case .recurring:
                    RecurringView()
                case .reports:
                    ReportsView()
                case .settings:
                    // Les réglages ont leur propre fenêtre (⌘,)
                    ContentUnavailableView {
                        Label("Réglages", systemImage: "gearshape")
                    } description: {
                        Text("Les réglages s'ouvrent dans une fenêtre séparée.")
                    } actions: {
                        SettingsLink {
                            Text("Ouvrir les réglages")
                        }
                    }
                }
            }
            // La page occupe toute la zone : sans cela, une page au contenu réduit (état vide)
            // est centrée avec son filet, qui se retrouve au milieu de l'écran
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Filet sous la barre d'outils, sur toutes les pages : sépare l'en-tête du contenu
            .safeAreaInset(edge: .top, spacing: 0) {
                Divider()
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
            || showBudgetForm || showProjectForm || showBookForm || showFilterForm
        guard !isPresenting else { return }

        switch command {
        case .transaction: showTransactionForm = true
        case .account: showAccountForm = true
        case .category: showCategoryForm = true
        case .payee: showPayeeForm = true
        case .budget: showBudgetForm = true
        case .project: showProjectForm = true
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
        // Le bouton des filtres forme son propre groupe, détaché des autres boutons
        // de la barre d'outils par un espace de part et d'autre.
        if shouldShowFilters {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(placement: .automatic) {
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
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }
        }

        ToolbarItem(placement: .automatic) {
                // Menu « + » : un clic crée une transaction, un clic long ouvre le menu.
                // Les raccourcis sont affichés par macOS à droite de chaque entrée.
                Menu {
                    creationButton(.transaction)
                    Divider()
                    creationButton(.account)
                    creationButton(.category)
                    creationButton(.payee)
                    creationButton(.budget)
                    creationButton(.project)
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
        case .projects: return "Projets"
        case .recurring: return "Récurrent"
        case .reports: return "Rapports"
        case .settings: return "Paramètres"
        }
    }

    private var valuation: AccountValuation {
        AccountValuation(transactionsController: transactionsController, investmentsController: investmentsController, savingsPlansController: savingsPlansController)
    }

    private var sidebarClosedAccounts: [Account] {
        guard showClosedAccounts else { return [] }
        return accountsController.closedAccounts.filter { !$0.isHiddenFromSidebar }
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
