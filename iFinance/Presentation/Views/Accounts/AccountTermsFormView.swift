import SwiftUI

/// Conditions d'un prêt (comptes de type Prêt) ou frais annuels (comptes de placement),
/// utilisés par les rapports « Dettes et crédits » et « Performance des placements »
struct AccountTermsFormView: View {
    let account: Account

    @EnvironmentObject var accountTermsController: AccountTermsController
    @Environment(\.dismiss) private var dismiss

    @State private var principal = ""
    @State private var rate = ""
    @State private var years = 20
    @State private var extraMonths = 0
    @State private var firstPayment = Date()
    @State private var insurance = ""
    @State private var isMortgage = true
    @State private var feeRate = ""
    @State private var isSaving = false

    private var isLoan: Bool { account.type.group == .debt }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isLoan ? "Conditions du prêt" : "Frais du compte",
                subtitle: account.name
            )

            Form {
                if isLoan {
                    Section {
                        amountField("Montant emprunté", text: $principal, suffix: account.currency)
                        amountField("Taux nominal", text: $rate, suffix: "%")
                        Stepper(value: $years, in: 0...35) {
                            HStack {
                                Text("Durée")
                                Spacer()
                                Text("\(years) an\(years > 1 ? "s" : "")\(extraMonths > 0 ? " et \(extraMonths) mois" : "")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Stepper("Mois supplémentaires", value: $extraMonths, in: 0...11)
                        DatePicker("Première échéance", selection: $firstPayment, displayedComponents: .date)
                    } footer: {
                        Text("Reportez les valeurs de votre offre de prêt. La mensualité et l’échéancier sont calculés pour un prêt amortissable à mensualités constantes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Section {
                        amountField("Assurance par mois", text: $insurance, suffix: account.currency)
                        Toggle(isOn: $isMortgage) {
                            Text("Crédit immobilier")
                            Text("Les indemnités de remboursement anticipé sont plafonnées à 6 mois d’intérêts et à 3 % du capital remboursé.")
                        }
                    } footer: {
                        if let payment = previewPayment {
                            Text("Mensualité calculée : \(PlanFormat.money(payment, account.currency)) hors assurance.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Section {
                        amountField("Frais annuels", text: $feeRate, suffix: "%")
                    } footer: {
                        Text("Frais de gestion du contrat et frais courants des fonds, en pourcentage de l’encours (document d’informations clés). Laisser vide si inconnus.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || !isValid)
            }
        }
        .frame(width: 520, height: isLoan ? 560 : 300)
        .sheetBackground()
        .onAppear(perform: load)
    }

    private func amountField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: text, prompt: Text("0"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
        }
    }

    // MARK: - Saisie

    private func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private var months: Int { years * 12 + extraMonths }

    private var loanTerms: LoanTerms? {
        guard let amount = parse(principal), amount > 0,
              let percent = parse(rate), percent >= 0, months > 0 else { return nil }
        return LoanTerms(
            principal: amount,
            annualRate: NSDecimalNumber(decimal: percent).doubleValue / 100,
            months: months,
            firstPaymentDate: firstPayment,
            monthlyInsurance: parse(insurance) ?? 0,
            isMortgage: isMortgage
        )
    }

    private var previewPayment: Decimal? {
        loanTerms.map { Decimal(LoanSchedule(terms: $0).payment) }
    }

    private var isValid: Bool {
        if isLoan {
            // Tout vide : on efface les conditions
            let empty = principal.trimmingCharacters(in: .whitespaces).isEmpty && rate.trimmingCharacters(in: .whitespaces).isEmpty
            return empty || loanTerms != nil
        }
        return feeRate.trimmingCharacters(in: .whitespaces).isEmpty || parse(feeRate) != nil
    }

    private func format(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
    }

    private func load() {
        let terms = accountTermsController.accountTerms(for: account.id)
        if let loan = terms.loan {
            principal = format(loan.principal)
            rate = format(Decimal(loan.annualRate * 100))
            years = loan.months / 12
            extraMonths = loan.months % 12
            firstPayment = loan.firstPaymentDate
            insurance = loan.monthlyInsurance == 0 ? "" : format(loan.monthlyInsurance)
            isMortgage = loan.isMortgage
        }
        if let fee = terms.annualFeeRate {
            feeRate = format(Decimal(fee * 100))
        }
    }

    private func save() {
        var terms = accountTermsController.accountTerms(for: account.id)
        if isLoan {
            terms.loan = loanTerms
        } else {
            terms.annualFeeRate = parse(feeRate).map { NSDecimalNumber(decimal: $0).doubleValue / 100 }
        }
        isSaving = true
        Task {
            await accountTermsController.save(terms)
            dismiss()
        }
    }
}
