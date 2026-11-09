import SwiftUI

// MARK: - Month check-in

/// Last month's wrap-up, one decision per screen, each with the facts
/// written out first: what was planned, what happened, where the money is.
struct CheckInSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let openPlan: () -> Void
    /// How many decisions there were when the sheet opened, for "1 of 3".
    @State private var total = 0

    struct Choice: Identifiable {
        let title: String
        var note: String? = nil
        let action: () -> Void
        var id: String { title }
    }

    struct Step {
        let symbol: String
        let title: String
        let message: String
        let choices: [Choice]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let check = store.monthCheckIn() {
                    let all = steps(check)
                    if let step = all.first { stepView(step, number: max(1, total - all.count + 1)) }
                } else {
                    done
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.monthCheckIn() == nil ? "Done" : "Later") { dismiss() }
                }
            }
        }
        .onAppear { total = store.monthCheckIn().map { steps($0).count } ?? 0 }
    }

    private var lastMonth: Date { store.month(-1, from: store.currentMonth) }
    private var lastName: String { lastMonth.formatted(.dateTime.month(.wide)) }
    private var thisName: String { store.currentMonth.formatted(.dateTime.month(.wide)) }
    private var title: String { "Wrap up \(lastName)" }

    private func stepView(_ step: Step, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if total > 1 {
                Text("\(number) of \(total)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            Image(systemName: step.symbol).font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text(step.title).font(.title2.bold())
            Text(step.message).font(.body).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            ForEach(Array(step.choices.enumerated()), id: \.element.id) { index, choice in
                VStack(spacing: 6) {
                    Button { withAnimation(.snappy) { choice.action() } } label: {
                        Text(choice.title).font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(index == 0 ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
                    .tint(Theme.accent)
                    if let note = choice.note {
                        Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
        }
        .id(step.title)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var done: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("\(lastName) is wrapped up").font(.title2.bold())
            Text("Nothing left to decide.").foregroundStyle(.secondary)
            Spacer()
            Button { dismiss() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private func steps(_ check: BudgetStore.CheckIn) -> [Step] {
        let plan = store.monthPlan(check.month)
        let m = check.month
        var steps: [Step] = []
        if check.savingsShort > 0 {
            let saved = max(0, store.savedAndInvested(in: m))
            let amount = Money.short(check.savingsShort)
            steps.append(Step(
                symbol: "banknote",
                title: "\(amount) didn’t make it to savings",
                message: "You planned to save \(Money.short(plan.savings)) in \(lastName), and \(Money.short(saved)) went in. The other \(amount) should still be in checking.",
                choices: [
                    Choice(title: "Save \(amount) in \(thisName)",
                           note: "Adds it to \(thisName)’s savings. Your spending money doesn’t change.") {
                        store.catchUp(.savings, check.savingsShort, for: m)
                    },
                    Choice(title: "Skip it", note: "It stays in checking.") { store.letGo(.savings, for: m) },
                ]))
        }
        if check.cardsShort > 0 {
            let paid = max(0, store.extraCardPayoff(in: m))
            let amount = Money.short(check.cardsShort)
            steps.append(Step(
                symbol: "creditcard",
                title: "\(amount) didn’t go to your cards",
                message: "You planned to pay down \(Money.short(plan.cardPaydown)) on cards in \(lastName), and \(Money.short(paid)) went toward them. The other \(amount) should still be in checking.",
                choices: [
                    Choice(title: "Pay \(amount) more in \(thisName)",
                           note: "Adds it to \(thisName)’s card paydown. Your spending money doesn’t change.") {
                        store.catchUp(.cards, check.cardsShort, for: m)
                    },
                    Choice(title: "Skip it", note: "It stays in checking.") { store.letGo(.cards, for: m) },
                ]))
        }
        if check.unspent > 0 {
            let amount = Money.short(check.unspent)
            var choices = [Choice(title: "Move it to savings", note: "Adds \(amount) to \(thisName)’s savings.") {
                store.useUnspent(check.unspent, for: m, as: .savings)
            }]
            if store.cardsOwed > 0 {
                choices.append(Choice(title: "Put it toward cards") { store.useUnspent(check.unspent, for: m, as: .cards) })
            }
            choices.append(Choice(title: "Leave it in checking") { store.useUnspent(check.unspent, for: m, as: .keep) })
            steps.append(Step(
                symbol: "sparkles",
                title: "\(amount) left over from \(lastName)",
                message: "You didn’t spend all of \(lastName)’s spending money. Give the \(amount) a job so it doesn’t just sit there.",
                choices: choices))
        }
        if check.overspent > 0 {
            let amount = Money.short(check.overspent)
            steps.append(Step(
                symbol: "exclamationmark.circle",
                title: "\(lastName) went \(amount) over",
                message: "You spent \(amount) more than \(lastName)’s plan allowed. It came out of checking, or money you meant to save.",
                choices: [
                    Choice(title: "Got it") { store.letGo(.overspent, for: m) },
                    Choice(title: "Change the plan", note: "If the plan was too tight, give spending more room.") {
                        store.letGo(.overspent, for: m)
                        openPlan()
                    },
                ]))
        }
        return steps
    }
}

/// Lets one button pick between two built-in styles.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Cover

/// One category went over: move room from another for this month only.
struct CoverSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryId: String
    let month: Date
    let openPlan: () -> Void

    var body: some View {
        let category = store.category(categoryId)
        let name = category?.name ?? "This category"
        let overrun = store.overruns(in: month).first { $0.id == categoryId }
        let over = overrun?.over ?? 0
        // Whole dollars, so the category ends at $0 left, not -$0.40.
        let amount = (over + 99) / 100 * 100
        let allowed = category.flatMap { store.limit($0, in: month) }
        let sources = store.coverSources(for: categoryId, in: month).filter { $0.room >= amount }
        let monthName = month.formatted(.dateTime.month(.wide))

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        CategoryIcon(categoryId: categoryId, size: 40)
                        Text(amount > 0 ? "\(name) is \(Money.short(over)) over" : "\(name) is covered")
                            .font(.title2.bold())
                        Text(amount == 0 ? "Nothing to move."
                             : allowed.map { "It has a \(Money.short($0)) limit this month. Move \(Money.short(amount)) from another category so the month still adds up." }
                             ?? "It went past what you usually spend. Move \(Money.short(amount)) from another category so the month still adds up.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if amount > 0 {
                    if sources.isEmpty {
                        Section {
                            Button("Change the plan", action: openPlan)
                        } footer: {
                            Text("No category has \(Money.short(amount)) to spare.")
                        }
                    } else {
                        Section {
                            ForEach(sources) { source in
                                Button {
                                    withAnimation { store.cover(categoryId, amount: amount, from: source.id, in: month) }
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        if source.id == BudgetStore.unassigned {
                                            SymbolIcon(symbol: "tray.fill", color: .gray)
                                        } else {
                                            CategoryIcon(categoryId: source.id, size: 30)
                                        }
                                        Text(source.name).foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(Money.short(source.room)) left").foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                                .tint(.primary)
                            }
                        } header: {
                            Text("Take \(Money.short(amount)) from")
                        } footer: {
                            Text("Rounded up to the dollar, for \(monthName) only. Next month goes back to your usual limits.")
                        }
                    }
                }
            }
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
        }
    }
}

// MARK: - Bank

/// Why numbers may be missing and how to fix the connection.
struct BankSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { BankHealthCard().padding() }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Bank sync")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
