import SwiftUI


// MARK: - Statistic Card (version avec option non-currency)
struct StatisticCard: View {
    let title: String
    let value: Decimal
    let color: Color
    var isCurrency: Bool = true
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if isCurrency {
                Text(value, format: .currency(code: "EUR"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            } else {
                Text("\(NSDecimalNumber(decimal: value).intValue)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}
