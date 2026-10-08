import SwiftUI

/// Réglages propres à un plan : plafond d'abondement de l'accord (PEE),
/// plafonds de déduction de l'avis d'impôt et tranche marginale (PER, PERCO)
struct SavingsPlanSettingsFormView: View {
    let account: Account

    @EnvironmentObject var savingsPlansController: SavingsPlansController
    @Environment(\.dismiss) private var dismiss

    @State private var matchingCap = ""
    @State private var ceilings: [Int: String] = [:]
    @State private var marginalRate: Double? = nil
    @State private var isSaving = false

    private let currentYear = Calendar.current.component(.year, from: Date())
    private static let marginalRates: [Double] = [0, 0.11, 0.30, 0.41, 0.45]

    private var kind: SavingsPlanPageKind { SavingsPlanPageKind(account.type) }

    /// Années proposées : les 5 dernières, celles où un plafond peut encore servir
    private var years: [Int] {
        Array((currentYear - 4)...currentYear).reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Réglages du plan", subtitle: account.name)

            Form {
                if kind == .pee {
                    Section {
                        amountField("Plafond annuel d’abondement", text: $matchingCap, placeholder: "Non renseigné")
                    } header: {
                        Text("Abondement")
                    } footer: {
                        Text("Montant maximal que votre entreprise verse chaque année, indiqué dans l’accord ou le règlement du plan. Plafond légal : 8 % du PASS, soit \(PlanFormat.money(PASS.peeMatchingCap(year: currentYear), account.currency)) en \(String(currentYear)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if kind == .per {
                    Section {
                        Picker("Tranche marginale d’imposition", selection: $marginalRate) {
                            Text("Non renseignée").tag(Double?.none)
                            ForEach(Self.marginalRates, id: \.self) { rate in
                                Text(PlanFormat.percent(rate)).tag(Double?.some(rate))
                            }
                        }
                    } header: {
                        Text("Imposition")
                    } footer: {
                        Text("Sert à estimer l’économie d’impôt de vos versements déduits.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Section {
                        ForEach(years, id: \.self) { year in
                            amountField(
                                "Versements \(String(year))",
                                text: Binding(
                                    get: { ceilings[year] ?? "" },
                                    set: { ceilings[year] = $0 }
                                ),
                                placeholder: PlanFormat.round(PASS.perDeductionFloor(year: year), account.currency)
                            )
                        }
                    } header: {
                        Text("Plafonds de déduction")
                    } footer: {
                        Text("Reportez, pour chaque année de versement, le plafond calculé sur les revenus de l’année précédente (rubrique « plafond épargne retraite » de l’avis d’impôt), sans les plafonds non utilisés : les reports sont calculés par l’application. Laissé vide, le plancher légal (10 % du PASS) est utilisé.")
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
        .frame(width: 520, height: kind == .per ? 560 : 300)
        .sheetBackground()
        .onAppear(perform: load)
    }

    private func amountField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Saisie

    private func parse(_ text: String) -> Decimal?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .some(nil) }       // Champ vide : valeur effacée
        guard let value = Decimal(userInput: trimmed), value >= 0 else { return nil }   // Saisie invalide
        return .some(value)
    }

    private var isValid: Bool {
        guard parse(matchingCap) != nil else { return false }
        return ceilings.values.allSatisfy { parse($0) != nil }
    }

    private func format(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private func load() {
        let settings = savingsPlansController.planSettings(for: account.id)
        matchingCap = settings.matchingCap.map(format) ?? ""
        ceilings = settings.deductionCeilings.mapValues(format)
        marginalRate = settings.marginalTaxRate
    }

    private func save() {
        var settings = savingsPlansController.planSettings(for: account.id)

        if kind == .pee, let cap = parse(matchingCap) {
            settings.matchingCap = cap
        }
        if kind == .per {
            settings.marginalTaxRate = marginalRate
            for (year, text) in ceilings {
                guard let value = parse(text) else { continue }
                settings.deductionCeilings[year] = value
            }
        }

        isSaving = true
        Task {
            await savingsPlansController.saveSettings(settings)
            dismiss()
        }
    }
}
