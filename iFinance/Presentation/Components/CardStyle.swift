import SwiftUI
import AppKit

// Style natif macOS : pas d'ombre ni de carte flottante. Les blocs reprennent l'apparence
// d'une GroupBox (fond très légèrement teinté + filet), ce qui les détache du fond de fenêtre
// en clair comme en sombre, y compris depuis macOS 26 où fenêtre et contrôles sont blancs.
// L'API (pageBackground / cardBackground) est conservée : tous les écrans existants en héritent.

enum NativeMetrics {
    /// Rayon maximal des blocs groupés
    static let groupCornerRadius: CGFloat = 8
    /// Marge intérieure standard d'un bloc groupé
    static let groupPadding: CGFloat = 14
    /// Marge de page autour du contenu
    static let pagePadding: CGFloat = 20
    /// Espacement entre blocs
    static let groupSpacing: CGFloat = 12
}

extension View {
    /// Fond de page : celui de la fenêtre, sans teinte ajoutée
    func pageBackground() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }

    /// Fond de bloc groupé : teinte légère et filet, sans ombre
    func cardBackground(cornerRadius: CGFloat = NativeMetrics.groupCornerRadius) -> some View {
        let radius = min(cornerRadius, NativeMetrics.groupCornerRadius)
        return background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.separator)
        )
    }
}
