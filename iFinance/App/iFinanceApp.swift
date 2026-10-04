
import SwiftUI

@main
struct iFinanceApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .environmentObject(appSettings)
                .environmentObject(appState.bookController)
                .environmentObject(appState.accountsController)
                .environmentObject(appState.transactionsController)
                .environmentObject(appState.categoriesController)
                .environmentObject(appState.payeesController)
                .environmentObject(appState.budgetsController)
                .environmentObject(appState.annualBudgetController)
                .environmentObject(appState.projectsController)
                .environmentObject(appState.investmentsController)
                .environmentObject(appState.savingsPlansController)
                .frame(minWidth: 1000, minHeight: 700)
                // NSApp.appearance plutôt que preferredColorScheme : revenir à « Système » fonctionne
                .onAppear {
                    appSettings.theme.apply()
                    // Réglage « Masquer les montants à l'ouverture »
                    if UserDefaults.standard.bool(forKey: SettingsKeys.hideAmountsAtLaunch) {
                        appSettings.hideAmounts = true
                    }
                }
                .onChange(of: appSettings.theme) { _, theme in theme.apply() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            // Menu Fichier : un raccourci par type d'objet (remplace « Nouvelle fenêtre », qui prenait ⌘N)
            CommandGroup(replacing: .newItem) {
                creationButton(.transaction)
                Divider()
                creationButton(.account)
                creationButton(.category)
                creationButton(.payee)
                creationButton(.budget)
                Divider()
                creationButton(.book)
            }
        }

        // Fenêtre Réglages (⌘,), avec les mêmes contrôleurs que la fenêtre principale
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appSettings)
                .environmentObject(appState.bookController)
                .environmentObject(appState.accountsController)
                .environmentObject(appState.transactionsController)
                .environmentObject(appState.categoriesController)
                .environmentObject(appState.payeesController)
                .environmentObject(appState.budgetsController)
                .environmentObject(appState.annualBudgetController)
                .environmentObject(appState.projectsController)
                .environmentObject(appState.investmentsController)
                .environmentObject(appState.savingsPlansController)
        }
    }

    private func creationButton(_ command: CreationCommand) -> some View {
        Button(command.title) {
            NotificationCenter.default.post(name: CreationCommand.notification, object: command)
        }
        .keyboardShortcut(command.key, modifiers: command.modifiers)
    }
}

/// Commandes de création du menu Fichier, relayées à la fenêtre principale par notification
enum CreationCommand: String, CaseIterable, Identifiable {
    case transaction, account, category, payee, budget, book

    static let notification = Notification.Name("iFinance.creationCommand")

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transaction: return "Nouvelle transaction"
        case .account: return "Nouveau compte"
        case .category: return "Nouvelle catégorie"
        case .payee: return "Nouveau bénéficiaire"
        case .budget: return "Nouveau budget"
        case .book: return "Nouveau livre"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .transaction, .account, .book: return "n"
        case .category: return "c"
        case .payee, .budget: return "b"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .transaction: return .command
        case .account, .category, .payee: return [.command, .shift]
        case .budget, .book: return [.command, .option]
        }
    }
}
