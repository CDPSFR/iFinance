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
    let budgetRepository: BudgetRepository
    let annualBudgetRepository: AnnualBudgetRepository
    let projectRepository: ProjectRepository
    let recurringTemplateRepository: RecurringTemplateRepository
    let investmentPositionRepository: InvestmentPositionRepository
    let investmentTransactionRepository: InvestmentTransactionRepository
    let savingsPlanRepository: SavingsPlanRepository

    // Controllers
    let bookController: BooksController
    let accountsController: AccountsController
    let transactionsController: TransactionsController
    let categoriesController: CategoriesController
    let payeesController: PayeesController
    let budgetsController: BudgetsController
    let annualBudgetController: AnnualBudgetController
    let projectsController: ProjectsController
    let recurringController: RecurringController

    // Sauvegardes de la base
    let backupManager: BackupManager
    let investmentsController: InvestmentsController
    let savingsPlansController: SavingsPlansController

    init() {
        // Une restauration demandée à la session précédente s'applique avant d'ouvrir la base
        BackupManager.applyPendingRestoreIfNeeded()

        // Initialiser la base de données
        do {
            self.db = try SQLiteManager(dbName: "iFinance.sqlite")
        } catch {
            fatalError("❌ Impossible de démarrer iFinance : \(error.localizedDescription)")
        }

        // Exécuter les migrations
        let migrations = DatabaseMigrations(db: db)
        migrations.runMigrations()

        // Initialiser les repositories
        self.bookRepository = BookRepository(db: db)
        self.accountRepository = AccountRepository(db: db)
        self.transactionRepository = TransactionRepository(db: db)
        self.categoryRepository = CategoryRepository(db: db)
        self.payeeRepository = PayeeRepository(db: db)
        self.budgetRepository = BudgetRepository(db: db)
        self.annualBudgetRepository = AnnualBudgetRepository(db: db)
        self.projectRepository = ProjectRepository(db: db)
        self.recurringTemplateRepository = RecurringTemplateRepository(db: db)
        self.investmentPositionRepository = InvestmentPositionRepository(db: db)
        self.investmentTransactionRepository = InvestmentTransactionRepository(db: db)
        self.savingsPlanRepository = SavingsPlanRepository(db: db)

        // Initialiser les controllers
        self.bookController = BooksController(repository: bookRepository)
        self.accountsController = AccountsController(repository: accountRepository)
        self.transactionsController = TransactionsController(repository: transactionRepository)
        self.categoriesController = CategoriesController(repository: categoryRepository)
        self.payeesController = PayeesController(repository: payeeRepository)
        self.budgetsController = BudgetsController(repository: budgetRepository)
        self.annualBudgetController = AnnualBudgetController(repository: annualBudgetRepository)
        self.projectsController = ProjectsController(repository: projectRepository)
        self.recurringController = RecurringController(
            repository: recurringTemplateRepository,
            transactionRepository: transactionRepository
        )
        self.backupManager = BackupManager(db: db)
        self.investmentsController = InvestmentsController(
            positionRepository: investmentPositionRepository,
            transactionRepository: investmentTransactionRepository
        )
        self.savingsPlansController = SavingsPlansController(repository: savingsPlanRepository)

        // Le filtre par catégorie parente inclut ses sous-catégories
        transactionsController.subcategoryIDs = { [weak categoriesController] categoryID in
            categoriesController?.getSubcategories(for: categoryID).map { $0.id } ?? []
        }

        // Les comptes marqués « hors budget » ne consomment pas les budgets
        budgetsController.excludedAccountIDs = { [weak accountsController] in
            accountsController?.budgetExcludedAccountIDs ?? []
        }

        print("✅ iFinance AppState initialisé")
    }
}
