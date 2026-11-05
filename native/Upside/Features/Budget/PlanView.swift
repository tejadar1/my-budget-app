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
    @State private var useUsual = true
    /// Extra savings just this month, in dollars.
    @State private var extra = 0
    /// What "Fix it for me" did, shown until the next change.
    @State private var fixNote: String?

    private var month: Date { store.currentMonth }

    /// Everything the screen shows, worked out once per redraw.
    private struct Numbers {
        var base: MonthPlan
        var usualIncome: Cents
        var income: Cents
        var extraSavings: Cents
        var tripCost: Cents
        var toSpend: Cents
        var recommended: [String: Cents]
        /// Limits plus usual spending for categories without one.
        var total: Cents
        var owed: Cents
    }

    private func numbers() -> Numbers {
        let base = store.monthPlan(month)
        let usualIncome = store.averageIncome(before: month) ?? 0
        let planned = useUsual || plannedIncome == 0 ? nil : plannedIncome * 100
        let income = max(BudgetStore.incomeToPlanOn(planned: planned, usual: usualIncome), base.incomeReceived)
        let extraSavings = extra * 100
        // $0 for trips means each trip saves its own share.
        let tripCost = trips > 0 ? trips * 100 : store.tripScheduleSetAside(in: month)
        let toSpend = income - base.bills - (savings * 100 + extraSavings) - paydown * 100 - tripCost
        let total = limitsTotal(limits)
        return Numbers(base: base, usualIncome: usualIncome, income: income, extraSavings: extraSavings,
                       tripCost: tripCost, toSpend: toSpend,
                       recommended: store.recommendedLimits(toSpend: toSpend), total: total, owed: store.cardsOwed)
    }

    var body: some View {
        let n = numbers()
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    PlanSplit(parts: [
                        .init(name: "Bills", amount: n.base.bills, color: .gray),
                        .init(name: "Savings", amount: savings * 100 + n.extraSavings, color: Theme.accent),
                        .init(name: "Cards", amount: paydown * 100, color: .orange),
                        .init(name: "Trips", amount: n.tripCost, color: .cyan),
                        .init(name: "To spend", amount: n.toSpend, color: .blue),
                    ], income: n.income)
                }
                incomeSection(n)
                prioritiesSection(n).id("priorities")
                limitsSection(n)
                shortSection(n)
                spareSection(n)
            }
            .onAppear {
                // `-planScroll` opens at the sliders (used for screenshots).
                guard ProcessInfo.processInfo.arguments.contains("-planScroll") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("priorities", anchor: .top) }
            }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .onAppear(perform: load)
        }
    }

    private func incomeSection(_ n: Numbers) -> some View {
        Section {
            Toggle(isOn: $useUsual.animation()) {
                LabeledContent("Use my usual income", value: Money.short(n.usualIncome))
            }
            if !useUsual {
                amountRow("Income to plan for", $plannedIncome)
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
        guard !useUsual, planned > 0 else {
            return "Your usual is the paychecks above, added together. \(Money.short(n.base.incomeReceived)) in so far."
        }
        if n.usualIncome > 0 && planned > n.usualIncome {
            return "\(Money.short(planned - n.usualIncome)) above your usual. \(Money.short(n.base.incomeReceived)) in so far."
        }
        return "\(Money.short(n.base.incomeReceived)) in so far. Any extra counts when it arrives."
    }

    private func prioritiesSection(_ n: Numbers) -> some View {
        // Sliders reach as far as income after bills; cards stop at what's owed.
        let room = max(0, (n.income - n.base.bills) / 100)
        let owedDollars = (n.owed + 99) / 100
        return Section {
            SliderRow(label: "Savings each month", dollars: $savings, maxDollars: max(savings, room),
                      tint: Theme.accent, note: savings > 0 ? "\(Money.short(savings * 1200)) a year" : "Pay yourself first.")
            amountRow("Extra just this month", $extra)
            SliderRow(label: "Card paydown", dollars: $paydown,
                      maxDollars: max(paydown, n.owed > 0 ? min(room, owedDollars) : room),
                      tint: .orange, note: cardsNote(n.owed))
            SliderRow(label: "Trips each month", dollars: $trips, maxDollars: max(trips, room),
                      tint: .cyan, note: tripsNote)
            LabeledContent("To spend") {
                Text(Money.short(n.toSpend)).fontWeight(.bold)
                    .foregroundStyle(n.toSpend >= 0 ? Theme.accent : Theme.over)
            }
        } header: {
            Text("Pay yourself first")
        } footer: {
            if n.extraSavings > 0 { Text("The extra ends with the month.") }
        }
    }

    private func cardsNote(_ owed: Cents) -> String {
        guard owed > 0 else { return "No card balance." }
        guard paydown > 0 else { return "\(Money.short(owed)) owed. Balance won't go down." }
        let months = Int((Double(owed) / Double(paydown * 100)).rounded(.up))
        return "\(Money.short(owed)) owed · clear in about \(months) month\(months == 1 ? "" : "s")"
    }

    private var tripsNote: String {
        if trips > 0 { return "\(Money.short(trips * 1200)) a year for trips" }
        let own = store.tripScheduleSetAside(in: month)
        return own > 0 ? "At $0, each trip saves its share: \(Money.short(own)) this month." : "Nothing set aside for trips."
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
        return head + " No limit counts as usual."
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
                Text("Fix it for me trims limits, then trips, then cards, and savings last.")
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
                Text("Put money your limits don't use to work.")
            }
        }
    }

    private func load() {
        plannedIncome = (store.data.priorities?.plannedIncome ?? 0) / 100
        useUsual = store.data.priorities?.plannedIncome == nil
        extra = (store.plan.map { store.isInMonth($0.month, month) ? $0.goal : 0 } ?? 0) / 100
        savings = (store.data.priorities?.savings ?? 0) / 100
        paydown = (store.data.priorities?.cardPaydown ?? 0) / 100
        trips = (store.data.tripFund?.monthly ?? 0) / 100
        limits = Dictionary(uniqueKeysWithValues: store.everydayCategories.map { ($0.id, ($0.limit ?? 0) / 100) })
    }

    private func save() {
        store.data.priorities = Priorities(savings: savings * 100, cardPaydown: paydown * 100,
                                           plannedIncome: !useUsual && plannedIncome > 0 ? plannedIncome * 100 : nil)
        // The one-month extra; any lowered limits from that month are kept.
        if extra > 0 {
            let kept = store.plan.flatMap { store.isInMonth($0.month, month) ? $0.limits : nil } ?? [:]
            store.data.plan = SavingsPlan(month: month, goal: extra * 100, limits: kept)
        } else if let kept = store.plan, !kept.limits.isEmpty {
            // Covered overspending stays for the month even with no extra.
            store.data.plan = SavingsPlan(month: month, goal: 0, limits: kept.limits)
        } else {
            store.data.plan = nil
        }
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
                Text(Merchant.clean(source.name)).lineLimit(1)
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
        if source.estimated { return who + " · estimated from recent pay" }
        switch source.cadence {
        case .weekly: return who + " · weekly"
        case .biweekly: return who + " · every 2 weeks"
        case .other: return who
        }
    }
}

/// A plan amount you can drag or type, with what it means underneath.
private struct SliderRow: View {
    let label: String
    @Binding var dollars: Int
    let maxDollars: Int
    let tint: Color
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                TextField("$0", value: $dollars, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .font(.headline).frame(maxWidth: 130)
            }
            Slider(value: Binding(get: { Double(min(dollars, maxDollars)) },
                                  set: { dollars = Int($0.rounded()) }),
                   in: 0...Double(max(maxDollars, 25)), step: 25)
                .tint(tint)
                .accessibilityLabel(label)
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Where the month's income goes, as one bar: bills, savings, cards,
/// trips and what's left to spend. Dragging a slider moves the slices.
private struct PlanSplit: View {
    struct Part: Identifiable {
        var name: String
        var amount: Cents
        var color: Color
        var id: String { name }
    }
    let parts: [Part]
    let income: Cents

    var body: some View {
        let shown = parts.filter { $0.amount > 0 }
        let total = max(income, shown.reduce(0) { $0 + $1.amount }, 1)
        let over = shown.reduce(0) { $0 + $1.amount } - income
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Money.short(income)) a month").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(shown) { part in
                        Rectangle().fill(part.color)
                            .frame(width: max(2, geo.size.width * CGFloat(part.amount) / CGFloat(total) - 2))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .animation(.snappy, value: parts.map(\.amount))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      spacing: 6) {
                ForEach(parts.filter { $0.amount != 0 }) { part in
                    HStack(spacing: 6) {
                        Circle().fill(part.color).frame(width: 8, height: 8)
                        Text(part.name).foregroundStyle(.secondary)
                        Text(Money.short(part.amount)).monospacedDigit()
                            .foregroundStyle(part.amount < 0 ? Theme.over : .primary)
                    }
                    .font(.caption)
                }
            }
            if over > 0 {
                Text("\(Money.short(over)) more than your income").font(.caption.weight(.semibold)).foregroundStyle(Theme.over)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
