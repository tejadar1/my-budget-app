import Charts
import SwiftUI

/// Savings, front and center: this month's goal, what's actually been
/// saved or invested, and whether spending is leaving room for it.
struct SavingsCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    /// Opens Plan; nil hides the button (past months).
    var onChange: (() -> Void)? = nil
    @State private var showMoves = false

    var body: some View {
        let plan = store.monthPlan(month)
        let goal = plan.savings
        // Savings this month that went to paying for overspending.
        let cut = store.cut(.savings, in: month)
        let monthName = month.formatted(.dateTime.month(.wide))
        let saved = store.savedAndInvested(in: month)
        let usual = store.usual({ store.savedAndInvested(in: $0) }, before: month)
        let payoff = store.extraCardPayoff(in: month)

        let moves = store.savingsMoves(in: month)
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SAVINGS").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    if let onChange {
                        Button(goal + cut > 0 ? "Change in Plan" : "Set in Plan", action: onChange)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
                if goal > 0 {
                    // One number: what's moved so far against Plan's savings.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Money.short(saved)).heroNumber(30).foregroundStyle(Theme.accent)
                        Text("saved of \(Money.short(goal))").foregroundStyle(.secondary)
                    }
                    SplitBar(fraction: Double(saved) / Double(goal), fill: Theme.accent, height: 6)
                    Text(breakdown(plan, goal: goal, cut: cut) + ". Counts money moved into savings and investment accounts.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if cut > 0 {
                    // Planned, then given up to pay for overspending: say so,
                    // not "nothing set aside".
                    Text("$0 to save in \(monthName)").font(.title3.weight(.semibold))
                    Text("You planned \(Money.short(cut)). All of it went to paying for overspending this month. Next month goes back to your plan.")
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
                        if payoff > 0 { figure("Card paydown, not savings", payoff) }
                    }
                }
                if !moves.isEmpty {
                    Button { showMoves = true } label: {
                        HStack {
                            Text("What counted (\(moves.count))")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .card()
            .sheet(isPresented: $showMoves) { SavingsMovesSheet(month: month) }
    }

    private func breakdown(_ plan: MonthPlan, goal: Cents, cut: Cents) -> String {
        // What you planned, before anything went to overspending.
        let monthly = goal + cut - plan.savingsExtra
        let less = cut > 0 ? ", \(Money.short(cut)) less for overspending this month" : ""
        if plan.savingsExtra == 0 { return "\(Money.short(monthly)) every month" + less }
        if monthly == 0 { return "\(Money.short(plan.savingsExtra)) just this month" + less }
        return "\(Money.short(monthly)) every month + \(Money.short(plan.savingsExtra)) extra this month" + less
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

/// Savings opened from its Budget row.
struct SavingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let month: Date
    var openPlan: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SavingsCard(month: month, onChange: openPlan)
                    SavingsHistoryCard(month: month)
                }
                .padding()
            }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Savings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The transfers behind "saved so far", so the number can be checked.
private struct SavingsMovesSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.savingsMoves(in: month)) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Merchant.clean(t.payee)).lineLimit(1)
                                Text("\(t.date.formatted(.dateTime.month(.abbreviated).day())) · \(store.account(t.accountId)?.fullName ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let amount = store.savingsAmount(t)
                            Text((amount >= 0 ? "+" : "−") + Money.exact(abs(amount)))
                                .monospacedDigit()
                                .foregroundStyle(amount >= 0 ? Theme.accent : Theme.over)
                        }
                    }
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Interest and dividends don’t count.")
                        Spacer(minLength: 8)
                        LearnMore(topic: .savings)
                    }
                }
            }
            .navigationTitle("Saved in \(month.formatted(.dateTime.month(.wide)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Saved each month for the last year, with what the plan set aside as a
/// line: "am I actually saving?" at a glance.
struct SavingsHistoryCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    @State private var selected: Date?

    var body: some View {
        let history = store.savingsHistory(endingAt: month)
        let target = store.monthPlan(month).savings
        if history.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("SAVED EACH MONTH").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                Chart {
                    ForEach(history) { m in
                        BarMark(x: .value("Month", m.month, unit: .month), y: .value("Saved", Double(m.saved) / 100))
                            .foregroundStyle(m.planned > 0 && m.saved >= m.planned ? Theme.accent : Theme.accent.opacity(0.45))
                            .cornerRadius(4)
                    }
                    if target > 0 {
                        RuleMark(y: .value("Plan", Double(target) / 100))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if let selected, let m = history.first(where: { store.isInMonth($0.month, selected) }) {
                        RuleMark(x: .value("Month", m.month, unit: .month))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                Text("\(m.month.formatted(.dateTime.month(.abbreviated))): \(Money.short(m.saved))")
                                    .font(.caption.weight(.semibold))
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let dollars = value.as(Double.self) { Text(Money.short(Cents(dollars * 100))) }
                        }
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Saved each month")
                .accessibilityValue(history.map { "\($0.month.formatted(.dateTime.month(.wide))) \(Money.short($0.saved))" }
                    .joined(separator: ", "))
                Text(target > 0 ? "Dashed: the \(Money.short(target)) a month you plan to save. Full green: months that made it."
                                : "Money moved into savings and investment accounts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .card()
        }
    }
}
