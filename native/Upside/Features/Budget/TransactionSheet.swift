import SwiftUI

/// Tap any purchase: change its category, tag it to a trip, or mark it as
/// a credit card payment or transfer between your accounts.
struct TransactionSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transactionId: String
    @State private var prompt: BudgetStore.SortPrompt?
    @State private var showNewTrip = false

    var body: some View {
        NavigationStack {
            if let t = store.data.transactions.first(where: { $0.id == transactionId }) {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Money.exact(t.amount))
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundStyle(t.amount > 0 ? Theme.accent : Color.primary)
                            Text(t.payee).font(.headline)
                            Text("\(t.date.formatted(date: .abbreviated, time: .omitted)) · \(store.account(t.accountId)?.fullName ?? "")")
                                .font(.footnote).foregroundStyle(.secondary)
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
                    } footer: {
                        Text("Paying a credit card or moving money between your own accounts. The purchases on the card already count, so this doesn’t.")
                    }

                    if !t.isTransfer {
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
                .sortOthersPrompt($prompt)
                .navigationTitle("Purchase")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $showNewTrip) {
                    TripEditor(trip: nil) { trip in store.setTrip(t.id, trip.id) }
                }
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

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            titleVisibility: .visible,
            presenting: prompt
        ) { p in
            Button("Sort all \(p.otherIds.count + 1)") { withAnimation { store.sortAll(p) } }
            Button("Just this one", role: .cancel) { }
        } message: { p in
            Text("New \(p.storeName) purchases will follow if you sort all.")
        }
    }

    private var title: String {
        guard let p = prompt else { return "" }
        let n = p.otherIds.count
        return "Sort \(n) other \(p.storeName) purchase\(n == 1 ? "" : "s") as \(p.categoryName) too?"
    }
}
