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
        // Tous les boutons de l'inspecteur s'étirent : seul sur sa ligne, un bouton prend
        // toute la largeur ; à deux dans un HStack, chacun en prend la moitié.
        .buttonStyle(InspectorButtonStyle())
    }
}

/// Bouton d'inspecteur : largeur maximale, aspect d'un bouton bordé standard.
/// Les boutons qui déclarent leur propre style (.borderless, .plain) ne sont pas concernés.
struct InspectorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InspectorButtonBody(configuration: configuration)
    }

    private struct InspectorButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
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

// MARK: - Feuilles : en-tête et pied communs

/// En-tête de feuille : titre, sous-titre facultatif. Pas de croix de fermeture :
/// la feuille se ferme par « Annuler » (touche Échap).
struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

/// Pied de feuille : filet, actions secondaires à gauche, « Annuler » et action principale à droite
struct SheetFooter<Leading: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                leading
                Spacer()
                actions
            }
            .padding(12)
        }
    }
}

extension SheetFooter where Leading == EmptyView {
    init(@ViewBuilder actions: () -> Actions) {
        self.leading = EmptyView()
        self.actions = actions()
    }
}

// MARK: - État vide en haut de page

/// Message d'état vide posé en haut de la page (icône, titre, phrase, action facultative).
/// Construit avec des vues simples et un Spacer : contrairement à ContentUnavailableView
/// contraint par fixedSize, il ne peut pas étirer la fenêtre.
struct TopEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title2.weight(.semibold))

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .padding(.top, 6)
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
