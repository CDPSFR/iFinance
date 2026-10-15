import SwiftUI

/// Réglages › Livres : protection du livre sélectionné par un mot de passe
struct BookProtectionSection: View {
    let book: Book
    @EnvironmentObject var bookLock: BookLockController
    @EnvironmentObject var booksController: BooksController

    enum Action: String, Identifiable {
        case protect, change, remove, recovery
        var id: String { rawValue }
    }

    @State private var action: Action?

    private var isProtected: Bool { bookLock.isProtected(book.id) }
    private var isOpenAndUnlocked: Bool { book.id == booksController.currentBook?.id && !bookLock.isLocked }

    var body: some View {
        Section {
            LabeledContent {
                if isProtected {
                    HStack(spacing: 8) {
                        Button("Modifier…") { action = .change }
                        Button("Retirer…") { action = .remove }
                    }
                } else {
                    Button("Protéger…") { action = .protect }
                        .disabled(!bookLock.isAvailable)
                }
            } label: {
                Label(isProtected ? "Protégé par un mot de passe" : "Mot de passe",
                      systemImage: isProtected ? "lock.fill" : "lock.open")
                Text(isProtected
                     ? "La base de ce livre est chiffrée : sans le mot de passe ou la clé de secours, elle est illisible."
                     : "Chiffre la base de ce livre et demande un mot de passe pour l'ouvrir.")
            }

            if isProtected {
                LabeledContent {
                    Button("Générer…") { action = .recovery }
                } label: {
                    Text("Clé de secours")
                    Text("Remplace la clé de secours ; l'ancienne ne fonctionnera plus.")
                }

                if bookLock.biometricsAvailable {
                    Toggle(isOn: Binding(
                        get: { bookLock.isBiometricEnabled(for: book.id) },
                        set: { enabled in
                            if enabled {
                                if !bookLock.enableBiometrics(for: book.id) {
                                    bookLock.errorMessage = "Ouvrez et déverrouillez ce livre pour activer Touch ID."
                                }
                            } else {
                                bookLock.removeBiometricKey(for: book.id)
                            }
                        }
                    )) {
                        Text("Déverrouiller avec Touch ID")
                        Text(isOpenAndUnlocked ? "La clé du livre est gardée dans le trousseau de ce Mac." : "Ouvrez et déverrouillez ce livre pour l'activer.")
                    }
                    .disabled(!isOpenAndUnlocked && !bookLock.isBiometricEnabled(for: book.id))
                }
            }
        }
        .sheet(item: $action) { action in
            BookPasswordSheet(book: book, action: action, isPresented: Binding(
                get: { self.action != nil },
                set: { if !$0 { self.action = nil } }
            ))
        }
    }
}

/// Protéger, modifier le mot de passe, retirer la protection, nouvelle clé de secours
struct BookPasswordSheet: View {
    let book: Book
    let action: BookProtectionSection.Action
    @Binding var isPresented: Bool
    @EnvironmentObject var bookLock: BookLockController
    @EnvironmentObject var booksController: BooksController

    @State private var current = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var understood = false
    @State private var recoveryCode: String?
    @State private var noted = false
    @State private var error: String?

    private var title: String {
        switch action {
        case .protect: return "Protéger le livre"
        case .change: return "Modifier le mot de passe"
        case .remove: return "Retirer la protection"
        case .recovery: return "Nouvelle clé de secours"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, subtitle: "Livre « \(book.name) »")

            if let recoveryCode {
                RecoveryCodeNotice(code: recoveryCode, intro: action == .protect
                    ? "Le livre est chiffré. Si vous oubliez le mot de passe, seule cette clé permettra de l'ouvrir."
                    : "L'ancienne clé de secours ne fonctionne plus. Notez la nouvelle.")
                    .padding(20)
                Toggle("J'ai noté ma clé de secours en lieu sûr", isOn: $noted)
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
                SheetFooter {
                    EmptyView()
                } actions: {
                    Button("Terminer") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!noted)
                }
            } else {
                Form {
                    switch action {
                    case .protect:
                        Section {
                            NewPasswordFields(password: $password, confirmation: $confirmation)
                        } footer: {
                            Toggle(isOn: $understood) {
                                Text("Je comprends que sans le mot de passe ni la clé de secours, les données de ce livre seront perdues.")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.checkbox)
                            .padding(.top, 6)
                        }
                    case .change:
                        Section { SecureField("Mot de passe actuel", text: $current) }
                        Section("Nouveau mot de passe") { NewPasswordFields(password: $password, confirmation: $confirmation) }
                    case .remove:
                        Section {
                            SecureField("Mot de passe", text: $current)
                        } footer: {
                            Text("La base du livre sera enregistrée en clair : lisible par toute personne ayant accès à ce Mac ou à ses sauvegardes.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    case .recovery:
                        Section { SecureField("Mot de passe", text: $current) }
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .formStyle(.grouped)

                SheetFooter {
                    if bookLock.isWorking { ProgressView().controlSize(.small) }
                } actions: {
                    Button("Annuler") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle) { Task { await perform() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValid || bookLock.isWorking)
                }
            }
        }
        .frame(width: 460, height: action == .protect ? 380 : 340)
        .sheetBackground()
    }

    private var confirmTitle: String {
        switch action {
        case .protect: return "Protéger"
        case .change: return "Modifier"
        case .remove: return "Retirer la protection"
        case .recovery: return "Générer"
        }
    }

    private var isValid: Bool {
        switch action {
        case .protect: return NewPasswordFields.isValid(password, confirmation) && understood
        case .change: return !current.isEmpty && NewPasswordFields.isValid(password, confirmation)
        case .remove, .recovery: return !current.isEmpty
        }
    }

    private func perform() async {
        error = nil
        do {
            switch action {
            case .protect:
                recoveryCode = try await bookLock.protect(book.id, password: password)
            case .change:
                try await bookLock.changePassword(book.id, current: current, new: password)
                isPresented = false
            case .remove:
                try await bookLock.unprotect(book.id, password: current)
                isPresented = false
            case .recovery:
                recoveryCode = try await bookLock.regenerateRecoveryCode(book.id, password: current)
            }
            // Le cadenas des listes de livres suit l'état de protection
            await booksController.loadBooks()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
