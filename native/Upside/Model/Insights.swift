import Foundation

struct MonthSpend: Identifiable, Equatable {
    var month: Date
    var spent: Cents
    var id: Date { month }
}

// MARK: - Bills and subscriptions

/// A charge that comes back about once a month at about the same price.
struct Recurring: Identifiable, Equatable {
    var id: String            // payee key
    var name: String
    var categoryId: String?
    var amount: Cents         // latest charge, positive
    var previous: Cents?      // the charge before, when the price was steady
    var lastDate: Date
    var firstDate: Date
    var paidThisMonth: Bool
    var dueDate: Date?        // this month, when not paid yet
    var isSubscription: Bool
    var isNew: Bool           // started in the last couple of months

    var priceIncrease: Cents? {
        guard let previous, amount - previous >= 100, amount * 100 >= previous * 105 else { return nil }
        return amount - previous
    }
}

extension BudgetStore {
    /// Looks back six months for payees charged about once a month, on about
    /// the same day, for about the same amount, and still active.
    func recurringCharges() -> [Recurring] {
        let thisMonth = currentMonth
        let since = month(-6, from: thisMonth)
        let today = now()
        let charges = spendingTransactions.filter {
            $0.amount < 0 && $0.tripId == nil && $0.date >= since && $0.date <= today
        }
        let groups = Dictionary(grouping: charges) { BudgetStore.payeeKey($0.payee) }
        let historyStart = firstMonth

        return groups.compactMap { key, list -> Recurring? in
            let sorted = list.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            let months = Set(sorted.map { monthStart($0.date) })
            // Twice or more, about once a month, charged in the last 45 days.
            guard months.count >= 2, sorted.count <= months.count + 1,
                  today.timeIntervalSince(last.date) <= 45 * 86_400 else { return nil }

            let amounts = sorted.map { -$0.amount }
            let median = amounts.sorted()[amounts.count / 2]
            guard amounts.allSatisfy({ abs($0 - median) * 100 <= median * 35 }) || steadyThenChanged(amounts)
            else { return nil }

            let days = sorted.map { calendar.component(.day, from: $0.date) }
            guard (days.max() ?? 0) - (days.min() ?? 0) <= 10 else { return nil }

            // Price change only counts when it was steady before.
            let earlier = amounts.dropLast()
            let previous = earlier.last.flatMap { p in earlier.allSatisfy { $0 == p } ? p : nil }

            let paid = isInMonth(last.date, thisMonth)
            var due: Date? = nil
            if !paid {
                let dayCount = calendar.range(of: .day, in: .month, for: thisMonth)!.count
                let day = min(calendar.component(.day, from: last.date), dayCount)
                due = calendar.date(byAdding: .day, value: day - 1, to: thisMonth)
            }
            let categoryId = last.categoryId
            return Recurring(
                id: key, name: last.payee, categoryId: categoryId,
                amount: -last.amount, previous: previous,
                lastDate: last.date, firstDate: first.date,
                paidThisMonth: paid, dueDate: due,
                isSubscription: categoryId == "subscriptions",
                isNew: monthStart(first.date) >= month(-2, from: thisMonth)
                    && historyStart < month(-2, from: thisMonth))
        }
        .sorted { ($0.dueDate ?? $0.lastDate) < ($1.dueDate ?? $1.lastDate) }
    }

    /// A steady price with one change at the end (e.g. $15.49 → $22.99).
    private func steadyThenChanged(_ amounts: [Cents]) -> Bool {
        let earlier = amounts.dropLast()
        guard let p = earlier.first, earlier.count >= 2 else { return false }
        return earlier.allSatisfy { $0 == p }
    }

    // MARK: - Trends

    /// Spending in a category for the six months ending at `month`
    /// (fewer if the history doesn't go back that far).
    func monthlySpent(_ categoryId: String, endingAt month: Date, count: Int = 6) -> [MonthSpend] {
        (0..<count).reversed()
            .map { self.month(-$0, from: month) }
            .filter { $0 >= firstMonth }
            .map { MonthSpend(month: $0, spent: spent(categoryId, in: $0)) }
    }

    /// One plain sentence about the shape of finished months, oldest first.
    static func trendNote(_ points: [MonthSpend]) -> String? {
        guard points.count >= 3 else { return nil }
        let values = points.map(\.spent)
        let last3 = values.suffix(3)
        if zip(last3, last3.dropFirst()).allSatisfy({ $0 < $1 }), let a = last3.first, let b = last3.last,
           b * 10 > a * 11 {
            return "Up three months in a row."
        }
        if zip(last3, last3.dropFirst()).allSatisfy({ $0 > $1 }), let a = last3.first, let b = last3.last,
           b * 11 < a * 10 {
            return "Down three months in a row."
        }
        if let peak = values.indices.max(by: { values[$0] < values[$1] }) {
            var others = values; others.remove(at: peak)
            let median = others.sorted()[others.count / 2]
            if median > 0, values[peak] * 10 > median * 14 {
                return "\(points[peak].month.formatted(.dateTime.month(.wide))) was unusually high; the other months were steadier."
            }
        }
        return nil
    }

    // MARK: - Search

    /// Purchases whose store contains the text, or whose amount matches
    /// ("84.12", "$84.12", "1,200"). Newest first.
    func search(_ query: String) -> [Transaction] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let amount = BudgetStore.parseAmount(text)
        return data.transactions.filter { t in
            if let amount, abs(t.amount) == amount { return true }
            return t.payee.localizedCaseInsensitiveContains(text)
        }
    }

    static func parseAmount(_ text: String) -> Cents? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard cleaned.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: cleaned) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}
