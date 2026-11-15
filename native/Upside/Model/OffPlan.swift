import Foundation

/// Where a month went past its plan, in plain terms: which categories,
/// by how much, and what drove it (how many purchases, the biggest one).
extension BudgetStore {
    struct OffPlan: Identifiable {
        var category: Category
        /// What the month started with (or the usual, when it had no limit).
        var planned: Cents
        var hadLimit: Bool
        var spent: Cents
        var purchases: Int
        var biggest: Transaction?
        var over: Cents { spent - planned }
        var id: String { category.id }
    }

    /// Everyday categories over (or under) the plan the month started with,
    /// biggest miss first. No limit: compared with your usual month.
    func offPlan(in month: Date) -> (over: [OffPlan], under: [OffPlan]) {
        let all = everydayCategories.compactMap { c -> OffPlan? in
            let planned = originalLimit(c, in: month)
            guard let base = planned ?? averageSpent(c.id, before: month) else { return nil }
            let mine = spendingTransactions.filter { $0.categoryId == c.id && isInMonth($0.date, month) && $0.amount < 0 }
            let spent = spent(c.id, in: month)
            return OffPlan(category: c, planned: base, hadLimit: planned != nil, spent: spent,
                           purchases: mine.count, biggest: mine.min { $0.amount < $1.amount })
        }
        let over = all.filter { $0.over >= 1_000 }.sorted { $0.over > $1.over }
        let under = all.filter { $0.hadLimit && $0.over <= -1_000 }.sorted { $0.over < $1.over }
        return (over, under)
    }
}
