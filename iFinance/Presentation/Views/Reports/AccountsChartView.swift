import SwiftUI
import Charts

struct AccountsChartView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    
    struct AccountData: Identifiable {
        let id = UUID()
        let accountID: UUID
        let accountName: String
        let amount: Decimal
        let color: Color
        let percentage: Double
    }
    
    @EnvironmentObject var appSettings: AppSettings
    @State private var selectedAccountID: UUID?
    @State private var rawSelectedAngle: Double?
    
    // Palette de couleurs pour les comptes
    private let colorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .red, .yellow, .cyan, .mint, .indigo,
        .teal, .brown
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if accountData.isEmpty {
                emptyStateView
            } else {
                // Statistiques globales
                HStack(spacing: NativeMetrics.groupSpacing) {
                    StatisticCardView(
                        title: "Total dépenses",
                        value: totalExpenses,
                        color: .red,
                        isCurrency: true
                    )
                    
                    StatisticCardView(
                        title: "Nombre de comptes",
                        value: Decimal(accountData.count),
                        color: .primary,
                        isCurrency: false
                    )
                    
                    StatisticCardView(
                        title: "Dépense moyenne",
                        value: averageExpense,
                        color: .orange,
                        isCurrency: true
                    )
                }
                .padding()
                .frame(height: 120)
                
                
                if let highestAccount = accountData.max(by: { $1.amount > $0.amount }) {
                    ChartPopOverView(highestAccount.amount, highestAccount.accountName)
                        .padding(.vertical)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                
                // Graphique centré
                let hideAmounts = appSettings.hideAmounts
                VStack(spacing: 12) {
                    Chart {
                        ForEach(accountData.sorted { $0.amount > $1.amount }) { item in
                            SectorMark(
                                angle: .value("Montant",
                                              NSDecimalNumber(decimal: item.amount).doubleValue),
                                innerRadius: .ratio(0.618),
                                outerRadius: selectedAccountID == nil ? 130 : (selectedAccountID == item.accountID ? 130 : 120),
                                angularInset: 1.5
                            )
                            .cornerRadius(6)
                            .foregroundStyle(item.color)
                            .annotation(position: .overlay, alignment: .center) {
                                Text("\(NSDecimalNumber(decimal: item.amount).doubleValue, specifier: "%.0f")€")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .privacyBlur(hidden: hideAmounts)
                            }
                            .opacity(selectedAccountID == nil ? 1 : (selectedAccountID == item.accountID ? 1 : 0.4))
                        }
                    }
                    .chartAngleSelection(value: $rawSelectedAngle)
                    .chartBackground { chartProxy in
                        GeometryReader { geometry in
                            if let selectedID = selectedAccountID,
                               let account = accountData.first(where: { $0.accountID == selectedID }) {
                                
                                let innerWidth = geometry.size.width * 0.45
                                
                                VStack(spacing: 4) {
                                    Text(account.accountName)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                                .multilineTextAlignment(.center)
                                .frame(width: innerWidth)
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumScaleFactor(0.8)
                                .position(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )
                            }
                        }
                    }
                    .frame(height: 300)
                    .onChange(of: rawSelectedAngle, initial: false) { oldValue, newValue in
                        if let angle = newValue {
                            findAccountID(angle)
                        } else {
                            selectedAccountID = nil
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .cardBackground(cornerRadius: 12)
                .padding(.vertical)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Update Selected Account
    
    private func findAccountID(_ rangeValue: Double) {
        var initialValue: Double = 0.0
        let sortedData = accountData.sorted(by: { $0.amount > $1.amount })
        
        let convertedArray = sortedData.compactMap { item -> (UUID, Range<Double>) in
            let rangeEnd = initialValue + (item.amount as NSDecimalNumber).doubleValue
            let tuple = (item.accountID, initialValue..<rangeEnd)
            initialValue = rangeEnd
            return tuple
        }
        
        if let account = convertedArray.first(where: { $0.1.contains(rangeValue) }) {
            selectedAccountID = account.0
        } else {
            selectedAccountID = nil
        }
    }
    
    // MARK: - Data Processing
    
    private var accountData: [AccountData] {
        let expenses = transactionsController.filteredTransactions
            .filter { $0.type == .debit && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID) }
        
        guard !expenses.isEmpty else { return [] }
        
        let grouped = Dictionary(grouping: expenses) { $0.accountID }
        
        let totals = grouped.map { (accountID, transactions) -> (UUID, Decimal) in
            let total = transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
            return (accountID, total)
        }
        
        let grandTotal = totals.reduce(Decimal(0)) { $0 + $1.1 }
        
        let data = totals.compactMap { (accountID, amount) -> AccountData? in
            guard let account = accountsController.getAccount(id: accountID) else { return nil }
            
            let percentage = Double(truncating: NSDecimalNumber(decimal: (amount / grandTotal) * 100))
            
            // Couleur stable basée sur l'ID du compte
            let colorIndex = abs(accountID.hashValue) % colorPalette.count
            let color = colorPalette[colorIndex]
            
            return AccountData(
                accountID: accountID,
                accountName: account.name,
                amount: amount,
                color: color,
                percentage: percentage
            )
        }
        
        return data.sorted { $0.amount > $1.amount }
    }
    
    private var totalExpenses: Decimal {
        accountData.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    private var averageExpense: Decimal {
        guard !accountData.isEmpty else { return 0 }
        return totalExpenses / Decimal(accountData.count)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucune dépense à afficher")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Créez des transactions sur vos comptes pour voir la répartition")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    func ChartPopOverView(_ amount: Decimal, _ accountName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top compte")
                .font(.title3)
                .foregroundStyle(.gray)
            
            VStack(alignment: .leading, spacing: 4) {
                Text((amount as NSNumber) as! Decimal.FormatStyle.Currency.FormatInput, format: .currency(code: "EUR"))
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(accountName)
                    .font(.title3)
                    .textScale(.secondary)
            }
        }
    }
}
