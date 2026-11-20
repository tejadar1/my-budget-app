import Foundation

/// A new paycheck amount, noticed from the first one or two checks.
/// "Usual income" leans on the lower checks of the last 6 months, which
/// keeps one-off bonuses out but is slow to see a real drop (a bigger 401(k)
/// contribution, fewer hours). So a lower check is asked about right away;
/// a raise isn't: it has to keep arriving before the plan counts on it.
struct IncomeLevel: Codable, Equatable {
    /// The new check.
    var perCheck: Cents
    /// What the source adds to a month at that check.
    var monthly: Cents
    /// The month it applies from.
    var since: Date
}

extension BudgetStore {
    struct PayChange: Identifiable, Hashable {
        var sourceId: String
        var owner: Owner
        var oldMonthly: Cents
        var newMonthly: Cents
        /// How much smaller each check is.
        var perCheckDrop: Cents
        /// Lower checks in a row at about the new amount (1 or 2+).
        var inARow: Int
        var latestId: String
        var latestAmount: Cents
        var id: String { sourceId }
    }

    /// Paychecks that came in lower than usual and haven't been answered.
    func payChanges() -> [PayChange] {
        let all = payers()
        let since = month(-6, from: currentMonth)
        return incomeSources(before: currentMonth).filter { !$0.stopped && $0.monthly > 0 }.compactMap { source in
            let checks = incomeTransactions.filter { payerKey($0) == source.id }.sorted { $0.date < $1.date }
            guard checks.count >= 4, let latest = checks.last,
                  data.payChangeSeen?[source.id] != latest.id else { return nil }
            // Already planning on about this amount.
            if let level = data.incomeLevels?[source.id], latest.amount * 100 >= level.perCheck * 95 { return nil }
            // How many of the latest checks are at about the new amount.
            var run = 0
            for t in checks.reversed() {
                guard abs(t.amount - latest.amount) * 100 <= latest.amount * 2 else { break }
                run += 1
            }
            let before = checks.dropLast(run).suffix(6).map(\.amount).sorted()
            guard before.count >= 3 else { return nil }
            let typical = before[before.count / 2]
            let drop = typical - latest.amount
            // Small wiggles (a few dollars of tax) aren't a change.
            guard drop >= 5_000, drop * 100 >= typical * 5 else { return nil }
            let perMonth: Int
            switch all[source.id]?.cadence ?? .other {
            case .weekly: perMonth = 4
            case .biweekly: perMonth = 2
            case .other:
                let recent = checks.filter { $0.date >= since }
                let months = Set(recent.map { monthStart($0.date) }).count
                perMonth = max(1, Int((Double(recent.count) / Double(max(1, months))).rounded()))
            }
            return PayChange(sourceId: source.id, owner: source.owner, oldMonthly: source.monthly,
                             newMonthly: max(0, source.monthly - drop * perMonth), perCheckDrop: drop,
                             inARow: run, latestId: latest.id, latestAmount: latest.amount)
        }
    }

    /// "Plan on the new amount": from this month on, this paycheck counts
    /// at the lower amount, and an income you typed into Plan comes down by
    /// the same. If limits no longer fit, Budget says so as usual.
    func acceptPayChange(_ change: PayChange) {
        var updated = data
        var levels = updated.incomeLevels ?? [:]
        levels[change.sourceId] = IncomeLevel(perCheck: change.latestAmount, monthly: change.newMonthly, since: currentMonth)
        updated.incomeLevels = levels
        var seen = updated.payChangeSeen ?? [:]
        seen[change.sourceId] = change.latestId
        updated.payChangeSeen = seen
        if var priorities = updated.priorities, let planned = priorities.plannedIncome {
            priorities.plannedIncome = max(0, planned - (change.oldMonthly - change.newMonthly))
            updated.priorities = priorities
        }
        data = updated
    }

    /// "Just this once": don't ask about this check again. A later lower
    /// check asks again.
    func dismissPayChange(_ change: PayChange) {
        var seen = data.payChangeSeen ?? [:]
        seen[change.sourceId] = change.latestId
        data.payChangeSeen = seen
    }

    /// The level you chose for a source, while its checks are still at it
    /// (a raise later lets the usual take over again).
    func incomeLevel(_ sourceId: String, for month: Date) -> IncomeLevel? {
        guard let level = data.incomeLevels?[sourceId], month >= monthStart(level.since) else { return nil }
        let latest = incomeTransactions.filter { payerKey($0) == sourceId }.max { $0.date < $1.date }
        guard let latest, latest.amount * 100 <= level.perCheck * 105 else { return nil }
        return level
    }
}
