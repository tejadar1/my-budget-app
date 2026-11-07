import SwiftUI

/// Savings, front and center: this month's goal, what's actually been
/// saved or invested, and whether spending is leaving room for it.
struct SavingsCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    let onChange: () -> Void

    var body: some View {
        let plan = store.monthPlan(month)
        let goal = plan.savings
        let saved = store.savedAndInvested(in: month)
        let usual = store.usual({ store.savedAndInvested(in: $0) }, before: month)
        let payoff = store.extraCardPayoff(in: month)

        Button(action: onChange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SAVINGS").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(goal > 0 ? "Change in Plan" : "Set in Plan")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                if goal > 0 {
                    // One number: what's moved so far against Plan's savings.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Money.short(saved)).heroNumber(30).foregroundStyle(Theme.accent)
                        Text("saved of \(Money.short(goal))").foregroundStyle(.secondary)
                    }
                    SplitBar(fraction: Double(saved) / Double(goal), fill: Theme.accent, height: 6)
                    Text(breakdown(plan, goal: goal) + ". Counts money moved into savings and investment accounts.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Nothing set aside yet").font(.title3.weight(.semibold))
                    Text("Pay yourself first: pick an amount in Plan and limits fit around it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if goal > 0 {
                    Text(status(plan, left: max(0, goal - saved)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(plan.leftToSpend >= 0 ? Theme.accent : Theme.over)
                }
                if usual != nil || payoff > 0 {
                    Divider()
                    HStack(alignment: .top) {
                        if let usual { figure("Usually moved", usual) }
                        Spacer()
                        if payoff > 0 { figure("Extra paid on cards", payoff) }
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func breakdown(_ plan: MonthPlan, goal: Cents) -> String {
        let monthly = goal - plan.savingsExtra
        if plan.savingsExtra == 0 { return "\(Money.short(monthly)) every month" }
        if monthly == 0 { return "\(Money.short(plan.savingsExtra)) just this month" }
        return "\(Money.short(monthly)) every month + \(Money.short(plan.savingsExtra)) extra this month"
    }

    private func status(_ plan: MonthPlan, left: Cents) -> String {
        if left == 0 { return "Done for this month." }
        return plan.leftToSpend >= 0
            ? "On track: spending leaves room to move the other \(Money.short(left))."
            : "At risk: \(Money.short(-plan.leftToSpend)) over is coming out of it."
    }

    private func figure(_ label: String, _ value: Cents) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Money.short(value)).font(.headline.monospacedDigit())
        }
    }
}

/// Subtotals by kind of spending this month: everyday against its limits,
/// bills against what's expected, fees, and trips.
struct SpendingSubtotals: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let plan = store.monthPlan(month)
        let fees = store.minimizeSpent(in: month)
        let trips = store.totalSpent(in: month, includeTrips: true) - store.totalSpent(in: month)
        VStack(spacing: 12) {
            row("Everyday", spent: plan.everydaySpent - fees, of: plan.everydayLimits, note: "of limits")
            NavigationLink(value: Route.bills) {
                row("Bills", spent: plan.billsPaid, of: plan.bills, note: "of expected", chevron: true)
            }
            .buttonStyle(.plain)
            row("Fees & fines", spent: fees, of: nil, note: fees == 0 ? "none" : "aim for $0", warn: fees > 0)
            if trips > 0 { row("Trips", spent: trips, of: nil, note: "from the trip budget") }
        }
        .card()
    }

    private func row(_ label: String, spent: Cents, of total: Cents?, note: String,
                     warn: Bool = false, chevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text(total.map { "\(Money.short(spent)) of \(Money.short($0))" } ?? Money.short(spent))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(warn ? Theme.over : .primary)
                if chevron {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            if let total, total > 0 {
                SplitBar(fraction: Double(spent) / Double(total),
                         fill: spent > total ? Theme.over : Theme.accent, height: 6, overflow: Theme.over)
            }
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
