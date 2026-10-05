import SwiftUI

// MARK: - Ligne de tableau

/// Projet enrichi de sa dépense, pour l'affichage et le tri
struct ProjectTableRow: Identifiable {
    let project: Project
    let spent: Decimal
    let count: Int

    var id: UUID { project.id }
    var name: String { project.name }
    var budget: Decimal { project.budget ?? 0 }
    var remaining: Decimal { budget - spent }
    var isOverBudget: Bool { project.budget != nil && spent > budget }
    var sortDate: Date { project.startDate ?? project.createdAt }

    var progress: Double {
        guard budget > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: spent / budget).doubleValue, 0), 1)
    }
}

// MARK: - Liste des projets

struct ProjectsView: View {
    @EnvironmentObject var projectsController: ProjectsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    enum Scope: String, CaseIterable, Identifiable {
        case active = "En cours"
        case completed = "Terminés"
        case all = "Tous"

        var id: String { rawValue }
    }

    @State private var scope: Scope = .active
    @State private var searchText = ""
    @State private var selection: Set<Project.ID> = []
    @State private var sortOrder = [KeyPathComparator(\ProjectTableRow.name, comparator: .localizedStandard)]
    @State private var showForm = false
    @State private var projectToEdit: Project?
    @State private var projectToOpen: Project?
    @State private var projectToDelete: Project?
    @State private var showDeleteConfirmation = false

    var body: some View {
        let rows = tableRows

        VStack(spacing: 0) {
            if projectsController.projects.isEmpty {
                ContentUnavailableView {
                    Label("Aucun projet", systemImage: "folder")
                } description: {
                    Text("Un projet regroupe des transactions autour d'un même thème : un voyage, un achat, des travaux.")
                } actions: {
                    Button("Nouveau projet") { showForm = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summaryHeader
                Divider()
                table(rows)
                TableStatusBar(items: [
                    "\(rows.count) projet\(rows.count > 1 ? "s" : "")",
                    "Double-clic pour ouvrir un projet"
                ])
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher un projet")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Afficher", selection: $scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .help("Filtrer les projets par état")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showForm = true
                } label: {
                    Label("Nouveau projet", systemImage: "folder.badge.plus")
                }
                .help("Nouveau projet")
            }
        }
        .navigationDestination(item: $projectToOpen) { project in
            ProjectDetailView(project: project)
        }
        .sheet(isPresented: $showForm) {
            ProjectFormView(isPresented: $showForm)
        }
        .sheet(item: $projectToEdit) { project in
            ProjectFormView(
                isPresented: Binding(
                    get: { projectToEdit != nil },
                    set: { if !$0 { projectToEdit = nil } }
                ),
                projectToEdit: project
            )
        }
        .alert("Supprimer le projet ?", isPresented: $showDeleteConfirmation, presenting: projectToDelete) { project in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                Task { await delete(project) }
            }
        } message: { project in
            Text("Le projet « \(project.name) » sera supprimé. Ses transactions sont conservées et simplement détachées du projet.")
        }
    }

    // MARK: - Grands chiffres (projets en cours)

    private var summaryHeader: some View {
        let active = allRows.filter { !$0.project.isCompleted }
        let completed = allRows.count - active.count
        let budgeted = active.reduce(Decimal(0)) { $0 + $1.budget }
        let spent = active.reduce(Decimal(0)) { $0 + $1.spent }
        let remaining = active.filter { $0.project.budget != nil }.reduce(Decimal(0)) { $0 + $1.remaining }

        return HStack(alignment: .top, spacing: 40) {
            figure("Projets en cours", "\(active.count)", detail: "\(completed) terminé\(completed > 1 ? "s" : "")", isAmount: false)
            figure("Enveloppes", money(budgeted), detail: "Projets en cours")
            figure("Dépensé", money(spent), detail: "Projets en cours")
            figure("Reste à dépenser", money(remaining), detail: "Sur les enveloppes")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func figure(_ title: String, _ value: String, detail: String, isAmount: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .privacyBlur(hidden: isAmount && appSettings.hideAmounts)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tableau

    private func table(_ rows: [ProjectTableRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Projet", value: \.name) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: row.project.displayColor))
                        .frame(width: 10, height: 10)
                    Text(row.name)
                        .fontWeight(.medium)
                    if row.project.isCompleted {
                        Text("Terminé")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
            }

            TableColumn("Période", value: \.sortDate) { row in
                Text(periodText(row.project))
                    .foregroundStyle(.secondary)
            }

            TableColumn("Progression", value: \.progress) { row in
                if row.project.budget != nil {
                    ProgressView(value: row.progress)
                        .progressViewStyle(.linear)
                        .tint(row.isOverBudget ? .red : .accentColor)
                }
            }

            TableColumn("Enveloppe", value: \.budget) { row in
                amountText(row.project.budget.map { money($0) } ?? "—")
            }
            .width(110)

            TableColumn("Dépensé", value: \.spent) { row in
                amountText(money(row.spent))
            }
            .width(110)

            TableColumn("Reste", value: \.remaining) { row in
                amountText(row.project.budget == nil ? "—" : money(row.remaining), color: row.isOverBudget ? .red : .primary)
            }
            .width(110)

            TableColumn("Transactions", value: \.count) { row in
                Text("\(row.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
        }
        .contextMenu(forSelectionType: Project.ID.self) { ids in
            if let project = ids.first.flatMap({ projectsController.project(id: $0) }) {
                Button("Ouvrir") { projectToOpen = project }
                Button("Modifier…") { projectToEdit = project }
                Button(project.isCompleted ? "Rouvrir le projet" : "Marquer comme terminé") {
                    var updated = project
                    updated.isCompleted.toggle()
                    Task { await projectsController.updateProject(updated) }
                }
                Divider()
                Button("Supprimer…", role: .destructive) {
                    projectToDelete = project
                    showDeleteConfirmation = true
                }
            }
        } primaryAction: { ids in
            projectToOpen = ids.first.flatMap { projectsController.project(id: $0) }
        }
    }

    private func amountText(_ text: String, color: Color = .primary) -> some View {
        Text(text)
            .foregroundStyle(color)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .privacyBlur(hidden: appSettings.hideAmounts)
    }

    // MARK: - Données

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }

    private func periodText(_ project: Project) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        switch (project.startDate, project.endDate) {
        case let (start?, end?): return "\(start.formatted(format)) – \(end.formatted(format))"
        case let (start?, nil): return "Depuis le \(start.formatted(format))"
        case let (nil, end?): return "Jusqu'au \(end.formatted(format))"
        default: return "—"
        }
    }

    private var allRows: [ProjectTableRow] {
        let all = transactionsController.allTransactions
        return projectsController.projects.map { project in
            let transactions = projectsController.transactions(of: project.id, in: all)
            return ProjectTableRow(project: project, spent: projectsController.spent(transactions), count: transactions.count)
        }
    }

    private var tableRows: [ProjectTableRow] {
        allRows
            .filter { row in
                switch scope {
                case .active: return !row.project.isCompleted
                case .completed: return row.project.isCompleted
                case .all: return true
                }
            }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted(using: sortOrder)
    }

    private func delete(_ project: Project) async {
        await projectsController.deleteProject(id: project.id)
        selection.remove(project.id)
        // Les transactions détachées doivent être relues depuis la base
        await transactionsController.loadAllTransactions(for: accountsController.activeAccounts)
    }

    @EnvironmentObject var accountsController: AccountsController
}
