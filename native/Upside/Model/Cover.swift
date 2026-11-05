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
        var plan = data.plan.flatMap { isInMonth($0.month, month) ? $0 : nil }
            ?? SavingsPlan(month: month, goal: 0, limits: [:])
        let current = limit(target, in: month) ?? averageSpent(categoryId, before: month) ?? 0
        plan.limits[categoryId] = current + amount
        if source != Self.unassigned, let from = category(source), let fromLimit = limit(from, in: month) {
            plan.limits[source] = max(0, fromLimit - amount)
        }
        data.plan = plan
    }
}
