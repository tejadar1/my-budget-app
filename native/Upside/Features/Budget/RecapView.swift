import SwiftUI

/// Income, everything spent (bills and trips included) and what's left.
struct CashFlowRow: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let income = store.income(in: month)
        let spent = store.totalSpent(in: month, includeTrips: true)
        let left = income - spent
        if income > 0 {
            HStack {
                figure("Income", income, color: .primary)
                Spacer()
                figure("Spent", spent, color: .primary)
                Spacer()
                figure(left >= 0 ? "Left over" : "Short", left, color: left >= 0 ? Theme.accent : Theme.over)
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private func figure(_ label: String, _ value: Cents, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Money.short(value)).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
    }
}

/// Budget row that opens a month's recap.
struct RecapRow: View {
    let month: Date
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(month.formatted(.dateTime.month(.wide))) recap").font(.headline)
                    Text("How the month went, who spent what, and what’s left over.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct RecapView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    var body: some View {
        let limit = store.totalLimit(in: month)
        let spent = store.totalSpent(in: month)
        let usual = store.averageTotal(before: month)
        let income = store.income(in: month)
        let allSpent = store.totalSpent(in: month, includeTrips: true)
        let byOwner = store.spentByOwner(in: month)
        let categories = store.expenseCategories
            .filter { !$0.aimsForZero && $0.group != "Trips" }
            .map { ($0, store.spent($0.id, in: month)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let overs = categories.filter { c, s in (store.limit(c, in: month) ?? 0) > 0 && s > (store.limit(c, in: month) ?? 0) }
        let fees = store.expenseCategories.filter(\.aimsForZero).reduce(0) { $0 + store.spent($1.id, in: month) }

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(limit > 0
                             ? (spent <= limit ? "\(Money.short(limit - spent)) under" : "\(Money.short(spent - limit)) over")
                             : "\(Money.short(spent)) spent")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(limit > 0 && spent > limit ? Theme.over : Theme.accent)
                        if limit > 0 {
                            Text("Everyday spending: \(Money.short(spent)) of \(Money.short(limit))")
                                .foregroundStyle(.secondary)
                        }
                        if let usual, usual > 0 {
                            let diff = spent - usual
                            Text(diff <= 0 ? "\(Money.short(diff)) less than your usual month"
                                 : "\(Money.short(diff)) more than your usual month")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(diff <= 0 ? Theme.accent : Theme.warning)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if income > 0 {
                    Section("Money in and out") {
                        LabeledContent("Income", value: Money.short(income))
                        LabeledContent("Spent, including bills and trips", value: Money.short(allSpent))
                        LabeledContent(income >= allSpent ? "Left over" : "Short") {
                            Text(Money.short(income - allSpent))
                                .fontWeight(.semibold)
                                .foregroundStyle(income >= allSpent ? Theme.accent : Theme.over)
                        }
                    }
                }

                if !categories.isEmpty {
                    Section("Where it went") {
                        ForEach(categories.prefix(5), id: \.0.id) { category, amount in
                            LabeledContent(category.name, value: Money.short(amount))
                        }
                    }
                }

                if !overs.isEmpty {
                    Section("Over the limit") {
                        ForEach(overs, id: \.0.id) { category, amount in
                            LabeledContent(category.name) {
                                Text("\(Money.short(amount - (store.limit(category, in: month) ?? 0))) over")
                                    .foregroundStyle(Theme.over)
                            }
                        }
                    }
                }

                if store.people.isSetUp && !byOwner.isEmpty {
                    Section("Who spent") {
                        ForEach(Owner.allCases.filter { (byOwner[$0] ?? 0) > 0 }) { owner in
                            HStack(spacing: 12) {
                                OwnerBadge(owner: owner, people: store.people, size: 28)
                                Text(store.people.name(owner))
                                Spacer()
                                Text(Money.short(byOwner[owner] ?? 0)).fontWeight(.semibold)
                            }
                        }
                    }
                }

                Section("Cards") {
                    LabeledContent("Fees & interest") {
                        Text(Money.short(fees)).foregroundStyle(fees > 0 ? Theme.over : Theme.accent)
                    }
                    ForEach(store.creditCards) { card in
                        let m = store.cardMonth(card, month)
                        LabeledContent(card.name, value: "charged \(Money.short(m.charged)) · paid \(Money.short(m.paid))")
                    }
                }
            }
            .navigationTitle("\(month.formatted(.dateTime.month(.wide).year())) recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
