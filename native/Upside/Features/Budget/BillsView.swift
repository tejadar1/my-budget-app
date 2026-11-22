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
                             : "\(Money.short(due.reduce(0) { $0 + $1.amount })) in bills left to pay")
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
    /// The bill whose Stop was tapped, for the when-does-it-stop question.
    @State private var stopping: Recurring?

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
                        .heroNumber(40)
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
                            Text(line.stillToCome > 0 ? "\(Money.short(line.stillToCome)) left" : "paid")
                                .monospacedDigit()
                                .foregroundStyle(line.stillToCome > 0 ? Color.primary : Theme.accent)
                        }
                    }
                } header: {
                    Text("Counted in your plan")
                } footer: {
                    Text("Each bill counts at least its usual, so unpaid bills are planned for.")
                }
            }
            if !due.isEmpty {
                Section("Still due") {
                    ForEach(due) { b in
                        BillRow(bill: b, when: b.dueDate.map { "Due \(day($0))" } ?? "").swipeActions { stopButton(b); notButton(b) }
                            .contextMenu { stopButton(b); notButton(b) }
                    }
                }
            }
            if !paid.isEmpty {
                Section("Paid in \(monthName)") {
                    ForEach(paid) { b in
                        BillRow(bill: b, when: "Paid \(day(b.lastDate))").swipeActions { stopButton(b); notButton(b) }
                            .contextMenu { stopButton(b); notButton(b) }
                    }
                }
            }
            if !subscriptions.isEmpty {
                Section {
                    ForEach(subscriptions) { s in
                        BillRow(bill: s, when: "\(Money.short(s.amount * 12)) a year").swipeActions { stopButton(s); notButton(s) }
                            .contextMenu { stopButton(s); notButton(s) }
                    }
                } header: {
                    Text("Subscriptions")
                } footer: {
                    Text("\(Money.short(subscriptions.reduce(0) { $0 + $1.amount } * 12)) a year. Swipe left to stop one you cancelled.")
                }
            }

            let stopped = store.stoppedBills.filter { $0.from >= store.month(-6, from: store.currentMonth) }
            if !stopped.isEmpty {
                Section {
                    ForEach(stopped) { stop in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Merchant.clean(stop.name))
                                Text("\(Money.exact(stop.amount)) · \(stop.from > store.currentMonth ? "stops" : "stopped") in \(stop.from.formatted(.dateTime.month(.wide)))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restart") {
                                withAnimation { store.restartBill(stop.id) }
                                Haptics.tap()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Stopped")
                } footer: {
                    Text("If one charges again, it comes back on its own.")
                }
            }

            if let hidden = store.data.notRecurring, !hidden.isEmpty {
                Section {
                    DisclosureGroup("Not bills (\(hidden.count))") {
                        ForEach(hidden, id: \.self) { key in
                            HStack {
                                Text(key.capitalized)
                                Spacer()
                                Button("Show again") { withAnimation { store.restoreRecurring(key) } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                } footer: {
                    Text("Their purchases count in everyday categories.")
                }
            }

            if all.isEmpty {
                ContentUnavailableView("No bills found yet", systemImage: "calendar.badge.clock",
                                       description: Text("Upside finds charges that repeat each month once it has two months of history."))
            }
        }
        .navigationTitle("Bills & subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(stopping.map { "Stop \(Merchant.clean($0.name))?" } ?? "",
                            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                            titleVisibility: .visible, presenting: stopping) { bill in
            if bill.paidThisMonth {
                Button("Stop") { stop(bill, afterThisMonth: true) }
            } else {
                Button("It already stopped") { stop(bill, afterThisMonth: false) }
                Button("After this month’s payment") { stop(bill, afterThisMonth: true) }
            }
        } message: { bill in
            Text("\(Money.exact(bill.amount)) a month goes back to spending money once it stops.")
        }
    }

    private func stop(_ bill: Recurring, afterThisMonth: Bool) {
        withAnimation { store.stopBill(bill, afterThisMonth: afterThisMonth) }
        Haptics.success()
        stopping = nil
    }

    /// Swipe: "Stop", for a bill that's ending (cancelled, paid off).
    private func stopButton(_ bill: Recurring) -> some View {
        Button { stopping = bill } label: { Label("Stop", systemImage: "stop.circle") }
            .tint(.orange)
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
                Text(Merchant.clean(bill.name))
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
