import SwiftUI

/// Nouvel apport sur un plan : versement volontaire (virement) ou apport de l'entreprise (crédit)
struct ContributionFormView: View {
    let account: Account

    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @Environment(\.dismiss) private var dismiss

    @State private var origin: ContributionOrigin = .voluntary
    @State private var date = Date()
    @State private var amount = ""
    @State private var sourceAccountID: UUID?
    @State private var memo = ""
    @State private var availability: AvailabilityChoice
    @State private var availableDate: Date
    @State private var isDeducted = true

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: Account) {
        self.account = account
        let now = Date()
        let defaultDate = account.type.availabilityRule.defaultAvailability(for: now)
        _availability = State(initialValue: AvailabilityChoice(availableOn: defaultDate, contributionDate: now))
        _availableDate = State(initialValue: defaultDate ?? now)
        _origin = State(initialValue: ContributionOrigin.origins(for: account.type).first ?? .voluntary)
    }

    /// PER : le versement volontaire peut être déduit du revenu imposable (compartiment 1)
    private var asksDeduction: Bool {
        SavingsPlanPageKind(account.type) == .per && origin == .voluntary
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Nouvel apport", subtitle: account.name)

            Form {
                Section {
                    Picker("Origine", selection: $origin) {
                        ForEach(ContributionOrigin.origins(for: account.type), id: \.self) { origin in
                            Label(origin.displayName(for: account.type), systemImage: origin.icon).tag(origin)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    HStack {
                        Text("Montant (\(account.currency))")
                        Spacer()
                        TextField("0,00", text: $amount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .multilineTextAlignment(.trailing)
                    }

                    if origin == .voluntary {
                        Picker("Depuis le compte", selection: $sourceAccountID) {
                            Text("Aucun (versement externe)").tag(UUID?.none)
                            ForEach(sourceAccounts) { source in
                                Text(source.name).tag(UUID?.some(source.id))
                            }
                        }
                    }
                } footer: {
                    if origin == .employeeMandatory {
                        Text("Cotisation prélevée sur votre salaire, telle qu'elle figure sur votre fiche de paie.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if origin.isEmployerFunded {
                        Text("Saisissez le montant net investi, après CSG/CRDS, tel qu'il figure sur votre relevé.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if sourceAccountID != nil {
                        Text("Un virement est créé : le compte source est débité du même montant.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if asksDeduction {
                    Section {
                        Toggle("Déduit du revenu imposable", isOn: $isDeducted)
                    } footer: {
                        Text("Un versement déduit est imposé à la sortie en capital ; un versement non déduit ne l'est que sur ses gains.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    AvailabilityFields(choice: $availability, date: $availableDate, rule: account.type.availabilityRule)
                }

                Section {
                    TextField("Mémo (optionnel)", text: $memo)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedAmount == nil || isSaving)
            }
        }
        .frame(width: 520, height: 600)
        .sheetBackground()
        .onAppear {
            if sourceAccountID == nil {
                sourceAccountID = sourceAccounts.first { $0.type.group == .liquidity }?.id
            }
        }
        .onChange(of: date) { oldDate, newDate in
            // Suit la date du versement tant que la disponibilité est celle par défaut
            let previous = defaultAvailability(for: oldDate)
            guard availability == previous.choice,
                  availability != .onDate || availableDate == previous.date else { return }
            let next = defaultAvailability(for: newDate)
            availability = next.choice
            availableDate = next.date
        }
    }

    private func defaultAvailability(for contributionDate: Date) -> (choice: AvailabilityChoice, date: Date) {
        let availableOn = account.type.availabilityRule.defaultAvailability(for: contributionDate)
        return (AvailabilityChoice(availableOn: availableOn, contributionDate: contributionDate), availableOn ?? contributionDate)
    }

    private var sourceAccounts: [Account] {
        accountsController.activeAccounts.filter { $0.id != account.id }
    }

    private var parsedAmount: Decimal? {
        guard let value = Decimal(userInput: amount), value > 0 else { return nil }
        return value
    }

    private func save() {
        guard let value = parsedAmount else { return }
        isSaving = true
        errorMessage = nil
        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)

        Task {
            let transaction: Transaction?
            if origin == .voluntary, let sourceAccountID {
                transaction = await transactionsController.createTransfer(
                    from: sourceAccountID,
                    to: account.id,
                    amount: value,
                    date: date,
                    memo: trimmedMemo.isEmpty ? "Versement \(account.name)" : trimmedMemo
                )?.destination
            } else {
                transaction = await transactionsController.createTransaction(
                    accountID: account.id,
                    date: date,
                    amount: value,
                    type: .credit,
                    memo: trimmedMemo.isEmpty ? origin.displayName(for: account.type) : trimmedMemo
                )
            }

            guard let transaction else {
                errorMessage = transactionsController.error?.localizedDescription ?? "L'apport n'a pas pu être enregistré."
                isSaving = false
                return
            }

            await savingsPlansController.saveDetail(
                ContributionDetail(
                    transactionID: transaction.id,
                    origin: origin,
                    availableOn: availability.availableOn(contributionDate: date, chosenDate: availableDate),
                    isDeducted: asksDeduction ? isDeducted : nil
                ),
                accountID: account.id
            )
            await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
            dismiss()
        }
    }
}
