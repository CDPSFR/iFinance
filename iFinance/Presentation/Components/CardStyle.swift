import SwiftUI
import AppKit

// Depuis macOS 26, le fond de fenêtre et celui des contrôles sont tous deux blancs en mode
// clair : les cartes ne se détachent plus. Ces modificateurs teintent légèrement la page et
// donnent aux cartes une ombre et une bordure, en clair comme en sombre.

extension View {
    /// Fond de page légèrement teinté
    func pageBackground() -> some View {
        background(Color(nsColor: .windowBackgroundColor).overlay(Color.primary.opacity(0.045)))
    }

    /// Fond de carte : surface, ombre légère et bordure fine
    func cardBackground(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.separator.opacity(0.6))
        )
    }
}
