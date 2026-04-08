import SwiftUI
import Charts

struct PayeesChartView_old: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    
    struct PayeeData: Identifiable {
        let id = UUID()
        let payeeID: UUID
        let payeeName: String
        let totalAmount: Decimal
        let transactionCount: Int
        let averageAmount: Decimal
        let defaultCategory: Category?
    }
    
    @State private var selectedPayee: PayeeData?
    @State private var showExpenses = true
    @State private var showIncomes = false
    @State private var topCount: Int = 10
    
    let topOptions = [5, 10, 15, 20]
    
    var body: some View {
        VStack(spacing: 0) {
            if payeeData.isEmpty {
                emptyStateView
            } else {
                // Contrôles
                HStack(spacing: 20) {
                    // Type de transactions
                    HStack(spacing: 12) {
                        Text("Afficher:")
                            .font(.headline)
                        
                        Toggle("Dépenses", isOn: $showExpenses)
                            .toggleStyle(.checkbox)
                        
                        Toggle("Revenus", isOn: $showIncomes)
                            .toggleStyle(.checkbox)
                    }
                    
                    Spacer()
                    
                    // Nombre de bénéficiaires à afficher
                    HStack(spacing: 8) {
                        Text("Top")
                            .font(.headline)
                        
                        Picker("", selection: $topCount) {
                            ForEach(topOptions, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 70)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
                
                // Statistiques globales
                HStack(spacing: 40) {
                    StatisticCard(
                        title: "Total transactions",
                        value: Decimal(totalTransactionCount),
                        color: .blue,
                        isCurrency: false
                    )
                    
                    StatisticCard(
                        title: "Montant total",
                        value: totalAmount,
                        color: showExpenses && !showIncomes ? .red : (showIncomes && !showExpenses ? .green : .orange),
                        isCurrency: true
                    )
                    
                    StatisticCard(
                        title: "Montant moyen",
                        value: averageAmount,
                        color: .purple,
                        isCurrency: true
                    )
                }
                .padding()
                .frame(height: 120)
                
                Divider()
                
                HStack(spacing: 20) {
                    // Graphique en barres horizontales
                    VStack(spacing: 12) {
                        Text("Top \(topCount) bénéficiaires")
                            .font(.headline)
                        
                        Chart(displayedPayeeData) { item in
                            BarMark(
                                x: .value("Montant", NSDecimalNumber(decimal: item.totalAmount).doubleValue),
                                y: .value("Bénéficiaire", item.payeeName)
                            )
                            .foregroundStyle(getColorForPayee(item))
                            .cornerRadius(6)
                            .annotation(position: .overlay, alignment: .trailing) {
                                
                                Text("\(item.totalAmount)€")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                
                            }
                            .opacity(selectedPayee == nil ? 1.0 : (selectedPayee?.id == item.id ? 1.0 : 0.5))
                        }
                        .chartXAxis {
                            AxisMarks(position: .bottom) { value in
                                AxisValueLabel {
                                    if let doubleValue = value.as(Double.self) {
                                        Text(Decimal(doubleValue), format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                                            .font(.caption)
                                    }
                                }
                                AxisGridLine()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: max(400, Double(displayedPayeeData.count) * 35))
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Détails
                    ScrollView {
                        VStack(spacing: 8) {
                            Text("Détail par bénéficiaire")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 8)
                            
                            ForEach(displayedPayeeData) { item in
                                PayeeDetailRow(
                                    data: item,
                                    isSelected: selectedPayee?.id == item.id,
                                    currency: booksController.currentBook?.currency ?? "EUR",
                                    color: getColorForPayee(item)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedPayee?.id == item.id {
                                            selectedPayee = nil
                                        } else {
                                            selectedPayee = item
                                        }
                                    }
                                }
                                .onHover { isHovered in
                                    if isHovered {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedPayee = item
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(width: 400)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Data Processing
    
    private var payeeData: [PayeeData] {
        var transactions = transactionsController.filteredTransactions
            .filter { $0.payeeID != nil }
        
        // Filtrer par type
        if showExpenses && !showIncomes {
            transactions = transactions.filter { $0.type == .debit }
        } else if showIncomes && !showExpenses {
            transactions = transactions.filter { $0.type == .credit }
        } else if !showExpenses && !showIncomes {
            return []
        }
        
        guard !transactions.isEmpty else { return [] }
        
        // Grouper par bénéficiaire
        let grouped = Dictionary(grouping: transactions) { $0.payeeID! }
        
        // Créer les données
        let data = grouped.compactMap { (payeeID, txs) -> PayeeData? in
            guard let payee = payeesController.getPayee(id: payeeID) else { return nil }
            
            let total = txs.reduce(Decimal(0)) { $0 + abs($1.amount) }
            let average = total / Decimal(txs.count)
            let category = categoriesController.getCategory(id: payee.defaultCategoryID ?? UUID())
            
            return PayeeData(
                payeeID: payeeID,
                payeeName: payee.name,
                totalAmount: total,
                transactionCount: txs.count,
                averageAmount: average,
                defaultCategory: category
            )
        }
        
        // Trier par montant décroissant
        return data.sorted { $0.totalAmount > $1.totalAmount }
    }
    
    private var displayedPayeeData: [PayeeData] {
        Array(payeeData.prefix(topCount))
    }
    
    private var totalTransactionCount: Int {
        payeeData.reduce(0) { $0 + $1.transactionCount }
    }
    
    private var totalAmount: Decimal {
        payeeData.reduce(Decimal(0)) { $0 + $1.totalAmount }
    }
    
    private var averageAmount: Decimal {
        guard !payeeData.isEmpty else { return 0 }
        return totalAmount / Decimal(payeeData.count)
    }
    
    private func getColorForPayee(_ payee: PayeeData) -> Color {
        if showExpenses && !showIncomes {
            return .red
        } else if showIncomes && !showExpenses {
            return .green
        } else {
            // Utiliser la couleur de la catégorie par défaut si disponible
            if let category = payee.defaultCategory {
                return Color(hex: category.displayColor)
            }
            return .blue
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucune transaction avec bénéficiaire")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Créez des transactions avec des bénéficiaires pour voir les statistiques")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Payee Detail Row
struct PayeeDetailRow: View {
    let data: PayeesChartView_old.PayeeData
    let isSelected: Bool
    let currency: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icône
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundColor(color)
                
                // Informations
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.payeeName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let category = data.defaultCategory {
                        HStack(spacing: 4) {
                            Image(systemName: category.displayIcon)
                                .font(.caption2)
                            Text(category.name)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Montants
                VStack(alignment: .trailing, spacing: 4) {
                    Text(data.totalAmount, format: .currency(code: currency))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(data.transactionCount) transaction\(data.transactionCount > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            
            // Montant moyen
            if isSelected {
                Divider()
                    .padding(.horizontal, 12)
                
                HStack {
                    Text("Montant moyen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(data.averageAmount, format: .currency(code: currency))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? color.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? color : Color.clear, lineWidth: 2)
        )
    }
}
