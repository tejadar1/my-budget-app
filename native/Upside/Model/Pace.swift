import Foundation

/// Running totals through a month, for the pace charts. They come from the
/// same rules as the cards (each category's spending, refunds netted inside
/// it), so a chart's last point is always the number on the card.
extension BudgetStore {
    struct DayTotal: Identifiable, Equatable {
        var day: Int
        var spent: Cents
        var id: Int { day }
    }

    /// Spent through each day of `month` (1…today, or the whole month once
    /// it's over) in `categories`: each category's running net, never
    /// below zero, added up.
    func runningSpent(in month: Date, categories: [Category]) -> [DayTotal] {
        let ids = Set(categories.map(\.id))
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let last = isInMonth(now(), month) ? calendar.component(.day, from: now())
            : (month > now() ? 0 : days)
        guard last > 0 else { return [] }
        // Net by category and day, the way `spent` counts: trip purchases
        // stay with the trip, except in Travel.
        var byCategoryDay: [String: [Int: Cents]] = [:]
        for t in spendingTransactions where isInMonth(t.date, month) {
            guard let c = t.categoryId, ids.contains(c), t.tripId == nil || c == "travel" else { continue }
            byCategoryDay[c, default: [:]][calendar.component(.day, from: t.date), default: 0] -= t.amount
        }
        var running: [String: Cents] = [:]
        return (1...last).map { day in
            for (c, byDay) in byCategoryDay { running[c, default: 0] += byDay[day] ?? 0 }
            return DayTotal(day: day, spent: running.values.reduce(0) { $0 + max(0, $1) })
        }
    }

    /// Everyday spending through each day: what the Budget card's "left to
    /// spend" is counted from (no bills, no trips).
    func runningEverydaySpent(in month: Date) -> [DayTotal] {
        runningSpent(in: month, categories: expenseCategories.filter { $0.group != "Trips" && $0.group != "Bills" })
    }

    /// One category through each day of `month`.
    func runningSpent(_ categoryId: String, in month: Date) -> [DayTotal] {
        guard let c = category(categoryId) else { return [] }
        return runningSpent(in: month, categories: [c])
    }

    struct MonthSaved: Identifiable, Equatable {
        var month: Date
        var saved: Cents
        /// What the plan set aside that month (0 when none).
        var planned: Cents
        var id: Date { month }
    }

    /// Saved and invested each month for the last `count` months (through
    /// this one), with what the plan set aside then.
    func savingsHistory(endingAt month: Date, count: Int = 12) -> [MonthSaved] {
        (0..<count).reversed().map { self.month(-$0, from: month) }
            .filter { $0 >= firstFullMonth }
            .map { MonthSaved(month: $0, saved: max(0, savedAndInvested(in: $0)), planned: monthPlan($0).savings) }
    }
}
