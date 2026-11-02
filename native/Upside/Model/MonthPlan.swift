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

    func monthPlan(_ month: Date) -> MonthPlan {
        let isCurrent = month == currentMonth
        let actualIncome = income(in: month)
        let usualIncome = averageIncome(before: month) ?? 0
        let billIds = billCategoryIds
        let billsPaid = billIds.reduce(0) { $0 + spent($1, in: month) }
        let billsDue = isCurrent
            ? recurringCharges().filter { !$0.paidThisMonth && $0.categoryId.map(billIds.contains) == true }
                .reduce(0) { $0 + $1.amount }
            : 0
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
