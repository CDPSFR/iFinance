import SwiftUI

/// Réglages › Sauvegardes : sauvegardes automatiques, dossier, liste, suppression et restauration
struct BackupSettingsTab: View {
    @EnvironmentObject var backupManager: BackupManager

    @AppStorage(BackupManager.Keys.enabled) private var isEnabled = false
    @AppStorage(BackupManager.Keys.interval) private var interval = BackupInterval.weekly.rawValue
    @AppStorage(BackupManager.Keys.keepCount) private var keepCount = 10

    @State private var selection: Set<BackupFile.ID> = []
    @State private var showDeleteConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showRelaunchPrompt = false
    @State private var passwordSheet: BackupPasswordSheet.Mode?
    /// Sauvegarde à restaurer dont le mot de passe est demandé
    @State private var restoreNeedingPassword: BackupFile?

    private var selectedFiles: [BackupFile] {
        backupManager.backups.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: $isEnabled) {
                        Text("Sauvegardes automatiques")
                        Text("Une copie chiffrée de tous les livres est enregistrée à intervalle régulier quand l'app est ouverte.")
                    }
                    .onChange(of: isEnabled) { _, enabled in
                        guard enabled else { return }
                        // Sans dossier, on le demande tout de suite ; refus = on désactive
                        if backupManager.folderURL == nil, !backupManager.chooseFolder() {
                            isEnabled = false
                            return
                        }
                        Task { await backupManager.backupIfDue() }
                    }

                    Picker("Fréquence", selection: $interval) {
                        ForEach(BackupInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval.rawValue)
                        }
                    }
                    .disabled(!isEnabled)

                    Picker("Conserver", selection: $keepCount) {
                        Text("Les 5 dernières").tag(5)
                        Text("Les 10 dernières").tag(10)
                        Text("Les 30 dernières").tag(30)
                        Text("Toutes").tag(0)
                    }
                    .disabled(!isEnabled)
                }

                Section {
                    LabeledContent {
                        if backupManager.hasBackupPassword {
                            HStack {
                                Button("Modifier…") { passwordSheet = .change }
                                Button("Supprimer…") { passwordSheet = .remove }
                            }
                        } else {
                            Button("Définir…") { passwordSheet = .set }
                        }
                    } label: {
                        Label(backupManager.hasBackupPassword ? "Mot de passe des sauvegardes défini" : "Mot de passe des sauvegardes",
                              systemImage: backupManager.hasBackupPassword ? "lock.fill" : "lock.open")
                        Text(backupManager.blockedReason
                             ?? "Chiffre les livres sans mot de passe dans chaque sauvegarde. Les livres protégés gardent le leur.")
                            .foregroundStyle(backupManager.blockedReason == nil ? Color.secondary : Color.orange)
                    }
                }

                Section {
                    LabeledContent {
                        HStack {
                            Button("Choisir…") { backupManager.chooseFolder() }
                            Button("Afficher dans le Finder") { backupManager.revealFolder() }
                                .disabled(backupManager.folderURL == nil)
                        }
                    } label: {
                        Text("Dossier")
                        Text(backupManager.folderURL?.path ?? "Non choisi. Dossier conseillé : \(BackupManager.suggestedFolderURL.path)")
                            .textSelection(.enabled)
                    }

                    LabeledContent {
                        Button(backupManager.isWorking ? "Sauvegarde…" : "Sauvegarder maintenant") {
                            if backupManager.folderURL == nil, !backupManager.chooseFolder() { return }
                            Task { await backupManager.backupNow() }
                        }
                        .disabled(backupManager.isWorking)
                    } label: {
                        Text("Dernière sauvegarde")
                        Text(backupManager.lastBackupDate?.formatted(date: .long, time: .shortened) ?? "Aucune")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 370)

            Table(backupManager.backups, selection: $selection) {
                TableColumn("Sauvegarde") { file in
                    Text(file.date.formatted(date: .long, time: .shortened))
                }

                TableColumn("Fichier") { file in
                    Text(file.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                TableColumn("Taille") { file in
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(80)
            }
            .overlay {
                if backupManager.backups.isEmpty {
                    Text(backupManager.folderURL == nil ? "Choisissez un dossier pour commencer." : "Aucune sauvegarde dans ce dossier.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Text("\(backupManager.backups.count) sauvegarde\(backupManager.backups.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                    .disabled(selection.isEmpty)

                Button("Restaurer…") { showRestoreConfirmation = true }
                    .disabled(selectedFiles.count != 1)
                    .help("Remplacer la base actuelle par la sauvegarde sélectionnée")
            }
            .padding(16)
        }
        .onAppear { backupManager.refresh() }
        .alert(
            selectedFiles.count > 1 ? "Supprimer \(selectedFiles.count) sauvegardes ?" : "Supprimer cette sauvegarde ?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                backupManager.delete(selectedFiles)
                selection = []
            }
        } message: {
            Text("Les fichiers sont placés dans la Corbeille. La base actuelle n'est pas touchée.")
        }
        .alert("Restaurer cette sauvegarde ?", isPresented: $showRestoreConfirmation, presenting: selectedFiles.first) { file in
            Button("Annuler", role: .cancel) { }
            Button("Restaurer", role: .destructive) {
                Task { await restore(file, password: nil) }
            }
        } message: { file in
            Text("Toutes les données actuelles seront remplacées par celles du \(file.date.formatted(date: .long, time: .shortened)). Ce qui a été saisi depuis sera perdu. La base actuelle est gardée de côté par sécurité jusqu'à la restauration suivante.")
        }
        .alert("Relancer iFinance", isPresented: $showRelaunchPrompt) {
            Button("Plus tard", role: .cancel) { }
            Button("Relancer maintenant") { backupManager.relaunch() }
        } message: {
            Text("La restauration sera appliquée au prochain lancement de l'app.")
        }
        .sheet(item: $passwordSheet) { mode in
            BackupPasswordSheet(mode: mode, isPresented: Binding(
                get: { passwordSheet != nil },
                set: { if !$0 { passwordSheet = nil } }
            ))
        }
        .sheet(item: $restoreNeedingPassword) { file in
            RestorePasswordSheet(file: file, isPresented: Binding(
                get: { restoreNeedingPassword != nil },
                set: { if !$0 { restoreNeedingPassword = nil } }
            )) { password in
                await restore(file, password: password)
            }
        }
        .alert(
            "Sauvegardes",
            isPresented: Binding(
                get: { backupManager.errorMessage != nil },
                set: { if !$0 { backupManager.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupManager.errorMessage ?? "")
        }
    }

    /// Prépare la restauration ; demande le mot de passe de sauvegarde s'il faut
    @discardableResult
    private func restore(_ file: BackupFile, password: String?) async -> RestorePreparation {
        let result = await backupManager.prepareRestore(from: file, password: password)
        switch result {
        case .ready:
            restoreNeedingPassword = nil
            showRelaunchPrompt = true
        case .needsPassword:
            restoreNeedingPassword = file
        case .failed:
            restoreNeedingPassword = nil
        }
        return result
    }
}

/// Définir, modifier ou supprimer le mot de passe des sauvegardes
struct BackupPasswordSheet: View {
    enum Mode: String, Identifiable {
        case set, change, remove
        var id: String { rawValue }
    }

    let mode: Mode
    @Binding var isPresented: Bool
    @EnvironmentObject var backupManager: BackupManager

    @State private var current = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: mode == .set ? "Mot de passe des sauvegardes" : mode == .change ? "Modifier le mot de passe des sauvegardes" : "Supprimer le mot de passe des sauvegardes")
            Form {
                if mode != .set {
                    Section { SecureField("Mot de passe actuel", text: $current) }
                }
                if mode != .remove {
                    Section {
                        NewPasswordFields(password: $password, confirmation: $confirmation)
                    } footer: {
                        Text("Gardé dans le trousseau de ce Mac pour les sauvegardes automatiques. Il sera demandé pour restaurer une sauvegarde sur un autre Mac : notez-le. Les sauvegardes déjà faites gardent leur ancien mot de passe.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Sans mot de passe, les livres non protégés ne seront plus sauvegardés. Les sauvegardes existantes restent chiffrées avec ce mot de passe.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            SheetFooter {
                EmptyView()
            } actions: {
                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .remove ? "Supprimer" : "Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .frame(width: 460, height: 340)
        .sheetBackground()
    }

    private var isValid: Bool {
        switch mode {
        case .set: return NewPasswordFields.isValid(password, confirmation)
        case .change: return !current.isEmpty && NewPasswordFields.isValid(password, confirmation)
        case .remove: return !current.isEmpty
        }
    }

    private func save() {
        do {
            try backupManager.setBackupPassword(mode == .remove ? nil : password, current: mode == .set ? nil : current)
            isPresented = false
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Mot de passe d'une sauvegarde à restaurer (chiffrée avec un autre mot de passe que l'actuel)
struct RestorePasswordSheet: View {
    let file: BackupFile
    @Binding var isPresented: Bool
    let onSubmit: (String) async -> RestorePreparation

    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Mot de passe de la sauvegarde", subtitle: file.date.formatted(date: .long, time: .shortened))
            Form {
                Section {
                    SecureField("Mot de passe des sauvegardes", text: $password)
                } footer: {
                    Text("C'était le mot de passe des sauvegardes au moment où celle-ci a été faite.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            SheetFooter {
                if isWorking { ProgressView().controlSize(.small) }
            } actions: {
                Button("Annuler") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Restaurer") {
                    isWorking = true
                    Task {
                        let result = await onSubmit(password)
                        isWorking = false
                        if result == .needsPassword { error = "Mot de passe incorrect." }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || isWorking)
            }
        }
        .frame(width: 420, height: 260)
        .sheetBackground()
    }
}
