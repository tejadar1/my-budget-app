import SwiftUI

/// Budget row: bills still to come this month.
struct BillsRow: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let bills = store.recurringCharges()
        let due = bills.filter { !$0.paidThisMonth }
        let flagged = store.subscriptionQuestions()
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
    /// The bills category tapped, to say what's held and offer Paid for the month.
    @State private var held: BudgetStore.BillLine?
    /// Just released with Paid for the month: said once, where the money went.
    @State private var released: (name: String, amount: Cents)?

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
                        // Every category opens to what it counts; one still
                        // holding money can be released from there (or by swipe).
                        let open = Button { held = line } label: {
                            HStack { row; Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if line.stillToCome > 0 {
                            open.swipeActions { allPaidButton(line) }
                                .contextMenu { allPaidButton(line) }
                        } else {
                            open
                        }
                    }
                } header: {
                    Text("Counted in your plan")
                } footer: {
                    if let released {
                        Text("\(Money.short(released.amount)) from \(released.name) is back in your spending money. Plan can save it.")
                            .foregroundStyle(Theme.accent)
                    } else if lines.contains(where: { $0.stillToCome > 0 }) {
                        Text("Bills still to come are held from your spending money. Already paid? Tap it.")
                    } else {
                        Text("Every bill this month is paid. Nothing is being held.")
                    }
                }
            }
            if !due.isEmpty {
                Section {
                    ForEach(due) { b in
                        BillRow(bill: b, when: b.dueDate.map { "Due \(day($0))" } ?? "").swipeActions { stopButton(b) }
                            .swipeActions(edge: .leading) { paidButton(b) }
                            .contextMenu { paidButton(b); stopButton(b) }
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
                        BillRow(bill: b, when: "Paid \(day(b.lastDate))").swipeActions { stopButton(b) }
                            .contextMenu { stopButton(b) }
                    }
                }
            }
            if !subscriptions.isEmpty {
                Section {
                    ForEach(subscriptions) { s in
                        BillRow(bill: s, when: "\(Money.short(s.amount * 12)) a year").swipeActions { stopButton(s) }
                            .contextMenu { stopButton(s) }
                    }
                } header: {
                    Text("Subscriptions")
                } footer: {
                    Text("\(Money.short(subscriptions.reduce(0) { $0 + $1.amount } * 12)) a year. Swipe left to stop one.")
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
            // "Not a bill" lives here now: one Stop, not two swipe buttons.
            Button(bill.isSubscription ? "It's not a subscription" : "It's not a bill") {
                withAnimation { store.undoable("\(Merchant.clean(bill.name)) isn't a bill") { store.dismissRecurring(bill.id) } }
                stopping = nil
            }
        } message: { bill in
            Text("\(Money.exact(bill.amount)) a month goes back to spending money once it stops.")
        }
        .sheet(item: $picking) { bill in
            LastPaymentSheet(bill: bill)
        }
        .sheet(item: $held) { line in
            BillCategorySheet(categoryId: line.category.id, monthName: monthName) { release(line) }
        }
    }

    private func stop(_ bill: Recurring, afterThisMonth: Bool) {
        withAnimation { store.undoable("\(Merchant.clean(bill.name)) stopped") { store.stopBill(bill, afterThisMonth: afterThisMonth) } }
        Haptics.success()
        stopping = nil
    }

    /// Swipe on a category: everything this month is paid, stop holding money.
    private func release(_ line: BudgetStore.BillLine) {
        withAnimation {
            released = (line.category.name, line.stillToCome)
            store.undoable("\(line.category.name) paid for the month") { store.markBillCategoryDone(line.category.id) }
        }
        Haptics.success()
    }

    private func allPaidButton(_ line: BudgetStore.BillLine) -> some View {
        Button { release(line) } label: {
            Label("Paid", systemImage: "checkmark.circle")
        }
        .tint(Theme.accent)
    }

    /// Swipe right: "Paid", for a bill paid somewhere Upside can't see.
    private func paidButton(_ bill: Recurring) -> some View {
        Button { withAnimation { store.undoable("\(Merchant.clean(bill.name)) marked paid") { store.markBillPaid(bill.id) } }; Haptics.success() } label: {
            Label("Paid", systemImage: "checkmark.circle")
        }
        .tint(Theme.accent)
    }

    /// Swipe: "Stop", for a bill that's ending (cancelled, paid off).
    private func stopButton(_ bill: Recurring) -> some View {
        Button { stopping = bill } label: { Label("Stop", systemImage: "stop.circle") }
            .tint(.orange)
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
                if !store.isKept(bill), let up = bill.priceIncrease, let before = bill.previous {
                    Label("Up \(Money.exact(up)) from \(Money.exact(before))", systemImage: "arrow.up.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning)
                } else if !store.isKept(bill), bill.isNew && bill.isSubscription {
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

/// What one bills category counts this month, before you say it's all paid:
/// the bills Upside knows (paid, due, marked paid), other charges, and the
/// part of the usual that's held for anything else.
private struct BillCategorySheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryId: String
    let monthName: String
    let release: () -> Void

    var body: some View {
        let b = store.billBreakdown(categoryId)
        let held = b.line?.stillToCome ?? 0
        let name = store.category(categoryId)?.name ?? "Bills"
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(held > 0 ? "\(Money.short(held)) held" : "Nothing held").heroNumber(34)
                        Text("paid \(Money.short(b.line?.paid ?? 0)) in \(monthName) · usually \(Money.short(b.usual))")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !b.items.isEmpty {
                    Section {
                        ForEach(b.items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Merchant.clean(item.bill.name))
                                    Text(status(item)).font(.footnote)
                                        .foregroundStyle(item.bill.paidThisMonth ? Theme.accent : .secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(Money.exact(item.paid > 0 ? item.paid : item.bill.amount)).monospacedDigit()
                                    Text("usually \(Money.short(item.usual))").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Bills Upside knows")
                    }
                }

                if !b.others.isEmpty {
                    Section("Other charges this month") {
                        ForEach(b.others) { TransactionRow(transaction: $0) }
                    }
                }

                Section {
                    Text(explanation(b, held: held)).font(.subheadline)
                    if held > 0 {
                        Button {
                            release()
                            dismiss()
                        } label: {
                            Text("Paid for \(monthName)").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.accent)
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    if held > 0 { Text("Only \(monthName). The \(Money.short(held)) goes back to your spending money.") }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func status(_ item: BudgetStore.BillBreakdown.Item) -> String {
        if item.markedPaid { return "Marked paid" }
        if item.bill.paidThisMonth {
            return item.paid > 0 ? "Paid \(item.bill.lastDate.formatted(.dateTime.month(.abbreviated).day()))"
                                 : "Paid under another name"
        }
        if let due = item.bill.dueDate { return "Due \(due.formatted(.dateTime.month(.abbreviated).day()))" }
        return "Not yet this month"
    }

    private func explanation(_ b: BudgetStore.BillBreakdown, held: Cents) -> String {
        let due = b.items.filter { !$0.bill.paidThisMonth }
        if held == 0 { return "Everything expected here this month is in." }
        if !due.isEmpty {
            return "Held for \(due.map { Merchant.clean($0.bill.name) }.joined(separator: " and ")), still to come. Paid somewhere Upside can't see? Paid for the month releases it."
        }
        let other = max(0, b.usual - b.knownUsual)
        if b.items.isEmpty {
            return "Upside doesn't recognize a regular bill here yet, so it holds your usual \(Money.short(b.usual)). Nothing else coming? Paid for the month releases it."
        }
        return "These bills usually come to \(Money.short(b.knownUsual)) of your usual \(Money.short(b.usual)) here, so \(Money.short(other)) is held for anything else. Nothing else coming? Paid for the month releases it."
    }
}
