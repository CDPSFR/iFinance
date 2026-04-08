import SwiftUI

struct AccountListView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    
    @State private var showAccountForm = false
    @State private var showClosedAccounts = false
    @State private var accountToEdit: Account?
    @State private var accountToDelete: Account?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Comptes")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    accountToEdit = nil
                    showAccountForm = true
                } label: {
                    Label("Nouveau compte", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Toggle pour comptes fermés
            Toggle("Afficher les comptes fermés", isOn: $showClosedAccounts)
                .padding()
            
            // Liste des comptes
            if accountsController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if accountsController.activeAccounts.isEmpty && accountsController.closedAccounts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("Aucun compte")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Créez votre premier compte pour commencer")
                        .foregroundColor(.secondary)
                    
                    Button {
                        showAccountForm = true
                    } label: {
                        Label("Créer un compte", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Comptes actifs
                        if !accountsController.activeAccounts.isEmpty {
                            Section {
                                ForEach(accountsController.activeAccounts) { account in
                                    AccountCardView(
                                        account: account,
                                        isSelected: accountsController.selectedAccount?.id == account.id,
                                        onSelect: {
                                            accountsController.selectAccount(account)
                                        },
                                        onEdit: {
                                            accountToEdit = account
                                            showAccountForm = true
                                        },
                                        onClose: {
                                            Task { await accountsController.closeAccount(id: account.id) }
                                        },
                                        onDelete: {
                                            accountToDelete = account
                                            showDeleteConfirmation = true
                                        }
                                    )
                                }
                            } header: {
                                HStack {
                                    Text("Comptes actifs")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Comptes fermés
                        if showClosedAccounts && !accountsController.closedAccounts.isEmpty {
                            Section {
                                ForEach(accountsController.closedAccounts) { account in
                                    AccountCardView(
                                        account: account,
                                        isSelected: false,
                                        isClosed: true,
                                        onSelect: { },
                                        onReopen: {
                                            Task { await accountsController.reopenAccount(id: account.id) }
                                        },
                                        onDelete: {
                                            accountToDelete = account
                                            showDeleteConfirmation = true
                                        }
                                    )
                                }
                            } header: {
                                HStack {
                                    Text("Comptes fermés")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showAccountForm) {
            if let account = accountToEdit {
                AccountFormView(isPresented: $showAccountForm, accountToEdit: account)
            } else {
                AccountFormView(isPresented: $showAccountForm)
            }
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
        .onChange(of: bookController.currentBook?.id) { oldValue, newValue in
            if let bookID = newValue {
                Task {
                    await accountsController.loadAccounts(for: bookID)
                }
            }
        }
    }
}
