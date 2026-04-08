import SwiftUI

struct CategoryListView_old: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController
    
    @State private var showCategoryForm = false
    @State private var categoryToEdit: Category?
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirmation = false
    @State private var showDefaultCategoriesAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Catégories")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                if categoriesController.categories.isEmpty {
                    Button {
                        showDefaultCategoriesAlert = true
                    } label: {
                        Label("Créer catégories par défaut", systemImage: "sparkles")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button {
                    categoryToEdit = nil
                    showCategoryForm = true
                } label: {
                    Label("Nouvelle catégorie", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Contenu
            if categoriesController.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if categoriesController.categories.isEmpty {
                emptyCategoriesView
            } else {
                categoriesListView
            }
        }
        .sheet(isPresented: $showCategoryForm) {
            if let category = categoryToEdit {
                CategoryFormView(isPresented: $showCategoryForm, categoryToEdit: category)
            } else {
                CategoryFormView(isPresented: $showCategoryForm)
            }
        }
        .alert("Supprimer la catégorie ?", isPresented: $showDeleteConfirmation, presenting: categoryToDelete) { category in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await categoriesController.deleteCategory(id: category.id) }
            }
        } message: { category in
            if categoriesController.hasSubcategories(category.id) {
                Text("Cette catégorie contient des sous-catégories. Elles seront également supprimées.")
            } else {
                Text("Cette action est irréversible.")
            }
        }
        .alert("Créer les catégories par défaut ?", isPresented: $showDefaultCategoriesAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Créer") {
                Task {
                    if let bookID = bookController.currentBook?.id {
                        await categoriesController.createDefaultCategories(for: bookID)
                    }
                }
            }
        } message: {
            Text("Ceci créera un ensemble de catégories de base (Alimentation, Transport, Salaire, etc.) avec des sous-catégories.")
        }
        .task {
            if let bookID = bookController.currentBook?.id {
                await categoriesController.loadCategories(for: bookID)
            }
        }
        .onChange(of: bookController.currentBook?.id) { oldValue, newValue in
            if let bookID = newValue {
                Task {
                    await categoriesController.loadCategories(for: bookID)
                }
            }
        }
    }
    
    private var emptyCategoriesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Aucune catégorie")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Créez vos catégories pour organiser vos transactions")
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button {
                    showDefaultCategoriesAlert = true
                } label: {
                    Label("Catégories par défaut", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                
                Button {
                    showCategoryForm = true
                } label: {
                    Label("Créer une catégorie", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var categoriesListView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Catégories de dépenses
                if !categoriesController.expenseCategories.isEmpty {
                    categorySectionView(
                        title: "Dépenses",
                        categories: categoriesController.expenseCategories,
                        color: .red
                    )
                }
                
                // Catégories de revenus
                if !categoriesController.incomeCategories.isEmpty {
                    categorySectionView(
                        title: "Revenus",
                        categories: categoriesController.incomeCategories,
                        color: .green
                    )
                }
            }
            .padding()
        }
    }
    
    private func categorySectionView(title: String, categories: [Category], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            ForEach(categories) { category in
                CategoryCardView(
                    category: category,
                    subcategories: categoriesController.getSubcategories(for: category.id),
                    onEdit: { cat in
                        categoryToEdit = cat
                        showCategoryForm = true
                    },
                    onDelete: { cat in
                        categoryToDelete = cat
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }
}
