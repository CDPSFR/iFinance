import SwiftUI

struct AccountListView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var accountsController: AccountsController

    @State private var showNewAccountForm = false
    @State private var showClosedAccounts = false
    @State private var accountToEdit: Account?
    @State private var accountToDelete: Account?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Titre
            HStack {
                Text("Comptes")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // Contenu
            if accountsController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if accountsController.activeAccounts.isEmpty && accountsController.closedAccounts.isEmpty {
                emptyView
            } else {
                accountsScrollView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showNewAccountForm) {
            AccountFormView(isPresented: $showNewAccountForm)
        }
        .sheet(item: $accountToEdit) { account in
            AccountFormView(
                isPresented: Binding(
                    get: { accountToEdit != nil },
                    set: { if !$0 { accountToEdit = nil } }
                ),
                accountToEdit: account
            )
        }
        .alert("Supprimer le compte ?", isPresented: $showDeleteConfirmation, presenting: accountToDelete) { account in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await accountsController.deleteAccount(id: account.id) }
            }
        } message: { account in
            Text("Êtes-vous sûr de vouloir supprimer \"\(account.name)\" ? Cette action supprimera toutes les transactions associées.")
        }
        .task {
            if let bookID = bookController.currentBook?.id {
                await accountsController.loadAccounts(for: bookID)
            }
        }
        .onChange(of: bookController.currentBook?.id) { _, newValue in
            if let bookID = newValue {
                Task { await accountsController.loadAccounts(for: bookID) }
            }
        }
    }

    // MARK: - Scroll view

    private var accountsScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Comptes actifs
                if !accountsController.activeAccounts.isEmpty {
                    accountSection(
                        title: "Actifs",
                        accounts: accountsController.activeAccounts,
                        isClosed: false
                    )
                }

                // Toggle comptes fermés
                if !accountsController.closedAccounts.isEmpty {
                    Button {
                        withAnimation { showClosedAccounts.toggle() }
                    } label: {
                        HStack {
                            Text(showClosedAccounts ? "Masquer les comptes fermés" : "Afficher les comptes fermés")
                                .font(.subheadline)
                                .foregroundColor(.teal)
                            Spacer()
                            Image(systemName: showClosedAccounts ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.teal)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if showClosedAccounts {
                        accountSection(
                            title: "Fermés",
                            accounts: accountsController.closedAccounts,
                            isClosed: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func accountSection(title: String, accounts: [Account], isClosed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    AccountCardView(
                        account: account,
                        isClosed: isClosed,
                        onEdit: isClosed ? nil : ({ accountToEdit = account } as (() -> Void)?),
                        onClose: isClosed ? nil : ({ Task { await accountsController.closeAccount(id: account.id) } } as (() -> Void)?),
                        onReopen: isClosed ? ({ Task { await accountsController.reopenAccount(id: account.id) } } as (() -> Void)?) : nil,
                        onDelete: {
                            accountToDelete = account
                            showDeleteConfirmation = true
                        },
                        onTap: {
                            accountToEdit = account
                        }
                    )

                    if index < accounts.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text("Aucun compte")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Créez votre premier compte pour commencer")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showNewAccountForm = true
            } label: {
                Label("Créer un compte", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
