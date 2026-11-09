import SwiftUI

/// Business purchases and the reimbursements that paid them back.
struct BusinessView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let all = store.businessTransactions
        let spent = all.filter { $0.amount < 0 }
        let back = all.filter { $0.amount > 0 }
        List {
            if !all.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Money.short(store.businessOwed))
                            .heroNumber(40)
                        Text("still owed to you").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("Spent \(Money.short(-spent.reduce(0) { $0 + $1.amount })), paid back \(Money.short(back.reduce(0) { $0 + $1.amount })). Not in your budget.")
                }
            }
            if !spent.isEmpty {
                Section("Business purchases") {
                    ForEach(spent) { TransactionRow(transaction: $0) }
                }
            }
            if !back.isEmpty {
                Section("Paid back") {
                    ForEach(back) { TransactionRow(transaction: $0) }
                }
            }
        }
        .overlay {
            if all.isEmpty {
                ContentUnavailableView("No business expenses", systemImage: "briefcase",
                                       description: Text("Long-press a purchase in Transactions and choose Business expense."))
            }
        }
        .navigationTitle("Business")
        .navigationBarTitleDisplayMode(.inline)
    }
}
