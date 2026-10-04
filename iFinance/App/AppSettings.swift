import SwiftUI
import AppKit
import Combine

/// Thème de l'application
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    /// Apparence AppKit (nil = suivre le réglage de macOS)
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applique le thème à toutes les fenêtres, feuilles et menus de l'app
    @MainActor
    func apply() {
        NSApp.appearance = appearance
    }
}

class AppSettings: ObservableObject {
    @AppStorage("hideAmounts") var hideAmounts: Bool = false
    @AppStorage("appTheme") var theme: AppTheme = .system
}
