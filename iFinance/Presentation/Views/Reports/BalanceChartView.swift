import SwiftUI
import Charts

struct BalanceChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var appSettings: AppSettings
    
    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Decimal
    }
    
    @State private var selectedPoint: DataPoint?
    @State private var hoverLocation: CGPoint = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            if dataPoints.isEmpty {
                emptyStateView
            } else {
                // Statistiques
                HStack(spacing: 40) {
                    StatisticCard(
                        title: "Solde actuel",
                        value: currentBalance,
                        color: currentBalance >= 0 ? .green : .red
                    )
                    
                    StatisticCard(
                        title: "Solde initial",
                        value: initialBalance,
                        color: .blue
                    )
                    
                    StatisticCard(
                        title: "Variation",
                        value: variation,
                        color: variation >= 0 ? .green : .red
                    )
                }
                .padding(.vertical)
                
                Divider()
                
                // Graphique
                VStack(alignment: .leading) {
                    Text("Balance")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .padding(12)
                    
                    Chart {
                        ForEach(dataPoints) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Solde", NSDecimalNumber(decimal: point.balance).doubleValue)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)
                            
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Solde", NSDecimalNumber(decimal: point.balance).doubleValue)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Solde", NSDecimalNumber(decimal: point.balance).doubleValue)
                            )
                            .symbolSize(30)
                            .foregroundStyle(.blue)
                        }
                        
                        // Point sélectionné
                        if let selectedPoint {
                            PointMark(
                                x: .value("Date", selectedPoint.date),
                                y: .value("Solde", NSDecimalNumber(decimal: selectedPoint.balance).doubleValue)
                            )
                            .symbolSize(80)
                            .foregroundStyle(.red)
                            
                            RuleMark(x: .value("Date", selectedPoint.date))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                .foregroundStyle(.gray.opacity(0.5))
                        }
                    }
                    /*.background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )*/
                    .chartLegend(position: .bottomLeading)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if !hovering { selectedPoint = nil }
                                }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        hoverLocation = location
                                        if let date: Date = proxy.value(atX: location.x) {
                                            selectedPoint = nearestPoint(to: date)
                                        }
                                    case .ended:
                                        selectedPoint = nil
                                    }
                                }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let selectedPoint {
                            GeometryReader { geo in
                                let tooltipSize = CGSize(width: 160, height: 60)
                                let x = min(max(hoverLocation.x + 12, 0), geo.size.width - tooltipSize.width)
                                let y = min(max(hoverLocation.y - tooltipSize.height - 12, 0), geo.size.height - tooltipSize.height)
                                let tooltipPosition = CGPoint(x: x + tooltipSize.width/2, y: y + tooltipSize.height/2)
                                
                                tooltipView(for: selectedPoint)
                                    .frame(width: tooltipSize.width, height: tooltipSize.height)
                                    .position(tooltipPosition)
                            }
                        }
                    }
                    .frame(height: 300)
                    .padding(24)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
                .padding(.vertical)
                
            }
        }
    }
    
    private var dataPoints: [DataPoint] {
        // Déterminer le compte à utiliser
        let accountsToUse: [Account]
        if let accountID = transactionsController.filters.accountID {
            guard let account = accountsController.getAccount(id: accountID) else { return [] }
            accountsToUse = [account]
        } else {
            accountsToUse = accountsController.activeAccounts.filter { $0.countsInCashFlow }
        }

        let includedAccountIDs = Set(accountsToUse.map { $0.id })
        
        guard !accountsToUse.isEmpty else { return [] }
        
        // Déterminer la période
        let calendar = Calendar.current
        let (startDate, endDate): (Date, Date)
        
        if let dates = transactionsController.filters.dateRange.dates() {
            (startDate, endDate) = dates
        } else {
            // Par défaut : 30 derniers jours
            endDate = Date()
            startDate = calendar.date(byAdding: .day, value: -30, to: endDate)!
        }
        
        // Filtrer les transactions (uniquement les comptes inclus)
        let relevantTransactions = transactionsController.filteredTransactions
            .filter { $0.date >= startDate && $0.date < endDate && includedAccountIDs.contains($0.accountID) }
            .sorted { $0.date < $1.date }
        
        guard !relevantTransactions.isEmpty else { return [] }
        
        // Calculer les points pour chaque jour
        var points: [DataPoint] = []
        var currentDate = startDate
        
        // Solde initial au début de la période
        var balance: Decimal = 0
        for account in accountsToUse {
            // Solde initial du compte
            balance += account.initialBalance
            
            // Ajouter les transactions avant la période
            let previousTransactions = transactionsController.allTransactions
                .filter { $0.accountID == account.id && $0.date < startDate && $0.status != .skipped }
            
            for tx in previousTransactions {
                balance += tx.signedAmount
            }
        }
        
        // Générer un point par jour
        while currentDate <= endDate {
            // Transactions du jour
            let dayTransactions = relevantTransactions.filter { tx in
                calendar.isDate(tx.date, inSameDayAs: currentDate)
            }
            
            for tx in dayTransactions {
                balance += tx.signedAmount
            }
            
            points.append(DataPoint(date: currentDate, balance: balance))
            
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDay
        }
        
        return points
    }
    
    private var initialBalance: Decimal {
        guard let first = dataPoints.first else { return 0 }
        return first.balance
    }
    
    private var currentBalance: Decimal {
        guard let last = dataPoints.last else { return 0 }
        return last.balance
    }
    
    private var variation: Decimal {
        return currentBalance - initialBalance
    }
    
    private func nearestPoint(to date: Date) -> DataPoint? {
        dataPoints.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
    
    @ViewBuilder
    private func tooltipView(for point: DataPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.date, format: .dateTime.day().month().year())
                .font(.caption)
                .foregroundColor(.secondary)
            Text(point.balance, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                .font(.headline)
                .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(radius: 4)
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucune donnée à afficher")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Créez des transactions pour voir l'évolution du solde")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @EnvironmentObject var booksController: BooksController
}
