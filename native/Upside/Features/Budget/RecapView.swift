import SwiftUI

/// First thing on Budget: what came in, how that compares with usual,
/// and what's left after everything spent (bills and trips included).
struct IncomeCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let income = store.income(in: month)
        let spent = store.totalSpent(in: month, includeTrips: true)
        let left = income - spent
        let usual = store.averageIncome(before: month)
        let checks = store.paychecks(in: month)
        if income > 0 || (usual ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("INCOME").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.short(income))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
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
                HStack {
                    figure("Spent, incl. bills", spent, color: .primary)
                    Spacer()
                    figure(left >= 0 ? "Left over" : "Short", left, color: left >= 0 ? Theme.accent : Theme.over)
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

/// Budget row that opens a month's recap.
struct RecapRow: View {
    let month: Date
    var onDismiss: (() -> Void)? = nil
    let onOpen: () -> Void
    @State private var dragX: CGFloat = 0

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
                if onDismiss == nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.trailing, onDismiss == nil ? 0 : 24)
            .card()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Hide \(month.formatted(.dateTime.month(.wide))) recap")
            }
        }
        // Swipe left to hide.
        .offset(x: dragX)
        .opacity(1 - Double(min(1, abs(dragX) / 300)))
        .simultaneousGesture(onDismiss == nil ? nil : DragGesture(minimumDistance: 20)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragX = min(0, value.translation.width)
                }
            }
            .onEnded { value in
                if value.translation.width < -110 {
                    withAnimation(.snappy) { dragX = -500 }
                    onDismiss?()
                } else {
                    withAnimation(.snappy) { dragX = 0 }
                }
            })
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
                        if let usualIncome = store.averageIncome(before: month), usualIncome > 0 {
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
                    LabeledContent("Fees & interest (minimize)") {
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
