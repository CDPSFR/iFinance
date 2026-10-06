import SwiftUI
import UniformTypeIdentifiers

struct QIFImportView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var recurringController: RecurringController
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
    @State private var progressText = "Import en cours…"
    @State private var importError: String? = nil
    /// Lignes dont l'utilisateur a retiré le rapprochement avec une récurrence
    @State private var unlinked: Set<Int> = []
    @State private var reconciledCount = 0

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
                            unlinked = []
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
        .alert("Import impossible", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
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
        let matches = recurringMatches
        return VStack(spacing: 0) {
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

            if !matches.isEmpty {
                recurringSummary(matches)
            }

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
                            if let match = matches[i] {
                                recurringBadge(match, line: i)
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
            unlinked = []
            deselectAlreadyPosted()
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

    // MARK: - Récurrences

    /// Rapprochement des lignes avec les récurrences du compte de destination
    private var recurringMatches: [Int: RecurringImportMatch] {
        guard let accountID = selectedAccountID else { return [:] }
        let payeeNames = Dictionary(payeesController.payees.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let matcher = RecurringImportMatcher(
            templates: recurringController.templates,
            existingTransactions: transactionsController.allTransactions.filter { $0.accountID == accountID },
            payeeName: { payeeNames[$0] }
        )
        let lines = parsedTransactions.map { tx in
            tx.date.map { RecurringImportMatcher.Line(date: $0, amount: tx.amount ?? 0, payee: tx.payee) }
        }
        return matcher.matches(for: lines, accountID: accountID, excluded: unlinked)
    }

    /// Les lignes déjà saisies par une récurrence ne sont pas importées par défaut
    private func deselectAlreadyPosted() {
        for (index, match) in recurringMatches {
            if case .alreadyPosted = match { selected.remove(index) }
        }
    }

    private func recurringName(_ template: RecurringTemplate) -> String {
        template.payeeID.flatMap { id in payeesController.payees.first { $0.id == id }?.name }
            ?? template.memo
            ?? "Récurrence"
    }

    private func recurringSummary(_ matches: [Int: RecurringImportMatch]) -> some View {
        let posted = matches.values.filter { if case .alreadyPosted = $0 { return true } else { return false } }.count
        let reconciled = matches.count - posted
        var parts: [String] = []
        if reconciled > 0 { parts.append("\(reconciled) échéance\(reconciled > 1 ? "s" : "") reconnue\(reconciled > 1 ? "s" : "")") }
        if posted > 0 { parts.append("\(posted) déjà saisie\(posted > 1 ? "s" : "") (décochée\(posted > 1 ? "s" : ""))") }
        return Label(parts.joined(separator: " · "), systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .help("Les lignes reconnues sont rattachées à leur récurrence, qui avance à l'échéance suivante")
    }

    private func recurringBadge(_ match: RecurringImportMatch, line: Int) -> some View {
        let name = recurringName(match.template)
        let text: String
        let color: Color
        switch match {
        case .occurrence(_, let dueDate):
            text = "\(name) · échéance du \(dueDate.formatted(.dateTime.day().month()))"
            color = .accentColor
        case .alreadyPosted:
            text = "Déjà saisie par la récurrence « \(name) »"
            color = .orange
        }
        return HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(text)
            Button {
                unlinked.insert(line)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Ne pas rattacher cette ligne à la récurrence")
        }
        .font(.caption)
        .foregroundColor(color)
    }

    // MARK: - Step 3: Importing

    private var importingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(progressText)
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

                        if reconciledCount > 0 {
                            Label("\(reconciledCount) échéance(s) récurrente(s) rapprochée(s)", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
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
                unlinked = []
                deselectAlreadyPosted()
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
        progressText = "Préparation…"
        await Task.yield()

        await payeesController.loadPayees(for: bookID)

        // Jamais de date de substitution : une ligne sans date lisible n'est pas importée
        let importedIndices = selected.sorted().filter { parsedTransactions[$0].date != nil }
        let toImport = importedIndices.map { parsedTransactions[$0] }

        // Échéances réglées par l'import. Une récurrence n'avance que sur des échéances
        // consécutives importées : après une ligne décochée, les suivantes ne sont pas rattachées.
        var settled: [Int: RecurringTemplate] = [:]
        var lastDueDates: [UUID: Date] = [:]
        let occurrenceMatches = recurringMatches.compactMap { index, match -> (Int, RecurringTemplate, Date)? in
            if case .occurrence(let template, let dueDate) = match { return (index, template, dueDate) }
            return nil
        }
        for (templateID, group) in Dictionary(grouping: occurrenceMatches, by: { $0.1.id }) {
            for (index, template, dueDate) in group.sorted(by: { $0.2 < $1.2 }) {
                guard selected.contains(index) else { break }
                settled[index] = template
                lastDueDates[templateID] = dueDate
            }
        }

        // Bénéficiaires : recherche par nom (sans tenir compte de la casse) en accès direct,
        // puis création de tous les nouveaux en une seule écriture
        func key(_ name: String) -> String { name.folding(options: .caseInsensitive, locale: .current) }
        var payeesByKey: [String: Payee] = [:]
        for payee in payeesController.payees where payeesByKey[key(payee.name)] == nil {
            payeesByKey[key(payee.name)] = payee
        }
        var newNames: [String] = []
        var seen = Set<String>()
        for (index, tx) in zip(importedIndices, toImport) {
            // Une ligne rattachée prend le bénéficiaire de sa récurrence ; un virement n'en a pas
            if let template = settled[index], template.payeeID != nil || template.isTransfer { continue }
            guard let name = tx.payee?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            let nameKey = key(name)
            if payeesByKey[nameKey] == nil, seen.insert(nameKey).inserted {
                newNames.append(name)
            }
        }

        do {
            if !newNames.isEmpty {
                progressText = "Création de \(newNames.count) bénéficiaire(s)…"
                await Task.yield()
                for payee in try await payeesController.createPayees(bookID: bookID, names: newNames) {
                    payeesByKey[key(payee.name)] = payee
                }
            }

            progressText = "Écriture de \(toImport.count) transaction(s)…"
            await Task.yield()
            // Virement récurrent : la ligne devient un côté du virement, l'autre côté est créé sur
            // l'autre compte. Le lien du côté importé est posé après l'écriture (clé étrangère).
            var transferLinks: [Transaction] = []
            let transactions: [Transaction] = zip(importedIndices, toImport).flatMap { index, tx -> [Transaction] in
                guard let date = tx.date else { return [] }
                let payee = tx.payee
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .flatMap { payeesByKey[key($0)] }
                let amount = tx.amount ?? 0
                let template = settled[index]
                let memo = [tx.memo, tx.category].compactMap { $0 }.joined(separator: " – ").nilIfEmpty

                if let template, template.isTransfer,
                   let otherAccountID = accountID == template.accountID ? template.toAccountID : template.accountID {
                    var imported = Transaction(
                        date: date,
                        amount: amount,
                        accountID: accountID,
                        toAccountID: otherAccountID,
                        categoryID: template.categoryID,
                        type: .transfer,
                        memo: template.memo ?? memo,
                        recurringTemplateID: template.id,
                        status: .cleared
                    )
                    let mirror = Transaction(
                        date: date,
                        amount: -amount,
                        accountID: otherAccountID,
                        toAccountID: accountID,
                        linkedTransactionID: imported.id,
                        categoryID: template.categoryID,
                        type: .transfer,
                        memo: template.memo ?? memo,
                        recurringTemplateID: template.id,
                        status: .cleared
                    )
                    imported.linkedTransactionID = mirror.id
                    transferLinks.append(imported)
                    imported.linkedTransactionID = nil
                    return [imported, mirror]
                }

                return [Transaction(
                    date: date,
                    amount: abs(amount),
                    accountID: accountID,
                    payeeID: template?.payeeID ?? payee?.id,
                    categoryID: template?.categoryID ?? payee?.defaultCategoryID,
                    type: amount >= 0 ? .credit : .debit,
                    memo: memo,
                    recurringTemplateID: template?.id,
                    status: .cleared
                )]
            }
            // Toutes les transactions en une seule écriture : toutes ou aucune
            try await transactionsController.importTransactions(transactions)
            for transaction in transferLinks {
                await transactionsController.updateTransaction(transaction)
            }

            // Les échéances réglées ne sont plus proposées
            await recurringController.advanceAfterImport(lastDueDates)

            progressText = "Mise à jour des comptes…"
            await Task.yield()
            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)

            importedCount = transactions.count - transferLinks.count
            reconciledCount = settled.count
            createdPayees = newNames
            step = .done
        } catch {
            importError = "Aucune transaction n'a été importée. \(newNames.isEmpty ? "" : "Les nouveaux bénéficiaires ont pu être créés. ")(\(error.localizedDescription))"
            step = .preview
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
