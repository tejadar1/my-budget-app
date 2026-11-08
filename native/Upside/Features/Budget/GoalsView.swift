import SwiftUI

/// Goals on Budget: each with its progress and what it takes a month.
struct GoalsSection: View {
    @Environment(BudgetStore.self) private var store
    @State private var editing: Goal?
    @State private var adding = false

    var body: some View {
        SectionTitle(text: "Goals", trailing: store.goals.isEmpty ? nil : "\(Money.short(store.goalsSetAside(in: store.currentMonth))) a month")
        ForEach(store.goals) { goal in
            Button { editing = goal } label: { GoalCard(goal: goal) }
                .buttonStyle(.plain)
                .contextMenu {
                    if goal.accountId == nil {
                        Button("Add \(Money.short(store.goalMonthly(goal)))") {
                            withAnimation { store.addToGoal(goal.id, store.goalMonthly(goal)) }
                        }
                    }
                    if goal.kind == .bill {
                        Button("Bill paid, start over") { withAnimation { store.goalUsed(goal.id) } }
                    }
                    Button("Delete goal", role: .destructive) { withAnimation { store.deleteGoal(goal.id) } }
                }
        }
        Button { adding = true } label: {
            Label("Add a goal", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .sheet(isPresented: $adding) { GoalEditor(goal: nil) }
        .sheet(item: $editing) { GoalEditor(goal: $0) }
    }
}

private struct GoalCard: View {
    @Environment(BudgetStore.self) private var store
    let goal: Goal

    var body: some View {
        let saved = store.goalSaved(goal)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: goal.kind.symbol).foregroundStyle(Theme.accent)
                Text(goal.name).font(.headline)
                Spacer()
                Text("\(Money.short(saved)) of \(Money.short(goal.target))")
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            SplitBar(fraction: goal.target > 0 ? Double(saved) / Double(goal.target) : 0, fill: Theme.accent, height: 6)
            Text(detail(saved)).font(.footnote).foregroundStyle(.secondary)
        }
        .card()
    }

    private func detail(_ saved: Cents) -> String {
        var parts: [String] = []
        let monthly = store.goalMonthly(goal)
        if saved >= goal.target {
            parts.append("Fully funded")
        } else if monthly > 0 {
            parts.append("\(Money.short(monthly)) a month")
        }
        if let due = goal.due { parts.append("by \(due.formatted(.dateTime.month(.abbreviated).year()))") }
        if goal.kind == .emergency, let months = store.monthsCovered(goal) {
            parts.append(String(format: "covers %.1f months of essentials", months))
        }
        return parts.joined(separator: " · ")
    }
}

/// Add or change a goal.
struct GoalEditor: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: Goal?

    @State private var kind: Goal.Kind = .emergency
    @State private var name = ""
    @State private var target = 0
    @State private var months = 6
    @State private var saved = 0
    @State private var accountId: String? = nil
    @State private var hasDate = false
    @State private var due = Date()
    @State private var repeats = 12
    @State private var monthly = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(Goal.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Name", text: $name, prompt: Text(placeholder))
                }
                Section {
                    if kind == .emergency {
                        Picker("Months of essentials", selection: $months) {
                            ForEach([3, 6, 9, 12], id: \.self) { Text("\($0) months").tag($0) }
                        }
                        LabeledContent("Target", value: Money.short(emergencyTarget))
                    } else {
                        amountRow("Amount", $target)
                    }
                    Picker("Progress from", selection: $accountId) {
                        Text("What I enter").tag(String?.none)
                        ForEach(store.visibleAccounts.filter { $0.kind == .savings || $0.kind == .investment }) { a in
                            Text(a.fullName).tag(Optional(a.id))
                        }
                    }
                    if accountId == nil { amountRow("Saved so far", $saved) }
                } footer: {
                    if kind == .emergency {
                        Text("Essentials are your usual bills and everyday spending: \(Money.short(store.monthlyEssentials)) a month.")
                    }
                }
                Section {
                    if kind != .emergency {
                        Toggle("Needed by a date", isOn: $hasDate.animation())
                        if hasDate {
                            DatePicker("Date", selection: $due, in: Date()..., displayedComponents: .date)
                            if kind == .bill {
                                Picker("Comes back", selection: $repeats) {
                                    Text("Every 3 months").tag(3)
                                    Text("Every year").tag(12)
                                    Text("Just once").tag(0)
                                }
                            }
                        }
                    }
                    if kind == .emergency || !hasDate { amountRow("Each month", $monthly) }
                    LabeledContent("Sets aside", value: Money.short(store.goalMonthly(draft)) + " a month")
                } footer: {
                    Text("Taken off the top in your plan, like savings and trips.")
                }
                if let goal {
                    Section {
                        Button("Delete goal", role: .destructive) { store.deleteGoal(goal.id); dismiss() }
                    }
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveGoal(draft); dismiss() }
                        .disabled(draft.target <= 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var placeholder: String {
        switch kind {
        case .emergency: return "Emergency fund"
        case .bill: return "Car insurance"
        case .purchase: return "Kitchen renovation"
        }
    }

    private var emergencyTarget: Cents { store.monthlyEssentials * months / 100 * 100 }

    private var draft: Goal {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Goal(id: goal?.id ?? UUID().uuidString,
                    name: trimmed.isEmpty ? placeholder : trimmed,
                    kind: kind,
                    target: kind == .emergency ? emergencyTarget : target * 100,
                    saved: saved * 100,
                    accountId: accountId,
                    due: kind != .emergency && hasDate ? due : nil,
                    repeatsMonths: kind == .bill && hasDate && repeats > 0 ? repeats : nil,
                    monthly: kind == .emergency || !hasDate ? monthly * 100 : nil)
    }

    private func load() {
        guard let goal else { return }
        kind = goal.kind
        name = goal.name
        target = goal.target / 100
        saved = goal.saved / 100
        accountId = goal.accountId
        hasDate = goal.due != nil
        due = goal.due ?? Date()
        repeats = goal.repeatsMonths ?? 0
        monthly = (goal.monthly ?? 0) / 100
        if goal.kind == .emergency, store.monthlyEssentials > 0 {
            let exact = Double(goal.target) / Double(store.monthlyEssentials)
            months = [3, 6, 9, 12].min { abs(Double($0) - exact) < abs(Double($1) - exact) } ?? 6
        }
    }

    private func amountRow(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0", value: value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
        }
    }
}
