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
        let saved = store.savedAndInvested(in: month)
        let usual = store.usual({ store.savedAndInvested(in: $0) }, before: month)
        let payoff = store.extraCardPayoff(in: month)

        let moves = store.savingsMoves(in: month)
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SAVINGS").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    if let onChange {
                        Button(goal > 0 ? "Change in Plan" : "Set in Plan", action: onChange)
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

/// Savings opened from its Budget row.
struct SavingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let month: Date
    var openPlan: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView { SavingsCard(month: month, onChange: openPlan).padding() }
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
                    Text("Money into savings and investment accounts, and transfers you marked Saved & invested. Interest and dividends don’t count.")
                }
            }
            .navigationTitle("Saved in \(month.formatted(.dateTime.month(.wide)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
