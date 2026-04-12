import SwiftUI

struct ConvertToTransferView: View {
    let transaction: Transaction
    @Binding var isPresented: Bool
    let onConfirm: (UUID) -> Void   // destinationAccountID

    @EnvironmentObject var accountsController: AccountsController

    @State private var destinationAccountID: UUID? = nil

    private var availableAccounts: [Account] {
        accountsController.activeAccounts.filter { $0.id != transaction.accountID }
    }

    private var sourceAccount: Account? {
        accountsController.getAccount(id: transaction.accountID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Convertir en transfert")
                        .font(.headline)
                    Text("La dépense sera transformée en transfert entre comptes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                // Résumé de la transaction
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(transaction.amount, format: .currency(code: sourceAccount?.currency ?? "EUR"))
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text(transaction.date, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.07))
                    .cornerRadius(10)
                }

                // Schéma source → destination
                HStack(spacing: 0) {
                    // Compte source
                    VStack(spacing: 4) {
                        Image(systemName: sourceAccount?.type.icon ?? "creditcard")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text(sourceAccount?.name ?? "—")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Compte source")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)

                    // Compte destination
                    VStack(spacing: 4) {
                        Image(systemName: destinationAccountID.flatMap { accountsController.getAccount(id: $0)?.type.icon } ?? "questionmark.circle")
                            .font(.title2)
                            .foregroundColor(destinationAccountID != nil ? .green : .secondary)
                        Text(destinationAccountID.flatMap { accountsController.getAccount(id: $0)?.name } ?? "À choisir")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(destinationAccountID != nil ? .primary : .secondary)
                        Text("Compte destination")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)

                // Picker destination
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compte de destination")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Compte de destination", selection: $destinationAccountID) {
                        Text("Sélectionner…").tag(nil as UUID?)
                        ForEach(availableAccounts) { account in
                            Text(account.name).tag(account.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                // Avertissement
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text("Le bénéficiaire sera supprimé. La transaction opposée (crédit) sera créée sur le compte destination.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
            .padding()

            Spacer()

            Divider()

            // Footer
            HStack {
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Convertir") {
                    if let destID = destinationAccountID {
                        onConfirm(destID)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationAccountID == nil)
            }
            .padding()
        }
        .frame(width: 420, height: 480)
    }
}
