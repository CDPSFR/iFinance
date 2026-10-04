import SwiftUI

struct DuplicateDetectionView: View {

    @Binding var isPresented: Bool

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var appSettings: AppSettings

    // IDs à supprimer (l'utilisateur coche ceux qu'il veut garder)
    @State private var toDelete: Set<UUID> = []
    @State private var isDeleting = false
    @State private var isDone = false
    @State private var deletedCount = 0

    // Groupes de doublons : chaque groupe contient ≥2 transactions identiques
    private var duplicateGroups: [[Transaction]] {
        let txs = transactionsController.allTransactions

        // Clé de regroupement : (jour, montant absolu, payeeID, categoryID, type)
        let calendar = Calendar.current
        var groups: [String: [Transaction]] = [:]

        for tx in txs {
            let day = calendar.startOfDay(for: tx.date)
            let key = "\(day.timeIntervalSince1970)|\(tx.amount)|\(tx.payeeID?.uuidString ?? "nil")|\(tx.categoryID?.uuidString ?? "nil")|\(tx.type.rawValue)"
            groups[key, default: []].append(tx)
        }

        return groups.values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.date ?? .distantPast) > ($1.first?.date ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doublons détectés")
                        .font(.headline)
                    if !isDone {
                        Text("Cochez les transactions à conserver, les autres seront supprimées")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

            if isDone {
                doneView
            } else if isDeleting {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView("Suppression en cours…")
                    Spacer()
                }
            } else if duplicateGroups.isEmpty {
                emptyView
            } else {
                duplicateList
            }
        }
        .frame(width: 680, height: 560)
        .onAppear { preselectDuplicates() }
    }

    // MARK: - Duplicate list

    private var duplicateList: some View {
        VStack(spacing: 0) {
            // Résumé
            HStack {
                Label(
                    "\(duplicateGroups.count) groupe(s) de doublons — \(totalDuplicates) transaction(s) concernée(s)",
                    systemImage: "doc.on.doc"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                Spacer()
                Button("Tout cocher (garder 1)") { preselectDuplicates() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(duplicateGroups, id: \.first!.id) { group in
                        duplicateGroupView(group)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                if !toDelete.isEmpty {
                    Text("\(toDelete.count) transaction(s) à supprimer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button("Supprimer les doublons") {
                    Task { await performDeletion() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(toDelete.isEmpty)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func duplicateGroupView(_ group: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titre du groupe
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("\(group.count) transactions identiques")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.08))

            ForEach(Array(group.enumerated()), id: \.element.id) { index, tx in
                let isKept = !toDelete.contains(tx.id)
                HStack(spacing: 10) {
                    // Toggle garder/supprimer
                    Toggle("", isOn: Binding(
                        get: { isKept },
                        set: { keep in
                            if keep { toDelete.remove(tx.id) }
                            else { toDelete.insert(tx.id) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                    // Icône état
                    Image(systemName: isKept ? "checkmark.circle.fill" : "trash.circle.fill")
                        .foregroundColor(isKept ? .green : .red)
                        .font(.subheadline)

                    // Infos transaction
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tx.date, format: .dateTime.day().month().year())
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let account = accountsController.getAccount(id: tx.accountID) {
                                Text("· \(account.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(spacing: 6) {
                            if let payeeID = tx.payeeID,
                               let payee = payeesController.getPayee(id: payeeID) {
                                Text(payee.name).font(.caption).foregroundColor(.secondary)
                            }
                            if let catID = tx.categoryID {
                                Text("· \(categoriesController.getCategoryPath(for: catID))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            if let memo = tx.memo, !memo.isEmpty {
                                Text("· \(memo)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // Montant
                    Text(tx.signedAmount, format: .currency(code: accountsController.getAccount(id: tx.accountID)?.currency ?? "EUR"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(tx.type == .credit ? .green : .red)
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isKept ? Color.clear : Color.red.opacity(0.04))

                if index < group.count - 1 {
                    Divider().padding(.leading, 80)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(.green.opacity(0.8))
            Text("Aucun doublon détecté")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Toutes vos transactions sont uniques.")
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.red.opacity(0.8))
            Text("\(deletedCount) doublon(s) supprimé(s)")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            HStack {
                Spacer()
                Button("Fermer") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var totalDuplicates: Int {
        duplicateGroups.reduce(0) { $0 + $1.count }
    }

    /// Par défaut : dans chaque groupe, conserver la première transaction (la plus ancienne créée),
    /// marquer toutes les autres à supprimer.
    private func preselectDuplicates() {
        toDelete = []
        for group in duplicateGroups {
            let sorted = group.sorted { $0.date < $1.date }
            for tx in sorted.dropFirst() {
                toDelete.insert(tx.id)
            }
        }
    }

    private func performDeletion() async {
        isDeleting = true
        let ids = toDelete
        for id in ids {
            await transactionsController.deleteTransaction(id: id)
        }
        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
        deletedCount = ids.count
        isDeleting = false
        isDone = true
    }
}
