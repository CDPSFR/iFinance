import SwiftUI

/// Sélecteur de livre en tête de barre latérale : pastille, nom, sous-titre, chevrons.
/// Un clic ouvre la liste des livres dans un popover ; le clic droit propose la création d'un livre.
struct BookSelectorButton: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @Binding var showBookForm: Bool
    @State private var showPopover = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let book = booksController.currentBook {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(book.color.map { Color(hex: $0) } ?? Color.accentColor)
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
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                BookSwitcherPopover(
                    isPresented: $showPopover,
                    showBookForm: $showBookForm
                )
            }
            .contextMenu {
                Button("Changer de livre…") { showPopover = true }
                Button("Gérer les livres…") {
                    UserDefaults.standard.set(SettingsTab.books.rawValue, forKey: SettingsKeys.selectedSettingsTab)
                    openSettings()
                }
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

// MARK: - Popover de changement de livre

/// Liste des livres actifs, ancrée sous le sélecteur de la barre latérale.
/// Un clic sur un livre le sélectionne et referme le popover.
struct BookSwitcherPopover: View {
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var accountsController: AccountsController
    @Binding var isPresented: Bool
    @Binding var showBookForm: Bool

    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""
    @State private var accountCounts: [UUID: Int] = [:]

    /// La recherche n'apparaît qu'à partir de ce nombre de livres
    private static let searchThreshold = 6

    private var books: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return booksController.activeBooks }
        return booksController.activeBooks.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Livres")
                    .fontWeight(.semibold)
                Spacer()
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            if booksController.activeBooks.count >= Self.searchThreshold {
                TextField("Rechercher un livre", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(books) { book in
                        BookSwitcherRow(
                            book: book,
                            subtitle: subtitle(for: book),
                            isCurrent: book.id == booksController.currentBook?.id
                        ) {
                            booksController.selectBook(book)
                            isPresented = false
                        }
                    }

                    if books.isEmpty {
                        Text("Aucun livre ne correspond à la recherche.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .frame(height: listHeight)

            Divider()

            VStack(spacing: 1) {
                actionRow("Nouveau livre…", systemImage: "plus", hint: "⌥⌘N") {
                    isPresented = false
                    showBookForm = true
                }
                actionRow("Gérer les livres…", systemImage: "books.vertical", hint: nil) {
                    // Ouvre la fenêtre des réglages sur l'onglet Livres
                    isPresented = false
                    UserDefaults.standard.set(SettingsTab.books.rawValue, forKey: SettingsKeys.selectedSettingsTab)
                    openSettings()
                }
            }
        }
        .padding(10)
        .frame(width: 320)
        .task {
            accountCounts = await accountsController.activeAccountCounts(for: booksController.activeBooks.map(\.id))
        }
    }

    private var countLabel: String {
        let count = booksController.activeBooks.count
        return count > 1 ? "\(count) livres" : "\(count) livre"
    }

    /// Hauteur de la liste : celle de ses lignes, plafonnée à six lignes (défilement au-delà)
    private var listHeight: CGFloat {
        CGFloat(min(max(books.count, 1), 6)) * 46
    }

    private func subtitle(for book: Book) -> String {
        guard let count = accountCounts[book.id] else { return book.currency }
        return "\(count > 1 ? "\(count) comptes" : "\(count) compte") · \(book.currency)"
    }

    private func actionRow(_ title: String, systemImage: String, hint: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ligne d'un livre dans le popover : pastille de couleur, nom, comptes et devise, coche du livre courant
private struct BookSwitcherRow: View {
    let book: Book
    let subtitle: String
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(book.name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(book.color.map { Color(hex: $0) } ?? Color.accentColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(book.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isCurrent ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(isCurrent ? "\(book.name), livre actuel" : book.name)
    }
}
