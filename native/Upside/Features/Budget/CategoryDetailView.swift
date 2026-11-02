import Charts
import SwiftUI

/// One category: what's left, how it compares to usual, who spent it, and
/// this month's purchases.
struct CategoryDetailView: View {
    @Environment(BudgetStore.self) private var store
    let categoryId: String
    var month: Date? = nil
    /// A past month picked from the chart, opened as its own page.
    @State private var drill: MonthRef?

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
                                 markerLabel: average == nil ? nil : "usual",
                                 overflow: Theme.over)
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
                         limit: limit > 0 ? limit : nil, isCurrent: isCurrent) { picked in
                if picked != month { drill = MonthRef(date: picked) }
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
        .navigationDestination(item: $drill) { CategoryDetailView(categoryId: categoryId, month: $0.date) }
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
            parts.append(store.transferLabel(transaction))
        } else if let trip = transaction.tripId.flatMap({ id in store.data.trips.first { $0.id == id } }) {
            parts.append(trip.name)
        } else if let category = store.category(transaction.categoryId) {
            parts.append(transaction.isHunch ? "\(category.name)?" : category.name)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sorting new purchases

/// Purchases Upside sorted on a hunch. Confirm with ✓ or pick the right
/// category; either way it remembers the store.
struct ReviewView: View {
    @Environment(BudgetStore.self) private var store
    @State private var newCategoryFor: Transaction?
    @State private var prompt: BudgetStore.SortPrompt?
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
                ForEach(store.toCheck) { t in
                    HStack(spacing: 10) {
                        TransactionRow(transaction: t)
                        if t.categoryId != nil {
                            Button { withAnimation { store.confirm(t.id) } } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(store.category(t.categoryId)?.name ?? "Category") is right")
                        }
                        Menu {
                            Button {
                                withAnimation { prompt = store.sort(t.id, as: BankSync.transferCategory) }
                            } label: {
                                Label("Card payment or transfer", systemImage: "arrow.left.arrow.right")
                            }
                            ForEach(store.groupedCategories) { group in
                                Section(group.name) {
                                    ForEach(group.categories) { c in
                                        Button(c.name) {
                                            withAnimation { prompt = store.sort(t.id, as: c.id) }
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
                            Image(systemName: "pencil.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Pick a different category")
                    }
                }
            } footer: {
                Text("Upside sorted these on a hunch, and they already count in that category. Tap ✓ if it’s right or the pencil to change it; either way Upside remembers the store.")
            }
        }
        .overlay {
            if store.toCheck.isEmpty {
                ContentUnavailableView("All checked", systemImage: "checkmark.circle",
                                       description: Text("Upside is sure about every purchase."))
            }
        }
        .sortOthersPrompt($prompt)
        .navigationTitle("Check these")
        .alert("New category", isPresented: Binding(
            get: { newCategoryFor != nil },
            set: { if !$0 { newCategoryFor = nil } })) {
            TextField("Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) { newCategoryFor = nil }
            Button("Create") {
                if let t = newCategoryFor, !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                    let id = store.addCategory(newCategoryName, group: "Everyday")
                    withAnimation { prompt = store.sort(t.id, as: id) }
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
    @State private var showRecommended = LaunchArgs.open?.kind == "recommended"
    @State private var confirmRecalc = false
    @State private var openLimit: String? = LaunchArgs.open?.kind == "limit" ? LaunchArgs.open?.id : nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        confirmRecalc = true
                    } label: {
                        Label("Recalculate to fit my plan", systemImage: "arrow.clockwise")
                    }
                    .confirmationDialog("Recalculate every limit?", isPresented: $confirmRecalc, titleVisibility: .visible) {
                        Button("Recalculate") { withAnimation { _ = store.setLimitsToPlan(store.currentMonth) } }
                    } message: {
                        Text("Each everyday limit starts from your usual, then shopping, dining and other flexible spending is trimmed so everything fits after bills, savings, card paydown and trips. Limits you typed in are replaced.")
                    }
                    Button { showRecommended = true } label: {
                        Label("Recommended categories", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Use it after adding a bank or account. Tap a category to see its last 3 months and how its limit was set.")
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
            .sheet(isPresented: $showRecommended) { RecommendedCategoriesView() }
            .navigationDestination(isPresented: Binding(get: { openLimit != nil }, set: { if !$0 { openLimit = nil } })) {
                if let openLimit { LimitDetailView(categoryId: openLimit) }
            }
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

    var body: some View {
        NavigationLink {
            LimitDetailView(categoryId: category.id)
        } label: {
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
                Text(category.limit.map(Money.short) ?? "No limit")
                    .foregroundStyle(category.limit == nil ? .secondary : .primary)
                    .monospacedDigit()
            }
        }
    }
}

/// One category's limit: the last 3 months behind "usual", how the limit
/// was set, and where to change it.
struct LimitDetailView: View {
    @Environment(BudgetStore.self) private var store
    let categoryId: String
    @State private var dollars = 0

    var body: some View {
        if let category = store.category(categoryId) {
            let thisMonth = store.currentMonth
            let counted = store.averagingMonths(before: thisMonth)
            let shown = (1...3).map { store.month(-$0, from: thisMonth) }
            let usual = store.averageSpent(categoryId, before: thisMonth)
            let suggested = store.limitFromAverage(category)
            Form {
                Section {
                    ForEach(shown, id: \.self) { month in
                        LabeledContent(month.formatted(.dateTime.month(.wide))) {
                            if counted.contains(month) {
                                Text(Money.short(store.spent(categoryId, in: month))).monospacedDigit()
                            } else {
                                Text(month < store.firstFullMonth ? "not counted, partial month" : "no data")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Usual (average)") {
                        Text(usual.map(Money.short) ?? "—").fontWeight(.semibold).monospacedDigit()
                    }
                } header: {
                    Text("Last 3 months")
                } footer: {
                    if counted.count > 0 && counted.count < 3 {
                        Text("Averaged over \(counted.count) month\(counted.count == 1 ? "" : "s"); the others had no history yet.")
                    }
                }

                Section {
                    HStack {
                        Text("Monthly limit")
                        Spacer()
                        TextField("No limit", value: $dollars, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: 140)
                    }
                    if let suggested, category.limit != suggested {
                        Button("Use my usual: \(Money.short(suggested))") { dollars = suggested / 100 }
                    }
                    if category.limit != nil {
                        Button("Remove limit", role: .destructive) { dollars = 0 }
                    }
                } header: {
                    Text("Limit")
                } footer: {
                    Text(explanation(category, usual: usual, suggested: suggested))
                }

                Section {
                    LabeledContent("Spent so far", value: Money.short(store.spent(categoryId, in: thisMonth)))
                    if let lowered = store.plan?.limits[categoryId] {
                        LabeledContent("Savings plan lowers it to", value: Money.short(lowered))
                    }
                } header: {
                    Text(thisMonth.formatted(.dateTime.month(.wide)))
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { dollars = (category.limit ?? 0) / 100 }
            .onChange(of: dollars) { _, newValue in
                store.setLimit(categoryId, newValue > 0 ? newValue * 100 : nil)
            }
        }
    }

    private func explanation(_ category: Category, usual: Cents?, suggested: Cents?) -> String {
        guard let limit = category.limit else {
            return suggested.map { "No limit yet. Your usual would round up to \(Money.short($0))." } ?? "No limit yet."
        }
        if let usual, let suggested, limit == suggested {
            return "Your usual \(Money.short(usual)), rounded up to the next $10."
        }
        if let suggested {
            return "You set this. Your usual \(Money.short(usual ?? 0)) would round up to \(Money.short(suggested))."
        }
        return "You set this. There isn't enough history for a usual yet."
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
    /// Opens a month's purchases in this category.
    let onPick: (Date) -> Void
    @State private var selected: Date?

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
                .chartXSelection(value: $selected)
                .onChange(of: selected) { _, date in
                    guard let date else { return }
                    onPick(store.monthStart(date))
                    selected = nil
                }
                .frame(height: 150)
                .padding(.vertical, 6)
                .accessibilityLabel("Spending for the last \(points.count) months")
                .accessibilityValue(points.map { "\($0.month.formatted(.dateTime.month(.wide))) \(Money.short($0.spent))" }
                    .joined(separator: ", "))
                // The same months as rows: easier to tap, and VoiceOver can reach them.
                ForEach(points.reversed()) { point in
                    Button { onPick(point.month) } label: {
                        HStack {
                            Text(point.month.formatted(.dateTime.month(.wide).year()))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(Money.short(point.spent)).monospacedDigit().foregroundStyle(.secondary)
                            if point.month != month {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(point.month == month)
                }
            } header: {
                Text("Last \(points.count) months")
            } footer: {
                Text([BudgetStore.trendNote(finished), "Tap a month to see its purchases."].compactMap { $0 }.joined(separator: " "))
            }
        }
    }
}

/// Categories Upside thinks would help, based on what you buy.
struct RecommendedCategoriesView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let recommended = store.recommendedCategories()
        NavigationStack {
            List {
                if recommended.isEmpty {
                    ContentUnavailableView("Nothing to recommend", systemImage: "checkmark.circle",
                                           description: Text("Your spending fits the categories you have."))
                } else {
                    Section {
                        ForEach(recommended) { suggestion in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.name).font(.headline)
                                    Text("About \(Money.short(store.monthlyAverage(of: suggestion))) a month · \(suggestion.transactionIds.count) purchase\(suggestion.transactionIds.count == 1 ? "" : "s"), like \(suggestion.example)")
                                        .font(.footnote).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("Add") { withAnimation { store.accept(suggestion) } }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Add \(suggestion.name)")
                            }
                        }
                    } footer: {
                        Text("Adding one moves those purchases into it, and new ones from the same stores follow.")
                    }
                }
            }
            .navigationTitle("Recommended categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
