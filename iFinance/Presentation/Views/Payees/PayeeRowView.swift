import SwiftUI

// MARK: - Payee Stats

/// Activité d'un bénéficiaire calculée à partir des transactions chargées
struct PayeeStats {
    var count = 0
    var total: Decimal = 0          // Somme signée : < 0 dépenses, > 0 revenus
    var lastDate: Date?
}

// MARK: - Payee Avatar

/// Initiales sur un cercle de la couleur de la catégorie par défaut
struct PayeeAvatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom),
                in: Circle()
            )
    }

    private var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: Category

    var body: some View {
        let color = Color(hex: category.displayColor)
        Label(category.name, systemImage: category.displayIcon)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Payee Row View
struct PayeeRowView: View {
    let payee: Payee
    let stats: PayeeStats
    let defaultCategory: Category?
    let currency: String
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PayeeAvatar(name: payee.name, color: accentColor)

            // Informations du bénéficiaire
            VStack(alignment: .leading, spacing: 3) {
                Text(payee.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    if let category = defaultCategory {
                        CategoryChip(category: category)
                    }
                    if let city = payee.city {
                        Text(city)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Activité
            VStack(alignment: .trailing, spacing: 3) {
                if stats.count > 0 {
                    Text(totalText)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(stats.total > 0 ? .green : .primary)
                }
                Text(activityText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .help("Voir les transactions de \(payee.name)")
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Voir les transactions", systemImage: "list.bullet.rectangle")
            }

            Divider()

            Button {
                onEdit()
            } label: {
                Label("Modifier", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private var accentColor: Color {
        defaultCategory.map { Color(hex: $0.displayColor) } ?? .gray
    }

    private var totalText: String {
        let amount = abs(stats.total).formatted(.currency(code: currency))
        return stats.total > 0 ? "+\(amount)" : amount
    }

    private var activityText: String {
        guard stats.count > 0 else { return "Aucune opération" }
        let operations = "\(stats.count) opération\(stats.count > 1 ? "s" : "")"
        guard let lastDate = stats.lastDate else { return operations }
        return "\(operations) · \(lastDate.formatted(.relative(presentation: .named)))"
    }
}
