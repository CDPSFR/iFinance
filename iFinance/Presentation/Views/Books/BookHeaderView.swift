import SwiftUI

struct BookHeaderView: View {
    @EnvironmentObject var bookController: BooksController
    @Binding var showBookSelector: Bool
    @Binding var showBookForm: Bool
    
    var body: some View {
        
        Divider()
        HStack {
            
            
            // Logo et titre
            /*HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("iFinance")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()*/
            
            // Sélecteur de Book
            Menu {
                if bookController.currentBook != nil {
                    Button {
                        showBookSelector = true
                    } label: {
                        Label("Gérer les livres", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                
                Button {
                    showBookForm = true
                } label: {
                    Label("Nouveau livre", systemImage: "plus")
                }
                
                Divider()
                
                ForEach(bookController.activeBooks) { book in
                    Button {
                        bookController.selectBook(book)
                    } label: {
                        HStack {
                            Text(book.name)
                            if bookController.currentBook?.id == book.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let book = bookController.currentBook {
                        Text(book.name)
                            .fontWeight(.semibold)
                        Text("(\(book.currency))")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Sélectionner un livre")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .menuStyle(.borderlessButton)
        }
        //.padding()
        //.background(Color(NSColor.windowBackgroundColor))
    }
}
