import SwiftUI
import Charts

// Briques communes aux écrans de rapports : tableau de détail, répartition classée,
// infobulle de graphique et état vide.

// MARK: - Sens du rapport

/// Sens d'un rapport de répartition : dépenses ou revenus
enum ReportFlow {
    case expense
    case income

    var transactionType: TransactionType { self == .expense ? .debit : .credit }
    /// « Dépenses » / « Revenus »
    var title: String { self == .expense ? "Dépenses" : "Revenus" }
    /// « dépenses » / « revenus »
    var plural: String { self == .expense ? "dépenses" : "revenus" }
    /// « une dépense » / « un revenu »
    var oneOf: String { self == .expense ? "une dépense" : "un revenu" }
    /// « Dépense moyenne » / « Revenu moyen »
    var averageTitle: String { self == .expense ? "Dépense moyenne" : "Revenu moyen" }
    /// Couleur des barres : accent pour les dépenses, vert pour les revenus
    var color: Color { self == .expense ? .accentColor : .green }
}

// MARK: - Tableau de détail

struct ReportCell {
    let text: String
    var color: Color = .primary
    /// Les montants sont floutés quand « Masquer les montants » est actif
    var isAmount = true
}

struct ReportRow: Identifiable {
    let id: String
    let cells: [ReportCell]
}

/// Tableau encadré : première colonne alignée à gauche, les autres à droite, lignes alternées
struct ReportTable: View {
    let columns: [String]
    let rows: [ReportRow]
    var footnote: String? = nil

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        if index == 0 {
                            Text(column)
                                .gridColumnAlignment(.leading)
                        } else {
                            Text(column)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, row in
                    Divider()

                    GridRow {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                            if index == 0 {
                                Text(cell.text)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(cell.text)
                                    .foregroundStyle(cell.color)
                                    .privacyBlur(hidden: cell.isAmount && appSettings.hideAmounts)
                            }
                        }
                    }
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(rowIndex % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: NativeMetrics.groupCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NativeMetrics.groupCornerRadius, style: .continuous)
                    .strokeBorder(.separator)
            )

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Répartition classée

/// Élément d'une répartition (catégorie, compte ou bénéficiaire), du plus gros au plus petit
struct ReportBreakdownItem: Identifiable {
    let id: UUID
    let name: String
    let count: Int
    let amount: Decimal
    /// Part du total, de 0 à 1
    let share: Double

    var doubleAmount: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

enum ReportPalette {
    /// Couleurs attribuées par rang, pour distinguer les parts d'un anneau
    static let colors: [Color] = [.accentColor, .orange, .green, .purple, .red, .teal, .yellow, .gray]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}

extension Array where Element == ReportBreakdownItem {
    /// Construit une répartition triée à partir de totaux et de nombres de transactions par identifiant
    static func breakdown(_ entries: [(id: UUID, name: String, count: Int, amount: Decimal)]) -> [ReportBreakdownItem] {
        let total = entries.reduce(Decimal(0)) { $0 + $1.amount }
        return entries
            .sorted { $0.amount > $1.amount }
            .map { entry in
                ReportBreakdownItem(
                    id: entry.id,
                    name: entry.name,
                    count: entry.count,
                    amount: entry.amount,
                    share: total > 0 ? NSDecimalNumber(decimal: entry.amount / total).doubleValue : 0
                )
            }
    }

    var total: Decimal { reduce(Decimal(0)) { $0 + $1.amount } }
}

/// Barres horizontales classées, avec le montant au bout de chaque barre
struct ReportBarsBlock: View {
    let title: String
    let items: [ReportBreakdownItem]
    let money: (Decimal) -> String
    var color: Color = .accentColor

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupTitle(title)

            Chart(items) { item in
                BarMark(
                    x: .value("Montant", item.doubleAmount),
                    y: .value("Nom", item.name)
                )
                .foregroundStyle(color)
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text(money(item.amount))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: items.map { $0.name })
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .chartXScale(range: .plotDimension(endPadding: 90))
            .frame(height: CGFloat(max(items.count, 1)) * 30 + 10)
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }
}

/// Anneau de répartition avec sa légende chiffrée
struct ReportDonutBlock: View {
    let title: String
    let items: [ReportBreakdownItem]
    let total: Decimal
    let money: (Decimal) -> String

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupTitle(title)

            HStack(alignment: .center, spacing: 40) {
                Chart(Array(items.enumerated()), id: \.element.id) { index, item in
                    SectorMark(
                        angle: .value("Montant", item.doubleAmount),
                        innerRadius: .ratio(0.64),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(ReportPalette.color(at: index))
                }
                .chartLegend(.hidden)
                .chartBackground { _ in
                    VStack(spacing: 1) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(money(total))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                .frame(width: 210, height: 210)

                VStack(spacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(ReportPalette.color(at: index))
                                .frame(width: 10, height: 10)
                            Text(item.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                                .foregroundStyle(.secondary)
                            Text(money(item.amount))
                                .frame(minWidth: 90, alignment: .trailing)
                        }
                        .monospacedDigit()
                    }
                }
                .frame(maxWidth: 460)

                Spacer(minLength: 0)
            }
            .privacyBlur(hidden: appSettings.hideAmounts)
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }
}

// MARK: - Infobulle et état vide

/// Cadre d'infobulle affiché au survol d'un graphique
struct ReportTooltip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content
        }
        .font(.callout)
        .monospacedDigit()
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator)
        )
    }
}

struct ReportEmptyState: View {
    let systemImage: String
    var message = "Aucune transaction ne correspond à la période et aux comptes choisis."

    var body: some View {
        ContentUnavailableView(
            "Aucune donnée à afficher",
            systemImage: systemImage,
            description: Text(message)
        )
    }
}

/// Grille des chiffres clés en tête de rapport
struct ReportTiles<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: NativeMetrics.groupSpacing)],
            spacing: NativeMetrics.groupSpacing
        ) {
            content
        }
    }
}
