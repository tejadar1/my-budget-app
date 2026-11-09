import SwiftUI

/// Tap any purchase: change its category, tag it to a trip, or mark it as
/// a credit card payment or transfer between your accounts.
struct TransactionSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transactionId: String
    @State private var prompt: BudgetStore.SortPrompt?
    @State private var showNewTrip = false
    @State private var showSplit = false

    var body: some View {
        NavigationStack {
            if let t = store.data.transactions.first(where: { $0.id == BudgetStore.baseId(transactionId) }) {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Money.signed(t.amount))
                                .heroNumber(36)
                                .foregroundStyle(t.amount > 0 ? Theme.accent : Color.primary)
                            Text(Merchant.clean(t.payee)).font(.headline)
                            Text("\(t.date.formatted(date: .abbreviated, time: .omitted)) · \(store.account(t.accountId)?.fullName ?? "")")
                                .font(.footnote).foregroundStyle(.secondary)
                            if Merchant.clean(t.payee) != t.payee {
                                Text("On your statement: \(t.payee)").font(.caption).foregroundStyle(.secondary)
                            }
                            if let bank = t.bankCategory {
                                Text("Bank category: \(bank.hasPrefix("mcc:") ? "merchant code " + bank.dropFirst(4) : bank)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if t.isPending {
                                Text("Pending").font(.caption.bold()).foregroundStyle(Theme.warning)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Toggle(isOn: Binding(get: { t.isTransfer },
                                             set: { on in
                                                 if on { prompt = store.sort(t.id, as: BankSync.transferCategory) }
                                                 else { store.setTransfer(t.id, false) }
                                             })) {
                            Label(t.isTransfer ? store.transferLabel(t) : "Card payment or transfer",
                                  systemImage: "arrow.left.arrow.right")
                        }
                        if t.isTransfer && t.amount < 0 {
                            Toggle(isOn: Binding(get: { store.isMarkedSaving(t) || BankSync.isInvestmentPayee(t.payee) },
                                                 set: { store.setSaving(t.id, $0) })) {
                                Label("Saved & invested", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .tint(Theme.accent)
                            .disabled(BankSync.isInvestmentPayee(t.payee))
                        }
                    } footer: {
                        Text(t.isTransfer && t.amount < 0
                             ? "Turn on Saved & invested for money moved to savings or investing (like Robinhood). It counts toward your savings, and transfers worded the same way follow."
                             : "Card payments and moves between your accounts aren’t spending.")
                    }

                    if !t.isTransfer {
                        Section {
                            Toggle(isOn: Binding(get: { t.isBusiness }, set: { store.setBusiness(t.id, $0) })) {
                                Label(t.amount > 0 ? "Business reimbursement" : "Business expense", systemImage: "briefcase.fill")
                            }
                            .tint(Theme.accent)
                        } footer: {
                            Text(t.amount > 0 ? "Money paid back for work costs. It doesn’t count as income."
                                              : "You’ll be paid back, so it stays out of your budget. Upside tracks what you’re still owed.")
                        }
                    }

                    if !t.isTransfer, t.amount < 0 {
                        Section {
                            if let splits = t.splits {
                                ForEach(Array(splits.enumerated()), id: \.offset) { _, part in
                                    LabeledContent {
                                        Text(Money.signed(part.amount)).monospacedDigit()
                                    } label: {
                                        Text(store.category(part.categoryId ?? "")?.name ?? "No category")
                                        if let owner = part.owner { Text(store.people.name(owner)) }
                                    }
                                }
                            }
                            Button(t.splits == nil ? "Split this purchase…" : "Change split…") { showSplit = true }
                        } header: {
                            if t.splits != nil { Text("Split") }
                        } footer: {
                            if t.splits == nil { Text("Split a Costco run into groceries and home, or between the two of you.") }
                        }
                    }

                    if !t.isTransfer && t.splits == nil {
                        Section("Category") {
                            Picker("Category", selection: Binding(
                                get: { t.categoryId ?? "" },
                                set: { if !$0.isEmpty { prompt = store.sort(t.id, as: $0) } })) {
                                if t.categoryId == nil { Text("Choose…").tag("") }
                                ForEach(store.groupedCategories) { group in
                                    Section(group.name) {
                                        ForEach(group.categories) { Text($0.name).tag($0.id) }
                                    }
                                }
                                ForEach(store.data.categories.filter(\.isIncome)) { Text($0.name).tag($0.id) }
                            }
                            .pickerStyle(.navigationLink)
                        }

                        if store.data.tripsOff != true {
                        Section {
                            Picker("Trip", selection: Binding(
                                get: { t.tripId ?? "" },
                                set: { store.setTrip(t.id, $0.isEmpty ? nil : $0) })) {
                                Text("None").tag("")
                                ForEach(store.data.trips) { Text($0.name).tag($0.id) }
                            }
                            Button("New trip…") { showNewTrip = true }
                        } header: {
                            Text("Trip")
                        } footer: {
                            Text("Trip purchases count toward the trip, not everyday spending.")
                        }
                        }
                    }
                }
                .sortOthersPrompt($prompt)
                .navigationTitle("Purchase")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $showNewTrip) {
                    TripEditor(trip: nil) { trip in store.setTrip(t.id, trip.id) }
                }
                .sheet(isPresented: $showSplit) { SplitEditor(transaction: t) }
            }
        }
    }

}

extension View {
    /// "Sort 6 other LENNY'S BAGELS purchases as Dining too?"
    func sortOthersPrompt(_ prompt: Binding<BudgetStore.SortPrompt?>) -> some View {
        modifier(SortOthersPrompt(prompt: prompt))
    }
}

private struct SortOthersPrompt: ViewModifier {
    @Environment(BudgetStore.self) private var store
    @Binding var prompt: BudgetStore.SortPrompt?
    /// Shown a moment after `prompt` is set, so a closing menu or picker
    /// doesn't dismiss it on the way out. Stays until you answer.
    @State private var shown: BudgetStore.SortPrompt?

    func body(content: Content) -> some View {
        content
            .onChange(of: prompt?.id) { _, id in
                guard id != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { shown = prompt }
            }
            .alert(title, isPresented: Binding(get: { shown != nil },
                                               set: { if !$0 { shown = nil; prompt = nil } }),
                   presenting: shown) { p in
                Button("Sort all \(p.otherIds.count + 1)") { withAnimation { store.sortAll(p) } }
                Button("Just this one", role: .cancel) { }
            } message: { p in
                Text("New \(p.storeName) purchases will follow if you sort all.")
            }
    }

    private var title: String {
        guard let p = shown else { return "" }
        let n = p.otherIds.count
        return "Sort \(n) other \(p.storeName) purchase\(n == 1 ? "" : "s") as \(p.categoryName) too?"
    }
}

/// Split one purchase into parts by category and person. The parts must
/// add up to the purchase.
private struct SplitEditor: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction

    private struct Part: Identifiable {
        let id = UUID()
        var categoryId: String?
        /// Positive dollars and cents as typed.
        var amount: Decimal
        var owner: Owner?
    }

    @State private var parts: [Part] = []

    private var total: Decimal { Decimal(-transaction.amount) / 100 }
    private var assigned: Decimal { parts.reduce(0) { $0 + $1.amount } }
    private var left: Decimal { total - assigned }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Purchase", value: Money.exact(-transaction.amount))
                    LabeledContent("Left to assign") {
                        Text(left.formatted(.currency(code: "USD")))
                            .foregroundStyle(left == 0 ? Theme.accent : Theme.over).monospacedDigit()
                    }
                    Button("Half each: \(store.people.name(.p1)) and \(store.people.name(.p2))") { halves() }
                }
                ForEach($parts) { $part in
                    Section {
                        Picker("Category", selection: $part.categoryId) {
                            Text("Choose…").tag(String?.none)
                            ForEach(store.groupedCategories) { group in
                                Section(group.name) {
                                    ForEach(group.categories) { Text($0.name).tag(Optional($0.id)) }
                                }
                            }
                        }
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("$0.00", value: $part.amount, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
                        }
                        Picker("Whose", selection: $part.owner) {
                            Text("Account’s owner").tag(Owner?.none)
                            ForEach(Owner.pickable) { Text(store.people.name($0)).tag(Optional($0)) }
                        }
                        if parts.count > 1 {
                            Button("Remove part", role: .destructive) { parts.removeAll { $0.id == part.id } }
                        }
                    }
                }
                Section {
                    Button("Add a part") {
                        parts.append(Part(categoryId: parts.last?.categoryId, amount: max(0, left), owner: nil))
                    }
                    if transaction.splits != nil {
                        Button("Don’t split", role: .destructive) {
                            store.split(transaction.id, into: [])
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.split(transaction.id, into: parts.map {
                            Split(categoryId: $0.categoryId, amount: -Self.cents($0.amount), owner: $0.owner)
                        })
                        dismiss()
                    }
                    .disabled(left != 0 || parts.contains { $0.categoryId == nil })
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let splits = transaction.splits {
            parts = splits.map { Part(categoryId: $0.categoryId, amount: Decimal(-$0.amount) / 100, owner: $0.owner) }
        } else {
            parts = [Part(categoryId: transaction.categoryId, amount: total, owner: nil),
                     Part(categoryId: nil, amount: 0, owner: nil)]
        }
    }

    /// Same category, half each; the odd cent goes to the first.
    private func halves() {
        let cents = -transaction.amount
        let second = cents / 2
        let category = parts.first?.categoryId ?? transaction.categoryId
        parts = [Part(categoryId: category, amount: Decimal(cents - second) / 100, owner: .p1),
                 Part(categoryId: category, amount: Decimal(second) / 100, owner: .p2)]
    }

    private static func cents(_ dollars: Decimal) -> Cents {
        Int(NSDecimalNumber(decimal: dollars * 100).doubleValue.rounded())
    }
}
