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
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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
        // Fond légèrement teinté pour détacher les cartes (blanc sur blanc depuis macOS 26)
        .background(Color(nsColor: .windowBackgroundColor).overlay(Color.primary.opacity(0.045)))
        .sheet(isPresented: $showPayeeForm) {
            PayeeFormView(isPresented: $showPayeeForm)
        }
        .sheet(item: $payeeToEdit) { payee in
            PayeeFormView(
                isPresented: Binding(
                    get: { payeeToEdit != nil },
                    set: { if !$0 { payeeToEdit = nil } }
                ),
                payeeToEdit: payee
            )
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
        let stats = payeeStats()
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(groupedPayees.keys.sorted(), id: \.self) { letter in
                    PayeeGroupView(
                        letter: letter,
                        payees: groupedPayees[letter] ?? [],
                        stats: stats,
                        currency: bookController.currentBook?.currency ?? "EUR",
                        categoriesController: categoriesController,
                        onEdit: { payee in
                            payeeToEdit = payee
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
            .padding(.bottom)
        }
    }
    
    // MARK: - Grouped Payees
    private var groupedPayees: [String: [Payee]] {
        Dictionary(grouping: filteredPayees.sorted { $0.name < $1.name }) { payee in
            String(payee.name.prefix(1).uppercased())
        }
    }
    
    // MARK: - Payee Stats
    private func payeeStats() -> [UUID: PayeeStats] {
        var stats: [UUID: PayeeStats] = [:]

        for transaction in transactionsController.allTransactions where transaction.status != .skipped {
            guard let payeeID = transaction.payeeID else { continue }
            var entry = stats[payeeID, default: PayeeStats()]
            entry.count += 1
            entry.total += transaction.signedAmount
            if entry.lastDate.map({ transaction.date > $0 }) ?? true {
                entry.lastDate = transaction.date
            }
            stats[payeeID] = entry
        }

        return stats
    }
}

// MARK: - Payee Group View
struct PayeeGroupView: View {
    let letter: String
    let payees: [Payee]
    let stats: [UUID: PayeeStats]
    let currency: String
    let categoriesController: CategoriesController
    let onEdit: (Payee) -> Void
    let onDelete: (Payee) -> Void
    let onSelectPayee: (Payee) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(letter)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(payees.enumerated()), id: \.element.id) { index, payee in
                    PayeeRowView(
                        payee: payee,
                        stats: stats[payee.id] ?? PayeeStats(),
                        defaultCategory: payee.defaultCategoryID.flatMap { categoriesController.getCategory(id: $0) },
                        currency: currency,
                        onTap: { onSelectPayee(payee) },
                        onEdit: { onEdit(payee) },
                        onDelete: { onDelete(payee) }
                    )

                    if index < payees.count - 1 {
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator.opacity(0.6))
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
}
