import Foundation

/// Valeur du compte et versé net à une date
struct InvestmentSeriesPoint: Identifiable, Equatable {
    let date: Date
    /// Titres valorisés au dernier cours connu à cette date, plus les espèces
    let value: Decimal
    /// Versements moins retraits cumulés (solde initial compris)
    let invested: Decimal

    var id: Date { date }
}

/// Calculs purs d'analyse d'un compte d'investissement (sans accès base)
enum InvestmentAnalytics {

    // MARK: - Historique reconstitué

    /// Valeur du compte et versé net sur `samples` dates régulièrement espacées entre `start` et `end`.
    /// La quantité de chaque titre est rejouée depuis les opérations ; son cours est le dernier
    /// cours connu à la date (historique des cours, sinon prix des opérations, sinon PRU).
    static func series(
        account: Account,
        cashTransactions: [Transaction],
        operations: [InvestmentTransaction],
        positions: [InvestmentPosition],
        priceHistory: [UUID: [PositionPrice]],
        from start: Date,
        to end: Date,
        samples: Int = 48
    ) -> [InvestmentSeriesPoint] {
        guard start < end, samples >= 2 else { return [] }

        let cash = cashTransactions.sorted { $0.date < $1.date }
        let byPosition = Dictionary(grouping: operations.filter { $0.positionID != nil }) { $0.positionID! }
        let prices = Dictionary(uniqueKeysWithValues: positions.map { position in
            (position.id, knownPrices(position, operations: byPosition[position.id] ?? [], history: priceHistory[position.id] ?? []))
        })

        let step = end.timeIntervalSince(start) / Double(samples - 1)
        return (0..<samples).map { index in
            // La dernière date est exactement la fin, pour retomber sur la valeur du jour
            let date = index == samples - 1 ? end : start.addingTimeInterval(step * Double(index))

            let invested = account.initialBalance + cash
                .filter { $0.date <= date }
                .reduce(Decimal(0)) { $0 + $1.signedAmount }
            let operationsCash = operations
                .filter { $0.date <= date }
                .reduce(Decimal(0)) { $0 + PositionCalculator.cashImpact($1) }

            var securities = Decimal(0)
            for position in positions {
                let history = (byPosition[position.id] ?? []).filter { $0.date <= date }
                let quantity = PositionCalculator.replay(history).quantity
                guard quantity > 0 else { continue }
                securities += quantity * price(at: date, in: prices[position.id] ?? [], fallback: position.averageCost)
            }

            return InvestmentSeriesPoint(date: date, value: invested + operationsCash + securities, invested: invested)
        }
    }

    /// Cours connus d'une position, triés par date : historique, prix des opérations, cours actuel
    private static func knownPrices(
        _ position: InvestmentPosition,
        operations: [InvestmentTransaction],
        history: [PositionPrice]
    ) -> [(date: Date, price: Decimal)] {
        var known: [(date: Date, price: Decimal)] = history.map { ($0.date, $0.price) }
        for operation in operations {
            guard let price = operation.price, price > 0 else { continue }
            switch operation.type {
            case .buy, .sell, .transfer: known.append((operation.date, price))
            default: break
            }
        }
        if let price = position.currentPrice, let date = position.lastUpdated {
            known.append((date, price))
        }
        return known.sorted { $0.date < $1.date }
    }

    /// Dernier cours connu à la date ; à défaut le premier cours connu, puis le PRU
    private static func price(at date: Date, in known: [(date: Date, price: Decimal)], fallback: Decimal) -> Decimal {
        if let last = known.last(where: { $0.date <= date }) { return last.price }
        return known.first?.price ?? fallback
    }

    // MARK: - Performance

    /// Rendement annualisé pondéré par les flux (taux de rendement interne).
    /// `flows` : versements positifs, retraits négatifs. Renvoie nil si l'historique est trop
    /// court (moins de 90 jours) ou si le calcul n'a pas de solution.
    static func annualizedReturn(flows: [(date: Date, amount: Decimal)], finalValue: Decimal, at end: Date = Date()) -> Double? {
        guard let first = flows.map({ $0.date }).min(), end.timeIntervalSince(first) >= 90 * 86_400 else { return nil }

        // Point de vue de l'épargnant : un versement est une sortie (négatif), la valeur finale une entrée
        var cashFlows: [(years: Double, amount: Double)] = flows.map {
            ($0.date.timeIntervalSince(first) / (365.25 * 86_400), -NSDecimalNumber(decimal: $0.amount).doubleValue)
        }
        cashFlows.append((end.timeIntervalSince(first) / (365.25 * 86_400), NSDecimalNumber(decimal: finalValue).doubleValue))

        func netPresentValue(_ rate: Double) -> Double {
            cashFlows.reduce(0) { $0 + $1.amount / pow(1 + rate, $1.years) }
        }

        var low = -0.95, high = 10.0
        var lowValue = netPresentValue(low), highValue = netPresentValue(high)
        guard lowValue.isFinite, highValue.isFinite, lowValue * highValue < 0 else { return nil }

        // Dichotomie : robuste même quand les flux changent plusieurs fois de signe
        for _ in 0..<100 {
            let middle = (low + high) / 2
            let value = netPresentValue(middle)
            if abs(value) < 0.005 { return middle }
            if value * lowValue < 0 {
                high = middle
                highValue = value
            } else {
                low = middle
                lowValue = value
            }
        }
        return (low + high) / 2
    }

    /// Dividendes et intérêts nets perçus depuis `start`
    static func income(_ operations: [InvestmentTransaction], since start: Date) -> Decimal {
        operations
            .filter { ($0.type == .dividend || $0.type == .interest) && $0.date >= start }
            .reduce(Decimal(0)) { $0 + $1.amount - $1.fees }
    }
}
