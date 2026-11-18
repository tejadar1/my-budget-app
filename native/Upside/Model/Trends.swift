import Foundation

/// Comparing months, and the year as a whole. Trips stay out of the month
/// comparisons (a vacation isn't a trend); the year counts everything.
extension BudgetStore {

    // MARK: - Months side by side

    /// Spending (bills included, trips not) and income for each month,
    /// oldest first, ending at `month`. Months before the bank history
    /// starts are left out.
    func monthTotals(endingAt month: Date, count: Int = 12) -> [MonthTotal] {
        (0..<count).reversed()
            .map { self.month(-$0, from: month) }
            .filter { $0 >= firstFullMonth }
            .map { MonthTotal(month: $0, spent: totalSpent(in: $0), income: income(in: $0)) }
    }

    /// The last month that's over (the one before this month).
    var lastFinishedMonth: Date { month(-1, from: currentMonth) }

    /// One sentence on the shape of spending lately: the last three
    /// finished months against the three before them.
    static func spendingNote(_ finished: [MonthTotal]) -> String? {
        guard finished.count >= 2 else { return nil }
        let recent = Array(finished.suffix(3))
        let average = recent.reduce(0) { $0 + $1.spent } / recent.count
        guard finished.count >= 6 else {
            return "About \(Money.short(average)) a month over the last \(recent.count) months."
        }
        let before = finished.dropLast(3).suffix(3)
        let earlier = before.reduce(0) { $0 + $1.spent } / before.count
        let diff = average - earlier
        if abs(diff) < 5_000 || abs(diff) * 100 < earlier * 3 {
            return "About \(Money.short(average)) a month lately, steady with the three months before."
        }
        return "About \(Money.short(average)) a month lately, \(Money.short(abs(diff))) \(diff < 0 ? "less" : "more") than the three months before."
    }

    /// "That's about 31% of what comes in (about $14,540 a month)."
    static func incomeShareNote(_ finished: [MonthTotal]) -> String? {
        let recent = finished.suffix(3).filter { $0.income > 0 }
        guard !recent.isEmpty else { return nil }
        let income = recent.reduce(0) { $0 + $1.income } / recent.count
        let spent = recent.reduce(0) { $0 + $1.spent } / recent.count
        guard income > 0 else { return nil }
        let share = Int((Double(spent) / Double(income) * 100).rounded())
        return "That's about \(share)% of what comes in (about \(Money.short(income)) a month)."
    }

    /// Categories that moved the most in `month` compared with their
    /// usual (the three months before), biggest change first. Small
    /// wobbles (under $25 or 15%) are left out.
    func categoryChanges(in month: Date) -> [CategoryChange] {
        expenseCategories.filter { $0.group != "Trips" }.compactMap { c in
            let spent = spent(c.id, in: month)
            let usual = averageSpent(c.id, before: month) ?? 0
            let diff = spent - usual
            guard abs(diff) >= 2_500, abs(diff) * 100 >= usual * 15 else { return nil }
            return CategoryChange(category: c, spent: spent, usual: usual)
        }
        .sorted { abs($0.diff) > abs($1.diff) }
    }

    /// Every category with spending in the last `count` months, as a row
    /// of months, biggest average first.
    func categoryTrends(endingAt month: Date, count: Int = 6) -> [CategoryTrend] {
        expenseCategories.filter { $0.group != "Trips" }.compactMap { c in
            let points = monthlySpent(c.id, endingAt: month, count: count)
            let total = points.reduce(0) { $0 + $1.spent }
            guard total > 0 else { return nil }
            return CategoryTrend(category: c, points: points, average: total / points.count,
                                 note: Self.trendNote(points))
        }
        .sorted { $0.average > $1.average }
    }

    // MARK: - The year

    /// Years with any full month of history, oldest first.
    var reviewYears: [Int] {
        let first = calendar.component(.year, from: firstFullMonth)
        let last = calendar.component(.year, from: currentMonth)
        return first <= last ? Array(first...last) : [last]
    }

    /// The year to open first: last year during January (so it reads as a
    /// finished year), otherwise this one.
    var defaultReviewYear: Int {
        let year = calendar.component(.year, from: currentMonth)
        let january = calendar.component(.month, from: currentMonth) == 1
        return january && reviewYears.contains(year - 1) ? year - 1 : year
    }

    func yearReview(_ year: Int) -> YearReview {
        let months = (1...12)
            .compactMap { calendar.date(from: DateComponents(year: year, month: $0)) }
            .filter { $0 >= firstFullMonth && $0 <= currentMonth }
        let finished = months.filter { $0 < currentMonth }

        var review = YearReview(year: year, months: months, finishedMonths: finished,
                                isOver: year < calendar.component(.year, from: currentMonth))
        for m in months {
            review.income += income(in: m)
            review.spent += totalSpent(in: m, includeTrips: true)
            review.everyday += totalSpent(in: m)
            review.saved += savedAndInvested(in: m)
            review.fees += minimizeSpent(in: m)
            for (owner, amount) in spentByOwner(in: m) { review.byOwner[owner, default: 0] += amount }
        }
        // Per category, the same way `spent` counts it (each month netted,
        // trip purchases left to the trip), in one pass.
        var byCategoryMonth: [String: [Date: Cents]] = [:]
        let inYear = spendingTransactions.filter { t in months.contains { isInMonth(t.date, $0) } }
        for t in inYear {
            guard let id = t.categoryId, t.tripId == nil || id == "travel" else { continue }
            byCategoryMonth[id, default: [:]][monthStart(t.date), default: 0] -= t.amount
        }
        let byCategory = byCategoryMonth.mapValues { $0.values.reduce(0) { $0 + max(0, $1) } }
        review.trips = review.spent - review.everyday
        review.categories = expenseCategories.filter { $0.group != "Trips" }
            .compactMap { c in byCategory[c.id].flatMap { $0 > 0 ? CategoryTotal(category: c, spent: $0) : nil } }
            .sorted { $0.spent > $1.spent }

        let finishedTotals = finished.map { MonthSpend(month: $0, spent: totalSpent(in: $0)) }
        review.finishedEveryday = finishedTotals.reduce(0) { $0 + $1.spent }
        review.highest = finishedTotals.max { $0.spent < $1.spent }
        review.lowest = finishedTotals.count >= 2 ? finishedTotals.min { $0.spent < $1.spent } : nil

        // Months judged against the plan they started with. Only months
        // whose plan was kept count; today's limits say nothing about March.
        let everyday = everydayCategories
        for m in finished where data.originalLimits?[Self.monthKey(m)] != nil {
            let planned = everyday.compactMap { originalLimit($0, in: m) }.reduce(0, +)
            guard planned > 0 else { continue }
            review.monthsWithPlan += 1
            let spent = everyday.reduce(0) { $0 + self.spent($1.id, in: m) }
            if spent <= planned { review.monthsOnPlan += 1 }
        }

        // The biggest one-off purchases: not bills (rent would always win).
        let bills = billCategoryIds
        review.biggest = Array(inYear
            .filter { t in t.amount < 0 && !t.id.contains("#")
                && !(t.categoryId.map(bills.contains) ?? false) }
            .sorted { $0.amount < $1.amount }
            .prefix(3))
        return review
    }
}

struct MonthTotal: Identifiable, Equatable {
    var month: Date
    var spent: Cents
    var income: Cents
    var id: Date { month }
}

struct CategoryChange: Identifiable {
    var category: Category
    var spent: Cents
    var usual: Cents
    var diff: Cents { spent - usual }
    var id: String { category.id }
}

struct CategoryTrend: Identifiable {
    var category: Category
    var points: [MonthSpend]
    var average: Cents
    var note: String?
    var id: String { category.id }
}

struct CategoryTotal: Identifiable {
    var category: Category
    var spent: Cents
    var id: String { category.id }
}

struct YearReview {
    var year: Int
    /// Months of the year with history, through this month.
    var months: [Date]
    /// The same, without this month (still under way).
    var finishedMonths: [Date]
    /// A past year (December is over).
    var isOver: Bool
    var income: Cents = 0
    /// Everything spent: bills, everyday and trips.
    var spent: Cents = 0
    /// Spent without trips.
    var everyday: Cents = 0
    /// Spent without trips, in finished months only.
    var finishedEveryday: Cents = 0
    var trips: Cents = 0
    var saved: Cents = 0
    var fees: Cents = 0
    var byOwner: [Owner: Cents] = [:]
    var categories: [CategoryTotal] = []
    var highest: MonthSpend?
    var lowest: MonthSpend?
    var monthsWithPlan = 0
    var monthsOnPlan = 0
    var biggest: [Transaction] = []

    var leftOver: Cents { income - spent }
    /// A typical finished month's spending (no trips).
    var monthlyAverage: Cents? {
        finishedMonths.isEmpty ? nil : finishedEveryday / finishedMonths.count
    }
}
