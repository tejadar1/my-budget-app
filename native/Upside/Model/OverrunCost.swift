import Foundation

/// The plan's order: savings, then cards, then trips, then goals, then
/// limits. Paying for overspending starts from the bottom of that order.
enum PlanPriority: String, Codable, CaseIterable, Identifiable {
    case goals, trips, cards, savings
    var id: String { rawValue }

    /// "Save $100 less"
    func action(_ amount: Cents) -> String {
        switch self {
        case .savings: return "Save \(Money.short(amount)) less"
        case .cards: return "Pay \(Money.short(amount)) less on cards"
        case .trips: return "Put \(Money.short(amount)) less toward trips"
        case .goals: return "Put \(Money.short(amount)) less toward goals"
        }
    }

    /// "saved $100 less than planned"
    func done(_ amount: Cents) -> String {
        switch self {
        case .savings: return "saved \(Money.short(amount)) less than planned"
        case .cards: return "paid \(Money.short(amount)) less on cards"
        case .trips: return "put \(Money.short(amount)) less toward trips"
        case .goals: return "put \(Money.short(amount)) less toward goals"
        }
    }

    var noun: String {
        switch self {
        case .savings: return "savings"
        case .cards: return "cards"
        case .trips: return "trips"
        case .goals: return "goals"
        }
    }
}

/// One choice to pay for overspending this month.
struct OverrunCut: Codable, Equatable, Identifiable {
    var id: String
    var source: PlanPriority
    var amount: Cents
    /// The category that went over, when the choice was made for one.
    var categoryId: String?
}

/// Overspending isn't covered by quietly moving limits around. Everything
/// after savings, cards, trips and goals is already in limits, so money
/// spent past a limit comes from money no limit uses, or it costs one of
/// those. This says which, and lets you choose; the category stays over.
extension BudgetStore {
    struct OverrunCost {
        var overruns: [Overrun]
        var total: Cents
        /// Part of it that money no limit uses soaks up (less left at month end).
        var fromUnassigned: Cents
        /// Already paid for this month with less savings, cards, trips or goals.
        var paid: Cents
        /// Still has to come from somewhere (whole dollars).
        var needed: Cents
        /// What each can still give this month, bottom of the order first.
        var options: [Option]
        /// Categories with room left: where spending less would make up for it.
        var room: [CoverSource]
        var cuts: [OverrunCut]

        struct Option: Identifiable {
            var source: PlanPriority
            /// What it's set to this month, before this choice.
            var planned: Cents
            /// What choosing it takes: all that's needed, or all it has.
            var amount: Cents
            var id: PlanPriority { source }
        }
    }

    func overrunCuts(in month: Date) -> [OverrunCut] { plan(for: month)?.cuts ?? [] }

    func cut(_ source: PlanPriority, in month: Date) -> Cents {
        overrunCuts(in: month).filter { $0.source == source }.reduce(0) { $0 + $1.amount }
    }

    func overrunCost(in month: Date) -> OverrunCost {
        let plan = monthPlan(month)
        let overs = overruns(in: month)
        let total = overs.reduce(0) { $0 + $1.over }
        let cuts = overrunCuts(in: month)
        let paid = cuts.reduce(0) { $0 + $1.amount }
        // What the limits use (your usual where there's no limit), and the
        // money left over before anything was paid for.
        let allowed = everydayCategories.reduce(0) { $0 + (limit($1, in: month) ?? averageSpent($1.id, before: month) ?? 0) }
        let spare = max(0, plan.toSpend - paid - allowed)
        let fromUnassigned = min(total, spare)
        let needed = (max(0, total - fromUnassigned - paid) + 99) / 100 * 100
        let available: [(PlanPriority, Cents)] = [(.goals, plan.goals), (.trips, plan.trips),
                                                  (.cards, plan.cardPaydown), (.savings, plan.savings)]
        let options = needed > 0
            ? available.filter { $0.1 >= 100 }.map { OverrunCost.Option(source: $0.0, planned: $0.1, amount: min(needed, $0.1 / 100 * 100)) }
            : []
        let overIds = Set(overs.map(\.id))
        let room = everydayCategories.compactMap { c -> CoverSource? in
            guard !overIds.contains(c.id), let limit = limit(c, in: month) else { return nil }
            let left = (limit - spent(c.id, in: month)) / 100 * 100
            return left >= 1_000 ? CoverSource(id: c.id, name: c.name, room: left) : nil
        }
        .sorted { $0.room > $1.room }
        return OverrunCost(overruns: overs, total: total, fromUnassigned: fromUnassigned, paid: paid,
                           needed: needed, options: options, room: room, cuts: cuts)
    }

    /// Pays for overspending this month with less savings, cards, trips or
    /// goals. Your standing amounts don't change; next month is as planned.
    func payForOverspending(from source: PlanPriority, amount: Cents, categoryId: String?, in month: Date) {
        guard amount > 0 else { return }
        if !isPlanningWindow(month) { keepOriginalPlan(for: month) }
        var plan = data.plan.flatMap { isInMonth($0.month, month) ? $0 : nil }
            ?? SavingsPlan(month: month, goal: 0, limits: [:])
        plan.cuts = (plan.cuts ?? []) + [OverrunCut(id: UUID().uuidString, source: source, amount: amount, categoryId: categoryId)]
        data.plan = plan
    }

    func undoOverspendingCut(_ id: String, in month: Date) {
        guard var plan = data.plan, isInMonth(plan.month, month) else { return }
        plan.cuts = (plan.cuts ?? []).filter { $0.id != id }
        if plan.cuts?.isEmpty == true { plan.cuts = nil }
        data.plan = plan
    }

    /// What a month's overspending cost, in words: "saved $100 less than
    /// planned and paid $50 less on cards". Nil when nothing was paid for.
    func cutsSummary(in month: Date) -> String? {
        let cuts = overrunCuts(in: month)
        guard !cuts.isEmpty else { return nil }
        let parts = PlanPriority.allCases.reversed().compactMap { source -> String? in
            let amount = cuts.filter { $0.source == source }.reduce(0) { $0 + $1.amount }
            return amount > 0 ? source.done(amount) : nil
        }
        return parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first
    }

    /// One line for Needs attention: what overspending costs right now.
    func overrunNote(in month: Date) -> String {
        let cost = overrunCost(in: month)
        if cost.needed > 0 {
            let names = cost.options.map(\.source.noun)
            guard !names.isEmpty else { return "Nothing left to take it from: it's past the plan" }
            let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " or " + names.last! : names[0]
            return "Comes out of \(list) unless you spend less elsewhere"
        }
        if let summary = cutsSummary(in: month) { return "Paid for: " + summary }
        return "Money not in a limit covers it: \(Money.short(cost.fromUnassigned)) less left at month end"
    }

    /// Categories on pace to go over by month end (at least $25), from how
    /// fast they're spending. Only after the first week, so one big
    /// grocery run doesn't count as a pace.
    func onPaceToGoOver(in month: Date) -> [Overrun] {
        guard month == currentMonth else { return [] }
        let day = calendar.component(.day, from: now())
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        guard day >= 8, day < days else { return [] }
        return everydayCategories.compactMap { c -> Overrun? in
            guard let limit = limit(c, in: month), limit > 0 else { return nil }
            let spent = spent(c.id, in: month)
            guard spent < limit else { return nil }
            let projected = spent * days / day
            let over = (projected - limit) / 100 * 100
            return over >= 2_500 ? Overrun(category: c, over: over) : nil
        }
        .sorted { $0.over > $1.over }
    }

    /// Whether money no limit uses would soak up `amount` more spending.
    func spareCovers(_ amount: Cents, in month: Date) -> Bool {
        let cost = overrunCost(in: month)
        let plan = monthPlan(month)
        let allowed = everydayCategories.reduce(0) { $0 + (limit($1, in: month) ?? averageSpent($1.id, before: month) ?? 0) }
        let spare = max(0, plan.toSpend - cost.paid - allowed) - cost.fromUnassigned
        return amount <= spare
    }
}
