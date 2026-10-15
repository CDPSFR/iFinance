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
    /// Objectif de taux d'épargne, en pourcentage des revenus (rapport « Taux d'épargne »)
    static let savingsRateGoal = "savingsRateGoal"
    /// Onglet affiché dans la fenêtre des réglages (mémorisé, et modifiable depuis la fenêtre principale)
    static let selectedSettingsTab = "selectedSettingsTab"
}

/// Onglets de la fenêtre des réglages
enum SettingsTab: String {
    case general, books, accounts, data, backups, privacy
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

    @AppStorage(SettingsKeys.selectedSettingsTab) private var selectedTab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("Général", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)

            BooksSettingsTab()
                .tabItem { Label("Livres", systemImage: "book.closed") }
                .tag(SettingsTab.books.rawValue)

            AccountsSettingsTab()
                .tabItem { Label("Comptes", systemImage: "creditcard") }
                .tag(SettingsTab.accounts.rawValue)

            DataSettingsTab()
                .tabItem { Label("Données", systemImage: "cylinder.split.1x2") }
                .tag(SettingsTab.data.rawValue)

            BackupSettingsTab()
                .tabItem { Label("Sauvegardes", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.backups.rawValue)

            PrivacySettingsTab()
                .tabItem { Label("Confidentialité", systemImage: "lock") }
                .tag(SettingsTab.privacy.rawValue)
        }
        .frame(width: 720, height: 560)
    }
}

// MARK: - Général

struct GeneralSettingsTab: View {
    @EnvironmentObject var appSettings: AppSettings

    @AppStorage(SettingsKeys.startScreen) private var startScreen = "dashboard"
    @AppStorage(SettingsKeys.reportsDefaultPeriod) private var reportsDefaultPeriod = "all"
    @AppStorage(SettingsKeys.showSidebarBalances) private var showSidebarBalances = true
    @AppStorage(SettingsKeys.showClosedAccountsInSidebar) private var showClosedAccounts = true
    @AppStorage(SettingsKeys.savingsRateGoal) private var savingsRateGoal = 15.0

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

                Stepper(value: $savingsRateGoal, in: 0...80, step: 1) {
                    LabeledContent("Objectif de taux d'épargne") {
                        Text("\(Int(savingsRateGoal)) % des revenus")
                            .monospacedDigit()
                    }
                }
                .help("Part des revenus que vous visez de mettre de côté chaque mois ; sert de repère au rapport « Taux d'épargne ».")
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
    @EnvironmentObject var bookLock: BookLockController

    @State private var selection: Book.ID?
    @State private var editedName = ""
    @State private var showBookForm = false
    @State private var bookToDelete: Book?
    @State private var showDeleteConfirmation = false
    /// Mot de passe demandé pour supprimer un livre protégé
    @State private var deletePassword = ""
    @State private var deleteError: String?

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
                        if book.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Protégé par un mot de passe")
                        }
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
            // Mêmes marges que les cartes du formulaire en dessous (le style groupé ajoute 20 pt)
            .padding(.horizontal, 20)

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
            .padding(.horizontal, 20)

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

                    BookProtectionSection(book: book)
                }
                .formStyle(.grouped)
                .frame(minHeight: 300)
            } else {
                Text("Sélectionnez un livre pour le modifier.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
        .padding(.vertical, 16)
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
            if book.isProtected {
                SecureField("Mot de passe du livre", text: $deletePassword)
            }
            Button("Annuler", role: .cancel) { deletePassword = "" }
            Button("Supprimer", role: .destructive) {
                let password = deletePassword
                deletePassword = ""
                Task {
                    // Un livre protégé ne se supprime qu'avec son mot de passe
                    if book.isProtected, !(await bookLock.verifyPassword(book.id, password: password)) {
                        deleteError = "Mot de passe incorrect : le livre « \(book.name) » n'a pas été supprimé."
                        return
                    }
                    await booksController.deleteBook(id: book.id)
                    selection = booksController.currentBook?.id
                }
            }
        } message: { book in
            Text("Le livre « \(book.name) » sera supprimé avec tous ses comptes, transactions, catégories et budgets. Cette action est irréversible.")
        }
        .alert("Suppression impossible", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteError ?? "")
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
    @EnvironmentObject var appState: AppState
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
                    Text("Relevé QIF ou OFX exporté depuis votre banque.")
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
                        .disabled(booksController.currentBook == nil)
                } label: {
                    Text("Exporter le livre")
                    Text("Copie de la base du livre « \(booksController.currentBook?.name ?? "—") », non chiffrée. Pour tous les livres, utilisez les sauvegardes, qui sont chiffrées.")
                }

                LabeledContent {
                    Button("Afficher dans le Finder") { revealDatabase() }
                        .disabled(databaseURL == nil)
                } label: {
                    Text("Emplacement des données")
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
            StatementImportView(isPresented: $showQIFImport)
        }
        .sheet(isPresented: $showDuplicateDetection) {
            DuplicateDetectionView(isPresented: $showDuplicateDetection)
        }
    }

    // MARK: Base de données

    /// Dossier des données : catalogue des livres et un fichier par livre
    private var databaseURL: URL? {
        let url = appState.library.directory
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var databaseSize: String {
        let bytes = appState.library.totalSize
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "—"
    }

    private func revealDatabase() {
        guard let url = databaseURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Exporte une copie cohérente de la base du livre ouvert
    private func exportDatabase() {
        guard let book = booksController.currentBook else { return }
        let panel = NSSavePanel()
        panel.title = "Exporter le livre"
        panel.nameFieldStringValue = "\(book.name).sqlite"
        panel.allowedContentTypes = [.database]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                try appState.library.copyOpenBook(to: destinationURL)
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
    @EnvironmentObject var bookLock: BookLockController

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
                Picker(selection: $bookLock.autoLockMinutes) {
                    ForEach(BookLockController.autoLockChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Jamais" : "Après \(minutes) min d'inactivité").tag(minutes)
                    }
                } label: {
                    Text("Verrouiller les livres protégés")
                    Text("Aussi à la mise en veille, au verrouillage de l'écran, en changeant de livre et avec ⌘L.")
                }
            }

            QuoteSettingsSection()

            InflationSettingsSection()

            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vos données restent sur ce Mac")
                        .fontWeight(.semibold)
                    Text("iFinance ne se connecte à aucune banque. Vos comptes, transactions et montants ne quittent jamais ce Mac, et les fichiers importés sont lus localement. Les seules connexions possibles sont la mise à jour des cours et celle des indices INSEE ci-dessus, si vous les activez.")
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
