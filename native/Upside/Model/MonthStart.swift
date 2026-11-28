import Foundation

/// Starting a month, step by step, in the first days (while it's still
/// being planned): wrap up last month, check the income to plan on, then
/// set the plan. Each step uses the screen that already does it; this only
/// says what's left. It shows in Needs attention until you're done.
extension BudgetStore {
    struct MonthStart {
        var month: Date
        /// Last month still has decisions (leftover, savings or cards short).
        var wrapUpLeft: Int
        var incomeChecked: Bool
        var planSet: Bool
        var finished: Bool
        var stepsDone: Int { (wrapUpLeft == 0 ? 1 : 0) + (incomeChecked ? 1 : 0) + (planSet ? 1 : 0) }
        var allDone: Bool { stepsDone == 3 }
    }

    private func startKey(_ step: String, _ month: Date) -> String { "\(Self.monthKey(month)):\(step)" }

    /// This month's start, while it's being planned and not finished.
    /// Nil in a budget's first month (nothing to wrap up or compare).
    func monthStart() -> MonthStart? {
        let thisMonth = currentMonth
        guard isPlanningWindow(thisMonth), self.month(-1, from: thisMonth) >= firstFullMonth else { return nil }
        let done = Set(data.monthStartDone ?? [])
        let month = thisMonth
        let start = MonthStart(
            month: month,
            wrapUpLeft: monthCheckIn().map { [$0.savingsShort, $0.cardsShort, $0.unspent, $0.overspent].filter { $0 > 0 }.count } ?? 0,
            incomeChecked: done.contains(startKey("income", month)),
            planSet: data.originalLimits?[Self.monthKey(month)] != nil || done.contains(startKey("plan", month)),
            finished: done.contains(startKey("finished", month)))
        return start.finished || start.allDone ? nil : start
    }

    /// "Looks right": the income to plan on is checked.
    func confirmMonthIncome() { markStart("income") }

    /// The plan as it stands is this month's plan.
    func confirmMonthPlan() {
        keepOriginalPlan(for: currentMonth, force: true)
        markStart("plan")
    }

    /// Done for now, even with steps left (they're all still in Plan).
    func finishMonthStart() { markStart("finished") }

    private func markStart(_ step: String) {
        var keys = Set(data.monthStartDone ?? [])
        keys.insert(startKey(step, currentMonth))
        data.monthStartDone = keys.sorted()
    }
}
