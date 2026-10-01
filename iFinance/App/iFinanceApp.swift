
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
                .environmentObject(appState.investmentsController)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
