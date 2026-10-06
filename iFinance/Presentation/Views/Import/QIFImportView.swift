import SwiftUI
import UniformTypeIdentifiers

struct QIFImportView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    enum Step { case pickFile, preview, importing, done }
    @State private var step: Step = .pickFile

    @State private var selectedAccountID: UUID? = nil
    @State private var parsedTransactions: [QIFTransaction] = []
    @State private var importedCount = 0
    @State private var createdPayees: [String] = []
    @State private var errorMessage: String? = nil
    @State private var selectedFileName: String = ""
    @State private var selected: Set<Int> = []
    @State private var dateAnalysis: QIFDateAnalysis? = nil
    @State private var dateOrder: QIFDateOrder = .dayMonth

    private var currency: String { booksController.currentBook?.currency ?? "EUR" }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Importer un fichier QIF")

            switch step {
            case .pickFile:  pickFileView
            case .preview:   previewView
            case .importing: importingView
            case .done:      doneView
            }

            // Pied commun : les boutons dépendent de l'étape (aucun pendant l'import)
            if step != .importing {
                SheetFooter {
                    if step == .preview {
                        Button("Retour") {
                            step = .pickFile
                            parsedTransactions = []
                            selected = []
                            dateAnalysis = nil
                        }

                        Text("\(selected.count) transaction(s) à importer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } actions: {
                    if step == .done {
                        Button("Fermer") { isPresented = false }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Annuler") { isPresented = false }
                            .keyboardShortcut(.cancelAction)

                        if step == .preview {
                            Button("Importer") {
                                Task { await doImport() }
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(selected.isEmpty)
                        }
                    }
                }
            }
        }
        .frame(width: 620, height: 560)
        .sheetBackground()
    }

    // MARK: - Step 1: Pick file & account

    private var pickFileView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue.opacity(0.7))

            Text("Sélectionnez un fichier QIF et le compte cible")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Compte de destination")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Compte", selection: $selectedAccountID) {
                    Text("Choisir un compte…").tag(nil as UUID?)
                    ForEach(accountsController.activeAccounts) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 300)
            }

            Button {
                openFilePicker()
            } label: {
                Label(selectedFileName.isEmpty ? "Choisir un fichier QIF" : selectedFileName,
                      systemImage: "doc.badge.plus")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.bordered)
            .disabled(selectedAccountID == nil)

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Step 2: Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(parsedTransactions.count) transactions trouvées", systemImage: "list.bullet")
                    .font(.subheadline)
                Spacer()
                Button(selected.count == parsedTransactions.count ? "Tout désélectionner" : "Tout sélectionner") {
                    if selected.count == parsedTransactions.count {
                        selected.removeAll()
                    } else {
                        selected = Set(parsedTransactions.indices)
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            dateFormatBar

            Divider()

            List {
                ForEach(parsedTransactions.indices, id: \.self) { i in
                    let tx = parsedTransactions[i]
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(i) },
                            set: { if $0 { selected.insert(i) } else { selected.remove(i) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .disabled(tx.date == nil)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.payee ?? tx.memo ?? "Transaction")
                                .font(.body)
                            HStack(spacing: 6) {
                                if let date = tx.date {
                                    Text(date, format: .dateTime.day().month().year())
                                        .font(.caption).foregroundColor(.secondary)
                                    Text("·").font(.caption).foregroundColor(.secondary)
                                } else {
                                    Text("Date illisible : \(tx.rawDate ?? "absente")")
                                        .font(.caption).foregroundColor(.red)
                                }
                                if let cat = tx.category {
                                    Text(cat).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        if let amount = tx.amount {
                            Text(amount, format: .currency(code: currency))
                                .fontWeight(.medium)
                                .foregroundColor(amount >= 0 ? .green : .red)
                                .privacyBlur(hidden: appSettings.hideAmounts)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
    }

    /// Format des dates du fichier : détecté sur l'ensemble des lignes, modifiable
    private var dateFormatBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Format des dates")
                    .font(.subheadline)
                Spacer()
                Picker("Format des dates", selection: $dateOrder) {
                    ForEach(QIFDateOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if let hint = dateFormatHint {
                Label(hint.text, systemImage: hint.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(hint.isWarning ? .orange : .secondary)
            }

            if undatedCount > 0 {
                Label("\(undatedCount) transaction(s) sans date lisible : elles ne seront pas importées.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .onChange(of: dateOrder) { _, order in
            parsedTransactions = QIFParser.applyDateOrder(order, to: parsedTransactions)
            selected = selected.filter { parsedTransactions[$0].date != nil }
        }
    }

    private var undatedCount: Int {
        parsedTransactions.filter { $0.date == nil }.count
    }

    private var dateFormatHint: (text: String, isWarning: Bool)? {
        guard let analysis = dateAnalysis else { return nil }
        if analysis.isInconsistent {
            return ("Le fichier mélange les deux formats (\(analysis.dayFirstCount) ligne(s) JJ/MM, \(analysis.monthFirstCount) ligne(s) MM/JJ). Vérifiez les dates.", true)
        }
        if analysis.isAmbiguous {
            return ("Aucune date ne permet de trancher (jour et mois toujours ≤ 12). Vérifiez l'aperçu.", true)
        }
        let count = analysis.order == .dayMonth ? analysis.dayFirstCount : analysis.monthFirstCount
        return ("Format \(analysis.order.displayName) détecté sur \(count) date(s) sans ambiguïté.", false)
    }

    // MARK: - Step 3: Importing

    private var importingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView("Import en cours…")
            Spacer()
        }
    }

    // MARK: - Step 4: Done

    private var doneView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Transactions summary
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        Text("\(importedCount) transaction(s) importée(s)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 24)

                    Divider()

                    // Payees summary
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: createdPayees.isEmpty ? "person.crop.circle" : "person.crop.circle.badge.plus")
                                .foregroundColor(createdPayees.isEmpty ? .secondary : .orange)
                            Text(createdPayees.isEmpty
                                 ? "Aucun nouveau bénéficiaire créé"
                                 : "\(createdPayees.count) bénéficiaire(s) créé(s)")
                                .font(.headline)
                                .foregroundColor(createdPayees.isEmpty ? .secondary : .primary)
                            Spacer()
                        }

                        if !createdPayees.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(createdPayees, id: \.self) { name in
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text(name)
                                            .font(.body)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Choisir un fichier QIF"
        panel.allowedContentTypes = [UTType(filenameExtension: "qif") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let txs = try QIFParser.parse(url: url)
                if txs.isEmpty {
                    errorMessage = "Aucune transaction trouvée dans ce fichier."
                    return
                }
                let analysis = QIFParser.analyzeDates(txs)
                dateAnalysis = analysis
                dateOrder = analysis.order
                parsedTransactions = txs
                // Les lignes sans date lisible ne sont pas importables
                selected = Set(txs.indices.filter { txs[$0].date != nil })
                selectedFileName = url.lastPathComponent
                errorMessage = nil
                step = .preview
            } catch {
                errorMessage = "Erreur de lecture : \(error.localizedDescription)"
            }
        }
    }

    private func doImport() async {
        guard let accountID = selectedAccountID,
              let bookID = booksController.currentBook?.id else { return }
        step = .importing

        // Make sure payees are loaded
        await payeesController.loadPayees(for: bookID)

        // Jamais de date de substitution : une ligne sans date lisible n'est pas importée
        let toImport = selected.sorted().map { parsedTransactions[$0] }.filter { $0.date != nil }
        var count = 0
        var newPayeeNames: [String] = []

        for tx in toImport {
            guard let date = tx.date else { continue }

            // Resolve or create payee
            let payee = await resolvePayee(name: tx.payee, bookID: bookID, newPayeeNames: &newPayeeNames)

            let amount = tx.amount ?? 0
            let type: TransactionType = amount >= 0 ? .credit : .debit

            await transactionsController.createTransaction(
                accountID: accountID,
                date: date,
                amount: abs(amount),
                type: type,
                payeeID: payee?.id,
                categoryID: payee?.defaultCategoryID,
                memo: [tx.memo, tx.category]
                    .compactMap { $0 }
                    .joined(separator: " – ")
                    .nilIfEmpty
            )
            count += 1
        }

        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
        importedCount = count
        createdPayees = newPayeeNames
        step = .done
    }

    /// Returns the existing or newly created `Payee` matching `name`.
    /// Appends the name to `newPayeeNames` if a new payee was created.
    private func resolvePayee(name: String?, bookID: UUID, newPayeeNames: inout [String]) async -> Payee? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }

        // Look for existing payee (case-insensitive)
        if let existing = payeesController.payees.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }

        // Create new payee
        await payeesController.createPayee(bookID: bookID, name: name)

        // Find the newly created payee
        if let created = payeesController.payees.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            newPayeeNames.append(created.name)
            return created
        }

        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
