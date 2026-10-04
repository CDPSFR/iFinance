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
        case cashFlow = "Cash Flow - Revenus vs Dépenses"
        
        var icon: String {
            switch self {
            case .balance: return "chart.line.uptrend.xyaxis"
            case .monthlyBalance: return "chart.bar.xaxis"
            case .categories: return "chart.pie.fill"
            case .accounts: return "creditcard.fill"
            case .payees: return "person.2.fill"
            case .cashFlow: return "chart.bar.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rapports")
                    .font(.system(size: 34, weight: .bold))
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ReportTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.body)
                                Text(tab.rawValue)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.blue.opacity(0.1) : Color.clear)
                            .foregroundColor(selectedTab == tab ? .blue : .secondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            
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
            
            // Contenu du graphique
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding()
        }
        .pageBackground()
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
