import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {

    enum Destination: Hashable {
        case accounts
        case payees
        case categories
    }

    @EnvironmentObject var appSettings: AppSettings

    @State private var path = NavigationPath()
    @State private var exportError: String?
    @State private var showExportError = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // Titre
                HStack {
                    Text("Paramètres")
                        .font(.system(size: 34, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)

                // Contenu
                ScrollView {
                    VStack(spacing: 0) {
                        settingsSection(title: "Données") {
                            settingsRow(
                                icon: "creditcard.fill",
                                iconColor: .blue,
                                label: "Comptes",
                                destination: Destination.accounts
                            )
                            settingsRow(
                                icon: "person.crop.circle.fill",
                                iconColor: .orange,
                                label: "Bénéficiaires",
                                destination: Destination.payees
                            )
                            settingsRow(
                                icon: "folder.fill",
                                iconColor: .teal,
                                label: "Catégories",
                                destination: Destination.categories,
                                isLast: true
                            )
                        }

                        settingsSection(title: "Confidentialité") {
                            toggleRow(
                                icon: "eye.slash.fill",
                                iconColor: .purple,
                                label: "Masquer les montants",
                                isOn: Binding(
                                    get: { appSettings.hideAmounts },
                                    set: { appSettings.hideAmounts = $0 }
                                ),
                                isLast: true
                            )
                        }

                        settingsSection(title: "Outils") {
                            actionRow(
                                icon: "square.and.arrow.up.fill",
                                iconColor: .green,
                                label: "Exporter la base de données",
                                isLast: true,
                                action: exportDatabase
                            )
                        }
                    }
                }

                Spacer()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .accounts:
                    AccountListView()
                case .payees:
                    PayeeListView(selectedTab: .constant(.settings))
                case .categories:
                    CategoryListView(selectedTab: .constant(.settings))
                }
            }
            .alert("Erreur d'export", isPresented: $showExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportError ?? "Une erreur est survenue.")
            }
        }
    }

    // MARK: - Export

    private func exportDatabase() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let sourceURL = appSupport.appendingPathComponent("iFinance/iFinance.sqlite")

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            exportError = "Fichier de base de données introuvable."
            showExportError = true
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exporter la base de données"
        panel.nameFieldStringValue = "iFinance.sqlite"
        panel.allowedContentTypes = [.database]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                exportError = error.localizedDescription
                showExportError = true
            }
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Navigation row

    @ViewBuilder
    private func settingsRow(
        icon: String,
        iconColor: Color,
        label: String,
        destination: Destination,
        isLast: Bool = false
    ) -> some View {
        NavigationLink(value: destination) {
            rowContent(icon: icon, iconColor: iconColor, label: label, trailing: "chevron.right")
        }
        .buttonStyle(.plain)

        if !isLast {
            Divider().padding(.leading, 54)
        }
    }

    // MARK: - Toggle row

    @ViewBuilder
    private func toggleRow(
        icon: String,
        iconColor: Color,
        label: String,
        isOn: Binding<Bool>,
        isLast: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(iconColor))

            Text(label)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))

        if !isLast {
            Divider().padding(.leading, 54)
        }
    }

    // MARK: - Action row

    @ViewBuilder
    private func actionRow(
        icon: String,
        iconColor: Color,
        label: String,
        isLast: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(icon: icon, iconColor: iconColor, label: label, trailing: "square.and.arrow.up")
        }
        .buttonStyle(.plain)

        if !isLast {
            Divider().padding(.leading, 54)
        }
    }

    // MARK: - Row content

    @ViewBuilder
    private func rowContent(icon: String, iconColor: Color, label: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor)
                )

            Text(label)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: trailing)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
    }
}
