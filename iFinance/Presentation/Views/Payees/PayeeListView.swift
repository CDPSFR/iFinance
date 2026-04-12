import SwiftUI

struct PayeeListView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    
    // AJOUT: Binding pour contrôler la navigation
    @Binding var selectedTab: MainView.SidebarItem
    
    @State private var showPayeeForm = false
    @State private var payeeToEdit: Payee?
    @State private var payeeToDelete: Payee?
    @State private var showDeleteConfirmation = false
    @State private var searchQuery = ""
    @State private var navigateToTransactions = false
    @State private var selectedPayeeForNavigation: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Titre
            HStack {
                Text("Bénéficiaires")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Barre de recherche
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Rechercher un bénéficiaire...", text: $searchQuery)
                    .textFieldStyle(.plain)
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Contenu
            if payeesController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPayees.isEmpty {
                emptyPayeesView
            } else {
                payeesScrollView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showPayeeForm) {
            if let payee = payeeToEdit {
                PayeeFormView(isPresented: $showPayeeForm, payeeToEdit: payee)
            } else {
                PayeeFormView(isPresented: $showPayeeForm)
            }
        }
        .alert("Supprimer le bénéficiaire ?", isPresented: $showDeleteConfirmation, presenting: payeeToDelete) { payee in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await payeesController.deletePayee(id: payee.id) }
            }
        } message: { payee in
            Text("Êtes-vous sûr de vouloir supprimer \"\(payee.name)\" ? Les transactions associées ne seront pas supprimées mais n'auront plus de bénéficiaire.")
        }
        .task {
            if let bookID = bookController.currentBook?.id {
                await payeesController.loadPayees(for: bookID)
                await categoriesController.loadCategories(for: bookID)
            }
        }
        .onChange(of: bookController.currentBook?.id) { oldValue, newValue in
            if let bookID = newValue {
                Task {
                    await payeesController.loadPayees(for: bookID)
                    await categoriesController.loadCategories(for: bookID)
                }
            }
        }
        .onChange(of: navigateToTransactions) { oldValue, newValue in
            if newValue, let payeeID = selectedPayeeForNavigation {
                print("🔵 onChange déclenché - Application du filtre pour payeeID: \(payeeID)")
                
                // Appliquer le filtre de bénéficiaire
                var filters = transactionsController.filters
                filters.payeeID = payeeID
                transactionsController.updateFilters(filters)
                
                print("✅ Filtre appliqué - Transactions filtrées: \(transactionsController.filteredTransactions.count)")
                
                // 🔴 NAVIGATION: Changer vers la vue des transactions
                selectedTab = .allTransactions
                
                // Réinitialiser la navigation
                navigateToTransactions = false
                selectedPayeeForNavigation = nil
            }
        }
    }
    
    private var filteredPayees: [Payee] {
        if searchQuery.isEmpty {
            return payeesController.payees
        }
        
        return payeesController.payees.filter { payee in
            payee.name.localizedCaseInsensitiveContains(searchQuery) ||
            payee.city?.localizedCaseInsensitiveContains(searchQuery) == true
        }
    }
    
    private var emptyPayeesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            if searchQuery.isEmpty {
                Text("Aucun bénéficiaire")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Créez des bénéficiaires pour mieux organiser vos transactions")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    showPayeeForm = true
                } label: {
                    Label("Créer un bénéficiaire", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Aucun résultat")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Aucun bénéficiaire ne correspond à \"\(searchQuery)\"")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var payeesScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(groupedPayees.keys.sorted(), id: \.self) { letter in
                    PayeeGroupView(
                        letter: letter,
                        payees: groupedPayees[letter] ?? [],
                        transactionCounts: getPayeeTransactionCounts(),
                        categoriesController: categoriesController,
                        onEdit: { payee in
                            payeeToEdit = payee
                            showPayeeForm = true
                        },
                        onDelete: { payee in
                            payeeToDelete = payee
                            showDeleteConfirmation = true
                        },
                        onSelectPayee: { payee in
                            print("🟡 onSelectPayee appelé pour: \(payee.name)")
                            selectedPayeeForNavigation = payee.id
                            navigateToTransactions = true
                            print("🟡 navigateToTransactions = \(navigateToTransactions)")
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Grouped Payees
    private var groupedPayees: [String: [Payee]] {
        Dictionary(grouping: filteredPayees.sorted { $0.name < $1.name }) { payee in
            String(payee.name.prefix(1).uppercased())
        }
    }
    
    // MARK: - Transaction Count
    private func getPayeeTransactionCounts() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        
        for transaction in transactionsController.allTransactions {
            if let payeeID = transaction.payeeID {
                counts[payeeID, default: 0] += 1
            }
        }
        
        return counts
    }
}

// MARK: - Payee Group View
struct PayeeGroupView: View {
    let letter: String
    let payees: [Payee]
    let transactionCounts: [UUID: Int]
    let categoriesController: CategoriesController
    let onEdit: (Payee) -> Void
    let onDelete: (Payee) -> Void
    let onSelectPayee: (Payee) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // 🔤 LETTRE – À L’EXTÉRIEUR DU FOND
            Text(letter)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            // 🧱 CARTE AVEC FOND + RADIUS
            VStack(spacing: 0) {
                ForEach(payees) { payee in
                    PayeeRowView(
                        payee: payee,
                        count: transactionCounts[payee.id] ?? 0,
                        defaultCategory: categoriesController.getCategory(
                            id: payee.defaultCategoryID ?? UUID()
                        ),
                        onTap: { onSelectPayee(payee) },
                        onEdit: { onEdit(payee) },
                        onDelete: { onDelete(payee) }
                    )
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
}
