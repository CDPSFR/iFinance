import Foundation

/// Échéancier d'un prêt amortissable à mensualités constantes (calculs purs)
struct LoanSchedule {
    let terms: LoanTerms
    let calendar: Calendar

    init(terms: LoanTerms, calendar: Calendar = .current) {
        self.terms = terms
        self.calendar = calendar
    }

    var monthlyRate: Double { terms.annualRate / 12 }
    var principal: Double { NSDecimalNumber(decimal: terms.principal).doubleValue }

    /// Mensualité hors assurance
    var payment: Double {
        guard terms.months > 0 else { return 0 }
        guard monthlyRate > 0 else { return principal / Double(terms.months) }
        return principal * monthlyRate / (1 - pow(1 + monthlyRate, -Double(terms.months)))
    }

    var insurance: Double { NSDecimalNumber(decimal: terms.monthlyInsurance).doubleValue }

    /// Date de l'échéance numéro `index` (1 = première échéance)
    func dueDate(ofPayment index: Int) -> Date {
        calendar.date(byAdding: .month, value: index - 1, to: terms.firstPaymentDate) ?? terms.firstPaymentDate
    }

    var endDate: Date { dueDate(ofPayment: terms.months) }

    /// Nombre d'échéances déjà payées à la date
    func paymentsMade(asOf date: Date = Date()) -> Int {
        guard date >= terms.firstPaymentDate else { return 0 }
        let months = calendar.dateComponents([.month], from: terms.firstPaymentDate, to: date).month ?? 0
        return min(months + 1, terms.months)
    }

    func remainingPayments(asOf date: Date = Date()) -> Int {
        terms.months - paymentsMade(asOf: date)
    }

    /// Capital restant dû après `count` échéances
    func balance(afterPayments count: Int) -> Double {
        guard count < terms.months else { return 0 }
        guard count > 0 else { return principal }
        guard monthlyRate > 0 else { return principal - payment * Double(count) }
        let growth = pow(1 + monthlyRate, Double(count))
        return max(principal * growth - payment * (growth - 1) / monthlyRate, 0)
    }

    func balance(asOf date: Date = Date()) -> Double {
        balance(afterPayments: paymentsMade(asOf: date))
    }

    /// Intérêts restant à payer
    func remainingInterest(asOf date: Date = Date()) -> Double {
        max(payment * Double(remainingPayments(asOf: date)) - balance(asOf: date), 0)
    }

    var totalInterest: Double { max(payment * Double(terms.months) - principal, 0) }
    var totalInsurance: Double { insurance * Double(terms.months) }

    /// Part intérêts et capital de la prochaine échéance
    func nextPaymentSplit(asOf date: Date = Date()) -> (capital: Double, interest: Double) {
        guard remainingPayments(asOf: date) > 0 else { return (0, 0) }
        let interest = balance(asOf: date) * monthlyRate
        return (payment - interest, interest)
    }

    // MARK: - Remboursement anticipé

    struct Prepayment {
        let amount: Double
        let interestSaved: Double
        let monthsSaved: Int
        let newPayment: Double          // Mensualité si l'on réduit la mensualité
        let penalty: Double             // Indemnités de remboursement anticipé
    }

    /// Remboursement anticipé partiel aujourd'hui, en réduisant la durée ou la mensualité
    func prepayment(amount: Double, reduceDuration: Bool, asOf date: Date = Date()) -> Prepayment {
        let balance = self.balance(asOf: date)
        let remaining = remainingPayments(asOf: date)
        let paid = min(max(amount, 0), balance)
        let interestBefore = payment * Double(remaining) - balance
        let newBalance = balance - paid

        var interestAfter = 0.0
        var monthsSaved = 0
        var newPayment = payment

        if newBalance <= 0.01 {
            monthsSaved = remaining
            newPayment = 0
        } else if reduceDuration {
            // Même mensualité : on compte les échéances nécessaires
            var left = newBalance, months = 0
            while left > 0.01 && months < remaining {
                let interest = left * monthlyRate
                interestAfter += interest
                left = left + interest - min(payment, left + interest)
                months += 1
            }
            monthsSaved = remaining - months
        } else {
            // Même durée : nouvelle mensualité
            if monthlyRate > 0 {
                newPayment = newBalance * monthlyRate / (1 - pow(1 + monthlyRate, -Double(remaining)))
            } else {
                newPayment = newBalance / Double(max(remaining, 1))
            }
            interestAfter = newPayment * Double(remaining) - newBalance
        }

        return Prepayment(
            amount: paid,
            interestSaved: max(interestBefore - interestAfter, 0),
            monthsSaved: monthsSaved,
            newPayment: newPayment,
            penalty: penalty(on: paid, remainingMonths: remaining)
        )
    }

    /// Indemnités : immobilier, 6 mois d'intérêts plafonnés à 3 % du capital remboursé ;
    /// crédit à la consommation, 1 % (0,5 % à moins d'un an de la fin) au-delà de 10 000 € sur 12 mois
    func penalty(on amount: Double, remainingMonths: Int) -> Double {
        if terms.isMortgage {
            return min(amount * 0.03, amount * monthlyRate * 6)
        }
        guard amount > 10_000 else { return 0 }
        return amount * (remainingMonths > 12 ? 0.01 : 0.005)
    }
}
