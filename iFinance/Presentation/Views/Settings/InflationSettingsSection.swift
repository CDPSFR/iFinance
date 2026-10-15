import SwiftUI

/// Réglages › Confidentialité : mise à jour en ligne des indices des prix de l'INSEE
struct InflationSettingsSection: View {
    @EnvironmentObject var inflationService: InflationService

    var body: some View {
        Section {
            Toggle(isOn: $inflationService.isEnabled) {
                Text("Mettre à jour les indices INSEE en ligne")
                Text("Désactivé, le rapport « Inflation personnelle » utilise les valeurs intégrées à l'app (INSEE \(String(InflationTable.embedded.lastYear))).")
            }

            if inflationService.isEnabled {
                LabeledContent("Valeurs utilisées") {
                    Text("inflation \(String(inflationService.table.lastYear)) : \(inflationService.table.last.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))")
                        .monospacedDigit()
                }

                LabeledContent("Dernière mise à jour") {
                    Text(inflationService.lastUpdate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "jamais")
                }

                HStack(spacing: 8) {
                    Button(inflationService.isUpdating ? "Mise à jour…" : "Mettre à jour maintenant") {
                        Task { await inflationService.update() }
                    }
                    .disabled(inflationService.isUpdating)

                    if inflationService.isUpdating {
                        ProgressView().controlSize(.small)
                    }
                }

                if let result = inflationService.lastResult {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.success ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ce qui est envoyé")
                        .fontWeight(.semibold)
                    Text("Uniquement les identifiants publics des séries de prix, à la base de données de l'INSEE (bdm.insee.fr), une fois par mois au plus ou quand vous cliquez sur « Mettre à jour maintenant ». Aucune de vos données.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .onChange(of: inflationService.isEnabled) { _, enabled in
            if enabled { Task { await inflationService.updateIfStale() } }
        }
    }
}
