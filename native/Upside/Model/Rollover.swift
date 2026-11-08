import Foundation

/// What happens to money you didn't spend: a category can roll it into
/// next month's limit, and last month's leftover overall can go to
/// savings or cards instead of quietly disappearing.
extension BudgetStore {
    /// What a rolling category carries into `month` from the month before:
    /// last month's limit (its own rollover included) minus what was spent.
    /// Overspending doesn't carry; Cover handles that.
    func rolledIn(_ category: Category, to month: Date, depth: Int = 0) -> Cents {
        guard let since = category.rolloverSince, depth < 24 else { return 0 }
        let previous = self.month(-1, from: month)
        guard previous >= monthStart(since), let planned = plannedLimit(category, in: previous) else { return 0 }
        let available = planned + rolledIn(category, to: previous, depth: depth + 1)
        return max(0, available - spent(category.id, in: previous))
    }

    func setRollover(_ categoryId: String, _ on: Bool) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        data.categories[i].rolloverSince = on ? currentMonth : nil
    }

    /// Last month's unspent everyday money not already rolled into a
    /// category, while you haven't decided what to do with it. Nil when
    /// there's nothing (under $10) or it's handled.
    func unspentLastMonth() -> (month: Date, amount: Cents)? {
        let previous = month(-1, from: currentMonth)
        guard previous >= firstFullMonth, !(data.leftoverDone ?? []).contains(Self.monthKey(previous)) else { return nil }
        let left = monthPlan(previous).leftToSpend - monthPlan(currentMonth).rolledIn
        return left >= 1_000 ? (previous, left / 100 * 100) : nil
    }

    enum LeftoverChoice { case savings, cards, keep }

    /// Puts last month's unspent money toward savings or cards this month
    /// (raising this month's targets), or keeps it as spending money.
    func useUnspent(_ amount: Cents, for month: Date, as choice: LeftoverChoice) {
        var plan = data.plan.flatMap { isInMonth($0.month, currentMonth) ? $0 : nil }
            ?? SavingsPlan(month: currentMonth, goal: 0, limits: [:])
        switch choice {
        case .savings: plan.goal += amount
        case .cards: plan.cardExtra = (plan.cardExtra ?? 0) + amount
        case .keep: break
        }
        if choice != .keep { plan.carriedIn = (plan.carriedIn ?? 0) + amount }
        var updated = data
        if choice != .keep { updated.plan = plan }
        updated.leftoverDone = (data.leftoverDone ?? []) + [Self.monthKey(month)]
        data = updated
    }

    static func monthKey(_ month: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: month)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
