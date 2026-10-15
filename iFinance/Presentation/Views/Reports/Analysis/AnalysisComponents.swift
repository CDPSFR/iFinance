import SwiftUI

/// Ligne d'explication : libellé, précision, valeur à droite
struct ExplanationRow: View {
    let label: String
    var detail: String? = nil
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

/// Format commun des rapports d'analyse
struct AnalysisFormat {
    let currency: String
    let hidden: Bool

    func money(_ value: Decimal) -> String { hidden ? "•••" : PlanFormat.round(value, currency) }
    func cents(_ value: Decimal) -> String { hidden ? "•••" : PlanFormat.money(value, currency) }
    func signed(_ value: Decimal) -> String { hidden ? "•••" : (value > 0 ? "+" : "") + PlanFormat.round(value, currency) }
    func percent(_ value: Double, signed: Bool = false) -> String { PlanFormat.percent(value, signed: signed) }
    func month(_ date: Date) -> String { date.formatted(.dateTime.month(.wide).year()) }
    func day(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
}
