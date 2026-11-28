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
                if month == store.currentMonth {
                    // The same number as the Budget card, so there's one answer.
                    let left = store.monthPlan(month).leftToSpend
                    VStack(alignment: .leading, spacing: 2) {
                        Text(left >= 0 ? "\(Money.short(left)) left to spend" : "\(Money.short(-left)) over")
                            .font(.headline)
                            .foregroundStyle(left >= 0 ? Theme.accent : Theme.over)
                        Text(keep > 0 ? "After bills, and \(Money.short(keep)) for savings and trips."
                                      : "After bills.")
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
        // Judged against the plan as made; mid-month adjustments show beside it.
        // The verdict is everyday spending against everyday limits, as
        // planned: bills and trips aren't in limits, so they're not in it.
        // (Counting all spending against everyday limits made a month with
        // rent look thousands over, or a light month look under.)
        let planned = store.everydayCategories.filter { store.originalLimit($0, in: month) != nil }
        let limit = planned.compactMap { store.originalLimit($0, in: month) }.reduce(0, +)
        let spent = planned.reduce(0) { $0 + store.spent($1.id, in: month) }
        let usual: Cents? = planned.isEmpty ? nil
            : planned.reduce(0) { $0 + (store.averageSpent($1.id, before: month) ?? 0) }
        let income = store.income(in: month)
        let allSpent = store.totalSpent(in: month, includeTrips: true)
        let byOwner = store.spentByOwner(in: month)
        let categories = store.expenseCategories
            .filter { !$0.aimsForZero && $0.group != "Trips" }
            .map { ($0, store.spent($0.id, in: month)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        // Everyday spending the plan had no limit for.
        let everydayIds = Set(store.everydayCategories.map(\.id))
        let unplanned = categories.filter { c, _ in everydayIds.contains(c.id) && store.originalLimit(c, in: month) == nil }
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

                let off = store.offPlan(in: month)
                if !off.over.isEmpty {
                    let total = off.over.reduce(0) { $0 + $1.over }
                    let top = off.over.prefix(2).map { "\($0.category.name) (+\(Money.short($0.over)))" }
                    Section {
                        // Under overall, a category or two over isn't "the month went past the plan".
                        Text(limit > 0 && spent <= limit
                             ? (off.over.count == 1
                                ? "One category went past its plan: \(top[0])."
                                : "\(off.over.count) categories went \(Money.short(total)) past their plans. Most of it: \(top.joined(separator: " and ")).")
                             : "\(monthName) went \(Money.short(total)) past the plan. Most of it: \(top.joined(separator: " and ")).")
                            .font(.subheadline.weight(.semibold))
                        ForEach(off.over) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    CategoryIcon(categoryId: item.category.id, size: 26)
                                    Text(item.category.name)
                                    Spacer()
                                    Text("+\(Money.short(item.over))").fontWeight(.semibold).foregroundStyle(Theme.over)
                                }
                                Text(offPlanDetail(item)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if let summary = store.cutsSummary(in: month) {
                            Text("To pay for it, you \(summary).")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.over)
                        }
                        if !off.under.isEmpty {
                            Text("Went well: " + off.under.prefix(3).map { "\($0.category.name) \(Money.short(-$0.over)) under" }.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(Theme.accent)
                        }
                    } header: {
                        Text("Where it went off plan")
                    }
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

                if !unplanned.isEmpty {
                    Section {
                        ForEach(unplanned.prefix(5), id: \.0.id) { category, amount in
                            let usual = store.averageSpent(category.id, before: store.month(1, from: month)) ?? amount
                            let suggest = Int((Double(usual) / 1000).rounded(.up)) * 1000
                            VStack(alignment: .leading, spacing: 2) {
                                LabeledContent(category.name, value: Money.short(amount))
                                Text("A \(Money.short(suggest)) limit would cover a usual month.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Not in the plan")
                    } footer: {
                        Text("Add these in Plan so next month accounts for them.")
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

extension RecapView {
    var monthName: String { month.formatted(.dateTime.month(.wide)) }

    /// "Planned $500 · spent $810 · 14 purchases, biggest $95 at Nobu"
    func offPlanDetail(_ item: BudgetStore.OffPlan) -> String {
        var parts = [item.hadLimit ? "Planned \(Money.short(item.planned))" : "Usually \(Money.short(item.planned))",
                     "spent \(Money.short(item.spent))"]
        if item.purchases > 0 {
            var line = "\(item.purchases) purchase\(item.purchases == 1 ? "" : "s")"
            if let big = item.biggest, item.purchases > 1 {
                line += ", biggest \(Money.short(-big.amount)) at \(Merchant.clean(big.payee))"
            }
            parts.append(line)
        }
        return parts.joined(separator: " · ")
    }
}
