import SwiftUI

struct AccountCardView: View {
    let account: Account
    var isClosed: Bool = false
    var onEdit: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onReopen: (() -> Void)? = nil
    var onDelete: () -> Void
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Icône
            Image(systemName: account.type.icon)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isClosed ? Color.gray : account.type.color)
                )

            // Infos
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.body)
                        .foregroundColor(isClosed ? .secondary : .primary)

                    if isClosed {
                        Text("Fermé")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }

                Text(account.bank ?? account.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu {
            if !isClosed {
                if let onEdit {
                    Button { onEdit() } label: {
                        Label("Modifier", systemImage: "pencil")
                    }
                }
                if let onClose {
                    Button { onClose() } label: {
                        Label("Fermer le compte", systemImage: "lock")
                    }
                }
            } else {
                if let onReopen {
                    Button { onReopen() } label: {
                        Label("Rouvrir le compte", systemImage: "lock.open")
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

extension AccountType {
    var color: Color {
        switch self {
        case .creditCard: return .orange
        case .crypto:     return Color(red: 0.95, green: 0.6, blue: 0.1)
        default:          return group.color
        }
    }
}

extension AccountGroup {
    var color: Color {
        switch self {
        case .liquidity:  return .blue
        case .savings:    return .green
        case .investment: return .purple
        case .retirement: return .indigo
        case .debt:       return .red
        case .other:      return .gray
        }
    }
}
