import SwiftUI

// MARK: - Payee Row View
struct PayeeRowView: View {
    let payee: Payee
    let count: Int
    let defaultCategory: Category?
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Icône du bénéficiaire
            Image(systemName: "person.crop.circle.fill")
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(width: 28, height: 28)
            
            // Informations du bénéficiaire
            VStack(alignment: .leading, spacing: 4) {
                Text(payee.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                if let category = defaultCategory {
                    HStack(spacing: 4) {
                        Image(systemName: category.displayIcon)
                            .font(.caption)
                            .foregroundColor(Color(hex: category.displayColor))
                        
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let city = payee.city {
                    Text(city)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Nombre de transactions - Cliquable
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .onTapGesture {
                print("🟢 Clic détecté sur le compteur du bénéficiaire: \(payee.name)")
                onTap()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
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
}
