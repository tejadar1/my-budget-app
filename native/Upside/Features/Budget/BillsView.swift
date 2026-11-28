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
    /// The bill whose last month is being picked.
    @State private var picking: Recurring?
    /// The bills category tapped, to say what's held and offer All paid.
    @State private var held: BudgetStore.BillLine?

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
                        let row = HStack {
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
                        if line.stillToCome > 0 {
                            Button { held = line } label: { row.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .swipeActions { allPaidButton(line) }
                                .contextMenu { allPaidButton(line) }
                        } else {
                            row
                        }
                    }
                } header: {
                    Text("Counted in your plan")
                } footer: {
                    Text("Bills still to come are held from your spending money. All paid already? Swipe left: All paid.")
                }
            }
            if !due.isEmpty {
                Section {
                    ForEach(due) { b in
                        BillRow(bill: b, when: b.dueDate.map { "Due \(day($0))" } ?? "").swipeActions { stopButton(b); notButton(b) }
                            .swipeActions(edge: .leading) { paidButton(b) }
                            .contextMenu { paidButton(b); stopButton(b); notButton(b) }
                    }
                } header: {
                    Text("Still due")
                } footer: {
                    Text("Paid already? Upside looks for it under any name the bank uses. If it went through an account Upside can't see, swipe right: Paid.")
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
                Button("After this month") { stop(bill, afterThisMonth: true) }
            } else {
                Button("It already stopped") { stop(bill, afterThisMonth: false) }
                Button("After this month’s payment") { stop(bill, afterThisMonth: true) }
            }
            Button("Pick the last month…") {
                // After the dialog has closed: a sheet asked for while one closes can be dropped.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { picking = bill }
            }
        } message: { bill in
            Text("\(Money.exact(bill.amount)) a month goes back to spending money once it stops.")
        }
        .sheet(item: $picking) { bill in
            LastPaymentSheet(bill: bill)
        }
        .confirmationDialog(held.map { "\($0.category.name): \(Money.short($0.stillToCome)) held" } ?? "",
                            isPresented: Binding(get: { held != nil }, set: { if !$0 { held = nil } }),
                            titleVisibility: .visible, presenting: held) { line in
            Button("All paid for \(monthName)") {
                withAnimation { store.markBillCategoryDone(line.category.id) }
                Haptics.success()
            }
        } message: { line in
            Text(heldReason(line))
        }
    }

    private func stop(_ bill: Recurring, afterThisMonth: Bool) {
        withAnimation { store.stopBill(bill, afterThisMonth: afterThisMonth) }
        Haptics.success()
        stopping = nil
    }

    /// Why a category still holds money: the bills still to come, or a
    /// usual its known bills don't explain.
    private func heldReason(_ line: BudgetStore.BillLine) -> String {
        let bills = store.recurringCharges().filter { $0.categoryId == line.category.id }
        let due = bills.filter { !$0.paidThisMonth }.map { Merchant.clean($0.name) }
        let paid = bills.filter(\.paidThisMonth).map { Merchant.clean($0.name) }
        if !due.isEmpty {
            return "Still to come: \(due.joined(separator: ", ")). If you've paid already, tap All paid."
        }
        let paidText = paid.isEmpty ? "" : "\(paid.joined(separator: " and ")) \(paid.count == 1 ? "is" : "are") paid. "
        return paidText + "Held because this usually comes to \(Money.short(line.usual)) a month. Nothing else coming? Tap All paid."
    }

    /// Swipe on a category: everything this month is paid, stop holding money.
    private func allPaidButton(_ line: BudgetStore.BillLine) -> some View {
        Button {
            withAnimation { store.markBillCategoryDone(line.category.id) }
            Haptics.success()
        } label: {
            Label("All paid", systemImage: "checkmark.circle")
        }
        .tint(Theme.accent)
    }

    /// Swipe right: "Paid", for a bill paid somewhere Upside can't see.
    private func paidButton(_ bill: Recurring) -> some View {
        Button { withAnimation { store.markBillPaid(bill.id) }; Haptics.success() } label: {
            Label("Paid", systemImage: "checkmark.circle")
        }
        .tint(Theme.accent)
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
                if let last = store.lastPayment(bill.id) {
                    Label("Last payment in \(last.formatted(.dateTime.month(.wide).year()))", systemImage: "stop.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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

/// Stop a bill later: pick the month of its last payment (a loan paid off
/// in March, daycare through June). It counts through that month.
private struct LastPaymentSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let bill: Recurring
    @State private var last: Date?

    var body: some View {
        let months = (0..<24).map { store.month($0, from: store.currentMonth) }
        NavigationStack {
            Form {
                Section {
                    Picker("Month", selection: Binding(get: { last ?? months[1] }, set: { last = $0 })) {
                        ForEach(months, id: \.self) { m in
                            Text(m.formatted(.dateTime.month(.wide).year())).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                } footer: {
                    let chosen = last ?? months[1]
                    Text("Counted through \(chosen.formatted(.dateTime.month(.wide))). From \(store.month(1, from: chosen).formatted(.dateTime.month(.wide).year())), its \(Money.exact(bill.amount)) a month is spending money.")
                }
            }
            .navigationTitle("Last payment for \(Merchant.clean(bill.name))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stop") {
                        store.stopBill(bill, lastPayment: last ?? months[1])
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
