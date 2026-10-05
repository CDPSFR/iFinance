import SwiftUI

struct BookSelectorView: View {
    @EnvironmentObject var bookController: BooksController
    @Binding var isPresented: Bool
    @State private var showArchived = false
    @State private var showDeleteConfirmation = false
    @State private var bookToDelete: Book?
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête de feuille
            SheetHeader(title: "Mes livres")

            // Toggle Archivés
            Toggle("Afficher les livres archivés", isOn: $showArchived)
                .padding()
            
            // Liste des Books
            List {
                Section("Livres actifs") {
                    ForEach(bookController.activeBooks) { book in
                        BookRowView(
                            book: book,
                            isSelected: bookController.currentBook?.id == book.id,
                            onSelect: {
                                bookController.selectBook(book)
                                isPresented = false
                            },
                            onArchive: {
                                Task { await bookController.archiveBook(id: book.id) }
                            },
                            onDelete: {
                                bookToDelete = book
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
                
                if showArchived && !bookController.archivedBooks.isEmpty {
                    Section("Livres archivés") {
                        ForEach(bookController.archivedBooks) { book in
                            BookRowView(
                                book: book,
                                isSelected: false,
                                isArchived: true,
                                onSelect: { },
                                onUnarchive: {
                                    Task { await bookController.unarchiveBook(id: book.id) }
                                },
                                onDelete: {
                                    bookToDelete = book
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)

            // Pied de feuille : simple fermeture
            SheetFooter {
                Button("Fermer") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 600, height: 500)
        .sheetBackground()
        .alert("Supprimer le livre ?", isPresented: $showDeleteConfirmation, presenting: bookToDelete) { book in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await bookController.deleteBook(id: book.id) }
            }
        } message: { book in
            Text("Êtes-vous sûr de vouloir supprimer \"\(book.name)\" ? Cette action est irréversible et supprimera tous les comptes et transactions associés.")
        }
    }
}

struct BookRowView: View {
    let book: Book
    let isSelected: Bool
    var isArchived: Bool = false
    let onSelect: () -> Void
    var onArchive: (() -> Void)? = nil
    var onUnarchive: (() -> Void)? = nil
    var onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(book.name)
                        .font(.headline)
                    
                    if isArchived {
                        Text("Archivé")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                HStack {
                    Text(book.currency)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("Créé le \(book.createdAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
            
            // Actions
            Menu {
                if !isArchived {
                    Button {
                        onSelect()
                    } label: {
                        Label("Ouvrir", systemImage: "book.open")
                    }
                    
                    if let onArchive = onArchive {
                        Button {
                            onArchive()
                        } label: {
                            Label("Archiver", systemImage: "archivebox")
                        }
                    }
                } else {
                    if let onUnarchive = onUnarchive {
                        Button {
                            onUnarchive()
                        } label: {
                            Label("Désarchiver", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isArchived {
                onSelect()
            }
        }
    }
}
