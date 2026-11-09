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
            t.categoryId.map(incomeIds.contains) == true && !t.isTransfer && !t.isBusiness && t.amount > 0
                && onBudget.contains(t.accountId)
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

    /// One paycheck source: a payer into one account.
    struct IncomeSource: Identifiable {
        var id: String
        var name: String
        var accountId: String
        var owner: Owner
        var cadence: PayCadence
        /// What it adds to a normal month; 0 once it has stopped.
        var monthly: Cents
        var stopped: Bool
        /// Judged from only a few paychecks, because the bank shared little history.
        var estimated = false
    }

    /// Usual monthly income: the sum of every source still paying.
    func averageIncomeSmoothed(before month: Date) -> Cents? {
        let sources = incomeSources(before: month)
        if sources.isEmpty {
            // Months with history but no paycheck still count as $0 income.
            let months = (1...Self.averageMonths).map { self.month(-$0, from: month) }
            return months.contains(where: { $0 >= firstFullMonth }) ? 0 : nil
        }
        return sources.reduce(0) { $0 + $1.monthly }
    }

    /// Each source's usual month. Weekly and biweekly pay counts a normal
    /// month: 4 or 2 typical paychecks; the extra paycheck some months bring
    /// is a bonus when it arrives. "Typical" is the lower-quartile check of
    /// the last 6 months, not the average: overtime, bonuses and the fall
    /// months after Social Security stops being withheld shouldn't set the
    /// plan, since they don't last (withholding restarts in January). Other pay is averaged over the months the
    /// account has history. A source that has gone quiet (no pay in 3 weeks
    /// for weekly, 5 weeks otherwise) has stopped and adds nothing.
    func incomeSources(before month: Date) -> [IncomeSource] {
        let months = (1...Self.averageMonths).map { self.month(-$0, from: month) }
        guard let oldest = months.last else { return [] }
        let all = payers()
        let starts = accountHistoryStart
        let owners = data.incomeOwners ?? [:]
        let paidCount = Dictionary(grouping: incomeTransactions.filter { $0.date < month }, by: payerKey).mapValues(\.count)
        let regularStart = self.month(-6, from: month)
        let window = incomeTransactions.filter { $0.date >= min(regularStart, self.month(-1, from: oldest)) && $0.date < month }
        return Dictionary(grouping: window, by: payerKey).compactMap { key, list -> IncomeSource? in
            guard let latest = list.max(by: { $0.date < $1.date }) else { return nil }
            let payer = all[key] ?? Payer(cadence: .other, paidEarlyInMonth: false)
            var monthly: Cents
            var estimated = false
            if payer.cadence != .other {
                let recent = list.filter { $0.date >= regularStart }.map(\.amount).sorted()
                guard !recent.isEmpty, list.contains(where: { $0.date >= oldest }) else { return nil }
                monthly = recent[recent.count / 4] * (payer.cadence == .weekly ? 4 : 2)
            } else {
                let covered = months.filter { $0 >= (starts[latest.accountId] ?? oldest) }
                if covered.isEmpty {
                    // A bank that shared only a few weeks: judge the pattern from
                    // the paychecks it did send instead of dropping them.
                    guard let projected = Self.projectedMonthly(list) else { return nil }
                    monthly = projected
                    estimated = true
                } else {
                    let sum = list.filter { t in covered.contains { isInMonth(incomeMonth(t, payers: all), $0) } }
                        .reduce(0) { $0 + $1.amount }
                    guard sum > 0 else { return nil }
                    monthly = sum / covered.count
                }
            }
            let quietDays = month.timeIntervalSince(latest.date) / 86_400
            let regular = payer.cadence != .other || (paidCount[key] ?? 0) >= 3
            let stopped = regular && quietDays > (payer.cadence == .weekly ? 21 : 35)
            if stopped { monthly = 0 }
            let accountOwner = account(latest.accountId)?.owner ?? .unassigned
            return IncomeSource(id: key, name: latest.payee, accountId: latest.accountId,
                                owner: owners[key] ?? (accountOwner == .shared ? .unassigned : accountOwner),
                                cadence: payer.cadence, monthly: monthly, stopped: stopped, estimated: estimated)
        }
        .sorted { $0.monthly > $1.monthly }
    }

    /// A usual month from as few as two paychecks: a week apart is weekly,
    /// about two weeks apart is every two weeks (or the 1st and 15th), about
    /// a month apart is monthly. Nil when there's too little to tell.
    static func projectedMonthly(_ paychecks: [Transaction]) -> Cents? {
        let sorted = paychecks.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return nil }
        let gaps = zip(sorted, sorted.dropFirst()).map { ($1.date.timeIntervalSince($0.date) / 86_400).rounded() }
        let gap = gaps.sorted()[gaps.count / 2]
        let perMonth: Int
        switch gap {
        case 6...8: perMonth = 4
        case 12...17: perMonth = 2
        case 27...33: perMonth = 1
        default: return nil
        }
        let amounts = sorted.map(\.amount).sorted()
        return amounts[amounts.count / 4] * perMonth
    }

    /// Says whose paycheck a source is, for paychecks into a joint account.
    func setIncomeOwner(_ sourceId: String, _ owner: Owner) {
        var owners = data.incomeOwners ?? [:]
        owners[sourceId] = owner
        data.incomeOwners = owners
    }

    /// What each person brings in usually, from the sources still paying.
    func usualIncomeByOwner(before month: Date) -> [Owner: Cents] {
        incomeSources(before: month).reduce(into: [:]) { $0[$1.owner, default: 0] += $1.monthly }
    }
}
