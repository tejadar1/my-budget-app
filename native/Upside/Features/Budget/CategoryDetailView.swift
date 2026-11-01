import SwiftUI

/// One category: what's left, how it compares to usual, who spent it, and
/// this month's purchases.
struct CategoryDetailView: View {
    @Environment(BudgetStore.self) private var store
    let categoryId: String

    var body: some View {
        let month = store.currentMonth
        let category = store.category(categoryId)
        let spent = store.spent(categoryId, in: month)
        let average = store.averageSpent(categoryId, before: month)
        let limit = category?.limit ?? 0
        let left = limit - spent
        let byOwner = store.spentByOwner(categoryId: categoryId, in: month)
        let transactions = store.data.transactions
            .filter { $0.categoryId == categoryId && store.isInMonth($0.date, month) }

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(limit == 0 ? Money.short(spent)
                         : left < 0 ? "\(Money.short(left)) over" : "\(Money.short(left)) left")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(limit == 0 ? Color.primary : Status(limit: limit, left: left).color)
                    if limit > 0 {
                        SplitBar(fraction: Double(spent) / Double(limit),
                                 segments: segments(byOwner),
                                 fill: Status(limit: limit, left: left).color,
                                 height: 10,
                                 marker: average.map { Double($0) / Double(limit) },
                                 markerLabel: average == nil ? nil : "usual")
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16) {
                        GridRow {
                            stat("This month", Money.short(spent))
                            stat("Usual", average.map(Money.short) ?? "—")
                            stat("Pace", pace(spent: spent, limit: limit))
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            if !byOwner.isEmpty {
                Section("Who spent") {
                    ForEach(Owner.allCases.filter { (byOwner[$0] ?? 0) > 0 }) { owner in
                        HStack(spacing: 12) {
                            OwnerBadge(owner: owner, people: store.people, size: 32)
                            Text(store.people.name(owner))
                            Spacer()
                            Text(Money.short(byOwner[owner] ?? 0)).fontWeight(.semibold)
                        }
                    }
                }
            }

            Section("This month") {
                if transactions.isEmpty {
                    Text("Nothing yet").foregroundStyle(.secondary)
                }
                ForEach(transactions) { t in
                    TransactionRow(transaction: t)
                }
            }
        }
        .navigationTitle(category?.name ?? "Category")
        .navigationBarTitleDisplayMode(.large)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }

    /// Compares spending so far with an even pace through the month.
    private func pace(spent: Cents, limit: Cents) -> String {
        guard limit > 0 else { return "—" }
        let cal = store.calendar
        let today = store.now()
        let days = Double(cal.range(of: .day, in: .month, for: today)!.count)
        let expected = Double(limit) * Double(cal.component(.day, from: today)) / days
        if Double(spent) <= expected * 1.05 { return "On track" }
        if spent > limit { return "Over" }
        return "Ahead"
    }
}

struct TransactionRow: View {
    @Environment(BudgetStore.self) private var store
    let transaction: Transaction

    var body: some View {
        let account = store.account(transaction.accountId)
        HStack(spacing: 12) {
            if let account {
                OwnerBadge(owner: account.owner, people: store.people, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee).lineLimit(1)
                Text("\(transaction.date.formatted(.dateTime.month(.abbreviated).day())) · \(account?.institution ?? "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.exact(transaction.amount))
                .font(.body.monospacedDigit())
                .foregroundStyle(transaction.amount > 0 ? Theme.accent : Color.primary)
        }
    }
}

// MARK: - Sorting new purchases

/// Purchases the bank couldn't place. Pick once; Upside remembers the store.
struct ReviewView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.uncategorized) { t in
                    HStack {
                        TransactionRow(transaction: t)
                        Menu {
                            ForEach(store.groupedCategories) { group in
                                Section(group.name) {
                                    ForEach(group.categories) { c in
                                        Button(c.name) {
                                            withAnimation { store.categorize(t.id, as: c.id) }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "tag.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                        }
                        .accessibilityLabel("Choose category")
                    }
                }
            } footer: {
                Text("Choosing a category also sorts future purchases from the same store.")
            }
        }
        .overlay {
            if store.uncategorized.isEmpty {
                ContentUnavailableView("All sorted", systemImage: "checkmark.circle",
                                       description: Text("Every purchase has a category."))
            }
        }
        .navigationTitle("To sort")
    }
}

// MARK: - Limits

struct LimitsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        withAnimation { store.setLimitsFromAverages() }
                    } label: {
                        Label("Use my 3-month averages", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("Sets each limit to what you usually spend, rounded up. Limits reset every month.")
                }
                ForEach(store.groupedCategories) { group in
                    if group.name != "Trips" {
                        Section(group.name) {
                            ForEach(group.categories) { category in
                                LimitRow(category: category)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Monthly limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LimitRow: View {
    @Environment(BudgetStore.self) private var store
    let category: Category
    @State private var dollars: Int = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                if let avg = store.averageSpent(category.id, before: store.currentMonth) {
                    Text("usual \(Money.short(avg))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("No limit", value: $dollars, format: .currency(code: "USD").precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .onChange(of: dollars) { _, newValue in
                    store.setLimit(category.id, newValue > 0 ? newValue * 100 : nil)
                }
        }
        .onAppear { dollars = (category.limit ?? 0) / 100 }
        .onChange(of: category.limit) { _, newValue in
            dollars = (newValue ?? 0) / 100
        }
    }
}
