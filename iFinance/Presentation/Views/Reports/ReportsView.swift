import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    
    @State private var selectedTab: ReportTab = .balance
    @State private var showFilters = false
    
    enum ReportTab: String, CaseIterable {
        case balance = "Évolution du solde"
        case monthlyBalance = "Solde mensuel"
        case categories = "Dépenses par catégorie"
        case accounts = "Dépenses par compte"
        case payees = "Dépenses par bénéficiaire"
        case cashFlow = "Revenus et dépenses"
        
        var icon: String {
            switch self {
            case .balance: return "chart.line.uptrend.xyaxis"
            case .monthlyBalance: return "chart.bar.xaxis"
            case .categories: return "chart.pie"
            case .accounts: return "creditcard"
            case .payees: return "person.2"
            case .cashFlow: return "chart.bar"
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
            
            // Contenu du graphique
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(NativeMetrics.pagePadding)
            }
        }
        .pageBackground()
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
