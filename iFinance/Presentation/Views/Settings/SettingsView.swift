import SwiftUI

struct SettingsView: View {

    enum Destination: Hashable {
        case accounts
        case payees
        case categories
    }

    @State private var path = NavigationPath()

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

    // MARK: - Row builder

    @ViewBuilder
    private func settingsRow(
        icon: String,
        iconColor: Color,
        label: String,
        destination: Destination,
        isLast: Bool = false
    ) -> some View {
        NavigationLink(value: destination) {
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

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if !isLast {
            Divider()
                .padding(.leading, 68)
        }
    }
}
