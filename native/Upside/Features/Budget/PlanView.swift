import SwiftUI

/// The one place to plan the month: savings, card paydown and trips come
/// off the top, and everyday limits are recommended to fit what's left.
struct PlanView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var savings = 0
    @State private var paydown = 0
    @State private var trips = 0
    /// Everyday limits in whole dollars; 0 means no limit.
    @State private var limits: [String: Int] = [:]
    @State private var showExtra = false

    private var month: Date { store.currentMonth }

    var body: some View {
        let base = store.monthPlan(month)
        let extraSavings = store.plan.map { store.isInMonth($0.month, month) ? $0.goal : 0 } ?? 0
        let toSpend = base.income - base.bills - (savings * 100 + extraSavings) - paydown * 100 - trips * 100
        let recommended = store.recommendedLimits(toSpend: toSpend)
        let total = limits.values.reduce(0, +) * 100
        let owed = store.cardsOwed

        NavigationStack {
            Form {
                Section {
                    LabeledContent(base.incomeIsUsual ? "Income (usual)" : "Income", value: Money.short(base.income))
                    LabeledContent("Bills (expected)", value: "–" + Money.short(base.bills))
                } header: {
                    Text(month.formatted(.dateTime.month(.wide)))
                }

                Section {
                    amountRow("Savings each month", $savings)
                    amountRow("Card paydown each month", $paydown)
                    if owed > 0 {
                        HStack(spacing: 8) {
                            ForEach([6, 12], id: \.self) { months in
                                Button("Clear cards in \(months) mo") { paydown = (owed / months + 99) / 100 }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    amountRow("Trips each month", $trips)
                    LabeledContent("To spend") {
                        Text(Money.short(toSpend)).fontWeight(.bold)
                            .foregroundStyle(toSpend >= 0 ? Theme.accent : Theme.over)
                    }
                } header: {
                    Text("Pay yourself first")
                } footer: {
                    Text(priorityFooter(owed: owed, extra: extraSavings))
                }

                Section {
                    Button("Use recommended limits") {
                        withAnimation { limits = recommended.mapValues { $0 / 100 } }
                    }
                    .fontWeight(.semibold)
                    ForEach(store.everydayCategories) { c in
                        LimitPlanRow(name: c.name,
                                     usual: store.averageSpent(c.id, before: month) ?? 0,
                                     recommended: recommended[c.id],
                                     dollars: Binding(get: { limits[c.id] ?? 0 }, set: { limits[c.id] = max(0, $0) }))
                    }
                } header: {
                    Text("Everyday limits")
                } footer: {
                    Text(total <= toSpend
                         ? "Limits add up to \(Money.short(total)) of \(Money.short(toSpend)) to spend."
                         : "Limits add up to \(Money.short(total)), \(Money.short(total - toSpend)) more than you have. Use the recommended limits or lower some.")
                        .foregroundStyle(total <= toSpend ? Color.secondary : Theme.over)
                }

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

    private func priorityFooter(owed: Cents, extra: Cents) -> String {
        var parts = ["Taken off before everyday spending."]
        if owed > 0 && paydown > 0 {
            parts.append("Cards: \(Money.short(owed)) owed, paid off in about \(Int((Double(owed) / Double(paydown * 100)).rounded(.up))) months.")
        }
        if store.data.tripFund == nil && trips == 0 && store.tripSetAside(in: month) > 0 {
            parts.append("Trips are saving \(Money.short(store.tripSetAside(in: month))) a month on their own; enter an amount to use a set trip fund instead.")
        }
        if extra > 0 { parts.append("Plus \(Money.short(extra)) extra savings this month.") }
        return parts.joined(separator: " ")
    }

    private func load() {
        savings = (store.data.priorities?.savings ?? 0) / 100
        paydown = (store.data.priorities?.cardPaydown ?? 0) / 100
        trips = (store.data.tripFund?.monthly ?? 0) / 100
        limits = Dictionary(uniqueKeysWithValues: store.everydayCategories.map { ($0.id, ($0.limit ?? 0) / 100) })
    }

    private func save() {
        store.data.priorities = Priorities(savings: savings * 100, cardPaydown: paydown * 100)
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
