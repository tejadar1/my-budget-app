import SwiftUI

/// Tap any purchase: change its category, tag it to a trip, or mark it as
/// a credit card payment or transfer between your accounts.
struct TransactionSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transactionId: String
    @State private var remember = true
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
                                             set: { store.setTransfer(t.id, $0) })) {
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
                                set: { if !$0.isEmpty { store.setCategory(t.id, $0, remember: remember) } })) {
                                if t.categoryId == nil { Text("Choose…").tag("") }
                                ForEach(store.groupedCategories) { group in
                                    Section(group.name) {
                                        ForEach(group.categories) { Text($0.name).tag($0.id) }
                                    }
                                }
                                ForEach(store.data.categories.filter(\.isIncome)) { Text($0.name).tag($0.id) }
                            }
                            .pickerStyle(.navigationLink)
                            Toggle("Use for all \(storeName(t.payee)) purchases", isOn: $remember)
                                .font(.subheadline)
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

    private func storeName(_ payee: String) -> String {
        let key = BudgetStore.payeeKey(payee)
        return key.isEmpty ? "these" : key.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
