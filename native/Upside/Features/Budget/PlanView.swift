import SwiftUI

/// The one place to plan the month: savings, card paydown and trips come
/// off the top, and everyday limits are recommended to fit what's left.
struct PlanView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var plannedIncome = 0
    @State private var savings = 0
    @State private var paydown = 0
    @State private var trips = 0
    /// Everyday limits in whole dollars; 0 means no limit.
    @State private var limits: [String: Int] = [:]
    @State private var showExtra = false
    /// What "Fix it for me" did, shown until the next change.
    @State private var fixNote: String?

    private var month: Date { store.currentMonth }

    /// Everything the screen shows, worked out once per redraw.
    private struct Numbers {
        var base: MonthPlan
        var usualIncome: Cents
        var extraSavings: Cents
        var toSpend: Cents
        var recommended: [String: Cents]
        /// Limits plus usual spending for categories without one.
        var total: Cents
        var owed: Cents
    }

    private func numbers() -> Numbers {
        let base = store.monthPlan(month)
        let usualIncome = store.averageIncome(before: month) ?? 0
        let expected = BudgetStore.incomeToPlanOn(planned: plannedIncome > 0 ? plannedIncome * 100 : nil, usual: usualIncome)
        let income = max(expected, base.incomeReceived)
        let extraSavings = store.plan.map { store.isInMonth($0.month, month) ? $0.goal : 0 } ?? 0
        // $0 for trips means each trip saves its own share.
        let tripCost = trips > 0 ? trips * 100 : store.tripScheduleSetAside(in: month)
        let toSpend = income - base.bills - (savings * 100 + extraSavings) - paydown * 100 - tripCost
        let total = limitsTotal(limits)
        return Numbers(base: base, usualIncome: usualIncome, extraSavings: extraSavings, toSpend: toSpend,
                       recommended: store.recommendedLimits(toSpend: toSpend), total: total, owed: store.cardsOwed)
    }

    var body: some View {
        let n = numbers()
        NavigationStack {
            Form {
                incomeSection(n)
                prioritiesSection(n)
                limitsSection(n)
                shortSection(n)
                spareSection(n)
                Section {
                    Button("Save extra just this month…") { showExtra = true }
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .sheet(isPresented: $showExtra) { SavingsPlanView() }
            .onAppear(perform: load)
        }
    }

    private func incomeSection(_ n: Numbers) -> some View {
        Section {
            amountRow("Income to plan for", $plannedIncome)
            if n.usualIncome > 0 && plannedIncome * 100 != n.usualIncome {
                Button("Use my usual: \(Money.short(n.usualIncome))") { plannedIncome = (n.usualIncome + 50) / 100 }
                    .font(.subheadline)
            }
            ForEach(store.incomeSources(before: month)) { source in
                IncomeSourceRow(source: source)
            }
            LabeledContent("Bills (expected)", value: "–" + Money.short(n.base.bills))
        } header: {
            Text(month.formatted(.dateTime.month(.wide)))
        } footer: {
            Text(incomeFooter(n))
        }
    }

    private func incomeFooter(_ n: Numbers) -> String {
        let planned = plannedIncome * 100
        guard planned > 0 else {
            return "Leave at $0 to plan around your usual income: every paycheck above added together. A third paycheck is a bonus when it lands; one that stops for 5 weeks stops counting. Paid into an account that isn't connected? Mark that transfer as Income."
        }
        if n.usualIncome > 0 && planned > n.usualIncome {
            return "\(Money.short(planned - n.usualIncome)) more than your usual \(Money.short(n.usualIncome)). Fine if your usual is missing history or a raise; if less arrives, lower this. \(Money.short(n.base.incomeReceived)) has come in so far."
        }
        return "\(Money.short(n.base.incomeReceived)) has come in so far. If more arrives, the extra counts; finished months use what really came in."
    }

    private func prioritiesSection(_ n: Numbers) -> some View {
        Section {
            amountRow("Savings each month", $savings)
            if n.extraSavings > 0 {
                HStack {
                    Text("Extra just this month")
                    Spacer()
                    Text(Money.short(n.extraSavings)).monospacedDigit()
                    Button("Remove", role: .destructive) { withAnimation { store.data.plan = nil } }
                        .buttonStyle(.borderless)
                }
            }
            amountRow("Card paydown each month", $paydown)
            if n.owed > 0 {
                HStack(spacing: 8) {
                    ForEach([6, 12], id: \.self) { months in
                        Button("Clear cards in \(months) mo") { paydown = (n.owed / months + 99) / 100 }
                            .buttonStyle(.bordered)
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            amountRow("Trips each month", $trips)
            LabeledContent("To spend") {
                Text(Money.short(n.toSpend)).fontWeight(.bold)
                    .foregroundStyle(n.toSpend >= 0 ? Theme.accent : Theme.over)
            }
        } header: {
            Text("Pay yourself first")
        } footer: {
            Text(priorityFooter(owed: n.owed, extra: n.extraSavings))
        }
    }

    private func limitsSection(_ n: Numbers) -> some View {
        Section {
            Button("Use recommended limits") {
                withAnimation { limits = n.recommended.mapValues { $0 / 100 } }
            }
            .fontWeight(.semibold)
            ForEach(store.everydayCategories) { c in
                LimitPlanRow(name: c.name,
                             usual: store.averageSpent(c.id, before: month) ?? 0,
                             recommended: n.recommended[c.id],
                             dollars: Binding(get: { limits[c.id] ?? 0 }, set: { limits[c.id] = max(0, $0) }))
            }
        } header: {
            Text("Everyday limits")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let fixNote { Text(fixNote).foregroundStyle(Theme.accent) }
                Text(limitsFooter(n))
                    .foregroundStyle(n.total <= n.toSpend ? Color.secondary : Theme.over)
            }
        }
    }

    /// Recommended limits (cents), but never above a limit you already lowered.
    private func lowerOf(_ recommended: [String: Cents]) -> [String: Int] {
        recommended.mapValues { $0 / 100 }.merging(limits) { new, current in current > 0 ? min(new, current) : new }
    }

    /// Limits plus usual spending for categories without one.
    private func limitsTotal(_ limits: [String: Int]) -> Cents {
        store.everydayCategories.reduce(0) { sum, c in
            let dollars = limits[c.id] ?? 0
            return sum + (dollars > 0 ? dollars * 100 : (store.averageSpent(c.id, before: month) ?? 0))
        }
    }

    /// Closes the gap the least painful way: trim flexible limits further
    /// (up to 40%), then take from trips, then card paydown, and savings
    /// only as a last resort, since those come first in the plan.
    private func fixForMe(_ n: Numbers) {
        let before = limitsTotal(limits)
        let deeper = lowerOf(store.recommendedLimits(toSpend: n.toSpend, cap: 0.4))
        var gap = (limitsTotal(deeper) - n.toSpend + 999) / 1000 * 10
        var parts: [String] = []
        let trimmed = (before - limitsTotal(deeper)) / 100
        if trimmed > 0 { parts.append("trimmed limits \(Money.short(trimmed * 100))") }
        // Trips at $0 means each trip saves its own share, so keep $10.
        func take(_ value: inout Int, _ label: String, keep: Int = 0) {
            guard gap > 0, value > keep else { return }
            let amount = min(value - keep, gap)
            value -= amount; gap -= amount
            parts.append("\(Money.short(amount * 100)) less \(label)")
        }
        take(&trips, "for trips", keep: 10)
        take(&paydown, "on cards")
        take(&savings, "saved")
        withAnimation { limits = deeper }
        fixNote = parts.isEmpty ? nil : "Fixed: " + parts.joined(separator: ", ") + ". Tap Save to keep it."
    }

    private func limitsFooter(_ n: Numbers) -> String {
        let fits = n.total <= n.toSpend
        let head = fits ? "Limits add up to \(Money.short(n.total)) of \(Money.short(n.toSpend)) to spend."
                        : "Limits add up to \(Money.short(n.total)), \(Money.short(n.total - n.toSpend)) more than you have."
        return head + " Categories without a limit count their usual spending."
    }

    /// Limits still more than there is to spend: a small cut can't close
    /// it, so offer the trade-offs: give a little from a priority, or cut
    /// limits deeper than the usual 25% for this month.
    @ViewBuilder private func shortSection(_ n: Numbers) -> some View {
        if n.total > n.toSpend {
            let gap = (n.total - n.toSpend + 999) / 1000 * 10
            Section {
                if paydown >= gap {
                    Button("Pay \(Money.short(gap * 100)) less on cards") { withAnimation { paydown -= gap } }
                }
                if trips > gap {
                    Button("Put \(Money.short(gap * 100)) less toward trips") { withAnimation { trips -= gap } }
                }
                if savings >= gap {
                    Button("Save \(Money.short(gap * 100)) less") { withAnimation { savings -= gap } }
                }
                Button("Cut limits deeper this month") {
                    withAnimation { limits = lowerOf(store.recommendedLimits(toSpend: n.toSpend, cap: 0.5)) }
                }
                Button { fixForMe(n) } label: {
                    Label("Fix it for me", systemImage: "wand.and.stars")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            } header: {
                Text("\(Money.short(gap * 100)) short")
            } footer: {
                Text("Recommended limits trim at most 25% below usual, so they can't close this alone. Fix it for me trims flexible limits a bit more, then takes from trips, then card paydown, and savings last.")
            }
        }
    }

    /// Money the limits don't use: put it toward savings or cards.
    @ViewBuilder private func spareSection(_ n: Numbers) -> some View {
        if n.toSpend - n.total >= 1000 {
            let spare = (n.toSpend - n.total) / 1000 * 10
            Section {
                Button("Add \(Money.short(spare * 100)) to savings") { withAnimation { savings += spare } }
                    .fontWeight(.semibold)
                if n.owed > 0 {
                    Button("Add \(Money.short(spare * 100)) to card paydown") { withAnimation { paydown += spare } }
                }
            } header: {
                Text("Your limits leave \(Money.short(n.toSpend - n.total)) unassigned")
            } footer: {
                Text("Lowering a limit frees money up. Put it to work here, or it just sits in Left to spend.")
            }
        }
    }

    private func priorityFooter(owed: Cents, extra: Cents) -> String {
        var parts = ["Taken off before everyday spending."]
        if owed > 0 && paydown > 0 {
            parts.append("Cards: \(Money.short(owed)) owed, paid off in about \(Int((Double(owed) / Double(paydown * 100)).rounded(.up))) months.")
        }
        if trips == 0 && store.tripScheduleSetAside(in: month) > 0 {
            parts.append("Trips are saving \(Money.short(store.tripScheduleSetAside(in: month))) this month on their own; enter an amount to use a set trip fund instead.")
        }
        if extra > 0 { parts.append("The extra comes from Save money this month and ends with the month.") }
        return parts.joined(separator: " ")
    }

    private func load() {
        plannedIncome = (store.data.priorities?.plannedIncome ?? 0) / 100
        savings = (store.data.priorities?.savings ?? 0) / 100
        paydown = (store.data.priorities?.cardPaydown ?? 0) / 100
        trips = (store.data.tripFund?.monthly ?? 0) / 100
        limits = Dictionary(uniqueKeysWithValues: store.everydayCategories.map { ($0.id, ($0.limit ?? 0) / 100) })
    }

    private func save() {
        store.data.priorities = Priorities(savings: savings * 100, cardPaydown: paydown * 100,
                                           plannedIncome: plannedIncome > 0 ? plannedIncome * 100 : nil)
        if trips > 0 {
            let fund = store.data.tripFund
            store.data.tripFund = TripFund(monthly: trips * 100, start: fund?.start ?? month,
                                           startingBalance: fund?.startingBalance ?? 0)
        } else {
            store.data.tripFund = nil
        }
        for c in store.everydayCategories {
            let dollars = limits[c.id] ?? 0
            store.setLimit(c.id, dollars > 0 ? dollars * 100 : nil)
        }
    }

    private func amountRow(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0", value: value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(.headline).frame(maxWidth: 130)
        }
    }
}

private struct LimitPlanRow: View {
    let name: String
    let usual: Cents
    let recommended: Cents?
    @Binding var dollars: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(recommended.map { "usual \(Money.short(usual)) → \(Money.short($0))" } ?? "usual \(Money.short(usual))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            TextField("No limit", value: $dollars, format: .currency(code: "USD").precision(.fractionLength(0)))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
        }
    }
}

/// One paycheck in the pot: whose it is (tap to change), how often it
/// comes, and what it adds to a normal month.
private struct IncomeSourceRow: View {
    @Environment(BudgetStore.self) private var store
    let source: BudgetStore.IncomeSource

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).lineLimit(1)
                Menu {
                    ForEach(Owner.pickable) { owner in
                        Button(store.people.name(owner)) { store.setIncomeOwner(source.id, owner) }
                    }
                } label: {
                    Text(detail).font(.caption).foregroundStyle(source.stopped ? Theme.over : Theme.accent)
                }
            }
            Spacer()
            Text(source.stopped ? "not counted" : Money.short(source.monthly) + "/mo")
                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let who = source.owner == .unassigned ? "Whose is this?" : store.people.name(source.owner)
        if source.stopped { return who + " · stopped" }
        switch source.cadence {
        case .weekly: return who + " · weekly"
        case .biweekly: return who + " · every 2 weeks"
        case .other: return who
        }
    }
}
