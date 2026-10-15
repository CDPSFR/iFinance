import SwiftUI
import UniformTypeIdentifiers

/// Export du livre ouvert : base SQLite complète, ou relevés QIF / OFX des comptes choisis
struct BookExportView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController

    enum Format: String, CaseIterable, Identifiable {
        case sqlite, qif, ofx
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sqlite: return "SQLite"
            case .qif: return "QIF"
            case .ofx: return "OFX"
            }
        }
        var detail: String {
            switch self {
            case .sqlite: return "Copie complète de la base du livre : comptes, opérations, budgets, projets, placements. Pour l'archiver ou l'ouvrir avec un outil SQLite."
            case .qif: return "Un fichier par compte, lisible par la plupart des logiciels de comptes. Catégories et virements inclus."
            case .ofx: return "Un seul fichier avec un relevé par compte et son solde, au format des banques. Réimportable dans iFinance sans doublons."
            }
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case all, thisYear, lastYear, last12Months
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Toutes les opérations"
            case .thisYear: return "Cette année"
            case .lastYear: return "L'année dernière"
            case .last12Months: return "Les 12 derniers mois"
            }
        }
        /// Début (nil : depuis la première opération) et fin incluse
        func range(now: Date = Date(), calendar: Calendar = .current) -> (start: Date?, end: Date) {
            let today = calendar.startOfDay(for: now)
            let year = calendar.component(.year, from: now)
            switch self {
            case .all: return (nil, today)
            case .thisYear: return (calendar.date(from: DateComponents(year: year, month: 1, day: 1)), today)
            case .lastYear:
                return (calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1)),
                        calendar.date(from: DateComponents(year: year - 1, month: 12, day: 31)) ?? today)
            case .last12Months: return (calendar.date(byAdding: .month, value: -12, to: today), today)
            }
        }
    }

    @State private var format: Format = .ofx
    @State private var period: Period = .all
    @State private var selectedAccounts: Set<UUID> = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var doneMessage: String?

    private var bookName: String { booksController.currentBook?.name ?? "iFinance" }
    private var accounts: [Account] {
        accountsController.accounts.sorted { ($0.isClosed ? 1 : 0, $0.name) < ($1.isClosed ? 1 : 0, $1.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Exporter le livre", subtitle: bookName)

            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(format.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if format != .sqlite {
                    Section {
                        Picker("Période", selection: $period) {
                            ForEach(Period.allCases) { Text($0.title).tag($0) }
                        }
                    }

                    Section {
                        ForEach(accounts) { account in
                            Toggle(isOn: Binding(
                                get: { selectedAccounts.contains(account.id) },
                                set: { if $0 { selectedAccounts.insert(account.id) } else { selectedAccounts.remove(account.id) } }
                            )) {
                                Label(account.isClosed ? "\(account.name) (clos)" : account.name, systemImage: account.type.icon)
                            }
                            .toggleStyle(.checkbox)
                        }
                    } header: {
                        HStack {
                            Text("Comptes")
                            Spacer()
                            Button(selectedAccounts.count == accounts.count ? "Tout désélectionner" : "Tout sélectionner") {
                                selectedAccounts = selectedAccounts.count == accounts.count ? [] : Set(accounts.map(\.id))
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }

                Section {
                    Label("Le fichier exporté n'est pas chiffré, même si le livre est protégé par un mot de passe.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let doneMessage {
                        Label(doneMessage, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                if isWorking { ProgressView().controlSize(.small) }
            } actions: {
                Button(doneMessage == nil ? "Annuler" : "Fermer") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Exporter…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || (format != .sqlite && selectedAccounts.isEmpty))
            }
        }
        .frame(width: 520, height: 560)
        .sheetBackground()
        .onAppear { selectedAccounts = Set(accountsController.activeAccounts.map(\.id)) }
    }

    // MARK: - Export

    private func export() {
        errorMessage = nil
        doneMessage = nil
        switch format {
        case .sqlite:
            save(name: "\(bookName).sqlite", type: .database) { url in
                try appState.library.copyOpenBook(to: url)
                return "Base du livre exportée."
            }
        case .ofx:
            save(name: "\(bookName).ofx", type: UTType(filenameExtension: "ofx") ?? .data) { url in
                let range = period.range()
                let exported = try await collect(range)
                let text = StatementExporter.ofx(exported, names: names, start: range.start, end: range.end)
                try text.write(to: url, atomically: true, encoding: .utf8)
                return "\(exported.count) compte(s), \(exported.reduce(0) { $0 + $1.transactions.count }) opération(s) exportés."
            }
        case .qif:
            exportQIF()
        }
    }

    /// QIF : un fichier par compte, dans le dossier choisi (fenêtre d'enregistrement pour un seul compte)
    private func exportQIF() {
        let chosen = accounts.filter { selectedAccounts.contains($0.id) }
        if chosen.count == 1, let account = chosen.first {
            save(name: "\(bookName) - \(account.name).qif", type: UTType(filenameExtension: "qif") ?? .data) { url in
                let exported = try await collect(period.range())
                try StatementExporter.qif(exported[0], names: names).write(to: url, atomically: true, encoding: .utf8)
                return "\(exported[0].transactions.count) opération(s) exportée(s)."
            }
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Dossier des fichiers QIF"
        panel.message = "Un fichier par compte sera créé dans ce dossier."
        panel.prompt = "Exporter"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            run {
                let exported = try await collect(period.range())
                for item in exported {
                    let url = uniqueURL(in: folder, name: "\(bookName) - \(item.account.name)", ext: "qif")
                    try StatementExporter.qif(item, names: names).write(to: url, atomically: true, encoding: .utf8)
                }
                return "\(exported.count) fichier(s) QIF créé(s)."
            }
        }
    }

    private func save(name: String, type: UTType, write: @escaping (URL) async throws -> String) {
        let panel = NSSavePanel()
        panel.title = "Exporter le livre"
        panel.nameFieldStringValue = sanitized(name)
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            run { try await write(url) }
        }
    }

    private func run(_ work: @escaping () async throws -> String) {
        isWorking = true
        Task {
            do {
                doneMessage = try await work()
            } catch {
                errorMessage = "L'export a échoué : \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    /// Opérations de la période pour chaque compte choisi (lues dans la base, comptes clos compris)
    private func collect(_ range: (start: Date?, end: Date)) async throws -> [ExportedAccount] {
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: range.end) ?? range.end
        var result: [ExportedAccount] = []
        for account in accounts where selectedAccounts.contains(account.id) {
            let all = try await transactionsController.fetchTransactions(for: account.id).filter { $0.status != .skipped }
            let inPeriod = all.filter { tx in tx.date < endOfDay && (range.start.map { tx.date >= $0 } ?? true) }
            let balance = account.initialBalance + all.filter { $0.date < endOfDay }.reduce(Decimal(0)) { $0 + $1.signedAmount }
            result.append(ExportedAccount(account: account, transactions: inPeriod, closingBalance: balance))
        }
        return result
    }

    private var names: ExportNames {
        let payees = Dictionary(payeesController.payees.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let accountNames = Dictionary(accountsController.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let categories = categoriesController
        return ExportNames(
            payee: { payees[$0] },
            category: { id in
                guard let category = categories.getCategory(id: id) else { return nil }
                if let parent = category.parentID.flatMap({ categories.getCategory(id: $0) }) {
                    return "\(parent.name):\(category.name)"
                }
                return category.name
            },
            account: { accountNames[$0] }
        )
    }

    private func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        let base = sanitized(name)
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(index)).\(ext)")
            index += 1
        }
        return url
    }
}
