import SwiftUI
import Charts

/// Rapport « Patrimoine net » : actifs, dettes et patrimoine net en fin de mois sur 12 mois,
/// puis détail par compte. Indépendant de la période et du compte choisis dans la barre d'outils.
struct NetWorthChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var investmentsController: InvestmentsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    /// Recul de la comparaison, en mois : on affiche les fins de mois de M-12 au mois en cours
    private static let monthCount = 12

    private enum Series: String, CaseIterable {
        case liquid = "Liquidités et épargne"
        case invested = "Placements"
        case debt = "Dettes"

        var color: Color {
            switch self {
            case .liquid: return .accentColor
            case .invested: return .teal
            case .debt: return .red
            }
        }
    }

    struct MonthPoint: Identifiable {
        let date: Date          // premier jour du mois
        let liquid: Decimal     // ≥ 0
        let invested: Decimal   // ≥ 0
        let debt: Decimal       // ≤ 0

        var id: Date { date }
        var net: Decimal { liquid + invested + debt }
    }

    struct AccountLine: Identifiable {
        let account: Account
        let before: Decimal
        let now: Decimal

        var id: UUID { account.id }
        var variation: Decimal { now - before }
    }

    @State private var selectedDate: Date?

    var body: some View {
        let accounts = self.accounts

        if accounts.isEmpty {
            ReportEmptyState(systemImage: "chart.bar.xaxis", message: "Aucun compte à prendre en compte dans le patrimoine.")
        } else {
            let points = monthPoints(accounts)
            let lines = accountLines(accounts)

            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(points)
                    chartBlock(points)
                    tableBlock(lines)
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ points: [MonthPoint]) -> some View {
        let last = points.last
        let first = points.first
        let net = last?.net ?? 0
        let variation = net - (first?.net ?? 0)
        let assets = (last?.liquid ?? 0) + (last?.invested ?? 0)
        let debt = -(last?.debt ?? 0)
        let debtVariation = debt + (first?.debt ?? 0)

        return ReportTiles {
            StatTile(title: "Patrimoine net", value: money(net), valueColor: net < 0 ? .red : .primary, detail: "aujourd'hui")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Variation sur \(Self.monthCount) mois",
                value: signed(variation),
                valueColor: variation >= 0 ? .green : .red,
                detail: percentChange(from: first?.net ?? 0, to: net)
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "Actifs", value: money(assets), detail: "liquidités, épargne et placements")
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Dettes",
                value: money(debt),
                valueColor: debt > 0 ? .red : .primary,
                detail: debt == 0 && debtVariation == 0 ? "aucune dette" : "\(signed(debtVariation)) en \(Self.monthCount) mois"
            )
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
    }

    // MARK: - Graphique

    private func chartBlock(_ points: [MonthPoint]) -> some View {
        let selected = selectedPoint(in: points)

        return VStack(alignment: .leading, spacing: 12) {
            GroupTitle("Actifs, dettes et patrimoine net en fin de mois")

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Mois", point.date, unit: .month),
                        y: .value("Montant", double(point.liquid))
                    )
                    .foregroundStyle(by: .value("Nature", Series.liquid.rawValue))

                    BarMark(
                        x: .value("Mois", point.date, unit: .month),
                        y: .value("Montant", double(point.invested))
                    )
                    .foregroundStyle(by: .value("Nature", Series.invested.rawValue))

                    BarMark(
                        x: .value("Mois", point.date, unit: .month),
                        y: .value("Montant", double(point.debt))
                    )
                    .foregroundStyle(by: .value("Nature", Series.debt.rawValue))
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Mois", point.date, unit: .month),
                        y: .value("Patrimoine net", double(point.net)),
                        series: .value("Série", "Patrimoine net")
                    )
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                    .symbolSize(24)
                }

                if let selected {
                    RuleMark(x: .value("Mois", selected.date, unit: .month))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ReportTooltip {
                                Text(monthName(selected.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Net \(money(selected.net))")
                                    .fontWeight(.semibold)
                                Text("Actifs \(money(selected.liquid + selected.invested))")
                                    .font(.caption)
                                if selected.debt != 0 {
                                    Text("Dettes \(money(-selected.debt))")
                                        .font(.caption)
                                }
                            }
                        }
                }
            }
            .chartForegroundStyleScale([
                Series.liquid.rawValue: Series.liquid.color,
                Series.invested.rawValue: Series.invested.color,
                Series.debt.rawValue: Series.debt.color
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 280)
            .privacyBlur(hidden: appSettings.hideAmounts)

            Text("La ligne suit le patrimoine net (actifs moins dettes).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    private func selectedPoint(in points: [MonthPoint]) -> MonthPoint? {
        guard let selectedDate else { return nil }
        let calendar = Calendar.current
        return points.first { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }

    // MARK: - Tableau par compte

    private func tableBlock(_ lines: [AccountLine]) -> some View {
        let totalBefore = lines.reduce(Decimal(0)) { $0 + $1.before }
        let totalNow = lines.reduce(Decimal(0)) { $0 + $1.now }

        var rows = lines.map { line in
            ReportRow(id: line.id.uuidString, cells: [
                ReportCell(text: line.account.name),
                ReportCell(text: line.now < 0 ? "Dette" : line.account.type.group.displayName, color: .secondary, isAmount: false),
                ReportCell(text: money(line.before), color: line.before < 0 ? .red : .primary),
                ReportCell(text: money(line.now), color: line.now < 0 ? .red : .primary),
                ReportCell(text: signed(line.variation), color: line.variation >= 0 ? .green : .red)
            ])
        }
        rows.append(ReportRow(id: "total", cells: [
            ReportCell(text: "Patrimoine net"),
            ReportCell(text: "", color: .secondary, isAmount: false),
            ReportCell(text: money(totalBefore)),
            ReportCell(text: money(totalNow)),
            ReportCell(text: signed(totalNow - totalBefore), color: totalNow - totalBefore >= 0 ? .green : .red)
        ]))

        return ReportTable(
            columns: ["Compte", "Nature", "Il y a \(Self.monthCount) mois", "Aujourd'hui", "Variation"],
            rows: rows,
            footnote: "Les valeurs passées sont reconstituées à partir de la valeur actuelle et des transactions. Pour les comptes de placement, les variations de cours ne sont pas historisées : seule la valeur d'aujourd'hui tient compte des cours."
        )
    }

    // MARK: - Données

    /// Comptes ouverts inclus dans les rapports, toutes natures confondues
    private var accounts: [Account] {
        accountsController.activeAccounts.filter { !$0.isExcludedFromReports }
    }

    private var valuation: AccountValuation {
        AccountValuation(
            transactionsController: transactionsController,
            investmentsController: investmentsController,
            savingsPlansController: savingsPlansController
        )
    }

    /// Premier jour de chacun des derniers mois, de M-12 au mois en cours (13 points : 12 mois d'écart)
    private var monthStarts: [Date] {
        let calendar = Calendar.current
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return (0...Self.monthCount).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }

    /// Valeur de chaque compte à la fin de chaque mois : valeur actuelle moins les mouvements postérieurs.
    /// Le dernier point est la valeur actuelle, comme sur la page Patrimoine (transactions futures comprises).
    private func values(_ accounts: [Account], months: [Date]) -> [UUID: [Decimal]] {
        let calendar = Calendar.current
        let ends = months.map { calendar.date(byAdding: .month, value: 1, to: $0) ?? $0 }
        let valuation = self.valuation

        var byAccount: [UUID: [Transaction]] = [:]
        for transaction in transactionsController.allTransactions where transaction.status != .skipped {
            byAccount[transaction.accountID, default: []].append(transaction)
        }

        var result: [UUID: [Decimal]] = [:]
        for account in accounts {
            let current = valuation.value(of: account)
            let transactions = byAccount[account.id] ?? []
            result[account.id] = ends.enumerated().map { index, end in
                if index == ends.count - 1 { return current }
                let later = transactions
                    .filter { $0.date >= end }
                    .reduce(Decimal(0)) { $0 + $1.signedAmount }
                return current - later
            }
        }
        return result
    }

    private func monthPoints(_ accounts: [Account]) -> [MonthPoint] {
        let months = monthStarts
        let values = self.values(accounts, months: months)

        return months.enumerated().map { index, month in
            var liquid = Decimal(0), invested = Decimal(0), debt = Decimal(0)
            for account in accounts {
                let value = values[account.id]?[index] ?? 0
                if value < 0 {
                    debt += value
                } else {
                    switch account.type.group {
                    case .liquidity, .savings: liquid += value
                    default: invested += value
                    }
                }
            }
            return MonthPoint(date: month, liquid: liquid, invested: invested, debt: debt)
        }
    }

    private func accountLines(_ accounts: [Account]) -> [AccountLine] {
        let months = monthStarts
        let values = self.values(accounts, months: months)

        return accounts
            .map { account in
                let series = values[account.id] ?? []
                return AccountLine(account: account, before: series.first ?? 0, now: series.last ?? 0)
            }
            .sorted {
                if $0.account.type.group.sortOrder != $1.account.type.group.sortOrder {
                    return $0.account.type.group.sortOrder < $1.account.type.group.sortOrder
                }
                return $0.now > $1.now
            }
    }

    // MARK: - Format

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func signed(_ amount: Decimal) -> String {
        (amount > 0 ? "+" : "") + money(amount)
    }

    private func double(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year()).capitalized
    }

    private func percentChange(from start: Decimal, to end: Decimal) -> String? {
        guard start > 0 else { return nil }
        let ratio = double(end - start) / double(start)
        return (ratio > 0 ? "+" : "") + ratio.formatted(.percent.precision(.fractionLength(0)))
    }
}
