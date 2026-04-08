import SwiftUI

struct BookSelectorButton: View {
    @EnvironmentObject var booksController: BooksController
    @Binding var showBookSelector: Bool
    @Binding var showBookForm: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            if let book = booksController.currentBook {
                // Livre actuel
                Button {
                    showBookSelector = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.name)
                                .font(.body)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            
                            Text(book.currency)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    //.background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Bouton nouveau livre
                Button {
                    showBookForm = true
                } label: {
                    Label("Nouveau livre", systemImage: "plus.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            } else {
                // Aucun livre
                VStack(spacing: 8) {
                    Text("Aucun livre")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showBookForm = true
                    } label: {
                        Label("Créer un livre", systemImage: "plus.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }
}
