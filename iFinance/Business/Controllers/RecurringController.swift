import Foundation
import SwiftUI
import Combine

/// Transactions récurrentes : modèles, échéances calculées, validation.
/// Une échéance ne devient une transaction qu'à sa validation (ou à sa saisie automatique).
@MainActor
class RecurringController: ObservableObject {
    @Published var templates: [RecurringTemplate] = []
    @Published var error: Error?

    /// Fenêtre d'affichage des échéances à venir, en jours
    nonisolated static let horizonDays = 30

    private let repository: RecurringTemplateRepository
    private let transactionRepository: TransactionRepositoryProtocol
    private var currentBookID: UUID?

    init(repository: RecurringTemplateRepository, transactionRepository: TransactionRepositoryProtocol) {
        self.repository = repository
        self.transactionRepository = transactionRepository
    }

    // MARK: - Chargement

    /// Charge les récurrences du livre, puis saisit les échéances automatiques arrivées à terme.
    /// À appeler avant le chargement des transactions, pour que celles-ci incluent les saisies.
    func load(for bookID: UUID) async {
        currentBookID = bookID
        await reload()
        await postAutomaticOccurrences()
    }

    private func reload() async {
        guard let bookID = currentBookID else { return }
        do {
            templates = try await repository.fetchAll(for: bookID)
        } catch {
            self.error = error
            print("❌ Erreur chargement récurrences: \(error)")
        }
    }

    // MARK: - Lecture

    func template(id: UUID?) -> RecurringTemplate? {
        guard let id else { return nil }
        return templates.first { $0.id == id }
    }

    /// Échéances en retard et à venir, de la plus ancienne à la plus lointaine.
    /// `accountID` nil = tous les comptes.
    func occurrences(accountID: UUID? = nil, within days: Int = RecurringController.horizonDays) -> [RecurringOccurrence] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: Date())) ?? Date()
        return occurrences(accountID: accountID, until: horizon)
    }

    func occurrences(accountID: UUID? = nil, until horizon: Date) -> [RecurringOccurrence] {
        var result: [RecurringOccurrence] = []

        for template in templates where template.isActive {
            if let accountID, template.accountID != accountID { continue }

            var date = template.nextDueDate
            var isNext = true
            var guardCount = 0
            while date <= horizon, guardCount < 120 {
                if let endDate = template.endDate, date > endDate { break }
                result.append(RecurringOccurrence(template: template, date: date, isNext: isNext))
                isNext = false
                date = template.nextDate(after: date)
                guardCount += 1
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    /// Échéances arrivées à terme et non traitées (pastille de la barre latérale)
    var dueCount: Int {
        occurrences(within: 0).count
    }

    var lateCount: Int {
        occurrences(within: 0).filter { $0.isLate }.count
    }

    /// Charges récurrentes ramenées au mois (valeur positive)
    var monthlyCharges: Decimal {
        templates
            .filter { $0.isActive && $0.type == .debit }
            .reduce(Decimal(0)) { $0 + abs($1.monthlyAmount) }
    }

    /// Revenus récurrents ramenés au mois
    var monthlyIncome: Decimal {
        templates
            .filter { $0.isActive && $0.type == .credit }
            .reduce(Decimal(0)) { $0 + abs($1.monthlyAmount) }
    }

    /// Fin du mois en cours (dernier instant)
    nonisolated static var endOfCurrentMonth: Date {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? Date()
        return next.addingTimeInterval(-1)
    }

    /// Somme signée des échéances non traitées d'ici la fin du mois, pour le solde prévu
    func pendingAmount(accountID: UUID?, until date: Date = RecurringController.endOfCurrentMonth) -> Decimal {
        occurrences(accountID: accountID, until: date)
            .reduce(Decimal(0)) { $0 + $1.template.signedAmount }
    }

    // MARK: - CRUD

    func create(_ template: RecurringTemplate) async {
        do {
            try await repository.create(template)
            await reload()
        } catch {
            self.error = error
            print("❌ Erreur création récurrence: \(error)")
        }
    }

    func update(_ template: RecurringTemplate) async {
        do {
            try await repository.update(template)
            await reload()
        } catch {
            self.error = error
            print("❌ Erreur mise à jour récurrence: \(error)")
        }
    }

    func delete(id: UUID) async {
        do {
            try await repository.delete(id: id)
            await reload()
        } catch {
            self.error = error
            print("❌ Erreur suppression récurrence: \(error)")
        }
    }

    /// Suspend ou reprend une récurrence. À la reprise, les échéances passées pendant la
    /// suspension ne sont pas rattrapées : on repart de la prochaine date à venir.
    func setActive(_ isActive: Bool, for template: RecurringTemplate) async {
        var updated = template
        updated.isActive = isActive
        if isActive {
            let today = Calendar.current.startOfDay(for: Date())
            var guardCount = 0
            while updated.nextDueDate < today, guardCount < 1000 {
                updated.nextDueDate = updated.nextDate(after: updated.nextDueDate)
                guardCount += 1
            }
        }
        await update(updated)
    }

    // MARK: - Traitement des échéances

    /// Valide l'échéance : crée la transaction, puis avance la récurrence.
    /// `amount` et `date` remplacent ceux du modèle (montant variable, date réelle du prélèvement).
    /// Le rechargement des transactions reste à la charge de l'appelant.
    func validate(_ occurrence: RecurringOccurrence, amount: Decimal? = nil, date: Date? = nil) async {
        guard occurrence.isNext, let template = template(id: occurrence.template.id) else { return }

        do {
            try await transactionRepository.create(transaction(for: template, date: date ?? occurrence.date, amount: amount))
            try await repository.update(advanced(template, past: occurrence.date))
            await reload()
        } catch {
            self.error = error
            print("❌ Erreur validation échéance: \(error)")
        }
    }

    /// Passe l'échéance : aucune transaction, la récurrence avance à la suivante
    func skip(_ occurrence: RecurringOccurrence) async {
        guard occurrence.isNext, let template = template(id: occurrence.template.id) else { return }

        do {
            try await repository.update(advanced(template, past: occurrence.date))
            await reload()
        } catch {
            self.error = error
            print("❌ Erreur passage échéance: \(error)")
        }
    }

    /// Saisit les échéances arrivées à terme des récurrences en saisie automatique.
    /// Les autres restent affichées « en retard » jusqu'à validation ou passage.
    private func postAutomaticOccurrences() async {
        let today = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        var didPost = false

        for template in templates where template.isActive && template.autoPost {
            var current = template
            var guardCount = 0

            while current.isActive, current.nextDueDate < today, guardCount < 120 {
                if let endDate = current.endDate, current.nextDueDate > endDate { break }
                do {
                    try await transactionRepository.create(transaction(for: current, date: current.nextDueDate, amount: nil))
                    current = advanced(current, past: current.nextDueDate)
                    try await repository.update(current)
                    didPost = true
                } catch {
                    self.error = error
                    print("❌ Erreur saisie automatique: \(error)")
                    break
                }
                guardCount += 1
            }
        }

        if didPost { await reload() }
    }

    // MARK: - Outils

    private func transaction(for template: RecurringTemplate, date: Date, amount: Decimal?) -> Transaction {
        Transaction(
            date: date,
            amount: abs(amount ?? template.amount),
            accountID: template.accountID,
            payeeID: template.payeeID,
            categoryID: template.categoryID,
            type: template.type,
            memo: template.memo,
            recurringTemplateID: template.id,
            status: .cleared
        )
    }

    /// Récurrence avancée à l'échéance suivant `date` ; désactivée si sa date de fin est dépassée
    private func advanced(_ template: RecurringTemplate, past date: Date) -> RecurringTemplate {
        var updated = template
        updated.nextDueDate = template.nextDate(after: date)
        if let endDate = template.endDate, updated.nextDueDate > endDate {
            updated.isActive = false
        }
        return updated
    }
}
