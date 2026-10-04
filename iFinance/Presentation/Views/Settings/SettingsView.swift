import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Fenêtre Réglages (⌘,) : onglets Général, Livres, Comptes, Données, Confidentialité.
// Les préférences simples sont stockées dans UserDefaults sous les clés de SettingsKeys.

enum SettingsKeys {
    static let startScreen = "startScreen"
    static let reportsDefaultPeriod = "reportsDefaultPeriod"
    static let showSidebarBalances = "showSidebarBalances"
    static let showClosedAccountsInSidebar = "showClosedAccountsInSidebar"
    static let hideAmountsAtLaunch = "hideAmountsAtLaunch"
}

struct SettingsView: View {

    /// Destinations de navigation encore utilisées par l'écran Budgets de la fenêtre principale
    enum Destination: Hashable {
        case accounts
        case payees
        case categories
        case budgets
        case budget(Budget)
    }

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Général", systemImage: "gearshape") }

            BooksSettingsTab()
                .tabItem { Label("Livres", systemImage: "book.closed") }

            AccountsSettingsTab()
                .tabItem { Label("Comptes", systemImage: "creditcard") }

            DataSettingsTab()
                .tabItem { Label("Données", systemImage: "cylinder.split.1x2") }

            PrivacySettingsTab()
                .tabItem { Label("Confidentialité", systemImage: "lock") }
        }
        .frame(width: 720, height: 520)
    }
}

// MARK: - Général

struct GeneralSettingsTab: View {
    @EnvironmentObject var appSettings: AppSettings

    @AppStorage(SettingsKeys.startScreen) private var startScreen = "dashboard"
    @AppStorage(SettingsKeys.reportsDefaultPeriod) private var reportsDefaultPeriod = "all"
    @AppStorage(SettingsKeys.showSidebarBalances) private var showSidebarBalances = true
    @AppStorage(SettingsKeys.showClosedAccountsInSidebar) private var showClosedAccounts = true

    var body: some View {
        Form {
            Section {
                Picker("Apparence", selection: Binding(
                    get: { appSettings.theme },
                    set: { appSettings.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Couleur d'accent") {
                    Text("Système")
                        .foregroundStyle(.secondary)
                }

                Text("La couleur d'accent suit le réglage de macOS, dans Réglages Système › Apparence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Écran à l'ouverture", selection: $startScreen) {
                    Text("Vue d'ensemble").tag("dashboard")
                    Text("Toutes les transactions").tag("transactions")
                    Text("Budgets").tag("budgets")
                    Text("Rapports").tag("reports")
                }

                Picker("Période par défaut des rapports", selection: $reportsDefaultPeriod) {
                    Text("Toute la période").tag("all")
                    Text("12 derniers mois").tag("last12")
                }
            }

            Section("Barre latérale") {
                Toggle("Afficher les soldes", isOn: $showSidebarBalances)
                Toggle("Afficher les comptes clos", isOn: $showClosedAccounts)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Livres

struct BooksSettingsTab: View {
    @EnvironmentObject var booksController: BooksController

    @State private var selection: Book.ID?
    @State private var editedName = ""
    @State private var showBookForm = false
    @State private var bookToDelete: Book?
    @State private var showDeleteConfirmation = false

    private var selectedBook: Book? {
        booksController.books.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 12) {
            Table(booksController.books, selection: $selection) {
                TableColumn("Livre") { book in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(book.color.map { Color(hex: $0) } ?? Color.accentColor)
                            .frame(width: 10, height: 10)
                        Text(book.name)
                    }
                }

                TableColumn("Devise") { book in
                    Text(book.currency)
                        .foregroundStyle(.secondary)
                }
                .width(60)

                TableColumn("Créé le") { book in
                    Text(book.createdAt, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(.secondary)
                }
                .width(110)

                TableColumn("État") { book in
                    Text(stateLabel(for: book))
                        .foregroundStyle(book.id == booksController.currentBook?.id ? Color.primary : Color.secondary)
                }
                .width(90)
            }
            .frame(minHeight: 150)

            HStack(spacing: 8) {
                Button {
                    showBookForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Nouveau livre")

                Button {
                    bookToDelete = selectedBook
                    showDeleteConfirmation = selectedBook != nil
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedBook == nil)
                .help("Supprimer le livre")

                Spacer()

                if let book = selectedBook {
                    if book.isArchived {
                        Button("Désarchiver") {
                            Task { await booksController.unarchiveBook(id: book.id) }
                        }
                    } else {
                        Button("Archiver") {
                            Task { await booksController.archiveBook(id: book.id) }
                        }

                        Button("Ouvrir") {
                            booksController.selectBook(book)
                        }
                        .disabled(book.id == booksController.currentBook?.id)
                    }
                }
            }

            if let book = selectedBook {
                Form {
                    TextField("Nom", text: $editedName)
                        .onSubmit { rename(book) }

                    LabeledContent("Couleur") {
                        HStack(spacing: 8) {
                            ForEach(BookFormView.palette, id: \.hex) { item in
                                Button {
                                    setColor(item.hex, for: book)
                                } label: {
                                    Circle()
                                        .fill(Color(hex: item.hex))
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: book.color == item.hex ? 2 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.name)
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    LabeledContent("Devise principale") {
                        Text(book.currency)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: 170)
            } else {
                Text("Sélectionnez un livre pour le modifier.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
        .padding(16)
        .onAppear {
            if selection == nil {
                selection = booksController.currentBook?.id
            }
            editedName = selectedBook?.name ?? ""
        }
        .onChange(of: selection) { _, _ in
            editedName = selectedBook?.name ?? ""
        }
        .sheet(isPresented: $showBookForm) {
            BookFormView(isPresented: $showBookForm)
        }
        .alert("Supprimer le livre ?", isPresented: $showDeleteConfirmation, presenting: bookToDelete) { book in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task {
                    await booksController.deleteBook(id: book.id)
                    selection = booksController.currentBook?.id
                }
            }
        } message: { book in
            Text("Le livre « \(book.name) » sera supprimé avec tous ses comptes, transactions, catégories et budgets. Cette action est irréversible.")
        }
    }

    private func stateLabel(for book: Book) -> String {
        if book.isArchived { return "Archivé" }
        return book.id == booksController.currentBook?.id ? "Ouvert" : "Disponible"
    }

    private func rename(_ book: Book) {
        let name = editedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != book.name else { return }
        var updated = book
        updated.name = name
        Task { await booksController.updateBook(updated) }
    }

    private func setColor(_ hex: String, for book: Book) {
        var updated = book
        updated.color = hex
        Task { await booksController.updateBook(updated) }
    }
}

// MARK: - Comptes

struct AccountsSettingsTab: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController

    @State private var selection: Account.ID?
    @State private var showAccountForm = false
    @State private var accountToEdit: Account?
    @State private var accountToDelete: Account?
    @State private var showDeleteConfirmation = false

    private var accounts: [Account] {
        accountsController.accounts.sorted { lhs, rhs in
            if lhs.isClosed != rhs.isClosed { return !lhs.isClosed }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedAccount: Account? {
        accountsController.accounts.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tous les comptes du livre « \(booksController.currentBook?.name ?? "—") », y compris ceux masqués de la barre latérale et les comptes clos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(accounts, selection: $selection) {
                TableColumn("Compte") { account in
                    Text(account.name)
                        .foregroundStyle(account.isClosed ? Color.secondary : Color.primary)
                }

                TableColumn("Type") { account in
                    Text(account.type.displayName)
                        .foregroundStyle(.secondary)
                }

                TableColumn("Barre latérale") { account in
                    flagToggle("Afficher dans la barre latérale", isOn: !account.isHiddenFromSidebar) { value in
                        var updated = account
                        updated.isHiddenFromSidebar = !value
                        return updated
                    }
                }
                .width(90)

                TableColumn("Patrimoine") { account in
                    flagToggle("Inclure dans le patrimoine net", isOn: !account.isExcludedFromReports) { value in
                        var updated = account
                        updated.isExcludedFromReports = !value
                        return updated
                    }
                }
                .width(80)

                TableColumn("Budgets") { account in
                    flagToggle("Compter dans les budgets", isOn: !account.isExcludedFromBudgets) { value in
                        var updated = account
                        updated.isExcludedFromBudgets = !value
                        return updated
                    }
                }
                .width(70)

                TableColumn("État") { account in
                    Text(account.isClosed ? "Clos" : "Ouvert")
                        .foregroundStyle(.secondary)
                }
                .width(60)
            }
            .contextMenu(forSelectionType: Account.ID.self) { _ in
                EmptyView()
            } primaryAction: { items in
                // Double-clic : modifier le compte
                if let id = items.first {
                    accountToEdit = accountsController.accounts.first { $0.id == id }
                }
            }

            HStack(spacing: 8) {
                Button {
                    showAccountForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Nouveau compte")

                Button {
                    accountToDelete = selectedAccount
                    showDeleteConfirmation = selectedAccount != nil
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedAccount == nil)
                .help("Supprimer le compte")

                Spacer()

                if let account = selectedAccount {
                    if account.isClosed {
                        Button("Rouvrir le compte") {
                            Task { await accountsController.reopenAccount(id: account.id) }
                        }
                    } else {
                        Button("Clore le compte") {
                            Task { await accountsController.closeAccount(id: account.id) }
                        }
                    }

                    Button("Modifier…") {
                        accountToEdit = account
                    }
                }
            }
        }
        .padding(16)
        .sheet(isPresented: $showAccountForm) {
            AccountFormView(isPresented: $showAccountForm)
        }
        .alert("Supprimer le compte ?", isPresented: $showDeleteConfirmation, presenting: accountToDelete) { account in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await delete(account) }
            }
        } message: { account in
            Text(deleteMessage(for: account))
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
    }

    private func deleteMessage(for account: Account) -> String {
        let count = transactionsController.allTransactions.filter { $0.accountID == account.id }.count
        let transactions = count == 0
            ? "Il ne contient aucune transaction."
            : "Ses \(count) transaction\(count > 1 ? "s" : "") seront supprimées avec lui."
        return "Le compte « \(account.name) » sera supprimé définitivement. \(transactions) Pour garder l'historique, clôturez plutôt le compte."
    }

    private func delete(_ account: Account) async {
        await accountsController.deleteAccount(id: account.id)
        if selection == account.id { selection = nil }
        // Les transactions du compte disparaissent avec lui : on recharge la liste
        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
    }

    /// Case à cocher centrée qui enregistre le compte modifié
    private func flagToggle(_ label: String, isOn: Bool, update: @escaping (Bool) -> Account) -> some View {
        Toggle(label, isOn: Binding(
            get: { isOn },
            set: { value in
                let updated = update(value)
                Task { await accountsController.updateAccount(updated) }
            }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Données

struct DataSettingsTab: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController

    @State private var exportError: String?
    @State private var showExportError = false
    @State private var showQIFImport = false
    @State private var showDuplicateDetection = false
    @State private var showDefaultCategoriesConfirmation = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Importer…") { showQIFImport = true }
                } label: {
                    Text("Importer des transactions")
                    Text("Fichier QIF exporté depuis votre banque.")
                }

                LabeledContent {
                    Button("Analyser…") { showDuplicateDetection = true }
                } label: {
                    Text("Détecter les doublons")
                    Text("Recherche les transactions identiques dans le livre courant.")
                }
            }

            Section {
                LabeledContent {
                    Button("Exporter…") { exportDatabase() }
                } label: {
                    Text("Exporter la base de données")
                    Text("Copie complète de tous les livres, à conserver comme sauvegarde.")
                }

                LabeledContent {
                    Button("Afficher dans le Finder") { revealDatabase() }
                        .disabled(databaseURL == nil)
                } label: {
                    Text("Emplacement de la base")
                    Text(databaseURL?.path ?? "Introuvable")
                        .textSelection(.enabled)
                }

                LabeledContent("Taille") {
                    Text(databaseSize)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    Button("Créer…") { showDefaultCategoriesConfirmation = true }
                        .disabled(booksController.currentBook == nil)
                } label: {
                    Text("Créer les catégories courantes")
                    Text("Ajoute le jeu de catégories par défaut au livre courant.")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Erreur d'export", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "Une erreur est survenue.")
        }
        .alert("Créer les catégories courantes ?", isPresented: $showDefaultCategoriesConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Créer") {
                if let bookID = booksController.currentBook?.id {
                    Task { await categoriesController.createDefaultCategories(for: bookID) }
                }
            }
        } message: {
            Text("Les catégories par défaut seront ajoutées au livre « \(booksController.currentBook?.name ?? "") ». Les catégories existantes ne sont pas modifiées.")
        }
        .sheet(isPresented: $showQIFImport) {
            QIFImportView(isPresented: $showQIFImport)
        }
        .sheet(isPresented: $showDuplicateDetection) {
            DuplicateDetectionView(isPresented: $showDuplicateDetection)
        }
    }

    // MARK: Base de données

    private var databaseURL: URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = appSupport.appendingPathComponent("iFinance/iFinance.sqlite")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private var databaseSize: String {
        guard let url = databaseURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? Int64 else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func revealDatabase() {
        guard let url = databaseURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportDatabase() {
        let fileManager = FileManager.default
        guard let sourceURL = databaseURL else {
            exportError = "Fichier de base de données introuvable."
            showExportError = true
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exporter la base de données"
        panel.nameFieldStringValue = "iFinance.sqlite"
        panel.allowedContentTypes = [.database]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                exportError = error.localizedDescription
                showExportError = true
            }
        }
    }
}

// MARK: - Confidentialité

struct PrivacySettingsTab: View {
    @EnvironmentObject var appSettings: AppSettings

    @AppStorage(SettingsKeys.hideAmountsAtLaunch) private var hideAmountsAtLaunch = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { appSettings.hideAmounts },
                    set: { appSettings.hideAmounts = $0 }
                )) {
                    Text("Masquer les montants")
                    Text("Floute tous les montants, pour montrer l'app sans dévoiler vos chiffres.")
                }

                Toggle(isOn: $hideAmountsAtLaunch) {
                    Text("Masquer les montants à l'ouverture")
                    Text("L'app démarre toujours avec les montants floutés.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vos données restent sur ce Mac")
                        .fontWeight(.semibold)
                    Text("iFinance ne se connecte à aucune banque et n'envoie rien à un serveur. L'app n'a pas d'accès réseau. Les fichiers importés sont lus localement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}
