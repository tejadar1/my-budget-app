import SwiftUI

/// "Start December": three steps in the first days of a month, each
/// opening the screen that already does it, with what's left at a glance.
struct MonthStartSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Opens another sheet (wrap-up, Plan); this one comes back after.
    let open: (BudgetSheet) -> Void

    var body: some View {
        let month = store.currentMonth
        let name = month.formatted(.dateTime.month(.wide))
        let lastName = store.month(-1, from: month).formatted(.dateTime.month(.wide))
        let start = store.monthStart()
        let plan = store.monthPlan(month)
        NavigationStack {
            List {
                Section {
                    Text("Three steps to set up \(name). Each one opens where it's done; you come back here after.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                step(1, "Wrap up \(lastName)", done: (start?.wrapUpLeft ?? 0) == 0,
                     detail: (start?.wrapUpLeft ?? 0) == 0
                        ? "Nothing left to decide."
                        : "\(start!.wrapUpLeft) thing\(start!.wrapUpLeft == 1 ? "" : "s") to decide: what was left, saved or paid.") {
                    if (start?.wrapUpLeft ?? 0) > 0 {
                        Button("Wrap up") { open(.checkIn) }.buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                }

                step(2, "Income for \(name)", done: start?.incomeChecked ?? true,
                     detail: plan.incomePlanned.map { "You plan on \(Money.short($0)) a month." }
                        ?? "Your usual: \(Money.short(plan.income)) a month, from your paychecks.") {
                    if !(start?.incomeChecked ?? true) {
                        HStack {
                            Button("Looks right") { Haptics.tap(); withAnimation { store.confirmMonthIncome() } }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                            Button("Change") { open(.planning) }.buttonStyle(.bordered)
                        }
                    }
                }

                step(3, "Your plan", done: start?.planSet ?? true, detail: planDetail(plan)) {
                    if !(start?.planSet ?? true) {
                        HStack {
                            Button("Looks right") { Haptics.success(); withAnimation { store.confirmMonthPlan() } }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                                .disabled(plan.limitsOverBy > 0)
                            Button("Adjust") { open(.planning) }.buttonStyle(.bordered)
                        }
                    }
                }

                Section {
                    Button {
                        if start == nil || start!.allDone { dismiss() } else { store.finishMonthStart(); dismiss() }
                        Haptics.success()
                    } label: {
                        Text(start == nil ? "All set for \(name)" : "Done for now")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.accent)
                    .listRowBackground(Color.clear)
                } footer: {
                    if start != nil {
                        Text("Anything left is still in Plan, any time this month.")
                    }
                }
            }
            .navigationTitle("Start \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } } }
        }
    }

    private func planDetail(_ plan: MonthPlan) -> String {
        let parts = [("bills", plan.bills), ("savings", plan.savings), ("cards", plan.cardPaydown),
                     ("trips", plan.trips), ("goals", plan.goals)]
            .filter { $0.1 > 0 }.map { "\($0.0) \(Money.short($0.1))" }
        let first = parts.isEmpty ? "" : parts.joined(separator: " · ").capitalizedFirst + ". "
        if plan.limitsOverBy > 0 {
            return first + "Limits are \(Money.short(plan.limitsOverBy)) more than the \(Money.short(plan.toSpend)) to spend: adjust them first."
        }
        return first + "\(Money.short(plan.toSpend)) to spend; limits use \(Money.short(plan.everydayLimits))."
    }

    @ViewBuilder
    private func step<Actions: View>(_ n: Int, _ title: String, done: Bool, detail: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                    .font(.title2).foregroundStyle(done ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    actions()
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
