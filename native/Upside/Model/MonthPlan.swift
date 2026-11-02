import Foundation

/// The month top-down: income, minus bills, savings and trips, leaves
/// what you can spend on everyday things. One number to watch: left to spend.
struct MonthPlan: Equatable {
    var income: Cents
    /// Early in the month this is your usual income, not just what's in.
    var incomeIsUsual: Bool
    var billsPaid: Cents
    var billsDue: Cents
    var savings: Cents
    var trips: Cents
    var everydaySpent: Cents
    /// Sum of everyday limits (not bills or trips), to check they fit.
    var everydayLimits: Cents
    var daysLeft: Int?

    var bills: Cents { billsPaid + billsDue }
    var toSpend: Cents { income - bills - savings - trips }
    var leftToSpend: Cents { toSpend - everydaySpent }
    var perDay: Cents? { daysLeft.map { leftToSpend > 0 ? leftToSpend / max(1, $0) : 0 } }
    /// How far everyday limits overshoot what there is to spend (0 = fits).
    var limitsOverBy: Cents { max(0, everydayLimits - toSpend) }
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
        let everydayLimits = expenseCategories
            .filter { $0.group != "Bills" && $0.group != "Trips" && !$0.aimsForZero }
            .compactMap { limit($0, in: month) }.reduce(0, +)
        return MonthPlan(
            income: isCurrent ? max(actualIncome, usualIncome) : actualIncome,
            incomeIsUsual: isCurrent && usualIncome > actualIncome,
            billsPaid: billsPaid,
            billsDue: billsDue,
            savings: plan.map { isInMonth($0.month, month) ? $0.goal : 0 } ?? 0,
            trips: tripSetAside(in: month),
            everydaySpent: totalSpent(in: month) - billsPaid,
            everydayLimits: everydayLimits,
            daysLeft: isCurrent ? daysLeftInMonth : nil)
    }

    /// Lowers everyday limits so they fit what there is to spend, taking
    /// more from flexible categories (shopping, dining) and never more than
    /// 40% of a limit. Returns how much is still over (0 = fits).
    @discardableResult
    func fitLimitsToPlan(_ month: Date) -> Cents {
        let over = monthPlan(month).limitsOverBy
        guard over > 0 else { return 0 }
        let candidates = expenseCategories.filter { $0.group != "Bills" && $0.group != "Trips" && !$0.aimsForZero }
            .compactMap { c -> (Category, Cents, Double)? in
                guard let l = c.limit, l > 0 else { return nil }
                let room = Double(l) * max(0.1, flexibility(of: c)) * 0.4
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
