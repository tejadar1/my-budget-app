import SwiftUI

/// Budget row: what you're still owed for business expenses.
struct BusinessRow: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        if !store.businessTransactions.isEmpty {
            NavigationLink(value: Route.business) {
                HStack(spacing: 14) {
                    Image(systemName: "briefcase.fill")
                        .font(.title3).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.brown, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.businessOwed > 0 ? "\(Money.short(store.businessOwed)) waiting to be paid back"
                                                    : "Business expenses all paid back")
                            .font(.headline)
                        Text("Kept out of your budget until it's reimbursed.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

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
