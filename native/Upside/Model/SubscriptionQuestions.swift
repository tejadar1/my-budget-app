import Foundation

/// New subscriptions and price increases, asked once in Needs attention:
/// "New: Disney+, $13.99 a month. Keep it?" Keep, Stop, or Not a
/// subscription. A later price increase asks again.
extension BudgetStore {
    /// What an answer is remembered under: the bill, or for a price
    /// increase the bill at its new price (so the next increase asks again).
    static func subscriptionKey(_ bill: Recurring) -> String {
        bill.priceIncrease != nil ? "\(bill.id)@\(bill.amount)" : bill.id
    }

    /// Unanswered: price increases on any bill, and new subscriptions.
    func subscriptionQuestions() -> [Recurring] {
        let answered = Set(data.subscriptionsKept ?? [])
        return recurringCharges().filter { bill in
            (bill.priceIncrease != nil || (bill.isNew && bill.isSubscription))
                && !answered.contains(Self.subscriptionKey(bill))
                && lastPayment(bill.id) == nil      // you're cancelling it
        }
        .sorted { ($0.priceIncrease ?? 0, $0.amount) > ($1.priceIncrease ?? 0, $1.amount) }
    }

    /// Whether a bill's question has been answered (Keep).
    func isKept(_ bill: Recurring) -> Bool {
        (data.subscriptionsKept ?? []).contains(Self.subscriptionKey(bill))
    }

    func keepSubscription(_ bill: Recurring) {
        var keys = Set(data.subscriptionsKept ?? [])
        keys.insert(Self.subscriptionKey(bill))
        data.subscriptionsKept = keys.sorted()
    }
}
