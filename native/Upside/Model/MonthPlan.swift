import Foundation

/// The month top-down: income, minus bills, savings and trips, leaves
/// what you can spend on everyday things. One number to watch: left to spend.
struct MonthPlan: Equatable {
    var income: Cents
    /// Early in the month this is your usual income, not just what's in.
    var incomeIsUsual: Bool
    /// Set when you plan around your own income figure.
    var incomePlanned: Cents? = nil
    /// What's actually arrived this month.
    var incomeReceived: Cents = 0
    var billsPaid: Cents
    var billsDue: Cents
    var savings: Cents
    /// Of `savings`: the one-month extra from "Save money this month".
    var savingsExtra: Cents = 0
    var cardPaydown: Cents = 0
    var trips: Cents
    var everydaySpent: Cents
    /// Sum of everyday limits (not bills or trips), to check they fit.
    var everydayLimits: Cents
    var daysLeft: Int?
    /// Unspent money rolling-over categories carried in from last month.
    var rolledIn: Cents = 0
    /// Set aside for goals (emergency fund, yearly bills, big purchases).
    var goals: Cents = 0

    var bills: Cents { billsPaid + billsDue }
    var toSpend: Cents { income - bills - savings - cardPaydown - trips - goals + rolledIn }
    var leftToSpend: Cents { toSpend - everydaySpent }
    var perDay: Cents? { daysLeft.map { leftToSpend > 0 ? leftToSpend / max(1, $0) : 0 } }
    /// How far everyday limits overshoot what there is to spend (0 = fits).
    var limitsOverBy: Cents { max(0, everydayLimits - toSpend) }
    /// How much more than planned has come in (0 when not more).
    var aboveIncomePlan: Cents { incomePlanned.map { max(0, incomeReceived - $0) } ?? 0 }
}

extension BudgetStore {
    var billCategoryIds: Set<String> {
        Set(expenseCategories.filter { $0.group == "Bills" }.map(\.id))
    }

    /// One Bills category this month: paid so far, and what's expected.
    struct BillLine: Identifiable {
        var category: Category
        var paid: Cents
        var usual: Cents
        var expected: Cents
        var id: String { category.id }
        var stillToCome: Cents { max(0, expected - paid) }
    }

    /// Each Bills category expects at least its usual (3-month average),
    /// or more when a known bill is still due, so bills that vary or
    /// haven't been paid yet are still counted. Past months: what was paid.
    func billLines(_ month: Date) -> [BillLine] {
        let isCurrent = month == currentMonth
        let due = isCurrent ? Dictionary(grouping: recurringCharges().filter { !$0.paidThisMonth },
                                         by: { $0.categoryId ?? "" }) : [:]
        return expenseCategories.filter { $0.group == "Bills" }.compactMap { c in
            let paid = spent(c.id, in: month)
            let usual = averageSpent(c.id, before: month) ?? 0
            let knownDue = (due[c.id] ?? []).reduce(0) { $0 + $1.amount }
            let expected = isCurrent ? max(usual, paid + knownDue) : paid
            return expected > 0 || paid > 0 ? BillLine(category: c, paid: paid, usual: usual, expected: max(expected, paid)) : nil
        }
        .sorted { $0.expected > $1.expected }
    }

    func monthPlan(_ month: Date) -> MonthPlan {
        let isCurrent = month == currentMonth
        let actualIncome = income(in: month)
        let usualIncome = averageIncome(before: month) ?? 0
        let lines = billLines(month)
        let billsPaid = lines.reduce(0) { $0 + $1.paid }
        let billsDue = lines.reduce(0) { $0 + $1.stillToCome }
        // A category without a limit still needs its usual spending.
        let everydayLimits = everydayCategories
            .map { limit($0, in: month) ?? averageSpent($0.id, before: month) ?? 0 }.reduce(0, +)
        let planned = isCurrent ? data.priorities?.plannedIncome : nil
        let expected = Self.incomeToPlanOn(planned: planned, usual: usualIncome)
        return MonthPlan(
            income: isCurrent ? max(actualIncome, expected) : actualIncome,
            incomeIsUsual: isCurrent && planned == nil && usualIncome > actualIncome,
            incomePlanned: planned,
            incomeReceived: actualIncome,
            billsPaid: billsPaid,
            billsDue: billsDue,
            savings: (data.priorities?.savings ?? 0) + (plan.map { isInMonth($0.month, month) ? $0.goal : 0 } ?? 0),
            savingsExtra: plan.map { isInMonth($0.month, month) ? $0.goal : 0 } ?? 0,
            cardPaydown: (data.priorities?.cardPaydown ?? 0) + (plan.flatMap { isInMonth($0.month, month) ? $0.cardExtra : nil } ?? 0),
            trips: tripSetAside(in: month),
            everydaySpent: totalSpent(in: month) - billsPaid,
            everydayLimits: everydayLimits,
            daysLeft: isCurrent ? daysLeftInMonth : nil,
            rolledIn: everydayCategories.reduce(0) { $0 + rolledIn($1, to: month) },
            goals: goalsSetAside(in: month))
    }

    /// Lowers everyday limits so they fit what there is to spend, taking
    /// more from flexible categories (shopping, dining) and never more than
    /// 25% of a limit. Returns how much is still over (0 = fits).
    /// The income you entered wins; otherwise your usual. Your usual can
    /// be low when a bank only shares a few weeks of history, so a figure
    /// you typed is trusted, and the plan says when it's above your usual.
    static func incomeToPlanOn(planned: Cents?, usual: Cents) -> Cents {
        planned ?? usual
    }

    /// What's owed across visible credit cards right now.
    var cardsOwed: Cents { creditCards.reduce(0) { $0 + max(0, -$1.balance) } }

    /// Everyday categories: the ones with limits you control day to day.
    var everydayCategories: [Category] {
        expenseCategories.filter { $0.group != "Bills" && $0.group != "Trips" && !$0.aimsForZero }
    }

    /// The most a limit is cut below usual in one month. Small steps stick;
    /// what's still over shows as over, so you can lower more by hand.
    static let maxMonthlyCut = 0.25

    /// Recommended limits for a given amount to spend: each everyday
    /// category starts at its usual (rounded up to $10), then flexible ones
    /// (shopping first, then dining, entertainment…) are trimmed, never more
    /// than 25%, until the total fits. Doesn't change anything.
    func recommendedLimits(toSpend: Cents, cap: Double = maxMonthlyCut) -> [String: Cents] {
        var base: [String: Cents] = [:]
        for c in everydayCategories { if let l = limitFromAverage(c) { base[c.id] = l } }
        let over = base.values.reduce(0, +) - toSpend
        guard over > 0 else { return base }
        let rooms = Dictionary(uniqueKeysWithValues: everydayCategories.compactMap { c -> (String, Double)? in
            base[c.id].map { (c.id, Double($0) * max(0.1, flexibility(of: c)) * cap) }
        })
        let totalRoom = rooms.values.reduce(0, +)
        guard totalRoom > 0 else { return base }
        let share = min(1, Double(over) / totalRoom)
        return base.mapValues { $0 }.reduce(into: [:]) { result, entry in
            let lowered = Double(entry.value) - (rooms[entry.key] ?? 0) * share
            result[entry.key] = max(1000, Int(lowered / 1000) * 1000)
        }
    }

    /// Sets every everyday limit to its recommendation for this month's plan.
    @discardableResult
    func setLimitsToPlan(_ month: Date) -> Cents {
        let recommended = recommendedLimits(toSpend: monthPlan(month).toSpend)
        for category in everydayCategories { setLimit(category.id, recommended[category.id]) }
        return monthPlan(month).limitsOverBy
    }

    @discardableResult
    func fitLimitsToPlan(_ month: Date, cap: Double = maxMonthlyCut) -> Cents {
        let over = monthPlan(month).limitsOverBy
        guard over > 0 else { return 0 }
        let candidates = expenseCategories.filter { $0.group != "Bills" && $0.group != "Trips" && !$0.aimsForZero }
            .compactMap { c -> (Category, Cents, Double)? in
                guard let l = c.limit, l > 0 else { return nil }
                let room = Double(l) * max(0.1, flexibility(of: c)) * cap
                return (c, l, room)
            }
        let totalRoom = candidates.reduce(0) { $0 + $1.2 }
        guard totalRoom > 0 else { return over }
        let share = min(1, Double(over) / totalRoom)
        for (category, limit, room) in candidates {
            let lowered = Int((Double(limit) - room * share) / 1000) * 1000
            setLimit(category.id, max(1000, lowered))
        }
        return monthPlan(month).limitsOverBy
    }
}
