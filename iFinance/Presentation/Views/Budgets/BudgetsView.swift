import SwiftUI

struct BudgetsView: View {
    @EnvironmentObject var budgetsController: BudgetsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController

    @State private var showForm = false
    @State private var budgetToEdit: Budget? = nil
    @State private var searchText = ""

    private var filtered: [Budget] {
        guard !searchText.isEmpty else { return budgetsController.budgets }
        return budgetsController.budgets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Budgets")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Rechercher un budget", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 7)

            Divider()

            if filtered.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, budget in
                            let spent = budgetsController.spent(
                                for: budget,
                                transactions: transactionsController.allTransactions
                            )
                            NavigationLink(value: SettingsView.Destination.budget(budget)) {
                                BudgetRowView(
                                    budget: budget,
                                    spent: spent,
                                    onTap: {},
                                    onEdit: { budgetToEdit = budget },
                                    onDelete: {
                                        Task {
                                            await budgetsController.deleteBudget(id: budget.id)
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            if index < filtered.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .task {
            if let bookID = booksController.currentBook?.id {
                await budgetsController.loadBudgets(for: bookID)
            }
        }
        .sheet(isPresented: $showForm) {
            BudgetFormView(isPresented: $showForm)
        }
        .sheet(item: $budgetToEdit) { budget in
            BudgetFormView(
                isPresented: Binding(
                    get: { budgetToEdit != nil },
                    set: { if !$0 { budgetToEdit = nil } }
                ),
                budgetToEdit: budget
            )
        }
        .onChange(of: showForm) { _, isShowing in
            if !isShowing {
                Task {
                    if let bookID = booksController.currentBook?.id {
                        await budgetsController.loadBudgets(for: bookID)
                    }
                }
            }
        }
        .onChange(of: budgetToEdit) { _, value in
            if value == nil {
                Task {
                    if let bookID = booksController.currentBook?.id {
                        await budgetsController.loadBudgets(for: bookID)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "target")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("Aucun budget")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Créez des budgets pour suivre vos dépenses par catégorie")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Créer un budget") { showForm = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
