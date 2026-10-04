import Foundation
import SwiftUI
import Combine

@MainActor
class ProjectsController: ObservableObject {
    @Published var projects: [Project] = []
    @Published var error: Error?

    private let repository: ProjectRepositoryProtocol
    private var currentBookID: UUID?

    init(repository: ProjectRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load

    func loadProjects(for bookID: UUID) async {
        currentBookID = bookID
        do {
            projects = try await repository.fetchAll(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur chargement projets: \(error)")
        }
    }

    // MARK: - Lecture

    func project(id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Projets proposés pour rattacher une transaction : ceux en cours, plus celui déjà choisi
    func selectableProjects(including selectedID: UUID?) -> [Project] {
        projects.filter { !$0.isCompleted || $0.id == selectedID }
    }

    // MARK: - CRUD

    func createProject(_ project: Project) async {
        do {
            try await repository.create(project)
            await loadProjects(for: project.bookID)
        } catch {
            self.error = error
            print("❌ Erreur création projet: \(error)")
        }
    }

    func updateProject(_ project: Project) async {
        do {
            try await repository.update(project)
            await loadProjects(for: project.bookID)
        } catch {
            self.error = error
            print("❌ Erreur mise à jour projet: \(error)")
        }
    }

    /// Supprime le projet ; ses transactions sont conservées et simplement détachées
    func deleteProject(id: UUID) async {
        do {
            try await repository.delete(id: id)
            if let bookID = currentBookID { await loadProjects(for: bookID) }
        } catch {
            self.error = error
            print("❌ Erreur suppression projet: \(error)")
        }
    }

    // MARK: - Calculs

    /// Transactions rattachées au projet, hors occurrences ignorées
    func transactions(of projectID: UUID, in all: [Transaction]) -> [Transaction] {
        all.filter { $0.projectID == projectID && $0.status != .skipped }
    }

    /// Dépense nette du projet : dépenses moins remboursements, transferts exclus
    func spent(_ transactions: [Transaction]) -> Decimal {
        transactions
            .filter { $0.type != .transfer }
            .reduce(Decimal(0)) { $0 - $1.signedAmount }
    }
}
