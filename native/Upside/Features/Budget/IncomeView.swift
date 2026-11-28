import SwiftUI

/// Everything that comes in: this month so far, each paycheck source and
/// what it adds to a usual month, the last six months, and deposits that
/// aren't counted, so a paycheck taken for a transfer is easy to spot.
struct IncomeView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let month = store.currentMonth
        let plan = store.monthPlan(month)
        let sources = store.incomeSources(before: month)
        let usual = sources.reduce(0) { $0 + $1.monthly }
        let paychecks = store.paychecksThisMonth()
        let uncounted = store.uncountedDeposits()
        let history = store.monthTotals(endingAt: month, count: 6)
        let monthName = month.formatted(.dateTime.month(.wide))

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Money.short(plan.incomeReceived)).heroNumber(40)
                    Text("in so far in \(monthName) · usually \(Money.short(usual))")
                        .foregroundStyle(.secondary)
                    if let planned = plan.incomePlanned {
                        Text("Your plan counts on \(Money.short(planned)).")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            if !sources.isEmpty {
                Section {
                    ForEach(sources) { source in
                        SourceRow(source: source)
                            .swipeActions { notIncomeButton(source) }
                            .contextMenu { notIncomeButton(source) }
                    }
                } header: {
                    Text("Where it comes from")
                } footer: {
                    Text("A usual month from each. Tap a name to change whose it is. Not income? Swipe left.")
                }
            }

            Section {
                if paychecks.isEmpty {
                    Text("Nothing yet this month.").foregroundStyle(.secondary)
                } else {
                    ForEach(paychecks) { TransactionRow(transaction: $0) }
                }
            } header: {
                Text("This month")
            }

            if !uncounted.isEmpty {
                Section {
                    ForEach(uncounted) { t in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Merchant.clean(t.payee)).lineLimit(1)
                                Text("\(t.date.formatted(.dateTime.month(.abbreviated).day())) · \(store.whyNotIncome(t))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Money.exact(t.amount)).monospacedDigit()
                                Button("Count as income") {
                                    withAnimation { store.undoable("Counted as income") { store.countAsIncome(t.id) } }
                                    Haptics.success()
                                }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    Text("Deposits not counted")
                } footer: {
                    Text("The last two months, $100 or more. Moving your own money isn't income; a paycheck is.")
                }
            }

            if history.count >= 2 {
                Section("Last \(history.count) months") {
                    let peak = max(1, history.map(\.income).max() ?? 1)
                    ForEach(history.reversed()) { m in
                        HStack(spacing: 12) {
                            Text(m.month.formatted(.dateTime.month(.abbreviated)))
                                .frame(width: 40, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(m.month == month ? Theme.accent.opacity(0.4) : Theme.accent)
                                    .frame(width: max(4, geo.size.width * CGFloat(m.income) / CGFloat(peak)))
                            }
                            .frame(height: 10)
                            Text(Money.short(m.income)).monospacedDigit()
                                .frame(minWidth: 72, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                LearnMore(topic: .income)
            }
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Swipe: a source that isn't income (someone paying you back).
    private func notIncomeButton(_ source: BudgetStore.IncomeSource) -> some View {
        Button(role: .destructive) {
            withAnimation { store.undoable("\(Merchant.clean(source.name)) isn't income") { store.removeIncomeSource(source.id) } }
            Haptics.success()
        } label: {
            Label("Not income", systemImage: "minus.circle")
        }
    }
}

/// One source: whose it is (tap to change), how often it pays, when it
/// last did, and what it adds to a usual month. A quiet one can be kept.
private struct SourceRow: View {
    @Environment(BudgetStore.self) private var store
    let source: BudgetStore.IncomeSource

    var body: some View {
        let last = store.lastPaid(source.id)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Merchant.clean(source.name)).lineLimit(1)
                Menu {
                    ForEach(Owner.pickable) { owner in
                        Button(store.people.name(owner)) { store.setIncomeOwner(source.id, owner) }
                    }
                } label: {
                    Text(detail).font(.footnote).foregroundStyle(Theme.accent)
                }
                if let last {
                    Text("Last paid \(last.date.formatted(.dateTime.month(.abbreviated).day())) · \(Money.exact(last.amount))")
                        .font(.footnote).foregroundStyle(source.stopped ? Theme.over : .secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(source.stopped ? "not counted" : Money.short(source.monthly) + "/mo")
                    .monospacedDigit().foregroundStyle(source.stopped ? .secondary : .primary)
                if source.stopped {
                    Button("Still paying") {
                        withAnimation { store.undoable("\(Merchant.clean(source.name)) still counted") { store.setStillPaying(source.id, true) } }
                        Haptics.success()
                    }
                    .font(.footnote.weight(.semibold)).buttonStyle(.borderless)
                }
            }
        }
    }

    private var detail: String {
        let who = source.owner == .unassigned ? "Whose is this?" : store.people.name(source.owner)
        if source.stopped { return who + " · no pay lately" }
        switch source.cadence {
        case .weekly: return who + " · weekly"
        case .biweekly: return who + " · every 2 weeks"
        case .other: return source.estimated ? who + " · estimated" : who
        }
    }
}
