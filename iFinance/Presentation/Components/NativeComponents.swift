import SwiftUI

// Composants partagés du style natif macOS : inspecteur, pied de tableau, tuile de statistique.

// MARK: - Inspecteur

/// En-tête d'inspecteur : titre, valeur principale optionnelle et légende
struct InspectorHeader: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = .primary
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let value {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section d'inspecteur : filet supérieur, titre optionnel, contenu
struct InspectorSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ligne d'inspecteur : étiquette secondaire alignée à droite, valeur à gauche
struct InspectorRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 76
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension InspectorRow where Content == Text {
    /// Variante texte seul
    init(_ label: String, value: String) {
        self.label = label
        self.content = Text(value)
    }
}

/// Conteneur d'inspecteur : marges et espacement standard, défilant
struct InspectorContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
        }
    }
}

// MARK: - Pied de tableau

/// Barre d'état sous un tableau : légendes centrées, filet supérieur
struct TableStatusBar: View {
    let items: [String]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Tuile de statistique

/// Tuile compacte : légende, valeur, complément. Alignée à gauche, dans un bloc groupé.
/// Hauteur constante, avec ou sans complément.
struct StatTile: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    var detail: String? = nil
    var detailColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // La ligne de complément est toujours réservée : toutes les tuiles ont la même hauteur
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .accessibilityHidden(detail == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }
}

// MARK: - Titre de bloc

/// Titre de bloc groupé avec action optionnelle à droite
struct GroupTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            trailing
        }
    }
}

extension GroupTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

// MARK: - Panneau latéral sous l'en-tête

/// Contenu principal avec un panneau d'inspecteur à droite, logé sous l'en-tête de la page
/// (contrairement à `.inspector`, qui occupe toute la hauteur de la fenêtre).
struct SidePanelLayout<Main: View, Panel: View>: View {
    @Binding var isPresented: Bool
    var width: CGFloat = 280
    @ViewBuilder var main: Main
    @ViewBuilder var panel: Panel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                main
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isPresented {
                Divider()
                panel
                    .frame(width: width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}
