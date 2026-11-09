import SwiftUI

/// Every transaction, newest first: search, filter, and fix categories
/// without leaving the list.
struct TransactionsView: View {
    @Environment(BudgetStore.self) private var store
    @State private var query = ""
    @State private var filter: BudgetStore.TransactionFilter = .all
    @State private var categoryId: String?
    @State private var owner: Owner?
    @State private var prompt: BudgetStore.SortPrompt?

    var body: some View {
        let shown = store.transactions(matching: query, filter: filter, categoryId: categoryId, owner: owner)
        let months = Dictionary(grouping: shown) { store.monthStart($0.date) }.sorted { $0.key > $1.key }

        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $filter) {
                        Text("All").tag(BudgetStore.TransactionFilter.all)
                        Text("To check").tag(BudgetStore.TransactionFilter.toCheck)
                        Text("Transfers").tag(BudgetStore.TransactionFilter.transfers)
                        Text("Business").tag(BudgetStore.TransactionFilter.business)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    if categoryId != nil || owner != nil {
                        Button {
                            withAnimation { categoryId = nil; owner = nil }
                        } label: {
                            Label(activeFilterText + " · Clear", systemImage: "xmark.circle.fill")
                                .font(.subheadline)
                        }
                    }
                }

                ForEach(months, id: \.key) { entry in
                    Section {
                        ForEach(entry.value) { t in
                            TransactionRow(transaction: t)
                                .contextMenu { categoryMenu(for: t) }
                                .swipeActions(edge: .leading) {
                                    if t.isHunch {
                                        Button { withAnimation { store.confirm(t.id) } } label: {
                                            Label("Right", systemImage: "checkmark")
                                        }
                                        .tint(Theme.accent)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        withAnimation {
                                            if t.isTransfer { store.setTransfer(t.id, false) }
                                            else { prompt = store.sort(t.id, as: BankSync.transferCategory) }
                                        }
                                    } label: {
                                        Label(t.isTransfer ? "Spending" : "Transfer", systemImage: "arrow.left.arrow.right")
                                    }
                                    .tint(.indigo)
                                }
                        }
                    } header: {
                        HStack {
                            Text(entry.key.formatted(.dateTime.month(.wide).year()))
                            Spacer()
                            let spent = -entry.value.filter { $0.amount < 0 && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
                            Text("\(Money.short(spent)) spent").monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if shown.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(filter == .toCheck ? "All checked" : "Nothing here",
                                               systemImage: filter == .toCheck ? "checkmark.circle" : "list.bullet",
                                               description: Text(filter == .toCheck ? "Upside is sure about every purchase."
                                                                 : "Try a different filter."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: "Store or amount")
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Category", selection: $categoryId) {
                            Text("Any category").tag(String?.none)
                            ForEach(store.groupedCategories) { group in
                                Section(group.name) {
                                    ForEach(group.categories) { Text($0.name).tag(Optional($0.id)) }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        if store.people.isSetUp {
                            Picker("Person", selection: $owner) {
                                Text("Everyone").tag(Owner?.none)
                                ForEach(Owner.pickable) { Text(store.people.name($0)).tag(Optional($0)) }
                            }
                            .pickerStyle(.menu)
                        }
                    } label: {
                        Image(systemName: categoryId != nil || owner != nil
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter by category or person")
                }
            }
            .sortOthersPrompt($prompt)
        }
    }

    private var activeFilterText: String {
        [categoryId.flatMap { store.category($0)?.name }, owner.map { store.people.name($0) }]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// Long-press: pick a category right from the list.
    @ViewBuilder private func categoryMenu(for t: Transaction) -> some View {
        if t.isHunch, let c = store.category(t.categoryId) {
            Button { withAnimation { store.confirm(t.id) } } label: {
                Label("\(c.name) is right", systemImage: "checkmark")
            }
        }
        Button { prompt = store.sort(t.id, as: BankSync.transferCategory) } label: {
            Label("Card payment or transfer", systemImage: "arrow.left.arrow.right")
        }
        if t.isTransfer && t.amount < 0 && !BankSync.isInvestmentPayee(t.payee) {
            Button { withAnimation { store.setSaving(t.id, !store.isMarkedSaving(t)) } } label: {
                Label(store.isMarkedSaving(t) ? "Not savings" : "Saved & invested", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        Menu {
            ForEach(store.expenseCategories.filter { $0.group == "Bills" }) { c in
                Button(c.name) { prompt = store.markAsBill(t.id, as: c.id) }
            }
        } label: {
            Label("It's a bill", systemImage: "calendar.badge.clock")
        }
        Button { withAnimation { store.setBusiness(t.id, !t.isBusiness) } } label: {
            Label(t.isBusiness ? "Not business" : "Business expense", systemImage: "briefcase")
        }
        ForEach(store.groupedCategories) { group in
            Menu(group.name) {
                ForEach(group.categories) { c in
                    Button(c.name) { prompt = store.sort(t.id, as: c.id) }
                }
            }
        }
    }
}
