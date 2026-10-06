import SwiftUI

// MARK: - Actions d'une échéance

/// Boutons Valider / Modifier… / Passer d'une échéance, ou son état quand elle n'est pas actionnable
struct RecurringOccurrenceActions: View {
    let occurrence: RecurringOccurrence
    let onValidate: () -> Void
    let onEdit: () -> Void
    let onSkip: () -> Void

    var body: some View {
        if occurrence.template.autoPost {
            Text("saisie automatique")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if occurrence.isNext {
            HStack(spacing: 6) {
                Button("Valider", action: onValidate)
                    .buttonStyle(.borderedProminent)
                Button("Modifier…", action: onEdit)
                Button("Passer", action: onSkip)
            }
            .controlSize(.small)
        } else {
            Text("après la précédente")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Traitez d'abord l'échéance précédente de cette récurrence.")
        }
    }
}

// MARK: - Validation avec montant et date

/// Feuille de validation : montant réel (montant variable) et date réelle de l'opération
struct RecurringValidateView: View {
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var payeesController: PayeesController
    @Environment(\.dismiss) private var dismiss

    let occurrence: RecurringOccurrence

    @State private var amount: String
    @State private var date: Date

    init(occurrence: RecurringOccurrence) {
        self.occurrence = occurrence
        _amount = State(initialValue: occurrence.template.amount.formatted(.number.precision(.fractionLength(2)).grouping(.never)))
        _date = State(initialValue: occurrence.date)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Valider l'échéance",
                subtitle: occurrence.template.isTransfer
                    ? transferText(occurrence.template)
                    : payeesController.getPayee(id: occurrence.template.payeeID ?? UUID())?.name
                        ?? occurrence.template.memo
            )

            Form {
                Section {
                    LabeledContent("Montant") {
                        TextField("Montant", text: $amount, prompt: Text("0,00"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                    }

                    LabeledContent("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                            .frame(width: 260, alignment: .leading)
                    }
                } footer: {
                    if occurrence.template.isVariableAmount {
                        Text("Montant variable : le montant affiché est une estimation, saisissez le montant réel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                EmptyView()
            } actions: {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Valider") {
                    guard let value = parsedAmount else { return }
                    Task {
                        await recurringController.validate(occurrence, amount: value, date: date)
                        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedAmount == nil || parsedAmount == 0)
            }
        }
        .frame(width: 520, height: 280)
        .sheetBackground()
    }

    private var parsedAmount: Decimal? {
        let cleaned = amount
            .replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace && $0 != "\u{202F}" && $0 != "\u{00A0}" }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func transferText(_ template: RecurringTemplate) -> String {
        let source = accountsController.getAccount(id: template.accountID)?.name ?? "—"
        let destination = accountsController.getAccount(id: template.toAccountID ?? UUID())?.name ?? "—"
        return "Virement \(source) → \(destination)"
    }
}

// MARK: - Bandeau « À venir » de la liste des transactions

/// Échéances à venir affichées en tête de la liste des transactions.
/// `accountID` nil = tous les comptes ; `currentBalance` sert au solde prévu en fin de mois.
struct UpcomingOccurrencesBand: View {
    @EnvironmentObject var recurringController: RecurringController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    let accountID: UUID?
    var currentBalance: Decimal? = nil

    @AppStorage("showUpcomingOccurrences") private var isExpanded = true
    @State private var occurrenceToValidate: RecurringOccurrence?

    /// Nombre d'échéances affichées avant « et N autres »
    private static let visibleCount = 5

    var body: some View {
        let occurrences = recurringController.occurrences(accountID: accountID)

        if !occurrences.isEmpty {
            VStack(spacing: 0) {
                header(occurrences)

                if isExpanded {
                    ForEach(occurrences.prefix(Self.visibleCount)) { occurrence in
                        Divider().padding(.leading, 16)
                        row(occurrence)
                    }

                    if occurrences.count > Self.visibleCount {
                        Divider().padding(.leading, 16)
                        Text("et \(occurrences.count - Self.visibleCount) autres dans la page Récurrent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                    }
                }

                Divider()
            }
            .background(Color.primary.opacity(0.03))
            .sheet(item: $occurrenceToValidate) { occurrence in
                RecurringValidateView(occurrence: occurrence)
            }
        }
    }

    private func header(_ occurrences: [RecurringOccurrence]) -> some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 10)

                Text("À VENIR")
                    .fontWeight(.semibold)

                Text(occurrences.count > 1 ? "\(occurrences.count) échéances" : "1 échéance")

                let late = occurrences.filter { $0.isLate }.count
                if late > 0 {
                    Text("dont \(late) en retard")
                        .foregroundStyle(.red)
                }

                Spacer()

                if let currentBalance {
                    Text("Solde prévu fin de mois")
                    Text(money(currentBalance + recurringController.pendingAmount(accountID: accountID)))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .privacyBlur(hidden: appSettings.hideAmounts)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Masquer les échéances à venir" : "Afficher les échéances à venir")
    }

    private func row(_ occurrence: RecurringOccurrence) -> some View {
        let template = occurrence.template

        return HStack(spacing: 10) {
            Text(occurrence.date, format: .dateTime.day().month(.abbreviated))
                .frame(width: 60, alignment: .leading)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)

            Text(label(template))
                .lineLimit(1)

            if occurrence.isLate {
                Text("en retard")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let categoryID = template.categoryID {
                Text(categoriesController.getCategoryPath(for: categoryID))
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Sur une page de compte, un virement est une sortie ou une entrée ; sans compte, sans signe
            Text(money(template.isTransfer && accountID == nil ? abs(template.amount) : template.signedAmount(for: accountID)))
                .monospacedDigit()
                .privacyBlur(hidden: appSettings.hideAmounts)

            RecurringOccurrenceActions(
                occurrence: occurrence,
                onValidate: { validate(occurrence) },
                onEdit: { occurrenceToValidate = occurrence },
                onSkip: { skip(occurrence) }
            )
            .frame(width: 230, alignment: .trailing)
        }
        .italic()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private func validate(_ occurrence: RecurringOccurrence) {
        // Montant variable : on demande le montant réel avant de créer la transaction
        if occurrence.template.isVariableAmount {
            occurrenceToValidate = occurrence
            return
        }
        Task {
            await recurringController.validate(occurrence)
            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
        }
    }

    /// Bénéficiaire, ou « Virement vers Livret A » / « Virement depuis Courant » selon le compte affiché
    private func label(_ template: RecurringTemplate) -> String {
        guard template.isTransfer else {
            return payeesController.getPayee(id: template.payeeID ?? UUID())?.name ?? template.memo ?? "Sans bénéficiaire"
        }
        if let accountID, accountID == template.toAccountID {
            return "Virement depuis \(accountsController.getAccount(id: template.accountID)?.name ?? "—")"
        }
        return "Virement vers \(accountsController.getAccount(id: template.toAccountID ?? UUID())?.name ?? "—")"
    }

    private func skip(_ occurrence: RecurringOccurrence) {
        Task { await recurringController.skip(occurrence) }
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: booksController.currentBook?.currency ?? "EUR"))
    }
}
