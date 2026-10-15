import SwiftUI

/// Écran d'un livre protégé et verrouillé : mot de passe, Touch ID ou clé de secours
struct BookLockView: View {
    let book: Book
    @EnvironmentObject var bookLock: BookLockController

    @State private var password = ""
    @State private var showRecovery = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(book.name)
                    .font(.title2.weight(.semibold))
                Text("Ce livre est protégé par un mot de passe.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                SecureField("Mot de passe", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordFocused)
                    .onSubmit(unlock)

                Button(action: unlock) {
                    Group {
                        if bookLock.isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Déverrouiller")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || bookLock.isWorking)

                if bookLock.isBiometricEnabled(for: book.id), bookLock.biometricsAvailable {
                    Button {
                        Task { await bookLock.unlockWithBiometrics(bookName: book.name) }
                    } label: {
                        Label("Utiliser Touch ID", systemImage: "touchid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let message = bookLock.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Mot de passe oublié ?") { showRecovery = true }
                    .buttonStyle(.link)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .frame(width: 280)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .onAppear {
            passwordFocused = true
            // Touch ID proposé d'emblée s'il est activé pour ce livre
            if bookLock.isBiometricEnabled(for: book.id), bookLock.biometricsAvailable {
                Task { await bookLock.unlockWithBiometrics(bookName: book.name) }
            }
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryUnlockSheet(book: book, isPresented: $showRecovery)
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        let attempt = password
        Task {
            if await bookLock.unlock(password: attempt) {
                password = ""
            } else {
                password = ""
                passwordFocused = true
            }
        }
    }
}

/// Mot de passe oublié : la clé de secours ouvre le livre et définit un nouveau mot de passe
struct RecoveryUnlockSheet: View {
    let book: Book
    @Binding var isPresented: Bool
    @EnvironmentObject var bookLock: BookLockController

    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var newRecoveryCode: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Mot de passe oublié", subtitle: "Livre « \(book.name) »")

            if let newRecoveryCode {
                RecoveryCodeNotice(code: newRecoveryCode, intro: "Le livre est ouvert avec son nouveau mot de passe. L'ancienne clé de secours ne fonctionne plus : notez la nouvelle.")
                    .padding(20)
                Spacer(minLength: 0)
                SheetFooter {
                    EmptyView()
                } actions: {
                    Button("Terminer") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Form {
                    Section {
                        TextField("Clé de secours", text: $code, prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                            .font(.body.monospaced())
                    } footer: {
                        Text("La clé de secours a été affichée quand le livre a été protégé. Sans elle ni le mot de passe, le livre ne peut pas être ouvert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Nouveau mot de passe") {
                        NewPasswordFields(password: $newPassword, confirmation: $confirmation)
                    }
                    if let message = bookLock.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
                .formStyle(.grouped)

                SheetFooter {
                    EmptyView()
                } actions: {
                    Button("Annuler") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Ouvrir le livre") {
                        Task { newRecoveryCode = await bookLock.unlock(recoveryCode: code, newPassword: newPassword) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.isEmpty || !NewPasswordFields.isValid(newPassword, confirmation) || bookLock.isWorking)
                }
            }
        }
        .frame(width: 460, height: 440)
        .sheetBackground()
    }
}

/// Nouveau mot de passe et sa confirmation, avec la règle de longueur
struct NewPasswordFields: View {
    @Binding var password: String
    @Binding var confirmation: String

    static func isValid(_ password: String, _ confirmation: String) -> Bool {
        password.count >= BookCrypto.minimumPasswordLength && password == confirmation
    }

    var body: some View {
        SecureField("Mot de passe", text: $password)
        SecureField("Confirmation", text: $confirmation)
        if !password.isEmpty, password.count < BookCrypto.minimumPasswordLength {
            Text("Au moins \(BookCrypto.minimumPasswordLength) caractères.")
                .font(.caption).foregroundStyle(.orange)
        } else if !confirmation.isEmpty, password != confirmation {
            Text("Les deux mots de passe sont différents.")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

/// Clé de secours à noter : affichée une seule fois, copiable
struct RecoveryCodeNotice: View {
    let code: String
    let intro: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Clé de secours", systemImage: "key.fill")
                .font(.headline)
            Text(intro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(code)
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            Text("Gardez-la hors de ce Mac (gestionnaire de mots de passe, papier). Elle ne sera plus jamais affichée.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
