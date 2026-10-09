import Foundation
import SwiftUI
import Combine

/// Conditions de prêt et frais des comptes, utilisés par les rapports patrimoniaux
@MainActor
class AccountTermsController: ObservableObject {
    @Published var terms: [UUID: AccountTerms] = [:]
    @Published var error: Error?

    private let repository: AccountTermsRepository

    init(repository: AccountTermsRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            let all = try await repository.fetchAll()
            terms = Dictionary(all.map { ($0.accountID, $0) }, uniquingKeysWith: { _, last in last })
        } catch {
            self.error = error
            print("❌ Erreur chargement conditions des comptes: \(error)")
        }
    }

    func accountTerms(for accountID: UUID) -> AccountTerms {
        terms[accountID] ?? AccountTerms(accountID: accountID)
    }

    func loan(for accountID: UUID) -> LoanTerms? {
        terms[accountID]?.loan
    }

    func feeRate(for accountID: UUID) -> Double? {
        terms[accountID]?.annualFeeRate
    }

    func save(_ newTerms: AccountTerms) async {
        do {
            if newTerms.loan == nil && newTerms.annualFeeRate == nil {
                try await repository.delete(accountID: newTerms.accountID)
                terms[newTerms.accountID] = nil
            } else {
                try await repository.save(newTerms)
                terms[newTerms.accountID] = newTerms
            }
        } catch {
            self.error = error
            print("❌ Erreur enregistrement conditions du compte: \(error)")
        }
    }
}
