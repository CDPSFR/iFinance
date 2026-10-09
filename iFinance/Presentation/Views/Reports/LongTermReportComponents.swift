import SwiftUI

// Composants communs aux rapports « Placements, retraite et dettes »

/// Barre horizontale proportionnelle, éventuellement découpée en segments
struct LTBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let fraction: Double          // Part de la largeur totale (0…1)
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 12
    /// Repère vertical (0…1), ex. un seuil
    var marker: Double? = nil

    init(fraction: Double, color: Color, height: CGFloat = 12, marker: Double? = nil) {
        self.segments = [Segment(fraction: fraction, color: color)]
        self.height = height
        self.marker = marker
    }

    init(segments: [Segment], height: CGFloat = 12, marker: Double? = nil) {
        self.segments = segments
        self.height = height
        self.marker = marker
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(geometry.size.width * CGFloat(min(max(segment.fraction, 0), 1)), 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                if let marker {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: height + 6)
                        .offset(x: geometry.size.width * CGFloat(min(max(marker, 0), 1)) - 1)
                }
            }
        }
        .frame(height: height)
    }
}

/// Ligne « libellé, barre, montant, complément » des blocs de rapport
struct LTBarRow: View {
    let label: String
    var detail: String? = nil
    let bar: LTBar
    let value: String
    var valueColor: Color = .primary
    var extra: String? = nil
    var labelWidth: CGFloat = 200
    var isEmphasized = false

    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .fontWeight(isEmphasized ? .semibold : .regular)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: labelWidth, alignment: .leading)

            bar

            Text(value)
                .monospacedDigit()
                .fontWeight(isEmphasized ? .semibold : .regular)
                .foregroundStyle(valueColor)
                .frame(width: 100, alignment: .trailing)
                .privacyBlur(hidden: appSettings.hideAmounts)

            if let extra {
                Text(extra)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 90, alignment: .trailing)
            }
        }
    }
}

/// Point d'attention (liste « À faire », fiscalité)
struct LTNoticeRow: View {
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var color: Color = .accentColor
    var valueColor: Color = .primary
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(valueColor)
            }
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 5)
    }
}

/// Grille de blocs sur deux colonnes ; un bloc seul sur sa ligne occupe toute la largeur
struct LTBlockGrid: View {
    let blocks: [AnyView]

    var body: some View {
        let rows = stride(from: 0, to: blocks.count, by: 2).map { Array(blocks.indices[$0..<min($0 + 2, blocks.count)]) }

        Grid(alignment: .topLeading, horizontalSpacing: NativeMetrics.groupSpacing, verticalSpacing: NativeMetrics.groupSpacing) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    if row.count == 1 {
                        blocks[row[0]]
                            .gridCellColumns(2)
                    } else {
                        ForEach(row, id: \.self) { index in
                            blocks[index]
                        }
                    }
                }
            }
        }
    }
}

/// Palette des rapports patrimoniaux
enum LTPalette {
    static let series: [Color] = [.accentColor, .teal, .purple, .orange, .gray, .green, .pink]

    static func color(at index: Int) -> Color {
        series[index % series.count]
    }
}
