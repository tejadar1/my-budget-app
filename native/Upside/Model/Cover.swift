import Foundation

/// Covering overspending: when a category runs over, move room from
/// another one for this month only, so the month still adds up.
extension BudgetStore {
    struct Overrun: Identifiable {
        var category: Category
        var over: Cents
        var id: String { category.id }
    }

    struct CoverSource: Identifiable {
        /// A category id, or `unassigned` for money no limit uses.
        var id: String
        var name: String
        var room: Cents
    }

    static let unassigned = "unassigned"

    /// The limit as planned before this month's adjustments (covers,
    /// re-balancing, edits once spending started), plus any rollover.
    /// Month-end looks at this.
    func originalLimit(_ category: Category, in month: Date) -> Cents? {
        let saved = data.originalLimits?[Self.monthKey(month)]
        let planned = saved.map { $0[category.id] } ?? category.limit
        guard let planned, planned > 0 else { return nil }
        return planned + (limit(category, in: month) ?? 0) - (plannedLimit(category, in: month) ?? 0)
    }

    /// Saves this month's plan as it stands, once: the first change after
    /// spending has started. Changes before that are making the plan.
    func keepOriginalPlan(for month: Date) {
        let key = Self.monthKey(month)
        guard data.originalLimits?[key] == nil, totalSpent(in: month) > 0 else { return }
        var all = data.originalLimits ?? [:]
        all[key] = Dictionary(uniqueKeysWithValues: everydayCategories.compactMap { c in c.limit.map { (c.id, $0) } })
        // A year is plenty for recaps.
        for old in all.keys.sorted().dropLast(12) { all[old] = nil }
        data.originalLimits = all
    }

    /// Everyday categories past their limit this month. One without a limit
    /// is over once it passes its usual, since that's what the plan counted.
    func overruns(in month: Date) -> [Overrun] {
        everydayCategories.compactMap { c -> Overrun? in
            let used = spent(c.id, in: month)
            let allowed = limit(c, in: month) ?? averageSpent(c.id, before: month) ?? 0
            return used > allowed ? Overrun(category: c, over: used - allowed) : nil
        }
        .sorted { $0.over > $1.over }
    }

    /// Where the room can come from: money not in any limit first, then
    /// categories with room left, most room first.
    func coverSources(for categoryId: String, in month: Date) -> [CoverSource] {
        var result: [CoverSource] = []
        let plan = monthPlan(month)
        let spare = plan.toSpend - plan.everydayLimits
        if spare > 0 { result.append(CoverSource(id: Self.unassigned, name: "Money not in a limit", room: spare)) }
        let rooms = everydayCategories.compactMap { c -> CoverSource? in
            guard c.id != categoryId, let limit = limit(c, in: month) else { return nil }
            let room = limit - spent(c.id, in: month)
            return room > 0 ? CoverSource(id: c.id, name: c.name, room: room) : nil
        }
        return result + rooms.sorted { $0.room > $1.room }
    }

    /// Raises this month's limit for `categoryId` by `amount`, taken from
    /// `source`'s limit (or from unassigned money). Next month goes back to
    /// the usual limits.
    func cover(_ categoryId: String, amount: Cents, from source: String, in month: Date) {
        guard amount > 0, let target = category(categoryId) else { return }
        keepOriginalPlan(for: month)
        var plan = data.plan.flatMap { isInMonth($0.month, month) ? $0 : nil }
            ?? SavingsPlan(month: month, goal: 0, limits: [:])
        let current = plannedLimit(target, in: month) ?? averageSpent(categoryId, before: month) ?? 0
        plan.limits[categoryId] = current + amount
        if source != Self.unassigned, let from = category(source), let fromLimit = plannedLimit(from, in: month) {
            plan.limits[source] = max(0, fromLimit - amount)
        }
        data.plan = plan
    }

    /// Saves the Plan's limits (whole dollars). A limit you changed becomes
    /// the standing limit and replaces any this-month cover on it; untouched
    /// limits keep their cover. The one-month extra savings rides along.
    /// `thisMonthOnly`: limits raised only to cover what's already spent
    /// (whole dollars → the standing limit to keep, in cents or nil); they
    /// apply to this month and next month goes back to the standing one.
    func savePlanLimits(_ limits: [String: Int], loaded: [String: Int], extra: Cents, in month: Date,
                        thisMonthOnly: [String: (shown: Int, standing: Cents?)] = [:]) {
        let changed = everydayCategories.map(\.id).filter { limits[$0] != loaded[$0] }
        if !changed.isEmpty { keepOriginalPlan(for: month) }
        var kept = data.plan.flatMap { isInMonth($0.month, month) ? $0.limits : nil } ?? [:]
        for id in changed {
            kept[id] = nil
            let dollars = limits[id] ?? 0
            if let only = thisMonthOnly[id], only.shown == dollars {
                setLimit(id, only.standing)
                kept[id] = dollars * 100
            } else {
                setLimit(id, dollars > 0 ? dollars * 100 : nil)
            }
        }
        // Keep what last month's leftover was put toward.
        let existing = data.plan.flatMap { isInMonth($0.month, month) ? $0 : nil }
        let carried = (existing?.carriedIn ?? 0) > 0 || (existing?.cardExtra ?? 0) > 0
        if extra > 0 || !kept.isEmpty || carried {
            var plan = existing ?? SavingsPlan(month: month, goal: 0, limits: [:])
            plan.goal = extra
            plan.limits = kept
            data.plan = plan
        } else {
            data.plan = nil
        }
    }
}
