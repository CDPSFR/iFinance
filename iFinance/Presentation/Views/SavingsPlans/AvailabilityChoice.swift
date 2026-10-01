import SwiftUI

/// Saisie de la disponibilité d'un apport
enum AvailabilityChoice: Hashable, CaseIterable {
    case immediate
    case onDate
    case retirement

    var displayName: String {
        switch self {
        case .immediate: return "Disponible immédiatement"
        case .onDate: return "Bloqué jusqu'au"
        case .retirement: return "Bloqué jusqu'à la retraite"
        }
    }

    /// Choix correspondant à une date de disponibilité stockée
    init(availableOn: Date?, contributionDate: Date) {
        guard let availableOn else {
            self = .retirement
            return
        }
        self = availableOn <= contributionDate ? .immediate : .onDate
    }

    /// Date à stocker (nil = jusqu'à la retraite)
    func availableOn(contributionDate: Date, chosenDate: Date) -> Date? {
        switch self {
        case .immediate: return contributionDate
        case .onDate: return chosenDate
        case .retirement: return nil
        }
    }
}

struct AvailabilityFields: View {
    @Binding var choice: AvailabilityChoice
    @Binding var date: Date
    let rule: AvailabilityRule

    var body: some View {
        Picker("Disponibilité", selection: $choice) {
            ForEach(AvailabilityChoice.allCases, id: \.self) { choice in
                Text(choice.displayName).tag(choice)
            }
        }

        if choice == .onDate {
            DatePicker("Disponible le", selection: $date, displayedComponents: .date)
        }

        if case .lockedYears(let years) = rule {
            Text("Par défaut : \(years) ans après le versement. La date exacte dépend du règlement de votre plan (figure sur vos relevés).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
