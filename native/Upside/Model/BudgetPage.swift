import Foundation

/// What the Budget page shows and in what order: a short list of things
/// that need you, and categories with the ones closest to their limit first.
/// How Budget lists categories.
enum CategorySort: String, CaseIterable, Identifiable {
    case closest, mostLeft, mostSpent, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .closest: return "Closest to the limit"
        case .mostLeft: return "Most left"
        case .mostSpent: return "Most spent"
        case .name: return "Name"
        }
    }
}

extension BudgetStore {
    enum Attention: Hashable, Identifiable {
        /// A bank stopped sending activity or SimpleFIN reported a problem.
        case bank
        /// A category past its limit, and by how much.
        case over(categoryId: String, amount: Cents)
        /// Several categories over, called out together.
        case rebalance(categories: Int, amount: Cents)
        /// A category on pace to go over by month end.
        case onPace(categoryId: String, amount: Cents)
        /// Income above the plan waiting for a job.
        case extraIncome(amount: Cents)
        /// Last month's check-in, with this many decisions left.
        case checkIn(decisions: Int)
        /// Purchases sorted on a hunch.
        case toCheck(count: Int)
        /// Everyday limits add up to more than there is to spend.
        case limitsOver(amount: Cents)

        /// Warnings you can hide, and the amount that brings one back if it grows.
        var hideableAmount: Cents? {
            switch self {
            case .over(_, let amount), .rebalance(_, let amount), .onPace(_, let amount), .limitsOver(let amount): amount
            default: nil
            }
        }

        var id: String {
            switch self {
            case .bank: "bank"
            case .over(let id, _): "over-\(id)"
            case .rebalance: "rebalance"
            case .onPace(let id, _): "pace-\(id)"
            case .extraIncome: "extra-income"
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
        let cost = overrunCost(in: currentMonth)
        let decided = cost.cuts.reduce(0) { $0 + $1.amount }
        // Overspending you've paid for is handled: it leaves this list (the
        // category still shows over, and the recap names it).
        if cost.total - decided > 0 {
            if overs.count >= 2 {
                items.append(.rebalance(categories: overs.count, amount: overs.reduce(0) { $0 + $1.over }))
            } else if let one = overs.first {
                items.append(.over(categoryId: one.id, amount: one.over))
            }
        }
        if let pace = onPaceToGoOver(in: currentMonth).first {
            items.append(.onPace(categoryId: pace.id, amount: pace.over))
        }
        let extra = monthPlan(currentMonth).extraIncome
        if extra >= 5_000 { items.append(.extraIncome(amount: extra)) }
        if let check = monthCheckIn() {
            let decisions = [check.savingsShort, check.cardsShort, check.unspent, check.overspent].filter { $0 > 0 }.count
            items.append(.checkIn(decisions: decisions))
        }
        if !toCheck.isEmpty { items.append(.toCheck(count: toCheck.count)) }
        // Limits past what there is to spend, beyond the overspending above.
        let overPart = max(0, cost.total - cost.fromUnassigned - decided)
        let limitsPart = max(0, cost.needed - overPart) / 100 * 100
        if limitsPart > 0 { items.append(.limitsOver(amount: limitsPart)) }
        let hidden = data.hiddenAttention ?? [:]
        return items.filter { item in
            guard let amount = item.hideableAmount, let was = hidden[hideKey(item)] else { return true }
            return amount > was + 1_000
        }
    }

    private func hideKey(_ item: Attention) -> String { "\(Self.monthKey(currentMonth)):\(item.id)" }

    /// Hides a row for this month, until its amount grows.
    func hideAttention(_ item: Attention) {
        guard let amount = item.hideableAmount else { return }
        let prefix = Self.monthKey(currentMonth) + ":"
        var hidden = (data.hiddenAttention ?? [:]).filter { $0.key.hasPrefix(prefix) }
        hidden[hideKey(item)] = amount
        data.hiddenAttention = hidden
    }

    /// Everyday categories worth showing (a limit, spending, or a usual),
    /// the most used-up first; ones without a limit after, by spending.
    func categoryRows(in month: Date, sort: CategorySort = .closest) -> [Category] {
        let rows = everydayCategories.compactMap { c -> (c: Category, used: Double, spent: Cents, left: Cents?)? in
            let used = spent(c.id, in: month)
            let limit = limit(c, in: month) ?? 0
            guard limit > 0 || used > 0 || (averageSpent(c.id, before: month) ?? 0) > 0 else { return nil }
            return (c, limit > 0 ? Double(used) / Double(limit) : -1, used, limit > 0 ? limit - used : nil)
        }
        let sorted: [(c: Category, used: Double, spent: Cents, left: Cents?)]
        switch sort {
        case .closest:
            sorted = rows.sorted { $0.used != $1.used ? $0.used > $1.used : $0.spent > $1.spent }
        case .mostLeft:
            // No limit has nothing "left": those go last, by spending.
            sorted = rows.sorted { a, b in
                switch (a.left, b.left) {
                case let (x?, y?): return x != y ? x > y : a.spent > b.spent
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.spent > b.spent
                }
            }
        case .mostSpent:
            sorted = rows.sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.c.name < $1.c.name }
        case .name:
            sorted = rows.sorted { $0.c.name.localizedStandardCompare($1.c.name) == .orderedAscending }
        }
        return sorted.map(\.c)
    }
}
