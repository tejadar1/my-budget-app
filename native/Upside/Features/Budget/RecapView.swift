import SwiftUI

/// First thing on Budget: what came in, how that compares with usual,
/// and what's left after everything spent (bills and trips included).
struct IncomeCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let income = store.income(in: month)
        let spent = store.totalSpent(in: month, includeTrips: true)
        // Trip purchases come out of the fund, so the month sets aside the
        // fund's amount instead of counting the trip spending.
        let fund = store.tripSetAside(in: month)
        let tripSpend = fund > 0 ? store.totalSpent(in: month, includeTrips: true) - store.totalSpent(in: month) : 0
        let left = income - (spent - tripSpend) - fund
        let usual = store.averageIncome(before: month)
        let checks = store.paychecks(in: month)
        if income > 0 || (usual ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("INCOME").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.short(income))
                        .heroNumber(30)
                        .monospacedDigit()
                    Spacer()
                    if let usual, usual > 0 {
                        Text("usual \(Money.short(usual))")
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if checks.extra > 0 {
                    Label("Includes \(checks.extra) extra paycheck\(checks.extra == 1 ? "" : "s") this month",
                          systemImage: "plus.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                } else if income == 0 {
                    Text("No paychecks yet this month").font(.footnote).foregroundStyle(.secondary)
                }
                Divider()
                let keep = store.setAside(in: month)
                if let safe = store.safeToSpend(in: month), month == store.currentMonth {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(safe >= 0 ? "\(Money.short(safe)) safe to spend"
                                       : "\(Money.short(-safe)) over")
                            .font(.headline)
                            .foregroundStyle(safe >= 0 ? Theme.accent : Theme.over)
                        let expecting = (usual ?? 0) > income
                        Text((expecting ? "Counts your usual \(Money.short(usual ?? 0)) income. " : "")
                             + (keep > 0
                                ? (safe >= 0 ? "Keeps \(Money.short(keep)) for savings and trips, after bills left to pay."
                                             : "This comes out of the \(Money.short(keep)) for savings and trips.")
                                : "After bills left to pay this month."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    figure("Spent, incl. bills", spent - tripSpend, color: .primary)
                    if fund > 0 {
                        Spacer()
                        figure("Set aside for trips", fund, color: .primary)
                    }
                    Spacer()
                    figure(month == store.currentMonth ? (left >= 0 ? "Left so far" : "Short so far")
                                                       : (left >= 0 ? "Left over" : "Short"),
                           left, color: left >= 0 ? Theme.accent : Theme.over)
                }
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
                            .heroNumber(40)
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
                        if let usualIncome = store.averageIncome(before: month), usualIncome > 0, usualIncome != income {
                            LabeledContent("Usual income", value: Money.short(usualIncome))
                        }
                        LabeledContent("Spent, including bills and trips", value: Money.short(allSpent))
                        LabeledContent("Saved & invested", value: Money.short(store.savedAndInvested(in: month)))
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
                    LabeledContent("Fees & fines (minimize)") {
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
