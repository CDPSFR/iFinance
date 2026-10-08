import SwiftUI

/// Modifie l'origine et la disponibilité d'un apport existant
struct ContributionDetailFormView: View {
    let account: Account
    let flow: PlanFlow

    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @Environment(\.dismiss) private var dismiss

    @State private var origin: ContributionOrigin
    @State private var availability: AvailabilityChoice
    @State private var availableDate: Date
    @State private var isDeducted: Bool

    init(account: Account, flow: PlanFlow) {
        self.account = account
        self.flow = flow
        _origin = State(initialValue: flow.origin ?? .voluntary)
        _availability = State(initialValue: AvailabilityChoice(availableOn: flow.availableOn, contributionDate: flow.date))
        _availableDate = State(initialValue: flow.availableOn ?? flow.date)
        _isDeducted = State(initialValue: flow.isDeducted)
    }

    /// PER : le versement volontaire peut être déduit du revenu imposable (compartiment 1)
    private var asksDeduction: Bool {
        SavingsPlanPageKind(account.type) == .per && origin == .voluntary
    }

    /// Origines du plan, plus celle de l'apport si elle n'en fait pas partie
    private var origins: [ContributionOrigin] {
        var list = ContributionOrigin.origins(for: account.type)
        if let current = flow.origin, !list.contains(current) {
            list.append(current)
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Apport du \(flow.date.formatted(date: .abbreviated, time: .omitted))",
                subtitle: flow.amount.formatted(.currency(code: account.currency))
            )

            Form {
                Section {
                    Picker("Origine", selection: $origin) {
                        ForEach(origins, id: \.self) { origin in
                            Label(origin.displayName(for: account.type), systemImage: origin.icon).tag(origin)
                        }
                    }
                } footer: {
                    Text("Le montant et la date se modifient depuis l'onglet Mouvements.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if asksDeduction {
                    Section {
                        Toggle("Déduit du revenu imposable", isOn: $isDeducted)
                    }
                }

                Section {
                    AvailabilityFields(choice: $availability, date: $availableDate, rule: account.type.availabilityRule)
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    guard let transactionID = flow.transactionID else { return }
                    Task {
                        await savingsPlansController.saveDetail(
                            ContributionDetail(
                                transactionID: transactionID,
                                origin: origin,
                                availableOn: availability.availableOn(contributionDate: flow.date, chosenDate: availableDate),
                                isDeducted: asksDeduction ? isDeducted : nil
                            ),
                            accountID: account.id
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(flow.transactionID == nil)
            }
        }
        .frame(width: 520, height: 440)
        .sheetBackground()
    }
}
