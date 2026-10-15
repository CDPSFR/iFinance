import Foundation

/// Relevé d'un compte contenu dans un fichier OFX (un fichier peut en contenir plusieurs)
struct OFXStatement: Identifiable {
    let id = UUID()
    /// Numéro du compte (ACCTID), tel qu'écrit dans le fichier
    var accountNumber: String = ""
    /// Code banque et code guichet (BANKID, BRANCHID), absents pour une carte de crédit
    var bankID: String?
    var branchID: String?
    /// CHECKING, SAVINGS, CREDITLINE… ; « CREDITCARD » pour un relevé de carte
    var accountType: String?
    var currency: String?
    var transactions: [QIFTransaction] = []
    /// Solde comptable du relevé (LEDGERBAL) et sa date
    var balance: Decimal?
    var balanceDate: Date?

    var isCreditCard: Bool { accountType == "CREDITCARD" }

    /// « Compte 12345678901 » ou « Carte 4974… », pour le choix du relevé
    var title: String {
        let kind = isCreditCard ? "Carte" : "Compte"
        return accountNumber.isEmpty ? kind : "\(kind) \(accountNumber)"
    }
}

/// Lecture des relevés OFX : version 1 (SGML, balises de valeur sans fermeture, la plus courante
/// dans les banques françaises) et version 2 (XML). Seuls les relevés bancaires et de carte sont lus ;
/// les relevés de comptes-titres sont ignorés.
enum OFXParser {
    enum ParseError: LocalizedError {
        case notOFX

        var errorDescription: String? {
            "Ce fichier n'est pas un relevé OFX lisible."
        }
    }

    static func parse(url: URL) throws -> [OFXStatement] {
        let data = try Data(contentsOf: url)
        return try parseString(QIFParser.decode(data))
    }

    static func parseString(_ content: String) throws -> [OFXStatement] {
        guard let start = content.range(of: "<OFX>", options: .caseInsensitive) else { throw ParseError.notOFX }
        let body = String(content[start.lowerBound...])

        var statements: [OFXStatement] = []
        var statement: OFXStatement?
        var transaction: QIFTransaction?
        /// Agrégats ouverts (les balises de valeur n'y entrent pas)
        var stack: [String] = []

        let scanner = TagScanner(body)
        while let token = scanner.next() {
            let name = token.name
            if token.isClosing {
                // Une balise fermante referme son agrégat et ceux restés ouverts à l'intérieur
                guard let index = stack.lastIndex(of: name) else { continue }
                stack.removeSubrange(index...)
                switch name {
                case "STMTTRN":
                    if let current = transaction, current.amount != nil || current.date != nil {
                        statement?.transactions.append(current)
                    }
                    transaction = nil
                case "STMTRS", "CCSTMTRS":
                    if let current = statement { statements.append(current) }
                    statement = nil
                default:
                    break
                }
                continue
            }

            guard let value = token.value else {
                // Ouverture d'un agrégat
                stack.append(name)
                switch name {
                case "STMTRS":
                    statement = OFXStatement()
                case "CCSTMTRS":
                    statement = OFXStatement(accountType: "CREDITCARD")
                case "STMTTRN":
                    transaction = QIFTransaction()
                default:
                    break
                }
                continue
            }

            // Valeur d'une opération
            if transaction != nil, stack.last == "STMTTRN" || stack.last == "PAYEE" {
                switch name {
                case "DTPOSTED":
                    transaction?.rawDate = value
                    transaction?.date = parseDate(value)
                case "TRNAMT":
                    transaction?.amount = parseAmount(value)
                case "FITID":
                    transaction?.fitID = value
                case "NAME":
                    transaction?.payee = value
                case "MEMO":
                    transaction?.memo = value
                default:
                    break
                }
                continue
            }

            // Valeurs du relevé
            guard statement != nil else { continue }
            switch (stack.last, name) {
            case (_, "CURDEF"):
                statement?.currency = value
            case ("BANKACCTFROM", "BANKID"):
                statement?.bankID = value
            case ("BANKACCTFROM", "BRANCHID"):
                statement?.branchID = value
            case ("BANKACCTFROM", "ACCTID"), ("CCACCTFROM", "ACCTID"):
                statement?.accountNumber = value
            case ("BANKACCTFROM", "ACCTTYPE"):
                statement?.accountType = value
            case ("LEDGERBAL", "BALAMT"):
                statement?.balance = parseAmount(value)
            case ("LEDGERBAL", "DTASOF"):
                statement?.balanceDate = parseDate(value)
            default:
                break
            }
        }

        // Fichier tronqué : le dernier relevé ouvert est gardé s'il contient des opérations
        if let current = statement, !current.transactions.isEmpty { statements.append(current) }

        // Une opération sans libellé prend son mémo comme libellé
        return statements.map { statement in
            var updated = statement
            updated.transactions = statement.transactions.map { transaction in
                var line = transaction
                if (line.payee ?? "").isEmpty { line.payee = line.memo; line.memo = nil }
                if line.memo == line.payee { line.memo = nil }
                return line
            }
            return updated
        }
    }

    // MARK: - Valeurs

    /// AAAAMMJJ, suivi éventuellement de l'heure et du fuseau (20260315120000.000[+1:CET]).
    /// Seul le jour compte : la date est celle du relevé, à minuit, comme en QIF.
    static func parseDate(_ value: String) -> Date? {
        let digits = value.prefix { $0.isNumber }
        guard digits.count >= 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    /// -12.50, -12,50 ou +1 234.56
    static func parseAmount(_ value: String) -> Decimal? {
        let cleaned = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Balises

    private struct Token {
        let name: String
        let isClosing: Bool
        /// Texte qui suit une balise ouvrante : présent pour une balise de valeur, nil pour un agrégat
        let value: String?
    }

    /// Parcours des balises : <NOM>valeur, <NOM>, </NOM>. Les déclarations et commentaires sont ignorés.
    private final class TagScanner {
        private let text: [Character]
        private var index = 0

        init(_ text: String) { self.text = Array(text) }

        func next() -> Token? {
            while index < text.count {
                guard text[index] == "<" else { index += 1; continue }
                guard let close = text[index...].firstIndex(of: ">") else { return nil }
                let inner = String(text[(index + 1)..<close]).trimmingCharacters(in: .whitespaces)
                index = close + 1
                if inner.hasPrefix("?") || inner.hasPrefix("!") || inner.isEmpty { continue }

                let isClosing = inner.hasPrefix("/")
                let name = (isClosing ? String(inner.dropFirst()) : inner)
                    .split(separator: " ").first.map { String($0).uppercased() } ?? ""
                if isClosing { return Token(name: name, isClosing: true, value: nil) }

                // Texte jusqu'à la balise suivante
                let end = text[index...].firstIndex(of: "<") ?? text.count
                let raw = String(text[index..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                index = end
                return Token(name: name, isClosing: false, value: raw.isEmpty ? nil : decodeEntities(raw))
            }
            return nil
        }

        private func decodeEntities(_ value: String) -> String {
            value.replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
    }
}
