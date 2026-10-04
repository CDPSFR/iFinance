import Foundation
import SwiftUI
import Combine

@MainActor
class BooksController: ObservableObject {
    @Published var books: [Book] = []
    @Published var activeBooks: [Book] = []
    @Published var archivedBooks: [Book] = []
    @Published var currentBook: Book?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository: BookRepositoryProtocol
    private let lastBookIDKey = "lastSelectedBookID"
    
    init(repository: BookRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Load Books
    
    func loadBooks() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            books = try await repository.fetchAll()
            activeBooks = books.filter { !$0.isArchived }
            archivedBooks = books.filter { $0.isArchived }
            
            // Charger le dernier livre sélectionné ou le premier actif par défaut
            if currentBook == nil {
                loadLastSelectedBook()
            }
            
        } catch {
            self.error = error
            print("❌ Erreur chargement books: \(error)")
        }
    }
    
    func loadActiveBooks() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            activeBooks = try await repository.fetchActive()
            
            // Charger le dernier livre sélectionné ou le premier actif par défaut
            if currentBook == nil {
                loadLastSelectedBook()
            }
            
        } catch {
            self.error = error
            print("❌ Erreur chargement books actifs: \(error)")
        }
    }
    
    // MARK: - Last Selected Book
    
    private func loadLastSelectedBook() {
        // Essayer de charger le dernier livre sélectionné
        if let lastBookIDString = UserDefaults.standard.string(forKey: lastBookIDKey),
           let lastBookID = UUID(uuidString: lastBookIDString),
           let lastBook = activeBooks.first(where: { $0.id == lastBookID }) {
            currentBook = lastBook
            print("✅ Dernier livre sélectionné chargé: \(lastBook.name)")
        } else {
            // Fallback sur le premier livre actif
            currentBook = activeBooks.first
            print("ℹ️ Aucun dernier livre trouvé, sélection du premier livre actif")
        }
    }
    
    private func saveLastSelectedBook(_ bookID: UUID) {
        UserDefaults.standard.set(bookID.uuidString, forKey: lastBookIDKey)
    }
    
    // MARK: - Create Book
    
    func createBook(name: String, currency: String = "EUR", color: String? = nil) async {
        let book = Book(name: name, currency: currency, color: color)
        
        do {
            try await repository.create(book)
            await loadBooks()
            selectBook(book)  // Utiliser selectBook pour sauvegarder la sélection
        } catch {
            self.error = error
            print("❌ Erreur création book: \(error)")
        }
    }
    
    // MARK: - Update Book
    
    func updateBook(_ book: Book) async {
        do {
            try await repository.update(book)
            await loadBooks()
            
            // Mettre à jour le currentBook si c'est celui-ci
            if currentBook?.id == book.id {
                currentBook = book
            }
        } catch {
            self.error = error
            print("❌ Erreur mise à jour book: \(error)")
        }
    }
    
    // MARK: - Delete Book
    
    func deleteBook(id: UUID) async {
        do {
            try await repository.delete(id: id)
            await loadBooks()
            
            // Si on supprime le book courant, sélectionner un autre
            if currentBook?.id == id {
                if let firstActive = activeBooks.first {
                    selectBook(firstActive)
                } else {
                    currentBook = nil
                }
            }
        } catch {
            self.error = error
            print("❌ Erreur suppression book: \(error)")
        }
    }
    
    // MARK: - Archive/Unarchive
    
    func archiveBook(id: UUID) async {
        do {
            try await repository.archive(id: id)
            await loadBooks()
            
            // Si on archive le book courant, sélectionner un autre
            if currentBook?.id == id {
                if let firstActive = activeBooks.first {
                    selectBook(firstActive)
                } else {
                    currentBook = nil
                }
            }
        } catch {
            self.error = error
            print("❌ Erreur archivage book: \(error)")
        }
    }
    
    func unarchiveBook(id: UUID) async {
        do {
            try await repository.unarchive(id: id)
            await loadBooks()
        } catch {
            self.error = error
            print("❌ Erreur désarchivage book: \(error)")
        }
    }
    
    // MARK: - Select Book
    
    func selectBook(_ book: Book) {
        currentBook = book
        saveLastSelectedBook(book.id)
        print("📘 Livre sélectionné et sauvegardé: \(book.name)")
    }
}
