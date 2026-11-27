import Foundation

/// Changing one limit from its category: it has to fit what there is to
/// spend. Raising one means lowering another (or less toward savings,
/// cards or trips, which is Plan's job), so the check is right there.
extension BudgetStore {
    /// How far the month's limits would go past what there is to spend with
    /// `categoryId` at `value` and `taking` lowered elsewhere (0 = fits).
    /// What's already spent counts where it's more than a limit.
    func limitOver(_ categoryId: String, to value: Cents, taking: [String: Cents] = [:], in month: Date) -> Cents {
        max(0, limitsCommitted(categoryId, to: value, taking: taking, in: month) - monthPlan(month).toSpend)
    }

    /// Money no limit would use after the change (0 when it doesn't fit).
    func limitSpare(_ categoryId: String, to value: Cents, taking: [String: Cents] = [:], in month: Date) -> Cents {
        max(0, monthPlan(month).toSpend - limitsCommitted(categoryId, to: value, taking: taking, in: month))
    }

    /// What the month's limits will use, given limits by category (cents;
    /// missing = your usual; a limit lowered to $0 is $0): each limit, or what's already spent where
    /// that's more. Plan, Budget and Adjust limit all count it this way, so
    /// money "not in any limit" never includes money overspending used.
    func committedSpending(limits: [String: Cents], in month: Date) -> Cents {
        everydayCategories.reduce(0) { sum, c in
            // A set limit gets what rolled over into it, as on Budget, the
            // same as `limit(_:in:)`: $0 is a limit of $0, not "your usual".
            let allowed = limits[c.id].map { $0 + rolledIn(c, to: month) } ?? (averageSpent(c.id, before: month) ?? 0)
            return sum + max(allowed, spent(c.id, in: month))
        }
    }

    /// The same, with this month's saved limits.
    func committedSpending(in month: Date) -> Cents {
        committedSpending(limits: Dictionary(uniqueKeysWithValues: everydayCategories.compactMap { c in
            plannedLimit(c, in: month).map { (c.id, $0) }
        }), in: month)
    }

    private func limitsCommitted(_ categoryId: String, to value: Cents, taking: [String: Cents], in month: Date) -> Cents {
        everydayCategories.reduce(0) { sum, c in
            let allowed = c.id == categoryId ? value
                : (limit(c, in: month) ?? averageSpent(c.id, before: month) ?? 0) - (taking[c.id] ?? 0)
            return sum + max(allowed, spent(c.id, in: month))
        }
    }

    /// Changes one limit, and lowers others by `taking` to make room.
    /// `thisMonthOnly`: just this month; otherwise from now on (this month
    /// included). Mid-month the month's original plan is kept for the recap.
    func adjustLimit(_ categoryId: String, to value: Cents, taking: [String: Cents] = [:],
                     fromPlan: [PlanPriority: Cents] = [:], thisMonthOnly: Bool, in month: Date) {
        if !isPlanningWindow(month) { keepOriginalPlan(for: month) }
        var plan = data.plan.flatMap { isInMonth($0.month, month) ? $0 : nil }
            ?? SavingsPlan(month: month, goal: 0, limits: [:])
        let current = taking.keys.reduce(into: [String: Cents]()) { result, id in
            result[id] = category(id).flatMap { plannedLimit($0, in: month) } ?? 0
        }
        if thisMonthOnly {
            plan.limits[categoryId] = value
            for (id, take) in taking { plan.limits[id] = max(0, (current[id] ?? 0) - take) }
        } else {
            // $0 here means a $0 limit, as Adjust limit showed it, not "no
            // limit" (which would count the category's usual and not fit).
            setLimit(categoryId, value)
            plan.limits[categoryId] = nil
            for (id, take) in taking {
                let standing = category(id)?.limit ?? current[id] ?? 0
                setLimit(id, max(0, standing - take))
                if plan.limits[id] != nil { plan.limits[id] = max(0, (current[id] ?? 0) - take) }
            }
        }
        data.plan = plan
        for (source, amount) in fromPlan where amount > 0 {
            lowerPriority(source, by: amount, thisMonthOnly: thisMonthOnly, for: categoryId, in: month)
        }
    }

    /// What savings, cards, trips and goals can still give this month.
    func planRoom(in month: Date) -> [(PlanPriority, Cents)] {
        let plan = monthPlan(month)
        return [(.goals, plan.goals), (.trips, plan.trips), (.cards, plan.cardPaydown), (.savings, plan.savings)]
            .filter { $0.1 >= 1_000 }
    }

    /// Whether lowering `source` can change the standing amount (so "from
    /// now on" means every month). Goals, and trips without a fund, are
    /// worked out each month, so only this month can give.
    func canLowerEveryMonth(_ source: PlanPriority) -> Bool {
        switch source {
        case .savings: return (data.priorities?.savings ?? 0) > 0
        case .cards: return (data.priorities?.cardPaydown ?? 0) > 0
        case .trips: return data.tripFund != nil
        case .goals, .room: return false
        }
    }

    /// Puts less toward savings, cards, trips or goals to make room for a
    /// limit: this month only (like paying for overspending), or from now on.
    func lowerPriority(_ source: PlanPriority, by amount: Cents, thisMonthOnly: Bool, for categoryId: String?, in month: Date) {
        guard amount > 0 else { return }
        guard !thisMonthOnly, canLowerEveryMonth(source) else {
            payForOverspending(from: source, amount: amount, categoryId: categoryId, in: month)
            return
        }
        var priorities = data.priorities ?? Priorities()
        switch source {
        case .savings:
            let take = min(amount, priorities.savings)
            priorities.savings -= take
            data.priorities = priorities
            if amount > take { payForOverspending(from: .savings, amount: amount - take, categoryId: categoryId, in: month) }
        case .cards:
            let take = min(amount, priorities.cardPaydown)
            priorities.cardPaydown -= take
            data.priorities = priorities
            if amount > take { payForOverspending(from: .cards, amount: amount - take, categoryId: categoryId, in: month) }
        case .trips:
            if var fund = data.tripFund {
                let take = min(amount, fund.monthly)
                fund.monthly -= take
                data.tripFund = fund
                if amount > take { payForOverspending(from: .trips, amount: amount - take, categoryId: categoryId, in: month) }
            }
        case .goals, .room:
            payForOverspending(from: source, amount: amount, categoryId: categoryId, in: month)
        }
        recordMonthSnapshot()
    }
}
