//
//  MonthlyBalanceChartView.swift
//  iFinance
//
//  Created by charles.du.portal on 08/01/2026.
//


import SwiftUI
import Charts

struct MonthlyBalanceChartView: View {

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var appSettings: AppSettings

    // MARK: - Data Models

    struct MonthlyBalance: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Decimal
        let income: Decimal
        let expense: Decimal
    }

    // MARK: - State

    @State private var selectedBalance: MonthlyBalance?
    @State private var hoverLocation: CGPoint = .zero

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if balanceData.isEmpty {
                emptyStateView
            } else {
                // Statistiques
                HStack(spacing: 40) {
                    StatisticCard(
                        title: "Solde moyen",
                        value: averageBalance,
                        color: averageBalance >= 0 ? .green : .red
                    )
                    
                    StatisticCard(
                        title: "Meilleur mois",
                        value: bestMonth?.balance ?? 0,
                        color: .green
                    )
                    
                    StatisticCard(
                        title: "Pire mois",
                        value: worstMonth?.balance ?? 0,
                        color: .red
                    )
                }
                .padding()

                Divider()

                // Graphique
                let hideAmounts = appSettings.hideAmounts
                Chart {
                    ForEach(balanceData) { item in
                        BarMark(
                            x: .value("Mois", item.date, unit: .month),
                            y: .value("Solde", NSDecimalNumber(decimal: item.balance).doubleValue)
                        )
                        .foregroundStyle(item.balance >= 0 ? Color.green : Color.red)
                        .cornerRadius(4)
                        .annotation(position: item.balance >= 0 ? .top : .bottom, alignment: .center) {
                            Text("\(NSDecimalNumber(decimal: item.balance).doubleValue, specifier: "%.0f")€")
                                .font(.caption)
                                .foregroundColor(item.balance >= 0 ? .green : .red)
                                .privacyBlur(hidden: hideAmounts)
                        }
                    }

                    // Ligne zéro
                    RuleMark(y: .value("Zéro", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.gray.opacity(0.5))

                    if let selectedBalance {
                        RuleMark(x: .value("Mois", selectedBalance.date))
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if !hovering { selectedBalance = nil }
                            }
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoverLocation = location
                                    selectedBalance = findBalanceAtShiftedLocation(location.x, in: proxy, geometry: geo)
                                case .ended:
                                    selectedBalance = nil
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let selectedBalance {
                        GeometryReader { geo in
                            let tooltipSize = CGSize(width: 200, height: 100)
                            let x = min(max(hoverLocation.x + 12, 0), geo.size.width - tooltipSize.width)
                            let y = min(max(hoverLocation.y - tooltipSize.height - 12, 0), geo.size.height - tooltipSize.height)
                            let position = CGPoint(x: x + tooltipSize.width / 2, y: y + tooltipSize.height / 2)

                            tooltipView(for: selectedBalance)
                                .frame(width: tooltipSize.width, height: tooltipSize.height)
                                .position(position)
                        }
                    }
                }
                .padding()
                .frame(height: 300)
                .cardBackground(cornerRadius: 12)
                .padding(.vertical)
            }
        }
    }

    // MARK: - Helpers

    private var balanceData: [MonthlyBalance] {
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
            let balance = income - expense
            
            return MonthlyBalance(
                date: date,
                balance: balance,
                income: income,
                expense: expense
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var averageBalance: Decimal {
        guard !balanceData.isEmpty else { return 0 }
        let total = balanceData.reduce(Decimal(0)) { $0 + $1.balance }
        return total / Decimal(balanceData.count)
    }

    private var bestMonth: MonthlyBalance? {
        balanceData.max { $0.balance < $1.balance }
    }

    private var worstMonth: MonthlyBalance? {
        balanceData.min { $0.balance < $1.balance }
    }

    private func nearestBalance(to date: Date) -> MonthlyBalance? {
        balanceData.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
    
    /// Trouve le solde en décalant la zone de détection de 50% vers la droite
    private func findBalanceAtShiftedLocation(_ xPosition: CGFloat, in proxy: ChartProxy, geometry: GeometryProxy) -> MonthlyBalance? {
        guard balanceData.count >= 2 else {
            if let date: Date = proxy.value(atX: xPosition) {
                return nearestBalance(to: date)
            }
            return nil
        }
        
        let firstX = proxy.position(forX: balanceData[0].date) ?? 0
        let secondX = proxy.position(forX: balanceData[1].date) ?? 0
        let intervalWidth = abs(secondX - firstX)
        
        let shiftedX = xPosition - (intervalWidth * 0.5)
        
        guard let date: Date = proxy.value(atX: shiftedX) else {
            return nil
        }
        
        return nearestBalance(to: date)
    }

    @ViewBuilder
    private func tooltipView(for balance: MonthlyBalance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(balance.date, format: .dateTime.month().year())
                .font(.headline)
                .foregroundColor(.primary)

            Divider()

            HStack {
                Text("Revenus :")
                    .foregroundColor(.secondary)
                Spacer()
                Text(balance.income, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                    .foregroundColor(.green)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .font(.caption)

            HStack {
                Text("Dépenses :")
                    .foregroundColor(.secondary)
                Spacer()
                Text(balance.expense, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                    .foregroundColor(.red)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .font(.caption)

            Divider()

            HStack {
                Text("Solde :")
                    .fontWeight(.semibold)
                Spacer()
                Text(balance.balance, format: .currency(code: booksController.currentBook?.currency ?? "EUR"))
                    .fontWeight(.bold)
                    .foregroundColor(balance.balance >= 0 ? .green : .red)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .font(.callout)
        }
        .padding(12)
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

            Text("Ajoutez des transactions pour visualiser votre solde mensuel")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
