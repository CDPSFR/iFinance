import SwiftUI

/// Sélecteur de livre en tête de barre latérale : pastille, nom, sous-titre, chevrons.
/// Un clic ouvre la liste des livres ; le clic droit propose la création d'un livre.
struct BookSelectorButton: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @Binding var showBookSelector: Bool
    @Binding var showBookForm: Bool

    var body: some View {
        if let book = booksController.currentBook {
            Button {
                showBookSelector = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(book.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(subtitle(for: book))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Changer de livre de comptes")
            .accessibilityLabel("Changer de livre de comptes, livre actuel : \(book.name)")
            .contextMenu {
                Button("Changer de livre…") { showBookSelector = true }
                Button("Nouveau livre…") { showBookForm = true }
            }
        } else {
            VStack(spacing: 8) {
                Text("Aucun livre")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showBookForm = true
                } label: {
                    Label("Créer un livre", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func subtitle(for book: Book) -> String {
        let count = accountsController.activeAccounts.count
        let accounts = count > 1 ? "\(count) comptes" : "\(count) compte"
        return "\(book.currency) · \(accounts)"
    }
}
