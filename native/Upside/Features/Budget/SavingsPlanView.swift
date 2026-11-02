import SwiftUI

/// Pick how much to save this month; Upside suggests where it comes from
/// (flexible spending only) and you adjust or skip categories.
struct SavingsPlanView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var goal = 0
    /// New limits in whole dollars, by category id.
    @State private var limits: [String: Int] = [:]

    private var month: Date { store.currentMonth }

    /// Biggest cut first.
    private var categories: [Category] {
        func cut(_ c: Category) -> Int { store.baseline(c, before: month) / 100 - (limits[c.id] ?? 0) }
        return store.expenseCategories.filter { limits[$0.id] != nil }.sorted { cut($0) > cut($1) }
    }

    private var saved: Cents {
        store.savings(of: limits.mapValues { $0 * 100 }, in: month)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Save this month")
                        Spacer()
                        TextField("Amount", value: $goal, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    Button("Suggest where it comes from") { suggest() }
                        .disabled(goal <= 0)
                } footer: {
                    let lastLeft = store.leftOver(in: store.month(-1, from: month))
                    Text((store.income(in: store.month(-1, from: month)) > 0
                          ? (lastLeft >= 0 ? "Last month you had \(Money.short(lastLeft)) left over. "
                             : "Last month you spent \(Money.short(lastLeft)) more than came in. ")
                          : "")
                         + "Only flexible spending is cut, never bills. Next month goes back to your normal limits.")
                }

                if !limits.isEmpty {
                    Section {
                        ForEach(categories) { category in
                            PlanRow(category: category,
                                    usual: store.baseline(category, before: month),
                                    limit: Binding(get: { limits[category.id] ?? 0 },
                                                   set: { limits[category.id] = max(0, $0) }))
                        }
                    } header: {
                        Text("Where the \(Money.short(goal * 100)) comes from")
                    } footer: {
                        Text(saved >= goal * 100
                             ? "Saves \(Money.short(saved)), meeting your \(Money.short(goal * 100)) goal."
                             : "Saves \(Money.short(saved)) of \(Money.short(goal * 100)). Skip a category or lower more to reach it.")
                            .foregroundStyle(saved >= goal * 100 ? Theme.accent : Theme.warning)
                    }

                    Section {
                        Button {
                            store.data.plan = SavingsPlan(month: month, goal: goal * 100,
                                                          limits: limits.mapValues { $0 * 100 })
                            dismiss()
                        } label: {
                            Text("Save \(Money.short(saved)) in \(month.formatted(.dateTime.month(.wide)))")
                                .bold().frame(maxWidth: .infinity)
                        }
                    }
                }

                if store.plan != nil {
                    Section {
                        Button("End this month’s plan", role: .destructive) {
                            store.data.plan = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Save money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let plan = store.plan {
            goal = plan.goal / 100
            limits = plan.limits.mapValues { $0 / 100 }
        } else {
            // A starting point: 10% of what flexible categories usually get.
            let flexibleUsual = store.expenseCategories
                .filter { store.flexibility(of: $0) > 0 }
                .reduce(0) { $0 + store.baseline($1, before: month) }
            goal = max(50, Int((Double(flexibleUsual) * 0.10 / 100 / 10).rounded()) * 10)
            suggest()
        }
    }

    private func suggest() {
        limits = store.suggestedLimits(toSave: goal * 100, in: month).mapValues { $0 / 100 }
    }
}

private struct PlanRow: View {
    let category: Category
    let usual: Cents
    @Binding var limit: Int

    private var cut: Cents { max(0, usual - limit * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.name).font(.headline)
                Spacer()
                Text(cut > 0 ? "−\(Money.short(cut))" : "No cut")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(cut > 0 ? Theme.accent : Color.secondary)
            }
            // Usual vs new limit, with the part being saved highlighted.
            GeometryReader { geo in
                let keep = usual > 0 ? min(1, Double(limit * 100) / Double(usual)) : 1
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.accent)
                    Capsule().fill(Color.secondary.opacity(0.3)).frame(width: geo.size.width * keep)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack {
                Text(limit > 0 ? "Usual \(Money.short(usual)) → \(Money.short(limit * 100))"
                               : "Usual \(Money.short(usual)) → skip this month")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if limit > 0 {
                    Stepper("Limit", value: $limit, in: 0...max(limit, usual / 100), step: 10)
                        .labelsHidden()
                }
            }
            Toggle("Skip this month", isOn: Binding(
                get: { limit == 0 },
                set: { limit = $0 ? 0 : max(10, usual / 100 / 2 / 10 * 10) }))
                .font(.footnote)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(category.name): saves \(Money.short(cut)), limit \(Money.short(limit * 100)) of usual \(Money.short(usual))")
    }
}

/// Budget row: this month's savings plan, or an offer to make one.
struct SavingsRow: View {
    @Environment(BudgetStore.self) private var store
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "banknote.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    if let plan = store.plan {
                        let saving = store.savings(of: plan.limits, in: store.currentMonth)
                        Text("Saving \(Money.short(saving)) this month").font(.headline)
                        Text(planSummary(plan)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Save money this month").font(.headline)
                        Text("Upside suggests what to trim, like shopping and dining.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func planSummary(_ plan: SavingsPlan) -> String {
        let skipped = plan.limits.filter { $0.value == 0 }.compactMap { store.category($0.key)?.name }
        let trimmed = plan.limits.filter { $0.value > 0 }.count
        var parts: [String] = []
        if !skipped.isEmpty { parts.append("skipping \(skipped.sorted().joined(separator: ", "))") }
        if trimmed > 0 { parts.append("\(trimmed) categor\(trimmed == 1 ? "y" : "ies") trimmed") }
        return parts.joined(separator: " · ").capitalizedFirst
    }
}

/// Red when card fees or interest show up this month.
struct FeesRow: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let fees = store.expenseCategories.filter(\.aimsForZero)
        let total = fees.reduce(0) { $0 + store.spent($1.id, in: month) }
        if total > 0, let first = fees.first {
            NavigationLink(value: Route.category(first.id, month)) {
                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.over, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Money.short(total)) in card fees & interest").font(.headline)
                        Text("Aim for $0: pay cards in full and on time.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
