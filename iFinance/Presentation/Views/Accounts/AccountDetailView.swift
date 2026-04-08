import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    
    var body: some View {
        if accountsController.selectedAccount != nil {
            TransactionListView()
        } else {
            VStack(spacing: 20) {
                Image(systemName: "creditcard")
                    .font(.system(size: 80))
                    .foregroundColor(.gray.opacity(0.5))
                
                Text("Sélectionnez un compte")
                    .font(.title)
                    .foregroundColor(.secondary)
                
                Text("Choisissez un compte dans la liste pour voir ses transactions")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
