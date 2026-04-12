import Foundation

struct QIFTransaction {
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
                current.date = parseDate(value)
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
                if current.date != nil || current.amount != nil {
                    transactions.append(current)
                }
                current = QIFTransaction()
            default:
                break
            }
        }

        // Last transaction if file doesn't end with ^
        if current.date != nil || current.amount != nil {
            transactions.append(current)
        }

        return transactions
    }

    // MARK: - Date parsing

    private static func parseDate(_ value: String) -> Date? {
        // Try common QIF date formats
        let formats = [
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "yyyy-MM-dd",
            "MM-dd-yyyy",
            "dd-MM-yyyy",
            "d/ M'yy",
            "MM/dd'yy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        // Handle QIF shorthand: "1/ 1' 6" style
        return nil
    }
}
