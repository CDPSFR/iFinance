import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    
    @State private var selectedTab: ReportTab = .cashFlow
    @State private var showFilters = false
    
    enum ReportTab: String, CaseIterable {
        case cashFlow = "Revenus et dépenses"
        case categories = "Dépenses par catégorie"
        case payees = "Dépenses par bénéficiaire"
        case accounts = "Dépenses par compte"
        case balance = "Évolution du solde"
        case monthlyBalance = "Solde mensuel"

        var icon: String {
            switch self {
            case .cashFlow: return "chart.bar"
            case .categories: return "chart.pie"
            case .payees: return "person.2"
            case .accounts: return "creditcard"
            case .balance: return "chart.line.uptrend.xyaxis"
            case .monthlyBalance: return "chart.bar.xaxis"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Liste des rapports (le titre est dans la barre d'outils)
            List(selection: tabSelection) {
                Section("Modèles") {
                    ForEach(ReportTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(Optional(tab))
                    }
                }
            }
            .listStyle(.inset)
            .frame(width: 250)

            Divider()

            VStack(spacing: 0) {
            // Badges filtres actifs
            if hasExtraFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
                                icon: "person.2",
                                onRemove: {
                                    var newFilters = transactionsController.filters
                                    newFilters.payeeID = nil
                                    transactionsController.updateFilters(newFilters)
                                }
                            )
                        }

                        Button {
                            var newFilters = transactionsController.filters
                            newFilters.transactionType = nil
                            newFilters.categoryID = nil
                            newFilters.payeeID = nil
                            transactionsController.updateFilters(newFilters)
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
            
            // Contenu du graphique
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(NativeMetrics.pagePadding)
            }
        }
        .pageBackground()
        .navigationSubtitle(selectedTab.rawValue)
        .onAppear {
            // Réglage « Période par défaut des rapports »
            if UserDefaults.standard.string(forKey: SettingsKeys.reportsDefaultPeriod) == "last12",
               transactionsController.filters.dateRange == .all {
                setDateRange(lastTwelveMonths)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Période
                Menu {
                    Button("Tout") { setDateRange(.all) }
                    Button("12 derniers mois") { setDateRange(lastTwelveMonths) }
                    Button("Cette année") { setDateRange(.thisYear) }
                    Divider()
                    Button("Ce mois") { setDateRange(.thisMonth) }
                    Button("Mois dernier") { setDateRange(.lastMonth) }
                } label: {
                    Label(periodTitle, systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                }
                .help("Période du rapport")

                // Comptes
                Menu {
                    Button("Tous les comptes") { transactionsController.filterByAccount(nil) }
                    Divider()
                    ForEach(accountsController.activeAccounts) { account in
                        Button(account.name) { transactionsController.filterByAccount(account.id) }
                    }
                } label: {
                    Label(accountTitle, systemImage: "creditcard")
                        .labelStyle(.titleAndIcon)
                }
                .help("Comptes pris en compte")
            }
        }
    }

    /// Filtres autres que la période et le compte, affichés en badges
    private var hasExtraFilters: Bool {
        let filters = transactionsController.filters
        return filters.transactionType != nil || filters.categoryID != nil || filters.payeeID != nil
    }

    // MARK: - Période et comptes

    /// Du premier jour du mois, onze mois en arrière, à la fin du mois en cours
    private var lastTwelveMonths: TransactionFilters.DateRange {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let start = calendar.date(byAdding: .month, value: -11, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
        return .custom(start: start, end: end)
    }

    private func setDateRange(_ range: TransactionFilters.DateRange) {
        var filters = transactionsController.filters
        filters.dateRange = range
        transactionsController.updateFilters(filters)
    }

    private var periodTitle: String {
        let range = transactionsController.filters.dateRange
        if range == lastTwelveMonths {
            return "12 derniers mois"
        }
        return range == .all ? "Toute la période" : range.displayName
    }

    private var accountTitle: String {
        if let accountID = transactionsController.filters.accountID,
           let account = accountsController.getAccount(id: accountID) {
            return account.name
        }
        return "Tous les comptes"
    }

    /// Sélection de la liste : jamais vide
    private var tabSelection: Binding<ReportTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if let newValue {
                    selectedTab = newValue
                }
            }
        )
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .balance:
            BalanceChartView()
        case .monthlyBalance:
            MonthlyBalanceChartView()
        case .categories:
            CategoriesChartView()
        case .accounts:
            AccountsChartView()
        case .payees:
            PayeesChartView()
        case .cashFlow:
            CashFlowChartView()
        }
    }
}
