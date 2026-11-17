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
                     thisMonthOnly: Bool, in month: Date) {
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
            setLimit(categoryId, value > 0 ? value : nil)
            plan.limits[categoryId] = nil
            for (id, take) in taking {
                let standing = category(id)?.limit ?? current[id] ?? 0
                setLimit(id, max(0, standing - take))
                if plan.limits[id] != nil { plan.limits[id] = max(0, (current[id] ?? 0) - take) }
            }
        }
        data.plan = plan
    }
}
