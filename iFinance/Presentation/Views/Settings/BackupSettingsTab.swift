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

    private var selectedFiles: [BackupFile] {
        backupManager.backups.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: $isEnabled) {
                        Text("Sauvegardes automatiques")
                        Text("Une copie complète de la base, tous livres confondus, est enregistrée à intervalle régulier quand l'app est ouverte.")
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
            .frame(height: 290)

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
                if backupManager.prepareRestore(from: file) {
                    showRelaunchPrompt = true
                }
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
}
