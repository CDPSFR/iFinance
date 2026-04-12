import SwiftUI
import Charts

struct PayeesChartView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var appSettings: AppSettings
    
    struct PayeeData: Identifiable {
        let id = UUID()
        let payeeID: UUID
        let payeeName: String
        let amount: Decimal
        let color: Color
        let percentage: Double
    }
    
    @State private var selectedPayeeID: UUID?
    @State private var rawSelectedAngle: Double?
    
    // Palette de couleurs pour les bénéficiaires
    private let colorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .red, .yellow, .cyan, .mint, .indigo,
        .teal, .brown
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if payeeData.isEmpty {
                emptyStateView
            } else {
                // Statistiques globales
                HStack(spacing: 40) {
                    StatisticCardView(
                        title: "Total dépenses",
                        value: totalExpenses,
                        color: .red,
                        isCurrency: true
                    )
                    
                    StatisticCardView(
                        title: "Nombre de bénéficiaires",
                        value: Decimal(payeeData.count),
                        color: .blue,
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
                
                Divider()
                
                if let highestPayee = payeeData.max(by: { $1.amount > $0.amount }) {
                    ChartPopOverView(highestPayee.amount, highestPayee.payeeName)
                        .padding(.vertical)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                
                // Graphique centré
                let hideAmounts = appSettings.hideAmounts
                VStack(spacing: 12) {
                    Chart {
                        ForEach(payeeData.sorted { $0.amount > $1.amount }) { item in
                            SectorMark(
                                angle: .value("Montant",
                                              NSDecimalNumber(decimal: item.amount).doubleValue),
                                innerRadius: .ratio(0.618),
                                outerRadius: selectedPayeeID == nil ? 130 : (selectedPayeeID == item.payeeID ? 130 : 120),
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
                            .opacity(selectedPayeeID == nil ? 1 : (selectedPayeeID == item.payeeID ? 1 : 0.4))
                        }
                    }
                    .chartAngleSelection(value: $rawSelectedAngle)
                    .chartBackground { chartProxy in
                        GeometryReader { geometry in
                            if let selectedID = selectedPayeeID,
                               let payee = payeeData.first(where: { $0.payeeID == selectedID }) {
                                
                                let innerWidth = geometry.size.width * 0.45
                                
                                VStack(spacing: 4) {
                                    Text(payee.payeeName)
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
                            findPayeeID(angle)
                        } else {
                            selectedPayeeID = nil
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Update Selected Payee
    
    private func findPayeeID(_ rangeValue: Double) {
        var initialValue: Double = 0.0
        let sortedData = payeeData.sorted(by: { $0.amount > $1.amount })
        
        let convertedArray = sortedData.compactMap { item -> (UUID, Range<Double>) in
            let rangeEnd = initialValue + (item.amount as NSDecimalNumber).doubleValue
            let tuple = (item.payeeID, initialValue..<rangeEnd)
            initialValue = rangeEnd
            return tuple
        }
        
        if let payee = convertedArray.first(where: { $0.1.contains(rangeValue) }) {
            selectedPayeeID = payee.0
        } else {
            selectedPayeeID = nil
        }
    }
    
    // MARK: - Data Processing
    
    private var payeeData: [PayeeData] {
        let expenses = transactionsController.filteredTransactions
            .filter { $0.type == .debit && $0.payeeID != nil }
        
        guard !expenses.isEmpty else { return [] }
        
        let grouped = Dictionary(grouping: expenses) { $0.payeeID! }
        
        let totals = grouped.map { (payeeID, transactions) -> (UUID, Decimal) in
            let total = transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
            return (payeeID, total)
        }
        
        let grandTotal = totals.reduce(Decimal(0)) { $0 + $1.1 }
        
        let data = totals.compactMap { (payeeID, amount) -> PayeeData? in
            guard let payee = payeesController.getPayee(id: payeeID) else { return nil }
            
            let percentage = Double(truncating: NSDecimalNumber(decimal: (amount / grandTotal) * 100))
            
            // ✅ CORRECTION : Couleur stable basée sur le hash de l'UUID
            let colorIndex = abs(payeeID.hashValue) % colorPalette.count
            let color = colorPalette[colorIndex]
            
            return PayeeData(
                payeeID: payeeID,
                payeeName: payee.name,
                amount: amount,
                color: color,
                percentage: percentage
            )
        }
        
        return data.sorted { $0.amount > $1.amount }
    }
    
    private var totalExpenses: Decimal {
        payeeData.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    private var averageExpense: Decimal {
        guard !payeeData.isEmpty else { return 0 }
        return totalExpenses / Decimal(payeeData.count)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucune dépense à afficher")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Créez des transactions avec des bénéficiaires pour voir la répartition")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    func ChartPopOverView(_ amount: Decimal, _ payeeName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top bénéficiaire")
                .font(.title3)
                .foregroundStyle(.gray)
            
            VStack(alignment: .leading, spacing: 4) {
                Text((amount as NSNumber) as! Decimal.FormatStyle.Currency.FormatInput, format: .currency(code: "EUR"))
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(payeeName)
                    .font(.title3)
                    .textScale(.secondary)
            }
        }
    }
}
