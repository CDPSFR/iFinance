import Foundation

/// Opérations d'un compte à exporter, avec leurs libellés résolus
struct ExportedAccount {
    let account: Account
    /// Opérations de la période, hors opérations ignorées
    let transactions: [Transaction]
    /// Solde du compte à la fin de la période
    let closingBalance: Decimal
}

/// Noms utilisés dans les fichiers : bénéficiaire, catégorie (« Parent:Sous-catégorie »), autre compte d'un virement
struct ExportNames {
    let payee: (UUID) -> String?
    let category: (UUID) -> String?
    let account: (UUID) -> String?
}

/// Export de relevés aux formats QIF et OFX, lisibles par les logiciels de comptes et par l'import d'iFinance
enum StatementExporter {

    // MARK: - QIF

    /// Un fichier QIF par compte : le format ne décrit bien qu'un compte à la fois
    static func qif(_ exported: ExportedAccount, names: ExportNames) -> String {
        var lines = ["!Type:\(qifType(exported.account.type))"]
        let formatter = dateFormatter("dd/MM/yyyy")
        for tx in exported.transactions.sorted(by: { $0.date < $1.date }) {
            lines.append("D\(formatter.string(from: tx.date))")
            lines.append("T\(amount(signed(tx)))")
            if tx.isReconciled { lines.append("CX") } else if tx.status == .cleared { lines.append("C*") }
            if let id = tx.payeeID, let payee = names.payee(id) { lines.append("P\(oneLine(payee))") }
            if let memo = tx.memo, !memo.isEmpty { lines.append("M\(oneLine(memo))") }
            if tx.type == .transfer, let other = tx.toAccountID.flatMap(names.account) {
                // Virement : l'autre compte entre crochets, comme dans Quicken
                lines.append("L[\(oneLine(other))]")
            } else if let id = tx.categoryID, let category = names.category(id) {
                lines.append("L\(oneLine(category))")
            }
            lines.append("^")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func qifType(_ type: AccountType) -> String {
        switch type.group {
        case .debt: return "Oth L"
        default: return type == .creditCard ? "CCard" : "Bank"
        }
    }

    // MARK: - OFX

    /// Un fichier OFX 1.0.2 (SGML) avec un relevé par compte ; les cartes de crédit dans leur section propre
    static func ofx(_ accounts: [ExportedAccount], names: ExportNames, start: Date?, end: Date, now: Date = Date()) -> String {
        let day = dateFormatter("yyyyMMdd")
        let stamp = dateFormatter("yyyyMMddHHmmss")
        let first = start ?? accounts.flatMap(\.transactions).map(\.date).min() ?? end

        func statement(_ exported: ExportedAccount, index: Int) -> String {
            let account = exported.account
            let isCard = account.type == .creditCard
            var body: [String] = []
            body.append("<CURDEF>\(account.currency)")
            if isCard {
                body.append("<CCACCTFROM><ACCTID>\(escape(accountID(account)))</CCACCTFROM>")
            } else {
                let bank = frenchBankCodes(account.iban)
                body.append("<BANKACCTFROM><BANKID>\(bank?.bank ?? "00000")<BRANCHID>\(bank?.branch ?? "00000")<ACCTID>\(escape(accountID(account)))<ACCTTYPE>\(ofxAccountType(account.type))</BANKACCTFROM>")
            }
            body.append("<BANKTRANLIST><DTSTART>\(day.string(from: first))<DTEND>\(day.string(from: end))")
            for tx in exported.transactions.sorted(by: { $0.date < $1.date }) {
                let value = signed(tx)
                var item = "<STMTTRN><TRNTYPE>\(tx.type == .transfer ? "XFER" : value < 0 ? "DEBIT" : "CREDIT")"
                item += "<DTPOSTED>\(day.string(from: tx.date))<TRNAMT>\(amount(value))"
                item += "<FITID>\(escape(tx.externalID ?? tx.id.uuidString))"
                let other = tx.type == .transfer ? tx.toAccountID.flatMap(names.account).map { "Virement \(value < 0 ? "vers" : "de") \($0)" } : nil
                if let name = tx.payeeID.flatMap(names.payee) ?? other {
                    item += "<NAME>\(escape(String(oneLine(name).prefix(32))))"
                }
                let category = tx.type == .transfer ? nil : tx.categoryID.flatMap(names.category)
                let memo = [tx.memo.map { oneLine($0) }, category].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
                if !memo.isEmpty { item += "<MEMO>\(escape(memo))" }
                body.append(item + "</STMTTRN>")
            }
            body.append("</BANKTRANLIST>")
            body.append("<LEDGERBAL><BALAMT>\(amount(exported.closingBalance))<DTASOF>\(day.string(from: end))</LEDGERBAL>")
            let tag = isCard ? "CCSTMT" : "STMT"
            return "<\(tag)TRNRS><TRNUID>\(index)<STATUS><CODE>0<SEVERITY>INFO</STATUS><\(tag)RS>\n" + body.joined(separator: "\n") + "\n</\(tag)RS></\(tag)TRNRS>"
        }

        let banks = accounts.enumerated().filter { $0.element.account.type != .creditCard }
        let cards = accounts.enumerated().filter { $0.element.account.type == .creditCard }
        var lines = [
            "OFXHEADER:100", "DATA:OFXSGML", "VERSION:102", "SECURITY:NONE", "ENCODING:UTF-8",
            "CHARSET:NONE", "COMPRESSION:NONE", "OLDFILEUID:NONE", "NEWFILEUID:NONE", "",
            "<OFX>",
            "<SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS><DTSERVER>\(stamp.string(from: now))<LANGUAGE>FRA</SONRS></SIGNONMSGSRSV1>"
        ]
        if !banks.isEmpty {
            lines.append("<BANKMSGSRSV1>")
            lines += banks.map { statement($0.element, index: $0.offset + 1) }
            lines.append("</BANKMSGSRSV1>")
        }
        if !cards.isEmpty {
            lines.append("<CREDITCARDMSGSRSV1>")
            lines += cards.map { statement($0.element, index: $0.offset + 1) }
            lines.append("</CREDITCARDMSGSRSV1>")
        }
        lines.append("</OFX>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Numéro de compte : celui de l'IBAN français (11 caractères), sinon l'IBAN, sinon l'identifiant du compte
    static func accountID(_ account: Account) -> String {
        let iban = (account.iban ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
        if let codes = frenchBankCodes(account.iban) { return codes.account }
        return iban.isEmpty ? account.id.uuidString : iban
    }

    /// FR76 BBBBB GGGGG CCCCCCCCCCC KK : codes banque, guichet et numéro de compte
    static func frenchBankCodes(_ iban: String?) -> (bank: String, branch: String, account: String)? {
        let value = (iban ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
        guard value.count == 27, value.hasPrefix("FR") || value.hasPrefix("MC") else { return nil }
        let chars = Array(value)
        return (String(chars[4..<9]), String(chars[9..<14]), String(chars[14..<25]))
    }

    private static func ofxAccountType(_ type: AccountType) -> String {
        switch type.group {
        case .liquidity: return "CHECKING"
        case .debt: return "CREDITLINE"
        default: return "SAVINGS"
        }
    }

    // MARK: - Outils

    /// Montant vu depuis le compte : négatif pour une sortie
    static func signed(_ tx: Transaction) -> Decimal { tx.signedAmount }

    private static func amount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    private static func escape(_ text: String) -> String {
        oneLine(text).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
