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
        var total = 0
        for c in store.everydayCategories {
            let dollars = limits[c.id] ?? 0
            total += dollars > 0 ? dollars * 100 : (store.averageSpent(c.id, before: month) ?? 0)
        }
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
            return "Leave at $0 to plan around your usual income. Your usual counts a normal month; a third paycheck is a bonus when it lands."
        }
        if n.usualIncome > 0 && planned > n.usualIncome {
            return "Planning on your usual \(Money.short(n.usualIncome)) until more arrives. The other \(Money.short(planned - n.usualIncome)) counts once it's in. \(Money.short(n.base.incomeReceived)) has come in so far."
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
            Text(limitsFooter(n))
                .foregroundStyle(n.total <= n.toSpend ? Color.secondary : Theme.over)
        }
    }

    private func limitsFooter(_ n: Numbers) -> String {
        let fits = n.total <= n.toSpend
        let head = fits ? "Limits add up to \(Money.short(n.total)) of \(Money.short(n.toSpend)) to spend."
                        : "Limits add up to \(Money.short(n.total)), \(Money.short(n.total - n.toSpend)) more than you have. Use the recommended limits or lower some."
        return head + " Categories without a limit count their usual spending."
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
