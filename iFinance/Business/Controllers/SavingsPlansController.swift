import Foundation
import SwiftUI
import Combine

@MainActor
class SavingsPlansController: ObservableObject {
    /// Valeurs relevées par compte, dans l'ordre chronologique
    @Published var valuations: [UUID: [ValuationSnapshot]] = [:]
    /// Origine / disponibilité des apports, par compte puis par transaction
    @Published var details: [UUID: [UUID: ContributionDetail]] = [:]
    /// Réglages saisis pour chaque plan (plafond d'abondement, plafonds de déduction, TMI)
    @Published var settings: [UUID: SavingsPlanSettings] = [:]
    @Published var isLoading = false
    @Published var error: Error?

    private let repository: SavingsPlanRepositoryProtocol

    init(repository: SavingsPlanRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load

    func load(for accounts: [Account]) async {
        isLoading = true
        defer { isLoading = false }

        valuations = [:]
        details = [:]
        settings = [:]
        for account in accounts where account.type.trackingMode == .valuations {
            await reload(accountID: account.id)
        }
    }

    func reload(accountID: UUID) async {
        do {
            valuations[accountID] = try await repository.fetchValuations(for: accountID)
            let fetched = try await repository.fetchContributionDetails(for: accountID)
            details[accountID] = Dictionary(fetched.map { ($0.transactionID, $0) }, uniquingKeysWith: { _, last in last })
            settings[accountID] = try await repository.fetchSettings(for: accountID)
        } catch {
            self.error = error
            print("❌ Erreur chargement plan d'épargne: \(error)")
        }
    }

    // MARK: - Valuations

    func addValuation(_ snapshot: ValuationSnapshot) async {
        do {
            try await repository.createValuation(snapshot)
            await reload(accountID: snapshot.accountID)
        } catch {
            self.error = error
            print("❌ Erreur création valorisation: \(error)")
        }
    }

    func updateValuation(_ snapshot: ValuationSnapshot) async {
        do {
            try await repository.updateValuation(snapshot)
            await reload(accountID: snapshot.accountID)
        } catch {
            self.error = error
            print("❌ Erreur mise à jour valorisation: \(error)")
        }
    }

    func deleteValuation(_ snapshot: ValuationSnapshot) async {
        do {
            try await repository.deleteValuation(id: snapshot.id)
            await reload(accountID: snapshot.accountID)
        } catch {
            self.error = error
            print("❌ Erreur suppression valorisation: \(error)")
        }
    }

    // MARK: - Contribution Details

    func saveDetail(_ detail: ContributionDetail, accountID: UUID) async {
        do {
            try await repository.saveContributionDetail(detail)
            await reload(accountID: accountID)
        } catch {
            self.error = error
            print("❌ Erreur enregistrement apport: \(error)")
        }
    }

    // MARK: - Settings

    func planSettings(for accountID: UUID) -> SavingsPlanSettings {
        settings[accountID] ?? SavingsPlanSettings(accountID: accountID)
    }

    func saveSettings(_ newSettings: SavingsPlanSettings) async {
        do {
            try await repository.saveSettings(newSettings)
            settings[newSettings.accountID] = newSettings
        } catch {
            self.error = error
            print("❌ Erreur enregistrement réglages du plan: \(error)")
        }
    }

    // MARK: - Summary

    func summary(for account: Account, transactions: [Transaction], asOf date: Date = Date()) -> SavingsPlanSummary {
        SavingsPlanCalculator.summary(
            account: account,
            transactions: transactions,
            valuations: valuations[account.id] ?? [],
            details: details[account.id] ?? [:],
            asOf: date
        )
    }

    func flows(for account: Account, transactions: [Transaction]) -> [PlanFlow] {
        SavingsPlanCalculator.flows(
            account: account,
            transactions: transactions,
            details: details[account.id] ?? [:]
        )
    }
}
