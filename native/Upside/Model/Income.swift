import Foundation

/// Paychecks: which month each belongs to, extra paychecks, and a usual
/// income that isn't thrown off by pay-date quirks.
extension BudgetStore {
    enum PayCadence { case weekly, biweekly, other }

    struct Payer {
        var cadence: PayCadence
        /// Usually paid on the 1st–5th, so an early deposit at the end of
        /// the month before (weekend or holiday) belongs to the next month.
        var paidEarlyInMonth: Bool
    }

    var incomeTransactions: [Transaction] {
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        let incomeIds = Set(data.categories.filter(\.isIncome).map(\.id))
        return data.transactions.filter { t in
            t.categoryId.map(incomeIds.contains) == true && !t.isTransfer && t.amount > 0 && onBudget.contains(t.accountId)
        }
    }

    /// Who pays into which account: Ron's and Ana's "PAYROLL DEPOSIT"
    /// are separate paychecks.
    func payerKey(_ t: Transaction) -> String { "\(Self.payeeKey(t.payee))|\(t.accountId)" }

    /// Each source of income and its pay pattern. Weekly and biweekly pay
    /// lands exactly 7 or 14 days apart; twice-a-month pay (1st and 15th)
    /// doesn't, so it isn't mistaken for biweekly.
    func payers() -> [String: Payer] {
        Dictionary(grouping: incomeTransactions, by: payerKey).mapValues { list in
            let dates = list.map(\.date).sorted()
            let gaps = zip(dates, dates.dropFirst()).map { ($1.timeIntervalSince($0) / 86_400).rounded() }
            func share(_ days: Double) -> Double {
                gaps.isEmpty ? 0 : Double(gaps.filter { abs($0 - days) <= 1 }.count) / Double(gaps.count)
            }
            let cadence: PayCadence = dates.count >= 3 && share(7) >= 0.7 ? .weekly
                : dates.count >= 3 && share(14) >= 0.7 ? .biweekly : .other
            let early = dates.filter { calendar.component(.day, from: $0) <= 5 }.count
            return Payer(cadence: cadence,
                         paidEarlyInMonth: cadence == .other && dates.count >= 3 && early * 2 >= dates.count)
        }
    }

    /// The month a paycheck is for: its own month, except a "paid on the
    /// 1st" paycheck that arrived in the last days of the month before.
    func incomeMonth(_ t: Transaction, payers: [String: Payer]) -> Date {
        let start = monthStart(t.date)
        guard payers[payerKey(t)]?.paidEarlyInMonth == true else { return start }
        let lastDay = calendar.range(of: .day, in: .month, for: t.date)!.count
        return calendar.component(.day, from: t.date) >= lastDay - 4 ? month(1, from: start) : start
    }

    /// Paychecks this month from weekly or every-two-weeks pay, and how
    /// many are extra (a 5th weekly or 3rd biweekly paycheck).
    func paychecks(in month: Date) -> (count: Int, extra: Int) {
        let all = payers()
        var count = 0, extra = 0
        for (key, payer) in all where payer.cadence != .other {
            let n = incomeTransactions.filter { payerKey($0) == key && isInMonth($0.date, month) }.count
            let usual = payer.cadence == .weekly ? 4 : 2
            count += n
            extra += max(0, n - usual)
        }
        return (count, extra)
    }

    /// Usual monthly income. Weekly and biweekly pay is the average
    /// paycheck × 52 or 26 ÷ 12, so a 3-paycheck month doesn't inflate it.
    /// Other pay is averaged per account over the months it has history.
    func averageIncomeSmoothed(before month: Date) -> Cents? {
        let months = (1...Self.averageMonths).map { self.month(-$0, from: month) }
        guard let oldest = months.last else { return nil }
        let all = payers()
        let starts = accountHistoryStart
        var total = 0
        var anyData = false
        let window = incomeTransactions.filter { $0.date >= self.month(-1, from: oldest) && $0.date < month }
        for (key, list) in Dictionary(grouping: window, by: payerKey) {
            let payer = all[key] ?? Payer(cadence: .other, paidEarlyInMonth: false)
            if payer.cadence != .other {
                let recent = list.filter { $0.date >= oldest }
                guard !recent.isEmpty else { continue }
                let average = recent.reduce(0) { $0 + $1.amount } / recent.count
                total += average * (payer.cadence == .weekly ? 52 : 26) / 12
                anyData = true
            } else {
                for (accountId, paid) in Dictionary(grouping: list, by: \.accountId) {
                    let covered = months.filter { $0 >= (starts[accountId] ?? oldest) }
                    guard !covered.isEmpty else { continue }
                    let sum = paid.filter { t in covered.contains { isInMonth(incomeMonth(t, payers: all), $0) } }
                        .reduce(0) { $0 + $1.amount }
                    total += sum / covered.count
                    anyData = true
                }
            }
        }
        // Months with history but no paycheck still count as $0 income.
        if !anyData, months.contains(where: { $0 >= firstFullMonth }) { return 0 }
        return anyData ? total : nil
    }
}
