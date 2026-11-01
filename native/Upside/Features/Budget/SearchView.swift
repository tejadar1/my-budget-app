import SwiftUI

/// Find a purchase by store or amount across every account and month.
struct SearchView: View {
    @Environment(BudgetStore.self) private var store
    @State var query = ""

    var body: some View {
        let results = store.search(query)
        let months = Dictionary(grouping: results) { store.monthStart($0.date) }
            .sorted { $0.key > $1.key }

        List {
            if !query.isEmpty && !results.isEmpty {
                let spent = -results.filter { $0.amount < 0 && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
                Section {
                    Text("\(results.count) result\(results.count == 1 ? "" : "s") · \(Money.short(spent)) spent")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(months, id: \.key) { entry in
                Section(entry.key.formatted(.dateTime.month(.wide).year())) {
                    ForEach(entry.value) { TransactionRow(transaction: $0) }
                }
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Search purchases", systemImage: "magnifyingglass",
                                       description: Text("Type a store, like Amazon, or an amount, like 84.12."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Store or amount")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}
