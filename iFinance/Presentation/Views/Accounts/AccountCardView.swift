import SwiftUI

struct AccountCardView: View {
    let account: Account
    let isSelected: Bool
    var isClosed: Bool = false
    let onSelect: () -> Void
    var onEdit: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onReopen: (() -> Void)? = nil
    var onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icône
            Image(systemName: account.type.icon)
                .font(.title)
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                )
            
            // Infos
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(account.name)
                        .font(.headline)
                    
                    if isClosed {
                        Text("Fermé")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                
                if let bank = account.bank {
                    Text(bank)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(account.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(account.currency)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Solde (simulé pour l'instant)
            VStack(alignment: .trailing, spacing: 2) {
                Text(account.initialBalance, format: .currency(code: account.currency))
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Solde initial")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Menu actions
            Menu {
                if !isClosed {
                    Button {
                        onSelect()
                    } label: {
                        Label("Sélectionner", systemImage: "checkmark.circle")
                    }
                    
                    if let onEdit = onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                    }
                    
                    if let onClose = onClose {
                        Button {
                            onClose()
                        } label: {
                            Label("Fermer le compte", systemImage: "lock")
                        }
                    }
                } else {
                    if let onReopen = onReopen {
                        Button {
                            onReopen()
                        } label: {
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
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isClosed {
                onSelect()
            }
        }
    }
}
