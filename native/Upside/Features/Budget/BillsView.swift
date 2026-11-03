import SwiftUI

/// Budget row: bills still to come this month.
struct BillsRow: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let bills = store.recurringCharges()
        let due = bills.filter { !$0.paidThisMonth }
        let flagged = bills.filter { $0.priceIncrease != nil || ($0.isNew && $0.isSubscription) }
        if !bills.isEmpty {
            NavigationLink(value: Route.bills) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(due.isEmpty ? "All bills paid this month"
                             : "\(Money.short(due.reduce(0) { $0 + $1.amount })) in bills still due")
                            .font(.headline)
                        Text(subtitle(due: due, flagged: flagged))
                            .font(.footnote)
                            .foregroundStyle(flagged.isEmpty ? Color.secondary : Theme.warning)
                            .lineLimit(1)
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

    private func subtitle(due: [Recurring], flagged: [Recurring]) -> String {
        if let up = flagged.first(where: { $0.priceIncrease != nil }) {
            return "\(up.name) went up \(Money.exact(up.priceIncrease ?? 0))"
        }
        if let new = flagged.first {
            return "New: \(new.name). Still using it?"
        }
        if let next = due.first, let date = next.dueDate {
            return "Next: \(next.name) on \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "Bills and subscriptions Upside found"
    }
}

/// Charges that repeat monthly: what's still due, what's paid, and what
/// subscriptions cost over a year.
struct BillsView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let all = store.recurringCharges()
        let due = all.filter { !$0.paidThisMonth }
        let paid = all.filter(\.paidThisMonth)
        let subscriptions = all.filter(\.isSubscription).sorted { $0.amount > $1.amount }
        let monthName = store.currentMonth.formatted(.dateTime.month(.wide))

        List {
            Section {
                let lines = store.billLines(store.currentMonth)
                let paidSoFar = lines.reduce(0) { $0 + $1.paid }
                VStack(alignment: .leading, spacing: 6) {
                    Text(Money.short(lines.reduce(0) { $0 + $1.stillToCome }))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                    Text("left to pay in \(monthName) · \(Money.short(paidSoFar)) paid so far")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            let lines = store.billLines(store.currentMonth)
            if !lines.isEmpty {
                Section {
                    ForEach(lines) { line in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.category.name)
                                Text(line.stillToCome > 0
                                     ? "paid \(Money.short(line.paid)) · usual \(Money.short(line.usual))"
                                     : "paid \(Money.short(line.paid))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(line.stillToCome > 0 ? "\(Money.short(line.stillToCome)) to come" : "done")
                                .monospacedDigit()
                                .foregroundStyle(line.stillToCome > 0 ? Color.primary : Theme.accent)
                        }
                    }
                } header: {
                    Text("Counted in your plan")
                } footer: {
                    Text("Each bill category counts at least its usual amount, so bills that haven't been paid yet are planned for. A bill in another category isn't counted; move it to the right category in Transactions.")
                }
            }
            if !due.isEmpty {
                Section("Still due") {
                    ForEach(due) { b in
                        BillRow(bill: b, when: b.dueDate.map { "Due \(day($0))" } ?? "").swipeActions { notButton(b) }
                    }
                }
            }
            if !paid.isEmpty {
                Section("Paid in \(monthName)") {
                    ForEach(paid) { b in
                        BillRow(bill: b, when: "Paid \(day(b.lastDate))").swipeActions { notButton(b) }
                    }
                }
            }
            if !subscriptions.isEmpty {
                Section {
                    ForEach(subscriptions) { s in
                        BillRow(bill: s, when: "\(Money.short(s.amount * 12)) a year").swipeActions { notButton(s) }
                    }
                } header: {
                    Text("Subscriptions")
                } footer: {
                    Text("\(Money.short(subscriptions.reduce(0) { $0 + $1.amount } * 12)) a year in total. Swipe left on anything that isn’t a subscription. Cancel the ones you don’t use with the company or in Settings › Apple Account › Subscriptions.")
                }
            }

            if let hidden = store.data.notRecurring, !hidden.isEmpty {
                Section {
                    ForEach(hidden, id: \.self) { key in
                        HStack {
                            Text(key.capitalized)
                            Spacer()
                            Button("Show again") { withAnimation { store.restoreRecurring(key) } }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Hidden")
                } footer: {
                    Text("Stores you said aren't bills or subscriptions.")
                }
            }

            if all.isEmpty {
                ContentUnavailableView("No bills found yet", systemImage: "calendar.badge.clock",
                                       description: Text("Upside finds charges that repeat each month once it has two months of history."))
            }
        }
        .navigationTitle("Bills & subscriptions")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Swipe: "Not a bill" / "Not a subscription".
    private func notButton(_ bill: Recurring) -> some View {
        Button(bill.isSubscription ? "Not a subscription" : "Not a bill", role: .destructive) {
            withAnimation { store.dismissRecurring(bill.id) }
        }
    }

    private func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct BillRow: View {
    @Environment(BudgetStore.self) private var store
    let bill: Recurring
    let when: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bill.name)
                Text([when, store.category(bill.categoryId)?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
                if let up = bill.priceIncrease, let before = bill.previous {
                    Label("Up \(Money.exact(up)) from \(Money.exact(before))", systemImage: "arrow.up.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning)
                } else if bill.isNew && bill.isSubscription {
                    Label("New since \(bill.firstDate.formatted(.dateTime.month(.wide))). Still using it?",
                          systemImage: "sparkle")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Text(Money.exact(bill.amount)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
