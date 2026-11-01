import Charts
import SwiftUI

/// One category: what's left, how it compares to usual, who spent it, and
/// this month's purchases.
struct CategoryDetailView: View {
    @Environment(BudgetStore.self) private var store
    let categoryId: String
    var month: Date? = nil

    var body: some View {
        let month = self.month ?? store.currentMonth
        let isCurrent = month == store.currentMonth
        let category = store.category(categoryId)
        let spent = store.spent(categoryId, in: month)
        let average = store.averageSpent(categoryId, before: month)
        let limit = category.flatMap { store.limit($0, in: month) } ?? 0
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
                            stat(isCurrent ? "This month" : "Spent", Money.short(spent))
                            stat("Usual", average.map(Money.short) ?? "—")
                            stat(isCurrent ? "Pace" : "Result",
                                 isCurrent ? pace(spent: spent, limit: limit)
                                 : limit == 0 ? "—" : left < 0 ? "Over" : "Under")
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            TrendSection(categoryId: categoryId, month: month,
                         limit: limit > 0 ? limit : nil, isCurrent: isCurrent)

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

            Section(isCurrent ? "This month" : month.formatted(.dateTime.month(.wide).year())) {
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
        // Early in the month one normal purchase shouldn't read as "ahead".
        let allowance = max(expected * 1.1, Double(limit) * 0.25)
        if Double(spent) <= allowance { return "On track" }
        if spent > limit { return "Over" }
        return "Ahead"
    }
}

struct TransactionRow: View {
    @Environment(BudgetStore.self) private var store
    let transaction: Transaction
    @State private var isEditing = false

    var body: some View {
        let account = store.account(transaction.accountId)
        Button { isEditing = true } label: {
            HStack(spacing: 12) {
                if let account {
                    OwnerBadge(owner: account.owner, people: store.people, size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.payee).lineLimit(1)
                    Text(detail(account))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(Money.exact(transaction.amount))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(transaction.isTransfer ? Color.secondary
                                     : transaction.amount > 0 ? Theme.accent : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isEditing) { TransactionSheet(transactionId: transaction.id) }
    }

    private func detail(_ account: Account?) -> String {
        var parts = [transaction.date.formatted(.dateTime.month(.abbreviated).day())]
        if let account { parts.append(account.institution) }
        if transaction.isTransfer {
            parts.append("not spending")
        } else if let trip = transaction.tripId.flatMap({ id in store.data.trips.first { $0.id == id } }) {
            parts.append(trip.name)
        } else if let category = store.category(transaction.categoryId) {
            parts.append(category.name)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sorting new purchases

/// Purchases the bank couldn't place. Pick once; Upside remembers the store.
struct ReviewView: View {
    @Environment(BudgetStore.self) private var store
    @State private var newCategoryFor: Transaction?
    @State private var newCategoryName = ""

    var body: some View {
        List {
            if !store.suggestedCategories.isEmpty {
                Section {
                    ForEach(store.suggestedCategories) { suggestion in
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New category: \(suggestion.name)").font(.headline)
                                Text("\(suggestion.transactionIds.count) purchase\(suggestion.transactionIds.count == 1 ? "" : "s"), like \(suggestion.example)")
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Create") { withAnimation { store.accept(suggestion) } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Suggested")
                }
            }
            Section {
                ForEach(store.uncategorized) { t in
                    HStack {
                        TransactionRow(transaction: t)
                        Menu {
                            Button {
                                withAnimation { store.categorize(t.id, as: BankSync.transferCategory) }
                            } label: {
                                Label("Not spending (card payment / transfer)", systemImage: "arrow.left.arrow.right")
                            }
                            ForEach(store.groupedCategories) { group in
                                Section(group.name) {
                                    ForEach(group.categories) { c in
                                        Button(c.name) {
                                            withAnimation { store.categorize(t.id, as: c.id) }
                                        }
                                    }
                                }
                            }
                            Button {
                                newCategoryName = ""
                                newCategoryFor = t
                            } label: {
                                Label("New category…", systemImage: "plus")
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
                Text("Choosing a category also sorts future purchases from the same store. Card payments and transfers between your accounts aren’t spending.")
            }
        }
        .overlay {
            if store.uncategorized.isEmpty {
                ContentUnavailableView("All sorted", systemImage: "checkmark.circle",
                                       description: Text("Every purchase has a category."))
            }
        }
        .navigationTitle("To sort")
        .alert("New category", isPresented: Binding(
            get: { newCategoryFor != nil },
            set: { if !$0 { newCategoryFor = nil } })) {
            TextField("Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) { newCategoryFor = nil }
            Button("Create") {
                if let t = newCategoryFor, !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                    let id = store.addCategory(newCategoryName, group: "Everyday")
                    withAnimation { store.categorize(t.id, as: id) }
                }
                newCategoryFor = nil
            }
        } message: {
            if let t = newCategoryFor {
                Text("For \(t.payee) and future purchases there.")
            }
        }
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
                                    .swipeActions {
                                        Button("Hide", role: .destructive) {
                                            withAnimation { store.hideCategory(category.id) }
                                        }
                                    }
                            }
                        }
                    }
                }
                AddCategorySection()
            }
            .navigationTitle("Categories & limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Add your own category.
private struct AddCategorySection: View {
    @Environment(BudgetStore.self) private var store
    @State private var name = ""
    @State private var group = "Everyday"

    var body: some View {
        Section {
            TextField("Category name", text: $name)
                .textInputAutocapitalization(.words)
            Picker("Group", selection: $group) {
                ForEach(store.groupNames.filter { $0 != "Trips" }, id: \.self) { Text($0).tag($0) }
            }
            Button("Add category") {
                withAnimation { store.addCategory(name, group: group) }
                name = ""
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Add a category")
        } footer: {
            Text("Swipe left on a category to hide it. Its history stays.")
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

/// Six months of spending as bars, with the limit as a line and one
/// sentence on whether it's a trend or a one-off.
private struct TrendSection: View {
    @Environment(BudgetStore.self) private var store
    let categoryId: String
    let month: Date
    let limit: Cents?
    let isCurrent: Bool

    var body: some View {
        let points = store.monthlySpent(categoryId, endingAt: month)
        // The current month is still filling up, so it doesn't count toward the trend.
        let finished = isCurrent ? Array(points.dropLast()) : points
        if points.count >= 2 {
            Section {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Month", point.month, unit: .month),
                                y: .value("Spent", Double(point.spent) / 100))
                            .foregroundStyle(point.month == month ? Theme.accent : Color.secondary.opacity(0.35))
                            .cornerRadius(4)
                    }
                    if let limit {
                        RuleMark(y: .value("Limit", Double(limit) / 100))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, alignment: .leading) {
                                Text("limit").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let dollars = value.as(Double.self) { Text(Money.short(Cents(dollars * 100))) }
                        }
                    }
                }
                .frame(height: 150)
                .padding(.vertical, 6)
                .accessibilityLabel("Spending for the last \(points.count) months")
                .accessibilityValue(points.map { "\($0.month.formatted(.dateTime.month(.wide))) \(Money.short($0.spent))" }
                    .joined(separator: ", "))
            } header: {
                Text("Last \(points.count) months")
            } footer: {
                if let note = BudgetStore.trendNote(finished) { Text(note) }
            }
        }
    }
}
