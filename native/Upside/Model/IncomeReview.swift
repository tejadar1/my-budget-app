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
    /// cards aren't deposits, so cards are left out.
    func uncountedDeposits(days: Int = 60) -> [Transaction] {
        let since = now().addingTimeInterval(-Double(days) * 86_400)
        let counted = Set(incomeTransactions.map(\.id))
        let accounts = Set(data.accounts.filter { $0.countsInBudget && $0.kind != .credit && $0.kind != .loan }.map(\.id))
        return data.transactions.filter { t in
            t.amount >= 10_000 && t.date >= since && accounts.contains(t.accountId) && !counted.contains(t.id)
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
}
