import SwiftUI

/// Regroupement de plusieurs bénéficiaires en un seul : nouveau nom et catégorie par défaut.
/// Le bénéficiaire le plus utilisé est conservé ; les autres lui cèdent leurs transactions et récurrences.
struct MergePayeesView: View {
    /// Bénéficiaires à regrouper, avec leur nombre d'opérations
    let payees: [(payee: Payee, count: Int)]
    @Binding var isPresented: Bool
    let onMerge: (_ targetID: UUID, _ name: String, _ defaultCategoryID: UUID?) -> Void

    @EnvironmentObject var payeesController: PayeesController
    @EnvironmentObject var categoriesController: CategoriesController

    @State private var name: String
    @State private var categoryID: UUID?

    init(payees: [(payee: Payee, count: Int)], isPresented: Binding<Bool>, onMerge: @escaping (UUID, String, UUID?) -> Void) {
        let sorted = payees.sorted { $0.count != $1.count ? $0.count > $1.count : $0.payee.name < $1.payee.name }
        self.payees = sorted
        self._isPresented = isPresented
        self.onMerge = onMerge
        let main = sorted.first?.payee
        // Nom proposé : le libellé simplifié du bénéficiaire le plus utilisé
        _name = State(initialValue: main.map { BankLabelCleaner.payeeName(from: $0.name) } ?? "")
        _categoryID = State(initialValue: main?.defaultCategoryID ?? sorted.compactMap { $0.payee.defaultCategoryID }.first)
    }

    private var target: Payee? { payees.first?.payee }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var totalCount: Int { payees.reduce(0) { $0 + $1.count } }

    /// Un bénéficiaire hors sélection porte déjà ce nom
    private var nameClash: Payee? {
        let ids = Set(payees.map { $0.payee.id })
        return payeesController.payees.first {
            !ids.contains($0.id) && $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Regrouper \(payees.count) bénéficiaires",
                subtitle: "\(totalCount) opération\(totalCount > 1 ? "s" : "") rattachée\(totalCount > 1 ? "s" : "") à un seul bénéficiaire"
            )

            Form {
                Section {
                    LabeledContent("Nouveau nom") {
                        TextField("Nouveau nom", text: $name, prompt: Text("Nom du bénéficiaire"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                    }

                    LabeledContent("Catégorie par défaut") {
                        CategoryPicker(selection: $categoryID, width: 260)
                    }
                } footer: {
                    if let clash = nameClash {
                        Label("« \(clash.name) » existe déjà et n'est pas sélectionné : les deux bénéficiaires porteront le même nom. Ajoutez-le à la sélection pour le regrouper aussi.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Bénéficiaires regroupés") {
                    ForEach(payees, id: \.payee.id) { entry in
                        HStack {
                            Text(entry.payee.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.count) opération\(entry.count > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                Text("Les notes et la localisation du bénéficiaire le plus utilisé sont conservées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } actions: {
                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("Regrouper") {
                    guard let target else { return }
                    onMerge(target.id, trimmedName, categoryID)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || payees.count < 2)
            }
        }
        .frame(width: 520, height: 500)
        .sheetBackground()
    }
}
