import Foundation

/// Pay yourself first, with a plan you can keep: extra income waits for a
/// job, paydays remind you to move savings, and limits far below what you
/// really spend step down toward the goal instead of failing every month.
extension BudgetStore {
    // MARK: - Extra income

    /// Gives income above the plan a job. Saving or paying cards raises
    /// that target by the same amount, so spending money doesn't change;
    /// `.keep` adds it to spending money.
    func useExtraIncome(_ amount: Cents, as choice: LeftoverChoice) {
        guard amount > 0 else { return }
        var plan = plan(for: currentMonth) ?? SavingsPlan(month: currentMonth, goal: 0, limits: [:])
        plan.extraIncomeUsed = (plan.extraIncomeUsed ?? 0) + amount
        switch choice {
        case .savings: plan.goal += amount
        case .cards: plan.cardExtra = (plan.cardExtra ?? 0) + amount
        case .keep: break
        }
        data.plan = plan
    }

    // MARK: - Payday

    /// A paycheck arrived in the last two days and this month's savings
    /// aren't done: move this paycheck's share now, before it's spent.
    /// Share = the paycheck × savings ÷ income, never more than what's left.
    func paydayReminder() -> (keys: [String], title: String, body: String)? {
        let plan = monthPlan(currentMonth)
        let remaining = plan.savings - max(0, savedAndInvested(in: currentMonth))
        guard remaining >= 1_000, plan.income > 0 else { return nil }
        let since = now().addingTimeInterval(-2 * 86_400)
        let sent = Set(data.alertsSent ?? [])
        let fresh = incomeTransactions.filter {
            $0.date >= since && isInMonth($0.date, currentMonth) && !sent.contains("payday-\($0.id)")
        }
        guard let paycheck = fresh.max(by: { $0.date < $1.date }) else { return nil }
        let share = Double(paycheck.amount) * Double(plan.savings) / Double(plan.income)
        let amount = min(remaining, Int((share / 1000).rounded(.up)) * 1000)
        guard amount >= 1_000 else { return nil }
        return (fresh.map { "payday-\($0.id)" },
                "Payday: move \(Money.short(amount)) to savings",
                "Before it gets spent. \(Money.short(remaining)) still to save this month.")
    }

    // MARK: - Stepping down

    /// How much a stepping limit drops each month you stay within it.
    static let stepShare = 0.9

    /// Start stepping a category's limit down to `goal`: this month it's
    /// 10% under what you usually spend (never under the goal or what's
    /// already spent).
    func stepDown(_ categoryId: String, to goal: Cents) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        let usual = averageSpent(categoryId, before: currentMonth) ?? goal
        let start = max(goal, Self.round10(Double(usual) * Self.stepShare), spentFloor(data.categories[i], in: currentMonth))
        data.categories[i].goalLimit = goal
        data.categories[i].limit = start
        data.categories[i].steppedThrough = currentMonth
    }

    func stopStepDown(_ categoryId: String) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        data.categories[i].goalLimit = nil
        data.categories[i].steppedThrough = nil
    }

    /// Once a month: each stepping limit drops 10% (to no less than its
    /// goal) if you stayed within it last month; if you went over, it
    /// stays, so a bad month repeats the step instead of piling on.
    func stepLimits() {
        for i in data.categories.indices {
            guard let goal = data.categories[i].goalLimit, var limit = data.categories[i].limit,
                  let through = data.categories[i].steppedThrough else { continue }
            var month = monthStart(through)
            while month < currentMonth {
                if spent(data.categories[i].id, in: month) <= limit {
                    limit = max(goal, Self.round10(Double(limit) * Self.stepShare))
                }
                month = self.month(1, from: month)
            }
            if limit == goal { data.categories[i].goalLimit = nil; data.categories[i].steppedThrough = nil }
            else { data.categories[i].steppedThrough = currentMonth }
            if data.categories[i].limit != limit { data.categories[i].limit = limit }
        }
    }

    /// Months of staying within the limit until it reaches its goal.
    func stepsToGoal(_ category: Category) -> Int? {
        guard let goal = category.goalLimit, var limit = category.limit, limit > goal else { return nil }
        var steps = 0
        while limit > goal && steps < 60 {
            limit = max(goal, Self.round10(Double(limit) * Self.stepShare))
            steps += 1
        }
        return steps
    }

    /// A limit under 75% of what you usually spend: likely to fail.
    func isBigCut(_ dollars: Int, for category: Category) -> Bool {
        guard dollars > 0, let usual = averageSpent(category.id, before: currentMonth), usual > 0 else { return false }
        return Double(dollars * 100) < Double(usual) * 0.75
    }

    // MARK: - Reality check

    /// How much more your usual everyday spending is than what there is to
    /// spend, with savings kept as planned. 0 = your usual fits.
    func realityGap(toSpend: Cents) -> Cents {
        let usual = everydayCategories.reduce(0) { $0 + (averageSpent($1.id, before: currentMonth) ?? 0) }
        return max(0, usual - toSpend)
    }

    static func round10(_ cents: Double) -> Cents { Int((cents / 1000).rounded()) * 1000 }
}
