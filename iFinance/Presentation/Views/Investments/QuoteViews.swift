import SwiftUI

// MARK: - Barre de mise à jour des cours (page d'un compte d'investissement)

/// Fraîcheur des cours du compte et bouton de mise à jour. N'apparaît que si la mise à jour
/// en ligne est activée dans les réglages.
struct QuoteUpdateBar: View {
    @EnvironmentObject var quoteService: QuoteService
    @EnvironmentObject var investmentsController: InvestmentsController

    let accountID: UUID

    @State private var showFailures = false

    private var positions: [InvestmentPosition] {
        (investmentsController.positions[accountID] ?? []).filter { $0.quantity > 0 }
    }

    var body: some View {
        if quoteService.isEnabled, !positions.isEmpty {
            HStack(spacing: 8) {
                Circle()
                    .fill(freshnessColor)
                    .frame(width: 7, height: 7)

                Text(freshnessText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let failures = quoteService.lastOutcome?.failures.filter({ failure in
                    positions.contains { $0.id == failure.positionID }
                }), !failures.isEmpty, !quoteService.isUpdating {
                    Button("\(failures.count) cours non mis à jour") { showFailures = true }
                        .buttonStyle(.link)
                        .font(.caption)
                        .popover(isPresented: $showFailures, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(failures) { failure in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(failure.name).fontWeight(.medium)
                                        Text(failure.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(width: 340, alignment: .leading)
                        }
                }

                Spacer()

                // Le bouton de mise à jour est dans l'en-tête de la fenêtre (QuoteUpdateToolbarButton) ;
                // ici, l'avancement s'affiche sur la même ligne, sans changer la hauteur de la barre.
                if quoteService.isUpdating {
                    Text("Mise à jour des cours… \(quoteService.progress.done) sur \(quoteService.progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    /// Cours le plus ancien parmi les positions détenues
    private var oldestUpdate: Date? {
        let dates = positions.map { $0.lastUpdated }
        guard !dates.contains(where: { $0 == nil }) else { return nil }
        return dates.compactMap { $0 }.min()
    }

    private var freshnessText: String {
        let missing = positions.filter { $0.currentPrice == nil || $0.lastUpdated == nil }.count
        if missing == positions.count { return "Aucun cours enregistré" }
        if missing > 0 { return "\(missing) position\(missing > 1 ? "s" : "") sans cours" }
        guard let oldest = oldestUpdate else { return "Aucun cours enregistré" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return "Cours le plus ancien : \(formatter.localizedString(for: oldest, relativeTo: Date()))"
    }

    private var freshnessColor: Color {
        guard let oldest = oldestUpdate else { return .red }
        let days = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0
        if days <= 1 { return .green }
        return days <= 7 ? .orange : .red
    }
}

// MARK: - Bouton de mise à jour (en-tête de la fenêtre)

/// Bouton « Mettre à jour les cours » de la barre d'outils. Pendant la mise à jour, un indicateur
/// d'activité prend sa place dans le même encombrement.
struct QuoteUpdateToolbarButton: View {
    @EnvironmentObject var quoteService: QuoteService
    @EnvironmentObject var investmentsController: InvestmentsController

    let accountID: UUID

    private var positions: [InvestmentPosition] {
        (investmentsController.positions[accountID] ?? []).filter { $0.quantity > 0 }
    }

    var body: some View {
        Button {
            Task { await quoteService.update(positions) }
        } label: {
            Label("Mettre à jour les cours", systemImage: "arrow.clockwise")
                .opacity(quoteService.isUpdating ? 0 : 1)
                .overlay {
                    if quoteService.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .disabled(!quoteService.isConfigured || quoteService.isUpdating || positions.isEmpty)
        .help(helpText)
        .accessibilityLabel(quoteService.isUpdating ? "Mise à jour des cours en cours" : "Mettre à jour les cours")
    }

    private var helpText: String {
        if quoteService.isUpdating {
            return "Mise à jour en cours : \(quoteService.progress.done) sur \(quoteService.progress.total)"
        }
        if !quoteService.isConfigured {
            return "Enregistrez une clé d'API dans Réglages › Confidentialité."
        }
        return "Mettre à jour les cours auprès de \(quoteService.provider.displayName). Seuls les symboles sont envoyés."
    }
}

// MARK: - Réglages

/// Section « Cours en ligne » de Réglages › Confidentialité
struct QuoteSettingsSection: View {
    @EnvironmentObject var quoteService: QuoteService

    @State private var apiKey = ""
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    var body: some View {
        Section {
            Toggle(isOn: $quoteService.isEnabled) {
                Text("Mettre à jour les cours en ligne")
                Text("Désactivé, iFinance ne contacte aucun service : les cours se saisissent à la main.")
            }

            if quoteService.isEnabled {
                Picker("Fournisseur", selection: $quoteService.providerID) {
                    ForEach(QuoteProviderRegistry.all, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .onChange(of: quoteService.providerID) { _, _ in loadKey() }

                Text(quoteService.provider.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if quoteService.provider.requiresAPIKey {
                    LabeledContent("Clé d'API") {
                        SecureField("Clé d'API", text: $apiKey, prompt: Text("Collez votre clé"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                            .onSubmit { saveKey() }
                    }

                }

                HStack(spacing: 8) {
                    if quoteService.provider.requiresAPIKey {
                        Button("Enregistrer la clé") { saveKey() }
                            .disabled(apiKey == (quoteService.apiKey ?? ""))
                    }

                    Button(isTesting ? "Test en cours…" : "Tester la connexion") {
                        if quoteService.provider.requiresAPIKey { saveKey() }
                        isTesting = true
                        Task {
                            let result = await quoteService.testConnection()
                            testSucceeded = result.success
                            testMessage = result.message
                            isTesting = false
                        }
                    }
                    .disabled(isTesting || (quoteService.provider.requiresAPIKey && apiKey.isEmpty))

                    if quoteService.provider.requiresAPIKey, let url = quoteService.provider.signupURL {
                        Link("Obtenir une clé", destination: url)
                    }
                }

                if let testMessage {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(testSucceeded ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ce qui est envoyé")
                        .fontWeight(.semibold)
                    Text(quoteService.provider.requiresAPIKey
                         ? "Uniquement le symbole ou le code ISIN de chaque position, et votre clé d'API, quand vous cliquez sur « Mettre à jour les cours ». Jamais vos quantités, vos montants, vos comptes ni vos transactions. La clé est conservée dans le trousseau de ce Mac."
                         : "Uniquement le symbole ou le code ISIN de chaque position, quand vous cliquez sur « Mettre à jour les cours ». Jamais vos quantités, vos montants, vos comptes ni vos transactions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Cours en ligne")
        }
        .onAppear { loadKey() }
    }

    private func loadKey() {
        apiKey = quoteService.apiKey ?? ""
        testMessage = nil
    }

    private func saveKey() {
        quoteService.apiKey = apiKey
    }
}
