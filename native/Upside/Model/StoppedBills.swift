import Foundation

/// A bill you stopped: cancelled, paid off, or simply over. From `from`
/// on it isn't expected, and its category stops counting it in its usual,
/// so the money is spending money again right away, not three months
/// later when the average catches up. If it charges again, it's back.
struct StoppedBill: Codable, Equatable, Identifiable {
    /// The bill's id: a payee key, or "key|price" for one of a store's prices.
    var id: String
    var name: String
    var categoryId: String?
    var amount: Cents
    /// The first month it no longer counts.
    var from: Date
}

extension BudgetStore {
    /// Stopped bills that haven't charged again since.
    var stoppedBills: [StoppedBill] {
        (data.stoppedBills ?? []).filter { stop in
            !spendingTransactions.contains { $0.amount < 0 && $0.date >= stop.from && Self.charge($0, isFor: stop.id) }
        }
    }

    /// Whether `bill` is stopped as of `month`.
    func isStopped(_ id: String, in month: Date) -> Bool {
        stoppedBills.contains { $0.id == id && $0.from <= month }
    }

    /// Stops a bill. `afterThisMonth`: it still charges once more this
    /// month (or was already paid), so it counts through this month.
    func stopBill(_ bill: Recurring, afterThisMonth: Bool) {
        let from = afterThisMonth || bill.paidThisMonth ? month(1, from: currentMonth) : currentMonth
        var stops = (data.stoppedBills ?? []).filter { $0.id != bill.id }
        stops.append(StoppedBill(id: bill.id, name: bill.name, categoryId: bill.categoryId,
                                 amount: bill.amount, from: from))
        data.stoppedBills = stops
    }

    func restartBill(_ id: String) {
        data.stoppedBills = (data.stoppedBills ?? []).filter { $0.id != id }
        if data.stoppedBills?.isEmpty == true { data.stoppedBills = nil }
    }

    /// What stopped bills added to a category's usual (its 3-month
    /// average) before `month`, so the usual can leave them out.
    func stoppedShare(_ categoryId: String, before month: Date) -> Cents {
        stoppedBills.filter { $0.categoryId == categoryId && $0.from <= month }.reduce(0) { sum, stop in
            let txns = spendingTransactions.filter { $0.categoryId == categoryId && Self.charge($0, isFor: stop.id) }
            return sum + max(0, -(perAccountAverage(txns, before: month) ?? 0))
        }
    }

    /// Whether a transaction is a charge for the bill `id` ("key" or "key|price").
    static func charge(_ t: Transaction, isFor id: String) -> Bool {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard payeeKey(t.payee) == parts[0] else { return false }
        guard parts.count == 2, let price = Int(parts[1]) else { return true }
        return -t.amount / 100 == price
    }
}
