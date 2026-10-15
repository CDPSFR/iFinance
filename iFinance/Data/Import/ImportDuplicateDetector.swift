import Foundation

/// Ligne d'import déjà présente dans le compte
enum ImportDuplicate: Equatable {
    /// Même identifiant bancaire (FITID) : l'opération a déjà été importée d'un relevé OFX
    case alreadyImported(transactionID: UUID)
    /// Même jour, même montant et même libellé qu'une transaction existante (saisie à la main, import QIF…)
    case probable(transactionID: UUID)
}

/// Repère les lignes d'un relevé déjà présentes dans le compte de destination.
/// Une transaction existante ne peut correspondre qu'à une seule ligne.
struct ImportDuplicateDetector {
    struct Line {
        let date: Date
        /// Montant signé (négatif pour une dépense)
        let amount: Decimal
        /// Libellé d'origine et nom de bénéficiaire qui en est tiré
        let label: String?
        let payeeName: String?
        let fitID: String?
    }

    /// Transactions du compte de destination
    let existing: [Transaction]
    let payeeName: (UUID) -> String?
    var calendar = Calendar.current

    func duplicates(for lines: [Line?]) -> [Int: ImportDuplicate] {
        var result: [Int: ImportDuplicate] = [:]
        var used = Set<UUID>()

        // 1. Identifiant bancaire : correspondance certaine
        let byFitID = Dictionary(existing.compactMap { tx in tx.externalID.map { ($0, tx) } }, uniquingKeysWith: { first, _ in first })
        for (index, line) in lines.enumerated() {
            guard let line, let fitID = line.fitID, let match = byFitID[fitID], !used.contains(match.id) else { continue }
            result[index] = .alreadyImported(transactionID: match.id)
            used.insert(match.id)
        }

        // 2. Même jour, même montant, même libellé
        let byDay = Dictionary(grouping: existing) { calendar.startOfDay(for: $0.date) }
        for (index, line) in lines.enumerated() where result[index] == nil {
            guard let line else { continue }
            let candidates = byDay[calendar.startOfDay(for: line.date)] ?? []
            if let match = candidates.first(where: { tx in
                !used.contains(tx.id) && signedAmount(tx) == line.amount && sameLabel(tx, line)
            }) {
                result[index] = .probable(transactionID: match.id)
                used.insert(match.id)
            }
        }
        return result
    }

    /// Montant signé tel qu'il apparaît sur le relevé du compte
    private func signedAmount(_ transaction: Transaction) -> Decimal {
        switch transaction.type {
        case .debit: return -abs(transaction.amount)
        case .credit: return abs(transaction.amount)
        case .transfer: return transaction.amount
        }
    }

    /// Libellés équivalents : même bénéficiaire, ou libellé d'origine retrouvé dans la note
    private func sameLabel(_ transaction: Transaction, _ line: Line) -> Bool {
        let existingPayee = transaction.payeeID.flatMap(payeeName).map(Self.folded)
        let memo = transaction.memo.map(Self.folded)
        let name = line.payeeName.map(Self.folded)
        let label = line.label.map(Self.folded)

        if let existingPayee, !existingPayee.isEmpty {
            if existingPayee == name || existingPayee == label { return true }
            if existingPayee.count >= 3, let label, label.contains(existingPayee) { return true }
        }
        if let memo, !memo.isEmpty, let label, !label.isEmpty, memo.contains(label) || label.contains(memo) { return true }
        // Opération sans libellé ni bénéficiaire des deux côtés (virement saisi à la main…)
        return existingPayee == nil && memo == nil && label == nil
    }

    nonisolated static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Rapproche le numéro de compte d'un relevé OFX d'un compte de l'app, par son IBAN
enum OFXAccountMatcher {
    static func account(for statement: OFXStatement, in accounts: [Account]) -> Account? {
        let number = normalized(statement.accountNumber)
        guard number.count >= 5 else { return nil }
        let matches = accounts.filter { account in
            guard let iban = account.iban.map(normalized), !iban.isEmpty else { return false }
            return iban.contains(number)
        }
        // Plusieurs comptes possibles : on préfère celui dont l'IBAN contient aussi les codes banque et guichet
        if matches.count > 1, let bank = statement.bankID.map(normalized), let branch = statement.branchID.map(normalized) {
            return matches.first { normalized($0.iban ?? "").contains(bank + branch) } ?? matches.first
        }
        return matches.first
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
