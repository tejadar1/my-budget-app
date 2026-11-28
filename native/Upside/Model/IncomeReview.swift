import Foundation

/// What the Income screen needs beyond the plan's numbers: when each
/// source last paid, and deposits that aren't counted as income, so a
/// paycheck that was mistaken for a transfer can be found and counted.
extension BudgetStore {
    /// The newest paycheck from a source (payer key).
    func lastPaid(_ sourceId: String) -> Transaction? {
        incomeTransactions.filter { payerKey($0) == sourceId }.max { $0.date < $1.date }
    }

    /// This month's paychecks, newest first (counted in the month they're for).
    func paychecksThisMonth() -> [Transaction] {
        let all = payers()
        return incomeTransactions.filter { isInMonth(incomeMonth($0, payers: all), currentMonth) }
            .sorted { $0.date > $1.date }
    }

    /// Deposits of $100 or more in the last two months into checking or
    /// savings that don't count as income (marked as a transfer, business,
    /// or sorted elsewhere), newest first. Card payments and refunds on
    /// cards aren't deposits, so cards are left out. So the list stays short
    /// enough to notice a missing paycheck, plain moves between your own
    /// accounts (bank wording, or the same amount leaving another account)
    /// and money between the two of you are left out, unless the payer has
    /// paid you income before: that's the paycheck taken for a transfer.
    func uncountedDeposits(days: Int = 60) -> [Transaction] {
        let since = now().addingTimeInterval(-Double(days) * 86_400)
        let income = incomeTransactions
        let counted = Set(income.map(\.id))
        let payers = Set(income.map { Self.payeeKey($0.payee) })
        let accounts = Set(data.accounts.filter { $0.countsInBudget && $0.kind != .credit && $0.kind != .loan }.map(\.id))
        let userSaid = Set(data.userTransfers ?? [])
        let outflows = data.transactions.filter { $0.amount < 0 && $0.date >= since.addingTimeInterval(-7 * 86_400) }
        return data.transactions.filter { t in
            guard t.amount >= 10_000, t.date >= since, accounts.contains(t.accountId), !counted.contains(t.id),
                  !userSaid.contains(t.id) else { return false }
            if payers.contains(Self.payeeKey(t.payee)) { return true }
            if Self.isHouseholdPayment(t.payee, people: people, known: data.householdPayees ?? [:]) { return false }
            if t.isTransfer && BankSync.looksLikeTransfer(t.payee) { return false }
            let moved = outflows.contains { o in
                o.accountId != t.accountId && o.amount == -t.amount && abs(o.date.timeIntervalSince(t.date)) <= 6 * 86_400
            }
            return !moved
        }
        .sorted { $0.date > $1.date }
    }

    /// Why a deposit isn't counted, in a few words.
    func whyNotIncome(_ t: Transaction) -> String {
        if t.isTransfer { return "Counted as a transfer" }
        if t.isBusiness { return "Business" }
        if let c = category(t.categoryId) { return "Sorted as \(c.name)" }
        return "Not sorted"
    }

    /// Counts a deposit as income: not a transfer, not business.
    func countAsIncome(_ transactionId: String) {
        guard let i = data.transactions.firstIndex(where: { $0.id == transactionId }),
              let income = data.categories.first(where: \.isIncome)?.id else { return }
        var t = data.transactions[i]
        t.isTransfer = false
        t.business = nil
        t.splits = nil
        t.categoryId = income
        t.autoSort = nil
        data.transactions[i] = t
    }

    /// "It's still paying": a quiet source keeps counting.
    func setStillPaying(_ sourceId: String, _ on: Bool) {
        var keys = Set(data.incomeStillPaying ?? [])
        if on { keys.insert(sourceId) } else { keys.remove(sourceId) }
        data.incomeStillPaying = keys.isEmpty ? nil : keys.sorted()
    }

    /// "Not income": a source sorted as income by mistake (a friend paying
    /// you back). Its deposits leave income and wait to be sorted (Check
    /// these for money from a person; Deposits not counted otherwise), and
    /// the rule that made them income is forgotten so new ones don't come back.
    func removeIncomeSource(_ sourceId: String) {
        let incomeIds = Set(data.categories.filter(\.isIncome).map(\.id))
        var keys = Set<String>()
        for i in data.transactions.indices {
            let t = data.transactions[i]
            guard t.amount > 0, payerKey(t) == sourceId, t.categoryId.map(incomeIds.contains) == true else { continue }
            keys.insert(Self.payeeKey(t.payee))
            data.transactions[i].categoryId = nil
            data.transactions[i].autoSort = nil
        }
        data.rules.removeAll { keys.contains($0.payeeKey) && incomeIds.contains($0.categoryId) }
        data.incomeOwners?[sourceId] = nil
        data.incomeLevels?[sourceId] = nil
        data.incomeStillPaying = data.incomeStillPaying?.filter { $0 != sourceId }
    }
}
