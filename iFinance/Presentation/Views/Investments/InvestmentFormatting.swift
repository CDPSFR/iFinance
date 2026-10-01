import Foundation

extension Decimal {
    /// Saisie utilisateur : accepte la virgule décimale et les espaces
    init?(userInput: String) {
        let cleaned = userInput
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        // Decimal(string:) accepte un préfixe numérique ("12abc" → 12) : on valide le format avant
        guard cleaned.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self = value
    }

    /// Représentation éditable (point remplacé par une virgule)
    var userInputString: String {
        "\(self)".replacingOccurrences(of: ".", with: ",")
    }
}
