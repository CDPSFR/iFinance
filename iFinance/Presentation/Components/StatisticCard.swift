import SwiftUI


// MARK: - Statistic Card (version avec option non-currency)
struct StatisticCard: View {
    let title: String
    let value: Decimal
    let color: Color
    var isCurrency: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if isCurrency {
                Text(value, format: .currency(code: "EUR"))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            } else {
                Text("\(NSDecimalNumber(decimal: value).intValue)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }
}
