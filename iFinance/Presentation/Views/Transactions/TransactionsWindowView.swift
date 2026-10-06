import SwiftUI

/// Ce qu'affiche une fenêtre de transactions : un bénéficiaire, ou une catégorie avec ses sous-catégories
struct TransactionsWindowScope: Codable, Hashable {
    enum Kind: String, Codable {
        case payee
        case category
    }

    var kind: Kind
    var id: UUID
    var title: String

    /// Identifiant du WindowGroup déclaré dans iFinanceApp
    static let windowID = "transactions"

    var subtitle: String {
        switch kind {
        case .payee: return "Bénéficiaire"
        case .category: return "Catégorie"
        }
    }
}

/// Fenêtre indépendante listant les transactions d'un bénéficiaire ou d'une catégorie.
/// Sa recherche et son tri lui sont propres : ils ne touchent pas aux filtres de la fenêtre principale.
struct TransactionsWindowView: View {
    let scope: TransactionsWindowScope

    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    @State private var searchText = ""
    @State private var selection: Set<UUID> = []
    @State private var sortOrder = [KeyPathComparator(\Row.date, order: .reverse)]
    @State private var transactionToEdit: Transaction?

    struct Row: Identifiable {
        let id: UUID
        let date: Date
        let account: String
        let payee: String
        let category: String
        /// Montant signé : négatif pour une dépense
        let amount: Decimal
        let memo: String
        let transaction: Transaction
    }

    var body: some View {
        let rows = self.rows

        VStack(spacing: 0) {
            if rows.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Aucune transaction",
                        systemImage: "list.bullet",
                        description: Text("Aucune transaction sur les comptes ouverts pour « \(scope.title) ».")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                table(rows)
            }
            TableStatusBar(items: statusItems(rows))
        }
        .navigationTitle(scope.title)
        .navigationSubtitle(scope.subtitle)
        .searchable(text: $searchText, prompt: "Rechercher")
        .sheet(item: $transactionToEdit) { transaction in
            TransactionFormView(
                isPresented: Binding(
                    get: { transactionToEdit != nil },
                    set: { if !$0 { transactionToEdit = nil } }
                ),
                transactionToEdit: transaction
            )
        }
    }

    // MARK: - Tableau

    private func table(_ rows: [Row]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { row in
                Text(row.date, format: .dateTime.day().month().year())
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 95)

            TableColumn("Compte", value: \.account)
                .width(min: 90, ideal: 130)

            TableColumn("Bénéficiaire", value: \.payee)
                .width(min: 100, ideal: 160)

            TableColumn("Catégorie", value: \.category)
                .width(min: 100, ideal: 170)

            TableColumn("Montant", value: \.amount) { row in
                Text(row.amount, format: .currency(code: currency))
                    .monospacedDigit()
                    .foregroundStyle(row.amount > 0 ? Color.green : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Mémo", value: \.memo)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let row = rows.first(where: { $0.id == ids.first }) {
                Button("Modifier…") { transactionToEdit = row.transaction }
            }
        } primaryAction: { ids in
            if ids.count == 1, let row = rows.first(where: { $0.id == ids.first }) {
                transactionToEdit = row.transaction
            }
        }
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    /// Catégories retenues : la catégorie et ses sous-catégories
    private var categoryIDs: Set<UUID> {
        Set([scope.id] + categoriesController.getSubcategories(for: scope.id).map { $0.id })
    }

    private var rows: [Row] {
        let categoryIDs = scope.kind == .category ? self.categoryIDs : []
        let accountNames = Dictionary(accountsController.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let payeeNames = Dictionary(payeesController.payees.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let query = searchText.trimmingCharacters(in: .whitespaces)

        let rows: [Row] = transactionsController.allTransactions.compactMap { transaction in
            switch scope.kind {
            case .payee:
                guard transaction.payeeID == scope.id else { return nil }
            case .category:
                guard let categoryID = transaction.categoryID, categoryIDs.contains(categoryID) else { return nil }
            }

            let row = Row(
                id: transaction.id,
                date: transaction.date,
                account: accountNames[transaction.accountID] ?? "",
                payee: transaction.payeeID.flatMap { payeeNames[$0] } ?? "",
                category: transaction.categoryID.map { categoriesController.getCategoryPath(for: $0) } ?? "",
                amount: transaction.signedAmount,
                memo: transaction.memo ?? "",
                transaction: transaction
            )

            guard query.isEmpty
                    || row.payee.localizedCaseInsensitiveContains(query)
                    || row.category.localizedCaseInsensitiveContains(query)
                    || row.memo.localizedCaseInsensitiveContains(query)
                    || row.account.localizedCaseInsensitiveContains(query) else { return nil }
            return row
        }

        return rows.sorted(using: sortOrder)
    }

    private func statusItems(_ rows: [Row]) -> [String] {
        var items = ["\(rows.count) transaction\(rows.count > 1 ? "s" : "")"]
        if !appSettings.hideAmounts, !rows.isEmpty {
            let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
            items.append("Total : \(total.formatted(.currency(code: currency)))")
        }
        return items
    }
}
