import SwiftUI
import Charts

// Blocs d'analyse de la page d'un compte d'investissement : courbe valeur / versé net et répartition.

// MARK: - Courbe valeur du compte et versements

struct InvestmentValueChart: View {
    @EnvironmentObject var appSettings: AppSettings

    enum Range: String, CaseIterable, Identifiable {
        case threeMonths = "3 M"
        case sixMonths = "6 M"
        case oneYear = "1 A"
        case threeYears = "3 A"
        case all = "Tout"

        var id: String { rawValue }

        /// Début de la période, nil pour tout l'historique
        func start(from end: Date) -> Date? {
            let calendar = Calendar.current
            switch self {
            case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: end)
            case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: end)
            case .oneYear: return calendar.date(byAdding: .year, value: -1, to: end)
            case .threeYears: return calendar.date(byAdding: .year, value: -3, to: end)
            case .all: return nil
            }
        }
    }

    let points: [InvestmentSeriesPoint]
    let currency: String
    @Binding var range: Range

    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Valeur du compte et versements")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                legend("Valeur", color: .accentColor, dashed: false)
                legend("Versé net", color: .secondary, dashed: true)

                Picker("Période", selection: $range) {
                    ForEach(Range.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            if points.count < 2 {
                Text("Pas encore assez d'historique pour tracer une courbe.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .padding(NativeMetrics.groupPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
    }

    private var chart: some View {
        let selected = selectedPoint
        let low = points.map { min(double($0.value), double($0.invested)) }.min() ?? 0

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", low),
                    yEnd: .value("Valeur", double(point.value))
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", double(point.value)),
                    series: .value("Série", "Valeur")
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Montant", double(point.invested)),
                    series: .value("Série", "Versé net")
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .interpolationMethod(.stepEnd)
            }

            if let selected {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ReportTooltip {
                            Text(selected.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Valeur \(money(selected.value))")
                                .fontWeight(.semibold)
                            Text("Versé net \(money(selected.invested))")
                                .font(.caption)
                            let gain = selected.value - selected.invested
                            Text("Écart \(gain > 0 ? "+" : "")\(money(gain))")
                                .font(.caption)
                                .foregroundStyle(gain >= 0 ? Color.green : Color.red)
                        }
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $selectedDate)
        .privacyBlur(hidden: appSettings.hideAmounts)
    }

    private var selectedPoint: InvestmentSeriesPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 2)
                .opacity(dashed ? 0.7 : 1)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func double(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}

// MARK: - Répartition

struct InvestmentAllocationChart: View {
    @EnvironmentObject var appSettings: AppSettings

    enum Mode: String, CaseIterable, Identifiable {
        case position = "Par position"
        case assetType = "Par classe"

        var id: String { rawValue }
    }

    struct Slice: Identifiable {
        let id: String
        let name: String
        let amount: Decimal
        let color: Color

        var doubleAmount: Double { NSDecimalNumber(decimal: amount).doubleValue }
    }

    let positions: [InvestmentPosition]
    let cash: Decimal
    let currency: String
    @Binding var mode: Mode

    /// Parts distinctes avant regroupement dans « Autres »
    private static let maxSlices = 6

    var body: some View {
        let slices = self.slices
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Répartition")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Répartition", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }

            if slices.isEmpty || total <= 0 {
                Text("Aucune position détenue.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Montant", slice.doubleAmount),
                            innerRadius: .ratio(0.62),
                            angularInset: 1
                        )
                        .foregroundStyle(slice.color)
                    }
                    .frame(width: 130, height: 130)
                    .overlay {
                        VStack(spacing: 1) {
                            Text("Total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(total.formatted(.currency(code: currency).precision(.fractionLength(0))))
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }
                    }
                    .accessibilityLabel("Répartition du compte, détaillée dans la légende")

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(slices) { slice in
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(slice.color)
                                    .frame(width: 9, height: 9)
                                Text(slice.name)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(NSDecimalNumber(decimal: slice.amount / total).doubleValue,
                                     format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(NativeMetrics.groupPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
    }

    private var slices: [Slice] {
        let held = positions.filter { $0.quantity > 0 }
        var entries: [(id: String, name: String, amount: Decimal)]

        switch mode {
        case .position:
            entries = held.map { ($0.id.uuidString, $0.name, PositionCalculator.marketValue($0)) }
        case .assetType:
            entries = Dictionary(grouping: held) { $0.assetType }.map { type, members in
                (type.rawValue, type.displayName, members.reduce(Decimal(0)) { $0 + PositionCalculator.marketValue($1) })
            }
        }
        entries.sort { $0.amount > $1.amount }

        if entries.count > Self.maxSlices {
            let rest = entries.dropFirst(Self.maxSlices - 1).reduce(Decimal(0)) { $0 + $1.amount }
            entries = Array(entries.prefix(Self.maxSlices - 1)) + [("others", "Autres", rest)]
        }

        var slices = entries.enumerated().map { index, entry in
            Slice(id: entry.id, name: entry.name, amount: entry.amount,
                  color: entry.id == "others" ? .gray : ReportPalette.color(at: index))
        }
        if cash > 0 {
            slices.append(Slice(id: "cash", name: "Espèces", amount: cash, color: .yellow))
        }
        return slices.filter { $0.amount > 0 }
    }
}
