import SwiftUI

/// Pay yourself first: savings, card paydown and trips come off the top,
/// and everyday limits fit what's left.
struct PrioritiesView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var savings = 0
    @State private var paydown = 0
    @State private var showExtra = false
    @State private var fitted: String?

    var body: some View {
        let month = store.currentMonth
        let owed = store.cardsOwed
        NavigationStack {
            Form {
                Section {
                    amountRow("Savings each month", $savings)
                } header: {
                    Text("Savings")
                } footer: {
                    Text("Kept every month before everyday spending.")
                }

                Section {
                    amountRow("Card paydown each month", $paydown)
                    if owed > 0 {
                        HStack(spacing: 8) {
                            ForEach([6, 12], id: \.self) { months in
                                Button("Clear in \(months) mo: \(Money.short(owed / months))") {
                                    paydown = (owed / months + 99) / 100
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                } header: {
                    Text("Credit cards")
                } footer: {
                    Text(owed > 0
                         ? "You owe \(Money.short(owed)) on your cards." + (paydown > 0 ? " At \(Money.short(paydown * 100)) a month, that's paid off in about \(Int((Double(owed) / Double(paydown * 100)).rounded(.up))) months." : "")
                         : "No card balances right now.")
                }

                Section {
                    LabeledContent("Trips this month", value: Money.short(store.tripSetAside(in: month)))
                } footer: {
                    Text("From your trip fund or each trip's monthly share. Change it in Trips.")
                }

                Section {
                    let plan = preview(month)
                    LabeledContent("Income", value: Money.short(plan.income))
                    LabeledContent("Bills", value: "–" + Money.short(plan.bills))
                    LabeledContent("Savings, cards and trips", value: "–" + Money.short(plan.savings + plan.cardPaydown + plan.trips))
                    LabeledContent("To spend") {
                        Text(Money.short(plan.toSpend)).fontWeight(.semibold)
                            .foregroundStyle(plan.toSpend >= 0 ? Theme.accent : Theme.over)
                    }
                    Button("Save and fit my limits to this") {
                        save()
                        let left = store.setLimitsToPlan(month)
                        fitted = left == 0 ? "Your everyday limits now fit."
                            : "Limits trimmed as far as they go; still \(Money.short(left)) over. Lower a limit or a priority."
                    }
                    .fontWeight(.semibold)
                } header: {
                    Text("This month")
                } footer: {
                    Text(fitted ?? "Limits start from your usual, then shopping, dining and other flexible spending is trimmed until everything fits.")
                }

                Section {
                    Button("Save extra just this month…") { showExtra = true }
                }
            }
            .navigationTitle("Pay yourself first")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .sheet(isPresented: $showExtra) { SavingsPlanView() }
            .onAppear {
                savings = (store.data.priorities?.savings ?? 0) / 100
                paydown = (store.data.priorities?.cardPaydown ?? 0) / 100
            }
        }
    }

    private func preview(_ month: Date) -> MonthPlan {
        var plan = store.monthPlan(month)
        let extra = store.plan.map { store.isInMonth($0.month, month) ? $0.goal : 0 } ?? 0
        plan.savings = savings * 100 + extra
        plan.cardPaydown = paydown * 100
        return plan
    }

    private func save() {
        store.data.priorities = Priorities(savings: savings * 100, cardPaydown: paydown * 100)
    }

    private func amountRow(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0", value: value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(.title3.weight(.semibold)).frame(maxWidth: 140)
        }
    }
}
