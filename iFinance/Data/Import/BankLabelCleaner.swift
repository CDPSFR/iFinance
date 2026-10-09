import Foundation

/// Transforme un libellé bancaire en nom de bénéficiaire, pour que les opérations d'un même
/// commerçant se regroupent sous un seul bénéficiaire :
/// « CB CARREFOUR MARKET FACT 280924 » → « CARREFOUR MARKET ».
///
/// Retire les préfixes de moyen de paiement (CB, CARTE X1234, PRLV SEPA, VIR…) et les parties
/// variables d'une opération à l'autre (FACT + date, dates, numéros de carte, références SEPA).
/// Le libellé d'origine n'est pas perdu : l'import le conserve dans la note de la transaction.
enum BankLabelCleaner {
    /// Nom de bénéficiaire tiré du libellé ; le libellé d'origine s'il ne reste rien d'exploitable
    static func payeeName(from label: String) -> String {
        let original = collapse(label)
        var text = original

        // Libellés sans commerçant : un bénéficiaire générique les regroupe
        for (pattern, name) in genericLabels where matches(pattern, text) {
            return name
        }

        text = applyRepeatedly(prefixes, to: text)
        text = applyRepeatedly(suffixes, to: text)
        text = collapse(text).trimmingCharacters(in: CharacterSet(charactersIn: " -/.*:,;"))

        // Trop court, réduit à des chiffres ou à un moyen de paiement : on garde le libellé tel quel
        guard text.count >= 2, text.rangeOfCharacter(from: .letters) != nil,
              !paymentWords.contains(text.uppercased()) else { return original }
        return text
    }

    // MARK: - Règles

    /// Mots qui désignent le moyen de paiement, jamais un bénéficiaire
    private static let paymentWords: Set<String> = ["CB", "CARTE", "PRLV", "PRELEVEMENT", "VIR", "VIREMENT", "FACT", "FACTURE"]

    /// Opérations sans commerçant identifiable
    private static let genericLabels: [(String, String)] = [
        (#"^(RETRAIT|RET)\b.*\b(DAB|GAB)\b"#, "Retrait DAB"),
        (#"^RETRAIT\b"#, "Retrait DAB"),
        (#"^(CHQ|CHEQUE)\b"#, "Chèque"),
        (#"^REMISE\s+(DE\s+)?(CHQ|CHEQUES?)\b"#, "Remise de chèques"),
        (#"^(COTIS|COTISATION|FRAIS|COMMISSION|AGIOS|INTERETS)\b"#, "Banque")
    ]

    /// Préfixes de moyen de paiement, retirés en début de libellé
    private static let prefixes: [String] = [
        // « FACTURE CARTE DU 051024 », « PAIEMENT PAR CARTE X1234 05/10 », « CB », « CARTE X1234 »
        #"^(FACTURE|PAIEMENT|ACHAT|AVOIR|REMBOURSEMENT)?\s*(PAR\s+)?(CB|CARTE)\b\s*(X?\*?\d{4}\b)?\s*(DU\s+)?(\d{2}[/.]?\d{2}([/.]?\d{2,4})?\b)?\s*"#,
        // « PRLV SEPA », « PRELEVEMENT EUROPEEN »
        #"^(PRLV|PRELEV|PRELEVEMENT)\b\.?\s*(SEPA\b)?\s*(EUROPEEN\b)?\s*"#,
        // « VIR SEPA RECU /DE », « VIREMENT EMIS A », « VIR INST »
        #"^(VIR|VIRT|VIREMENT)\b\.?\s*(SEPA\b)?\s*(INST(ANTANE)?\b)?\s*(RECU|EMIS|PERMANENT|EN\s+VOTRE\s+FAVEUR)?\s*(/?\s*(DE|A|DU|POUR)\b:?)?\s*"#,
        // « ECHEANCE PRET », « TIP »
        #"^(TIP|TELEREGLEMENT)\b\s*"#
    ]

    /// Parties variables, retirées en fin de libellé (et tout ce qui les suit)
    private static let suffixes: [String] = [
        // « FACT 280924 », « FACTURE 0510 »
        #"\s+FACT(URE)?\b\.?\s*\d{4,8}\b.*$"#,
        // Numéro de carte : « CARTE 4974XXXXXXXX1234 », « CARTE X1234 »
        #"\s+(CARTE|CB)\s+[\dX*]{4,}.*$"#,
        // Zones SEPA : « /MOTIF … », « /REF … », « ID EMETTEUR/… »
        #"\s*/\s*(MOTIF|REF|REFDO|REFBEN|LIB|ID|MDT|RUM|ECH|NPY|DE|A)\b.*$"#,
        #"\s+(ECH|REF|REFERENCE|ID\s+EMETTEUR|MDT|RUM|NUM|N°)\b[\s:/.].*$"#,
        // Dates : « 05/10 », « 05.10.24 », « 05/10/2024 »
        #"\s+\d{2}[/.]\d{2}([/.]\d{2,4})?\b.*$"#,
        // Références numériques : « 280924 », « 1234567 »
        #"\s+\d{5,}\b.*$"#,
        // Montant en devise : « 12,50EUR », « 9.99 USD »
        #"\s+\d+[,.]\d{2}\s*(EUR|USD|GBP|CHF)\b.*$"#
    ]

    // MARK: - Outils

    private static func applyRepeatedly(_ patterns: [String], to text: String) -> String {
        var current = text
        var changed = true
        var guardCount = 0
        while changed, guardCount < 10 {
            changed = false
            for pattern in patterns {
                let next = replace(pattern, in: current)
                // Une règle ne doit jamais tout effacer
                if next != current, !next.trimmingCharacters(in: .whitespaces).isEmpty {
                    current = next
                    changed = true
                }
            }
            guardCount += 1
        }
        return current
    }

    private static func replace(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
