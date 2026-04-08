
import SwiftUI

@main
struct iFinanceApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .environmentObject(appState.bookController)
                .environmentObject(appState.accountsController)
                .environmentObject(appState.transactionsController)
                .environmentObject(appState.categoriesController)
                .environmentObject(appState.payeesController)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
