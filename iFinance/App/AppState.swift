import Foundation
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    
    // Database
    let db: SQLiteManager
    
    // Repositories
    let bookRepository: BookRepository
    let accountRepository: AccountRepository
    let transactionRepository: TransactionRepository
    let categoryRepository: CategoryRepository
    let payeeRepository: PayeeRepository
    
    // Controllers
    let bookController: BooksController
    let accountsController: AccountsController
    let transactionsController: TransactionsController
    let categoriesController: CategoriesController
    let payeesController: PayeesController
    
    init() {
        // Initialiser la base de données
        self.db = SQLiteManager(dbName: "iFinance.sqlite")
        
        // Exécuter les migrations
        let migrations = DatabaseMigrations(db: db)
        migrations.runMigrations()
        
        // Initialiser les repositories
        self.bookRepository = BookRepository(db: db)
        self.accountRepository = AccountRepository(db: db)
        self.transactionRepository = TransactionRepository(db: db)
        self.categoryRepository = CategoryRepository(db: db)
        self.payeeRepository = PayeeRepository(db: db)
        
        // Initialiser les controllers
        self.bookController = BooksController(repository: bookRepository)
        self.accountsController = AccountsController(repository: accountRepository)
        self.transactionsController = TransactionsController(repository: transactionRepository)
        self.categoriesController = CategoriesController(repository: categoryRepository)
        self.payeesController = PayeesController(repository: payeeRepository)
        
        print("✅ iFinance AppState initialisé")
    }
}
