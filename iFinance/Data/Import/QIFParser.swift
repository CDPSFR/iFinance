import Foundation

/// Ordre du jour et du mois dans les dates d'un fichier QIF (l'année ISO AAAA-MM-JJ est reconnue d'office)
enum QIFDateOrder: String, CaseIterable, Identifiable {
    case dayMonth   // JJ/MM/AAAA (relevés français)
    case monthDay   // MM/JJ/AAAA (Quicken américain)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dayMonth: return "JJ/MM/AAAA"
        case .monthDay: return "MM/JJ/AAAA"
        }
    }
}

/// Résultat de l'analyse des dates d'un fichier, sur l'ensemble de ses lignes
struct QIFDateAnalysis: Equatable {
    var order: QIFDateOrder
    /// Lignes dont le premier nombre dépasse 12 (forcément JJ/MM)
    var dayFirstCount: Int
    /// Lignes dont le deuxième nombre dépasse 12 (forcément MM/JJ)
    var monthFirstCount: Int

    /// Aucune ligne ne permet de trancher : toutes les dates ont jour et mois ≤ 12
    var isAmbiguous: Bool { dayFirstCount == 0 && monthFirstCount == 0 }
    /// Le fichier contient des lignes des deux formats
    var isInconsistent: Bool { dayFirstCount > 0 && monthFirstCount > 0 }
}

struct QIFTransaction {
    /// Date telle qu'écrite dans le fichier (ligne D)
    var rawDate: String?
    /// Date interprétée selon l'ordre retenu pour le fichier ; nil si illisible
    var date: Date?
    var amount: Decimal?
    var payee: String?
    var memo: String?
    var category: String?
    var type: TransactionType {
        guard let amount else { return .debit }
        return amount >= 0 ? .credit : .debit
    }
}

struct QIFParser {

    static func parse(url: URL) throws -> [QIFTransaction] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseString(content)
    }

    static func parseString(_ content: String) -> [QIFTransaction] {
        var transactions: [QIFTransaction] = []
        var current = QIFTransaction()

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let code = String(trimmed.prefix(1))
            let value = String(trimmed.dropFirst())

            switch code {
            case "!":
                // Header line — skip
                break
            case "D":
                current.rawDate = value
            case "T", "U":
                // Amount: remove spaces, replace comma with dot
                let cleaned = value.replacingOccurrences(of: " ", with: "")
                                   .replacingOccurrences(of: ",", with: ".")
                                   .replacingOccurrences(of: "_", with: "")
                current.amount = Decimal(string: cleaned)
            case "P":
                current.payee = value.isEmpty ? nil : value
            case "M":
                current.memo = value.isEmpty ? nil : value
            case "L":
                // Category, strip leading [ ] for account refs
                let cat = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                current.category = cat.isEmpty ? nil : cat
            case "^":
                if current.rawDate != nil || current.amount != nil {
                    transactions.append(current)
                }
                current = QIFTransaction()
            default:
                break
            }
        }

        // Last transaction if file doesn't end with ^
        if current.rawDate != nil || current.amount != nil {
            transactions.append(current)
        }

        // L'ordre jour/mois est déterminé sur l'ensemble du fichier, jamais ligne par ligne
        return applyDateOrder(analyzeDates(transactions).order, to: transactions)
    }

    // MARK: - Date parsing

    /// Détermine l'ordre jour/mois à partir de toutes les dates du fichier.
    /// Sans indice (jour et mois toujours ≤ 12), l'ordre français JJ/MM est retenu par défaut.
    static func analyzeDates(_ transactions: [QIFTransaction]) -> QIFDateAnalysis {
        var dayFirst = 0
        var monthFirst = 0
        for raw in transactions.compactMap(\.rawDate) {
            guard let parts = dateParts(raw), !parts.isYearFirst else { continue }
            if parts.first > 12 && parts.second <= 12 { dayFirst += 1 }
            if parts.second > 12 && parts.first <= 12 { monthFirst += 1 }
        }
        let order: QIFDateOrder = monthFirst > dayFirst ? .monthDay : .dayMonth
        return QIFDateAnalysis(order: order, dayFirstCount: dayFirst, monthFirstCount: monthFirst)
    }

    /// Interprète toutes les dates avec le même ordre jour/mois
    static func applyDateOrder(_ order: QIFDateOrder, to transactions: [QIFTransaction]) -> [QIFTransaction] {
        transactions.map { transaction in
            var updated = transaction
            updated.date = transaction.rawDate.flatMap { parseDate($0, order: order) }
            return updated
        }
    }

    /// Lit une date QIF : 05/03/2026, 05-03-2026, 05/03/26, 5/ 3'26 (Quicken), 2026-03-05.
    /// Renvoie nil si la date est illisible ou n'existe pas (31/02).
    static func parseDate(_ value: String, order: QIFDateOrder) -> Date? {
        guard let parts = dateParts(value) else { return nil }

        let day: Int
        let month: Int
        if parts.isYearFirst {
            month = parts.first
            day = parts.second
        } else {
            switch order {
            case .dayMonth: day = parts.first; month = parts.second
            case .monthDay: month = parts.first; day = parts.second
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: parts.year, month: month, day: day)
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }
        return date
    }

    /// Les trois nombres d'une date, avec l'année ramenée sur 4 chiffres
    private static func dateParts(_ value: String) -> (first: Int, second: Int, year: Int, isYearFirst: Bool)? {
        let groups = value.split(whereSeparator: { !$0.isNumber }).map(String.init)
        guard groups.count == 3, let a = Int(groups[0]), let b = Int(groups[1]), let c = Int(groups[2]) else { return nil }

        // AAAA-MM-JJ
        if groups[0].count == 4 {
            return (b, c, a, true)
        }

        let year: Int
        switch groups[2].count {
        case 4:
            year = c
        case 1, 2:
            // Quicken note les années 2000 avec une apostrophe (5/ 3'26) ; sinon pivot à 70
            year = value.contains("'") || c < 70 ? 2000 + c : 1900 + c
        default:
            return nil
        }
        return (a, b, year, false)
    }
}
