import SwiftUI

struct BudgetRowView: View {
    let budget: Budget
    let spent: Decimal
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var appSettings: AppSettings

    private var amount: Decimal { budget.currentVersion?.amount ?? 0 }
    private var progress: Double {
        guard amount > 0 else { return 0 }
        return min(1.0, Double(truncating: NSDecimalNumber(decimal: spent / amount)))
    }
    private var remaining: Decimal { amount - spent }
    private var isOverBudget: Bool { spent > amount }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(isOverBudget ? Color.red.opacity(0.15) : Color.blue.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isOverBudget ? .red : .blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(budget.name)
                        .font(.body)
                    Spacer()
                    Text(amount, format: .currency(code: "EUR"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }

                ProgressView(value: progress)
                    .tint(isOverBudget ? .red : (progress > 0.8 ? .orange : .blue))

                HStack {
                    Text(budget.period.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if isOverBudget {
                        Text("Dépassé de \(spent - amount, format: .currency(code: "EUR"))")
                            .font(.caption)
                            .foregroundColor(.red)
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    } else {
                        Text("\(remaining, format: .currency(code: "EUR")) restants")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .privacyBlur(hidden: appSettings.hideAmounts)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onEdit() } label: {
                Label("Modifier", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}
