import Foundation

struct DatabaseSchema {
    
    static let createTableStatements: [String] = [
        createBooksTable,
        createAccountsTable,
        createCategoriesTable,
        createPayeesTable,
        createTransactionsTable,
        createRecurringTemplatesTable,
        createBudgetsTable,
        createBudgetVersionsTable,
        createInvestmentPositionsTable,
        createInvestmentTransactionsTable,
        createAccountValuationsTable,
        createContributionDetailsTable
    ]
    
    static let migrationStatements: [String] = [
        // Accounts
        "ALTER TABLE accounts ADD COLUMN iban TEXT;",
        "ALTER TABLE accounts ADD COLUMN bic TEXT;",
        "ALTER TABLE accounts ADD COLUMN is_excluded_from_reports INTEGER NOT NULL DEFAULT 0;",
        "ALTER TABLE accounts ADD COLUMN initial_balance_date TEXT;",
        "ALTER TABLE accounts ADD COLUMN is_hidden_from_sidebar INTEGER NOT NULL DEFAULT 0;",
        "ALTER TABLE accounts ADD COLUMN is_excluded_from_budgets INTEGER NOT NULL DEFAULT 0;",
        // Books
        "ALTER TABLE books ADD COLUMN color TEXT;"
    ]

    static let createIndexStatements: [String] = [
        // Indexes pour Transactions
        "CREATE INDEX IF NOT EXISTS idx_transactions_account_date ON transactions(account_id, date);",
        "CREATE INDEX IF NOT EXISTS idx_transactions_status_date ON transactions(status, date);",
        "CREATE INDEX IF NOT EXISTS idx_transactions_template ON transactions(recurring_template_id);",
        "CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id);",
        "CREATE INDEX IF NOT EXISTS idx_transactions_payee ON transactions(payee_id);",
        
        // Indexes pour Accounts
        "CREATE INDEX IF NOT EXISTS idx_accounts_book ON accounts(book_id);",
        
        // Indexes pour Categories
        "CREATE INDEX IF NOT EXISTS idx_categories_book ON categories(book_id);",
        "CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(parent_id);",
        
        // Indexes pour Payees
        "CREATE INDEX IF NOT EXISTS idx_payees_book ON payees(book_id);",
        
        // Indexes pour Budgets
        "CREATE INDEX IF NOT EXISTS idx_budgets_book ON budgets(book_id);",
        "CREATE INDEX IF NOT EXISTS idx_budget_versions_budget ON budget_versions(budget_id);",
        
        // Indexes pour Recurring Templates
        "CREATE INDEX IF NOT EXISTS idx_recurring_book ON recurring_templates(book_id);",
        "CREATE INDEX IF NOT EXISTS idx_recurring_active ON recurring_templates(is_active);",
        
        // Indexes pour Investment Positions
        "CREATE INDEX IF NOT EXISTS idx_positions_account ON investment_positions(account_id);",
        
        // Indexes pour Investment Transactions
        "CREATE INDEX IF NOT EXISTS idx_investment_txs_account ON investment_transactions(account_id);",
        "CREATE INDEX IF NOT EXISTS idx_investment_txs_position ON investment_transactions(position_id);",

        // Indexes pour les valorisations de comptes
        "CREATE INDEX IF NOT EXISTS idx_valuations_account_date ON account_valuations(account_id, date);"
    ]
    
    // MARK: - Books
    
    private static let createBooksTable = """
    CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'EUR',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        archived_at TEXT,
        color TEXT
    );
    """
    
    // MARK: - Accounts
    
    private static let createAccountsTable = """
    CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        bank TEXT,
        type TEXT NOT NULL,
        initial_balance REAL NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'EUR',
        iban TEXT,
        bic TEXT,
        is_excluded_from_reports INTEGER NOT NULL DEFAULT 0,
        initial_balance_date TEXT,
        is_hidden_from_sidebar INTEGER NOT NULL DEFAULT 0,
        is_excluded_from_budgets INTEGER NOT NULL DEFAULT 0,
        is_closed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );
    """
    
    // MARK: - Categories
    
    private static let createCategoriesTable = """
    CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        parent_id TEXT,
        color TEXT,
        icon TEXT,
        is_income INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL
    );
    """
    
    // MARK: - Payees
    
    private static let createPayeesTable = """
    CREATE TABLE IF NOT EXISTS payees (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        city TEXT,
        postal_code TEXT,
        notes TEXT,
        default_category_id TEXT,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY (default_category_id) REFERENCES categories(id) ON DELETE SET NULL
    );
    """
    
    // MARK: - Transactions
    
    private static let createTransactionsTable = """
    CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        account_id TEXT NOT NULL,
        to_account_id TEXT,
        linked_transaction_id TEXT,
        payee_id TEXT,
        category_id TEXT,
        type TEXT NOT NULL,
        memo TEXT,
        is_reconciled INTEGER NOT NULL DEFAULT 0,
        recurring_template_id TEXT,
        status TEXT NOT NULL DEFAULT 'cleared',
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
        FOREIGN KEY (to_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
        FOREIGN KEY (linked_transaction_id) REFERENCES transactions(id) ON DELETE SET NULL,
        FOREIGN KEY (payee_id) REFERENCES payees(id) ON DELETE SET NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
        FOREIGN KEY (recurring_template_id) REFERENCES recurring_templates(id) ON DELETE SET NULL
    );
    """
    
    // MARK: - Recurring Templates
    
    private static let createRecurringTemplatesTable = """
    CREATE TABLE IF NOT EXISTS recurring_templates (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        to_account_id TEXT,
        payee_id TEXT,
        category_id TEXT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        memo TEXT,
        frequency TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        day_of_month INTEGER,
        day_of_week INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
        FOREIGN KEY (to_account_id) REFERENCES accounts(id) ON DELETE SET NULL,
        FOREIGN KEY (payee_id) REFERENCES payees(id) ON DELETE SET NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
    );
    """
    
    // MARK: - Budgets

    private static let createBudgetsTable = """
    CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        note TEXT,
        period TEXT NOT NULL,
        category_ids TEXT NOT NULL DEFAULT '[]',
        anchor_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    );
    """

    static let createBudgetVersionsTable: String = """
    CREATE TABLE IF NOT EXISTS budget_versions (
        id TEXT PRIMARY KEY,
        budget_id TEXT NOT NULL,
        amount TEXT NOT NULL,
        effective_from TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY (budget_id) REFERENCES budgets(id) ON DELETE CASCADE
    );
    """
    
    // MARK: - Investment Positions
    
    private static let createInvestmentPositionsTable = """
    CREATE TABLE IF NOT EXISTS investment_positions (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        symbol TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity REAL NOT NULL,
        average_cost REAL NOT NULL,
        current_price REAL,
        currency TEXT NOT NULL DEFAULT 'EUR',
        asset_type TEXT NOT NULL,
        last_updated TEXT,
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
    );
    """
    
    // MARK: - Investment Transactions
    
    private static let createInvestmentTransactionsTable = """
    CREATE TABLE IF NOT EXISTS investment_transactions (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        position_id TEXT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        symbol TEXT,
        quantity REAL,
        price REAL,
        amount REAL NOT NULL,
        fees REAL NOT NULL DEFAULT 0,
        memo TEXT,
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
        FOREIGN KEY (position_id) REFERENCES investment_positions(id) ON DELETE SET NULL
    );
    """

    // MARK: - Account Valuations (relevés des plans d'épargne)

    static let createAccountValuationsTable = """
    CREATE TABLE IF NOT EXISTS account_valuations (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        date TEXT NOT NULL,
        value REAL NOT NULL,
        note TEXT,
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
    );
    """

    // MARK: - Contribution Details (origine et disponibilité des apports)

    static let createContributionDetailsTable = """
    CREATE TABLE IF NOT EXISTS contribution_details (
        transaction_id TEXT PRIMARY KEY,
        origin TEXT NOT NULL,
        available_on TEXT,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
    );
    """
}
