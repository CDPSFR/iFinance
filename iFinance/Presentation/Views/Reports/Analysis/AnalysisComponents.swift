import SwiftUI

/// Réponse en une phrase, en tête des rapports d'analyse : la question posée,
/// la réponse en clair et un complément. La couleur et l'icône donnent le ton.
struct ReportHeadline: View {
    enum Tone {
        case good, warning, bad, info

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .bad: return .red
            case .info: return .accentColor
            }
        }

        var icon: String {
            switch self {
            case .good: return "checkmark"
            case .warning: return "exclamationmark"
            case .bad: return "exclamationmark"
            case .info: return "info"
            }
        }
    }

    let question: String
    let answer: String
    var detail: String? = nil
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tone.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tone.color))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(question)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(answer)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NativeMetrics.groupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HStack(spacing: 0) {
                tone.color.frame(width: 4)
                Spacer(minLength: 0)
            }
        )
        .cardBackground()
        .clipShape(RoundedRectangle(cornerRadius: NativeMetrics.groupCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

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
