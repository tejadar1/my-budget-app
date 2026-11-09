import Foundation

/// What's worth a heads-up besides limits: bills about to hit, a checking
/// balance running low, and purchases bigger than usual. Pure rules here;
/// `Alerts` turns them into notifications.
extension BudgetStore {
    struct BillReminder: Equatable {
        var id: String
        var title: String
        var body: String
        /// 9am two days before it's due.
        var fireDate: Date
    }

    /// One reminder per unpaid bill or subscription still due this month.
    func billReminders() -> [BillReminder] {
        recurringCharges().compactMap { bill in
            guard !bill.paidThisMonth, let due = bill.dueDate else { return nil }
            let day = calendar.startOfDay(for: due)
            guard let twoBefore = calendar.date(byAdding: .day, value: -2, to: day),
                  let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: twoBefore),
                  fire > now() else { return nil }
            let key = Self.monthKey(currentMonth)
            return BillReminder(id: "bill-\(key)-\(bill.id)",
                                title: "\(Merchant.clean(bill.name)) is due \(due.formatted(.dateTime.weekday(.wide)))",
                                body: "About \(Money.short(bill.amount)), usually charged around the \(Self.ordinal(calendar.component(.day, from: due))).",
                                fireDate: fire)
        }
    }

    /// Checking is below `threshold`, or below what's still due in bills.
    /// Once a day at most.
    func lowBalanceAlert(threshold: Cents) -> (key: String, title: String, body: String)? {
        let checking = visibleAccounts.filter { $0.kind == .checking && $0.countsInBudget }
        guard !checking.isEmpty else { return nil }
        let balance = checking.reduce(0) { $0 + $1.balance }
        let due = monthPlan(currentMonth).billsDue
        let key = "low-\(calendar.startOfDay(for: now()).timeIntervalSince1970)"
        guard !(data.alertsSent ?? []).contains(key) else { return nil }
        if balance < due {
            return (key, "Checking is low for this month’s bills",
                    "\(Money.short(balance)) in checking, \(Money.short(due)) in bills still due.")
        }
        if balance < threshold {
            return (key, "Checking is under \(Money.short(threshold))", "\(Money.short(balance)) left across checking.")
        }
        return nil
    }

    /// Recent purchases (last 3 days) of `threshold` or more that aren't
    /// bills, transfers or business, each mentioned once.
    func largePurchases(threshold: Cents) -> [Transaction] {
        let since = now().addingTimeInterval(-3 * 86_400)
        let sent = Set(data.alertsSent ?? [])
        let bills = billCategoryIds
        // Whole purchases: a split $640 is one large purchase, not two.
        let spending = Set(spendingTransactions.map { Self.baseId($0.id) })
        return data.transactions.filter {
            spending.contains($0.id) && $0.date >= since && -$0.amount >= threshold
                && !sent.contains("large-\($0.id)") && !bills.contains($0.categoryId ?? "")
        }
    }

    private static func ordinal(_ day: Int) -> String {
        let suffix = (11...13).contains(day % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][day % 10] ?? "th"
        return "\(day)\(suffix)"
    }
}
