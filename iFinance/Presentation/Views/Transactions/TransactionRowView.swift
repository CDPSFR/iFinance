import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var appSettings: AppSettings
    
    var body: some View {
        HStack(spacing: 12) {
            // Icône type
            Image(systemName: transaction.type.icon)
                .font(.title3)
                .foregroundColor(colorForType(transaction.type))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(colorForType(transaction.type).opacity(0.1))
                )
            
            // Infos
            VStack(alignment: .leading, spacing: 4) {
                // Première ligne : Payee ou Mémo
                if let payeeID = transaction.payeeID,
                   let payee = payeesController.getPayee(id: payeeID) {
                    Text(payee.name)
                        .font(.headline)
                } else if let memo = transaction.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.headline)
                } else {
                    Text("Transaction")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                // Deuxième ligne : Catégorie, Status, Type
                HStack(spacing: 8) {
                    if transaction.status == .pending {
                        Text("En attente")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                    
                    if let categoryID = transaction.categoryID,
                       let category = categoriesController.getCategory(id: categoryID) {
                        HStack(spacing: 4) {
                            if let iconName = category.icon {
                                Image(systemName: iconName)
                                    .font(.caption)
                                    .foregroundColor(Color(hex: category.displayColor))
                            }
                            Text(categoriesController.getCategoryPath(for: categoryID))
                                .font(.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: category.displayColor).opacity(0.1))
                        .cornerRadius(4)
                    } else {
                        Text(transaction.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Montant
            Text(abs(transaction.amount), format: .currency(code: "EUR"))
                .font(.headline)
                .foregroundColor(colorForType(transaction.type))
                .privacyBlur(hidden: appSettings.hideAmounts)
            
            // Menu
            Menu {
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
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 4)
    }
    
    private func colorForType(_ type: TransactionType) -> Color {
        switch type {
        case .debit: return .red
        case .credit: return .green
        case .transfer: return .blue
        }
    }
}
