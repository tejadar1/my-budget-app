import Foundation

/// What the Budget page shows and in what order: a short list of things
/// that need you, and categories with the ones closest to their limit first.
extension BudgetStore {
    enum Attention: Hashable, Identifiable {
        /// A bank stopped sending activity or SimpleFIN reported a problem.
        case bank
        /// A category past its limit, and by how much.
        case over(categoryId: String, amount: Cents)
        /// Several categories over: rebalance them in one go.
        case rebalance(categories: Int, amount: Cents)
        /// Last month's check-in, with this many decisions left.
        case checkIn(decisions: Int)
        /// Purchases sorted on a hunch.
        case toCheck(count: Int)
        /// Everyday limits add up to more than there is to spend.
        case limitsOver(amount: Cents)

        var id: String {
            switch self {
            case .bank: "bank"
            case .over(let id, _): "over-\(id)"
            case .rebalance: "rebalance"
            case .checkIn: "checkin"
            case .toCheck: "check"
            case .limitsOver: "limits"
            }
        }
    }

    /// This month's to-dos, most important first: a broken bank explains
    /// missing numbers, so it leads. Empty when all is well.
    func attention() -> [Attention] {
        var items: [Attention] = []
        if !staleAccounts.isEmpty || !(data.syncErrors ?? []).isEmpty { items.append(.bank) }
        let overs = overruns(in: currentMonth)
        if overs.count >= 2 {
            items.append(.rebalance(categories: overs.count, amount: overs.reduce(0) { $0 + $1.over }))
        } else if let one = overs.first {
            items.append(.over(categoryId: one.id, amount: one.over))
        }
        if let check = monthCheckIn() {
            let decisions = [check.savingsShort, check.cardsShort, check.unspent, check.overspent].filter { $0 > 0 }.count
            items.append(.checkIn(decisions: decisions))
        }
        if !toCheck.isEmpty { items.append(.toCheck(count: toCheck.count)) }
        let plan = monthPlan(currentMonth)
        if plan.limitsOverBy > 0 { items.append(.limitsOver(amount: plan.limitsOverBy)) }
        return items
    }

    /// Everyday categories worth showing (a limit, spending, or a usual),
    /// the most used-up first; ones without a limit after, by spending.
    func categoryRows(in month: Date) -> [Category] {
        let rows = everydayCategories.compactMap { c -> (Category, Double, Cents)? in
            let used = spent(c.id, in: month)
            let limit = limit(c, in: month) ?? 0
            guard limit > 0 || used > 0 || (averageSpent(c.id, before: month) ?? 0) > 0 else { return nil }
            return (c, limit > 0 ? Double(used) / Double(limit) : -1, used)
        }
        return rows.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }.map(\.0)
    }
}
