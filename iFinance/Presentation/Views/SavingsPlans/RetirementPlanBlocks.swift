import SwiftUI
import Charts

// MARK: - Formats et couleurs

enum PlanFormat {
    static func money(_ amount: Decimal, _ currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    /// Montant arrondi à l'euro, pour les légendes et les blocs
    static func round(_ amount: Decimal, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    static func signed(_ amount: Decimal, _ currency: String) -> String {
        (amount > 0 ? "+" : "") + money(amount, currency)
    }

    static func percent(_ ratio: Double, signed: Bool = false) -> String {
        let style = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0...1))
        return signed ? ratio.formatted(style.sign(strategy: .always())) : ratio.formatted(style)
    }

    static func ratio(_ part: Decimal, _ total: Decimal) -> Double? {
        guard total != 0 else { return nil }
        return NSDecimalNumber(decimal: part / total).doubleValue
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

enum PlanPalette {
    private static let colors: [Color] = [.accentColor, .green, .orange, .purple, .teal]

    /// Couleur d'une origine, selon sa place dans les origines du plan
    static func color(for origin: ContributionOrigin, type: AccountType) -> Color {
        let origins = ContributionOrigin.origins(for: type)
        let index = origins.firstIndex(of: origin) ?? ContributionOrigin.allCases.firstIndex(of: origin) ?? 0
        return colors[index % colors.count]
    }

    static func color(for bucket: AvailabilityBucket, index: Int) -> Color {
        switch bucket.kind {
        case .available: return .green
        case .year: return [Color.teal, .accentColor, .purple][(index - 1) % 3]
        case .laterYears, .retirement, .annuity: return .gray
        case .capitalAfterTransfer: return .teal
        }
    }
}

// MARK: - Conteneur de bloc

/// Bloc groupé de la page d'un plan : titre, complément à droite, contenu
struct PlanBlock<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupTitle(title: title) {
                HStack(spacing: 10) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    accessory
                }
            }
            content
        }
        .padding(NativeMetrics.groupPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
    }
}

extension PlanBlock where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = EmptyView()
        self.content = content()
    }
}

/// Note en bas de bloc
struct PlanNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Valeur relevée et versements

struct PlanValueChartBlock: View {
    let history: [SavingsPlanHistoryPoint]
    let snapshotDates: Set<Date>
    let currency: String
    let onAddValuation: () -> Void

    var body: some View {
        PlanBlock(title: "Valeur relevée et versements") {
            HStack(spacing: 12) {
                legendItem(Circle().fill(Color.accentColor).frame(width: 7, height: 7), "Valeur à chaque relevé")
                legendItem(
                    Rectangle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).foregroundStyle(.secondary).frame(width: 12, height: 0),
                    "Versements nets"
                )
            }
        } content: {
            if history.count >= 2 {
                chart
                    .frame(height: 150)
                PlanNote("Entre deux relevés, la valeur est estimée : dernier relevé plus les versements faits depuis.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    PlanNote("Reportez la valeur de vos relevés (tous les 3 ou 6 mois par exemple) pour suivre la performance du plan. En attendant, la valeur affichée correspond aux versements.")
                    Button("Mettre à jour la valeur", action: onAddValuation)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            }
        }
    }

    private func legendItem<Marker: View>(_ marker: Marker, _ label: String) -> some View {
        HStack(spacing: 5) {
            marker
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bounds: (low: Double, high: Double) {
        let values = history.flatMap { [PlanFormat.double($0.value), PlanFormat.double($0.invested)] }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let margin = max((high - low) * 0.1, 1)
        return (max(low - margin, 0), high + margin)
    }

    private var chart: some View {
        let bounds = self.bounds

        return Chart {
            ForEach(history) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Bas", bounds.low),
                    yEnd: .value("Valeur", PlanFormat.double(point.value))
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", PlanFormat.double(point.value)),
                    series: .value("Série", "Valeur")
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(history.filter { snapshotDates.contains($0.date) }) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", PlanFormat.double(point.value))
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(28)
            }

            ForEach(history) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", PlanFormat.double(point.invested)),
                    series: .value("Série", "Versements nets")
                )
                .foregroundStyle(Color.secondary)
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: bounds.low...bounds.high)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: currency).precision(.fractionLength(0)))
                    }
                }
            }
        }
    }
}

// MARK: - Calendrier de disponibilité

struct AvailabilityCalendarBlock: View {
    let buckets: [AvailabilityBucket]
    let subtitle: String
    let note: String
    let currency: String

    var body: some View {
        PlanBlock(title: "Calendrier de disponibilité", subtitle: subtitle) {
            stackedBar
                .frame(height: 14)

            VStack(spacing: 6) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PlanPalette.color(for: bucket, index: index))
                            .frame(width: 8, height: 8)
                        Text(bucket.label)
                            .fontWeight(index == 0 ? .semibold : .regular)
                        Text(bucket.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(PlanFormat.round(bucket.value, currency))
                            .monospacedDigit()
                            .fontWeight(index == 0 ? .semibold : .regular)
                    }
                }
            }

            Spacer(minLength: 0)
            PlanNote(note)
        }
    }

    private var stackedBar: some View {
        let visible = Array(buckets.enumerated()).filter { $0.element.value > 0 }
        let total = visible.reduce(0.0) { $0 + PlanFormat.double($1.element.value) }

        return GeometryReader { geometry in
            let spacing: CGFloat = 2
            let available = max(geometry.size.width - spacing * CGFloat(max(visible.count - 1, 0)), 0)

            HStack(spacing: spacing) {
                if total > 0 {
                    ForEach(visible, id: \.element.id) { index, bucket in
                        Rectangle()
                            .fill(PlanPalette.color(for: bucket, index: index))
                            .frame(width: max(available * CGFloat(PlanFormat.double(bucket.value) / total), 3))
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - D'où vient l'argent

struct OriginsByYearBlock: View {
    let yearly: [YearlyOriginAmount]
    let totals: [ContributionOrigin: Decimal]
    let accountType: AccountType
    let note: String
    let currency: String

    private var origins: [ContributionOrigin] {
        ContributionOrigin.origins(for: accountType).filter { (totals[$0] ?? 0) > 0 }
            + ContributionOrigin.allCases.filter { !ContributionOrigin.origins(for: accountType).contains($0) && (totals[$0] ?? 0) > 0 }
    }

    var body: some View {
        PlanBlock(title: "D’où vient l’argent", subtitle: "apports par année et par origine") {
            if yearly.isEmpty {
                PlanNote("Aucun apport enregistré.")
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            } else {
                Chart(yearly) { entry in
                    BarMark(
                        x: .value("Année", String(entry.year)),
                        y: .value("Montant", PlanFormat.double(entry.amount))
                    )
                    .foregroundStyle(by: .value("Origine", entry.origin.displayName(for: accountType)))
                }
                .chartForegroundStyleScale(
                    domain: origins.map { $0.displayName(for: accountType) },
                    range: origins.map { PlanPalette.color(for: $0, type: accountType) }
                )
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: currency).precision(.fractionLength(0)))
                            }
                        }
                    }
                }
                .frame(height: 110)

                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(origins, id: \.self) { origin in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(PlanPalette.color(for: origin, type: accountType))
                                .frame(width: 8, height: 8)
                            Text(origin.displayName(for: accountType))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(PlanFormat.round(totals[origin] ?? 0, currency))
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }

            PlanNote(note)
        }
    }
}

// MARK: - Bloc de chiffres (abondement, déduction)

struct PlanFactRow: Identifiable {
    var id: String { label }
    let label: String
    var detail: String? = nil
    let value: String
    var color: Color = .primary
    var action: (() -> Void)? = nil
}

struct PlanFactsBlock: View {
    let title: String
    let subtitle: String
    let rows: [PlanFactRow]
    let footnote: String
    var onEdit: (() -> Void)? = nil

    var body: some View {
        PlanBlock(title: title, subtitle: subtitle) {
            if let onEdit {
                Button("Modifier…", action: onEdit)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        if let action = row.action {
                            Button(row.value, action: action)
                                .buttonStyle(.link)
                        } else {
                            Text(row.value)
                                .monospacedDigit()
                                .fontWeight(.semibold)
                                .foregroundStyle(row.color)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Spacer(minLength: 0)
            PlanNote(footnote)
        }
    }
}

// MARK: - Versements et plafond de déduction (PER)

struct DeductionCeilingsBlock: View {
    let history: [DeductionYear]
    let currentYear: Int
    let note: String
    let currency: String

    var body: some View {
        PlanBlock(title: "Versements et plafond de déduction", subtitle: "par année fiscale") {
            VStack(spacing: 8) {
                ForEach(history) { year in
                    let isCurrent = year.year == currentYear
                    HStack(spacing: 10) {
                        Text(String(year.year))
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .frame(width: 40, alignment: .leading)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.15))
                                Capsule()
                                    .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.6))
                                    .frame(width: geometry.size.width * CGFloat(min(year.ratio, 1)))
                            }
                        }
                        .frame(height: 8)

                        (Text(PlanFormat.round(year.deducted, currency))
                            + Text(" sur \(PlanFormat.round(year.ceiling, currency))\(year.isFloorCeiling ? "*" : "")")
                                .font(.caption)
                                .foregroundColor(.secondary))
                            .monospacedDigit()
                            .frame(width: 150, alignment: .trailing)

                        Text(PlanFormat.percent(year.ratio))
                            .monospacedDigit()
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Spacer(minLength: 0)
            PlanNote(note)
        }
    }
}

// MARK: - Rythme de versement (PER)

struct ContributionPaceBlock: View {
    let pace: ContributionPace
    let note: String
    let currency: String

    var body: some View {
        PlanBlock(title: "Rythme de versement", subtitle: "12 derniers mois") {
            let maxAmount = pace.months.map { PlanFormat.double($0.amount) }.max() ?? 0

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(pace.months) { month in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(month.amount > 0 ? Color.accentColor : Color.red.opacity(0.7))
                            .frame(height: month.amount > 0 && maxAmount > 0
                                   ? max(CGFloat(PlanFormat.double(month.amount) / maxAmount) * 56, 3)
                                   : 3)
                            .help(PlanFormat.money(month.amount, currency))
                        Text(month.start.formatted(.dateTime.month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    fact("Versement habituel", pace.usualAmount.map { "\(PlanFormat.round($0, currency)) par mois" } ?? "—")
                    fact("Mois versés", "\(pace.paidMonths) sur 12")
                }
                GridRow {
                    fact("Versé sur 12 mois", PlanFormat.round(pace.total, currency))
                    fact("Dernier versement", pace.lastContribution.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "—")
                }
            }

            Spacer(minLength: 0)
            PlanNote(note)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }
}
