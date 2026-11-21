import Foundation

/// The plan's order: savings, then cards, then trips, then goals, then
/// limits. Paying for overspending starts from the bottom of that order.
/// `room` isn't in the plan's order: it's lowering this month's limits
/// that still have room, the first thing to try.
enum PlanPriority: String, Codable, CaseIterable, Identifiable {
    case room, goals, trips, cards, savings
    var id: String { rawValue }

    /// "Save $100 less"
    func action(_ amount: Cents) -> String {
        switch self {
        case .room: return "Lower limits with room left by \(Money.short(amount))"
        case .savings: return "Save \(Money.short(amount)) less"
        case .cards: return "Pay \(Money.short(amount)) less on cards"
        case .trips: return "Put \(Money.short(amount)) less toward trips"
        case .goals: return "Put \(Money.short(amount)) less toward goals"
        }
    }

    /// "saved $100 less than planned"
    func done(_ amount: Cents) -> String {
        switch self {
        case .room: return "lowered limits with room left by \(Money.short(amount))"
        case .savings: return "saved \(Money.short(amount)) less than planned"
        case .cards: return "paid \(Money.short(amount)) less on cards"
        case .trips: return "put \(Money.short(amount)) less toward trips"
        case .goals: return "put \(Money.short(amount)) less toward goals"
        }
    }

    var noun: String {
        switch self {
        case .room: return "limits with room left"
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
    /// For `room`: how much each limit was lowered, to put back on Undo.
    var lowered: [String: Cents]? = nil
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
        /// How far the limits alone (what's spent where it's more) go past
        /// what there is to spend, before any choice.
        var committed: Cents
        var toSpend: Cents
        /// Still has to come from somewhere (nearest whole dollar).
        var needed: Cents
        /// What each can still give this month, bottom of the order first.
        var options: [Option]
        /// Categories with room left this month, most first.
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
        // Less savings, cards, trips or goals adds to what there is to spend;
        // lowering limits with room lowers what the limits use instead.
        let paid = cuts.filter { $0.source != .room }.reduce(0) { $0 + $1.amount }
        let allowed = everydayCategories.map { c in (c, limit(c, in: month) ?? averageSpent(c.id, before: month) ?? 0) }
        let allowedTotal = allowed.reduce(0) { $0 + $1.1 }
        // What the month will use if the rest of the limits get spent:
        // each limit, or what's spent where that's more.
        let committed = allowed.reduce(0) { $0 + max($1.1, spent($1.0.id, in: month)) }
        let spare = max(0, plan.toSpend - paid - allowedTotal)
        let fromUnassigned = min(total, spare)
        // To the nearest dollar, as amounts are shown: $4.30 over reads
        // "$4 over" and asks for $4, never $5. Under 50¢ is nothing to choose.
        let needed = (max(0, committed - plan.toSpend) + 50) / 100 * 100
        let room = roomLeft(in: month, excluding: Set(overs.map(\.id)))
        let roomTotal = room.reduce(0) { $0 + $1.room }
        var options: [OverrunCost.Option] = []
        if needed > 0 {
            if roomTotal > 0 {
                // Limits move in $10s, so say what will really be lowered.
                options.append(.init(source: .room, planned: roomTotal,
                                     amount: min((needed + 999) / 1_000 * 1_000, roomTotal)))
            }
            for (source, amount) in [(PlanPriority.goals, plan.goals), (.trips, plan.trips),
                                     (.cards, plan.cardPaydown), (.savings, plan.savings)] where amount >= 100 {
                options.append(.init(source: source, planned: amount, amount: min(needed, amount / 100 * 100)))
            }
        }
        return OverrunCost(overruns: overs, total: total, fromUnassigned: fromUnassigned, paid: paid,
                           committed: committed, toSpend: plan.toSpend,
                           needed: needed, options: options, room: room, cuts: cuts)
    }

    /// Limits with room not spent yet this month (whole $10s), most first.
    func roomLeft(in month: Date, excluding: Set<String> = []) -> [CoverSource] {
        everydayCategories.compactMap { c -> CoverSource? in
            guard !excluding.contains(c.id), let limit = limit(c, in: month) else { return nil }
            let left = (limit - spent(c.id, in: month)) / 1_000 * 1_000
            return left >= 1_000 ? CoverSource(id: c.id, name: c.name, room: left) : nil
        }
        .sorted { $0.room != $1.room ? $0.room > $1.room : $0.id < $1.id }
    }

    /// Which limits lowering `amount` of room would touch, most room first,
    /// in $10s. Never below what's spent.
    func roomToLower(_ amount: Cents, in month: Date) -> [(CoverSource, Cents)] {
        var need = amount
        var result: [(CoverSource, Cents)] = []
        for source in roomLeft(in: month, excluding: Set(overruns(in: month).map(\.id))) where need > 0 {
            let take = min(source.room, (need + 999) / 1_000 * 1_000)
            result.append((source, take))
            need -= take
        }
        return result
    }

    /// Pays for overspending this month: less savings, cards, trips or
    /// goals, or lower limits that still have room. Standing amounts and
    /// limits don't change; next month is as planned. What went over stays over.
    func payForOverspending(from source: PlanPriority, amount: Cents, categoryId: String?, in month: Date) {
        guard amount > 0 else { return }
        if !isPlanningWindow(month) { keepOriginalPlan(for: month) }
        var plan = data.plan.flatMap { isInMonth($0.month, month) ? $0 : nil }
            ?? SavingsPlan(month: month, goal: 0, limits: [:])
        var cut = OverrunCut(id: UUID().uuidString, source: source, amount: amount, categoryId: categoryId)
        if source == .room {
            var lowered: [String: Cents] = [:]
            for (room, take) in roomToLower(amount, in: month) {
                guard let c = category(room.id) else { continue }
                plan.limits[room.id] = (plannedLimit(c, in: month) ?? 0) - take
                lowered[room.id] = take
            }
            guard !lowered.isEmpty else { return }
            cut.lowered = lowered
            cut.amount = lowered.values.reduce(0, +)
        }
        plan.cuts = (plan.cuts ?? []) + [cut]
        data.plan = plan
    }

    func undoOverspendingCut(_ id: String, in month: Date) {
        guard var plan = data.plan, isInMonth(plan.month, month),
              let cut = plan.cuts?.first(where: { $0.id == id }) else { return }
        for (categoryId, amount) in cut.lowered ?? [:] {
            let standing = category(categoryId)?.limit
            let restored = (plan.limits[categoryId] ?? standing ?? 0) + amount
            plan.limits[categoryId] = restored == standing ? nil : restored
        }
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
            let names = cost.options.filter { $0.source != .room }.map(\.source.noun)
            let room = cost.options.contains { $0.source == .room }
            guard !names.isEmpty else {
                return room ? "Choose which limits with room left to lower" : "Nothing left to take it from: it's past the plan"
            }
            let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " or " + names.last! : names[0]
            return "Comes out of \(list)" + (room ? ", or lower limits with room left" : "")
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
