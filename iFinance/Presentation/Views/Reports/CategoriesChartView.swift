import SwiftUI
import Charts

struct CategoriesChartView: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var appSettings: AppSettings
    
    // https://www.youtube.com/watch?v=nu74-aRobSs
    
    struct CategoryData: Identifiable {
        let id = UUID()
        let categoryID: UUID
        let categoryName: String
        let amount: Decimal
        let color: Color
        let percentage: Double
    }
    
    @State private var selectedCategoryID: UUID?
    @State private var rawSelectedAngle: Double?
    
    var body: some View {
        VStack(spacing: 0) {
            if categoryData.isEmpty {
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
                        title: "Nombre de catégories",
                        value: Decimal(categoryData.count),
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
                
                if let highestCategory = categoryData.max(by: { $1.amount > $0.amount }) {
                    ChartPopOverView(highestCategory.amount, highestCategory.categoryName)
                        .padding(.vertical)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                        //.opacity(selectedCategoryID == nil ? 1 : 0)
                    
                }
                
                // Graphique centré
                VStack(spacing: 12) {
                    
                    let hideAmounts = appSettings.hideAmounts
                    Chart {
                        ForEach(categoryData.sorted { $0.amount > $1.amount }) { item in
                            SectorMark(
                                angle: .value("Montant",
                                              NSDecimalNumber(decimal: item.amount).doubleValue),
                                innerRadius: .ratio(0.618),
                                outerRadius: selectedCategoryID == nil ? 130 : (selectedCategoryID == item.categoryID ? 130 : 120),
                                angularInset: 1.5
                            )
                            .cornerRadius(6)
                            // .foregroundStyle(by: .value("Category", item.categoryName))
                            .foregroundStyle(item.color)
                            .annotation(position: .overlay, alignment: .center) {
                                Text("\(NSDecimalNumber(decimal: item.amount).doubleValue, specifier: "%.0f")€")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .privacyBlur(hidden: hideAmounts)
                            }
                            .opacity(selectedCategoryID == nil ? 1 : (selectedCategoryID == item.categoryID ? 1 : 0.4))
                        }
                    }
                    // .chartLegend(.hidden)
                    .chartAngleSelection(value: $rawSelectedAngle)
                    .chartBackground { chartProxy in
                        GeometryReader { geometry in
                            if let selectedID = selectedCategoryID,
                               let category = categoryData.first(where: { $0.categoryID == selectedID }) {

                                let innerWidth = geometry.size.width * 0.45

                                VStack(spacing: 4) {

                                    Text(category.categoryName)
                                        .font(.title3)
                                        .fontWeight(.semibold)

                                    /*Text(category.amount as NSNumber,
                                         format: .currency(code: "EUR"))
                                        .font(.headline)
                                        .foregroundStyle(.secondary)*/
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
                            findCategoryID(angle)
                        } else {
                            selectedCategoryID = nil
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Update Selected Category
    
    private func findCategoryID(_ rangeValue: Double) {
        var initialValue: Double = 0.0
        let sortedData = categoryData.sorted(by: { $0.amount > $1.amount })
        
        let convertedArray = sortedData.compactMap { item -> (UUID, Range<Double>) in
            let rangeEnd = initialValue + (item.amount as NSDecimalNumber).doubleValue
            let tuple = (item.categoryID, initialValue..<rangeEnd)
            initialValue = rangeEnd
            return tuple
        }
        
        if let category = convertedArray.first(where: { $0.1.contains(rangeValue) }) {
            selectedCategoryID = category.0
        } else {
            selectedCategoryID = nil
        }
    }
    
    // MARK: - Data Processing
    
    private var categoryData: [CategoryData] {
        let expenses = transactionsController.filteredTransactions
            .filter { $0.type == .debit && $0.categoryID != nil }
        
        guard !expenses.isEmpty else { return [] }
        
        let grouped = Dictionary(grouping: expenses) { $0.categoryID! }
        
        let totals = grouped.map { (categoryID, transactions) -> (UUID, Decimal) in
            let total = transactions.reduce(Decimal(0)) { $0 + abs($1.amount) }
            return (categoryID, total)
        }
        
        let grandTotal = totals.reduce(Decimal(0)) { $0 + $1.1 }
        
        let data = totals.compactMap { (categoryID, amount) -> CategoryData? in
            guard let category = categoriesController.getCategory(id: categoryID) else { return nil }
            
            let percentage = Double(truncating: NSDecimalNumber(decimal: (amount / grandTotal) * 100))
            
            return CategoryData(
                categoryID: categoryID,
                categoryName: categoriesController.getCategoryPath(for: categoryID),
                amount: amount,
                color: Color(hex: category.displayColor),
                percentage: percentage
            )
        }
        
        return data.sorted { $0.amount > $1.amount }
    }
    
    private var totalExpenses: Decimal {
        categoryData.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    private var averageExpense: Decimal {
        guard !categoryData.isEmpty else { return 0 }
        return totalExpenses / Decimal(categoryData.count)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucune dépense à afficher")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Créez des transactions avec des catégories pour voir la répartition")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    func ChartPopOverView(_ amount: Decimal, _ categoryName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top categories")
                .font(.title3)
                .foregroundStyle(.gray)
            
            VStack(alignment: .leading, spacing: 4){
                Text((amount as NSNumber) as! Decimal.FormatStyle.Currency.FormatInput, format: .currency(code: "EUR"))
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(categoryName)
                    .font(.title3)
                    .textScale(.secondary)
            }
        }
    }
}

// MARK: - Statistic Card
struct StatisticCardView: View {
    let title: String
    let value: Decimal
    let color: Color
    var isCurrency: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if isCurrency {
                Text(value, format: .currency(code: "EUR"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            } else {
                Text("\(NSDecimalNumber(decimal: value).intValue)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}
