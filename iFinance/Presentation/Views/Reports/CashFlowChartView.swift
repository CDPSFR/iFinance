import SwiftUI
import Charts

struct CashFlowChartView: View {

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    // MARK: - Data Models

    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let income: Decimal
        let expense: Decimal
    }

    struct CategorizedDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let type: String // "Revenus" ou "Dépenses"
        let amount: Decimal
    }

    // MARK: - State

    @State private var selectedPoint: DataPoint?
    @State private var hoverLocation: CGPoint = .zero

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if dataPoints.isEmpty {
                emptyStateView
            } else {
                // Statistiques
                HStack(spacing: 40) {
                    StatisticCard(title: "Revenus", value: totalIncome, color: .green)
                    StatisticCard(title: "Dépenses", value: totalExpense, color: .red)
                    StatisticCard(title: "Résultat", value: netResult, color: netResult >= 0 ? .green : .red)
                }
                .padding()

                Divider()

                // Graphique
                let hideAmounts = appSettings.hideAmounts
                Chart {
                    ForEach(categorizedDataPoints) { point in
                        BarMark(
                            x: .value("Mois", point.date, unit: .month),
                            y: .value("Montant", NSDecimalNumber(decimal: point.amount).doubleValue)
                        )
                        .foregroundStyle(point.type == "Revenus" ? Color.green : Color.red)
                        .position(by: .value("Type", point.type))
                        .cornerRadius(4)
                        .annotation(position: .top, alignment: .center) {
                            Text("\(NSDecimalNumber(decimal: point.amount).doubleValue, specifier: "%.0f")€")
                                .font(.caption)
                                .foregroundColor(point.type == "Revenus" ? .green : .red)
                                .privacyBlur(hidden: hideAmounts)
                        }
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Mois", selectedPoint.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().year())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .top)
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
                                    selectedPoint = findPointAtShiftedLocation(location.x, in: proxy, geometry: geo)
                                case .ended:
                                    selectedPoint = nil
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let selectedPoint {
                        GeometryReader { geo in
                            let tooltipSize = CGSize(width: 180, height: 80)
                            let x = min(max(hoverLocation.x + 12, 0), geo.size.width - tooltipSize.width)
                            let y = min(max(hoverLocation.y - tooltipSize.height - 12, 0), geo.size.height - tooltipSize.height)
                            let position = CGPoint(x: x + tooltipSize.width / 2, y: y + tooltipSize.height / 2)

                            tooltipView(for: selectedPoint)
                                .frame(width: tooltipSize.width, height: tooltipSize.height)
                                .position(position)
                        }
                    }
                }
                .padding()
                .frame(height: 300)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Helpers

    private var categorizedDataPoints: [CategorizedDataPoint] {
        dataPoints.flatMap { point in
            [
                CategorizedDataPoint(date: point.date, type: "Revenus", amount: point.income),
                CategorizedDataPoint(date: point.date, type: "Dépenses", amount: point.expense)
            ]
        }
    }

    private var dataPoints: [DataPoint] {
        let calendar = Calendar.current
        let filtered = transactionsController.filteredTransactions
            .filter { $0.status != .skipped && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID) }

        let grouped = Dictionary(grouping: filtered) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date))!
        }

        return grouped.map { date, transactions in
            let income = transactions
                .filter { $0.signedAmount > 0 }
                .reduce(Decimal(0)) { $0 + $1.signedAmount }
            let expense = transactions
                .filter { $0.signedAmount < 0 }
                .reduce(Decimal(0)) { $0 + abs($1.signedAmount) }
            return DataPoint(date: date, income: income, expense: expense)
        }
        .sorted { $0.date < $1.date }
    }

    private var totalIncome: Decimal {
        dataPoints.reduce(0) { $0 + $1.income }
    }

    private var totalExpense: Decimal {
        dataPoints.reduce(0) { $0 + $1.expense }
    }

    private var netResult: Decimal {
        totalIncome - totalExpense
    }

    private func nearestPoint(to date: Date) -> DataPoint? {
        dataPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
    
    /// Trouve le point en décalant la zone de détection de 50% vers la droite
    private func findPointAtShiftedLocation(_ xPosition: CGFloat, in proxy: ChartProxy, geometry: GeometryProxy) -> DataPoint? {
        guard dataPoints.count >= 2 else {
            // S'il n'y a qu'un seul point, pas de décalage nécessaire
            if let date: Date = proxy.value(atX: xPosition) {
                return nearestPoint(to: date)
            }
            return nil
        }
        
        // Calcule la largeur moyenne entre deux points
        let firstX = proxy.position(forX: dataPoints[0].date) ?? 0
        let secondX = proxy.position(forX: dataPoints[1].date) ?? 0
        let intervalWidth = abs(secondX - firstX)
        
        // Décale la position de 50% d'un intervalle vers la gauche
        let shiftedX = xPosition - (intervalWidth * 0.5)
        
        // Récupère la date au point décalé
        guard let date: Date = proxy.value(atX: shiftedX) else {
            return nil
        }
        
        return nearestPoint(to: date)
    }

    @ViewBuilder
    private func tooltipView(for point: DataPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.date, format: .dateTime.month().year())
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Revenus : \(point.income, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))")
                .foregroundColor(.green)
                .privacyBlur(hidden: appSettings.hideAmounts)

            Text("Dépenses : \(point.expense, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))")
                .foregroundColor(.red)
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
            Image(systemName: "chart.bar")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text("Aucune donnée à afficher")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Ajoutez des transactions pour visualiser vos revenus et dépenses")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
