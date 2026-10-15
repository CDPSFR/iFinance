import Foundation
import SwiftUI
import Combine

/// Catégories reliées aux cases de la déclaration de revenus (rapport « Préparer la déclaration »)
@MainActor
class TaxMappingController: ObservableObject {
    @Published var mapping: [UUID: TaxCase] = [:]
    @Published var error: Error?

    private let repository: TaxMappingRepository

    init(repository: TaxMappingRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            mapping = try await repository.fetchAll()
        } catch {
            self.error = error
            print("❌ Erreur chargement des cases fiscales: \(error)")
        }
    }

    func taxCase(for categoryID: UUID) -> TaxCase? {
        mapping[categoryID]
    }

    func set(_ taxCase: TaxCase?, for categoryID: UUID) async {
        do {
            try await repository.set(taxCase, for: categoryID)
            mapping[categoryID] = taxCase
        } catch {
            self.error = error
            print("❌ Erreur enregistrement case fiscale: \(error)")
        }
    }
}
