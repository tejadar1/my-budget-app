import SwiftUI

/// The top of Budget: income, minus bills, savings and trips, leaves
/// "to spend"; the big number is what's left of it.
struct MonthPlanCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    var onSavings: (() -> Void)? = nil

    var body: some View {
        let plan = store.monthPlan(month)
        let isPast = month < store.currentMonth
        let byOwner = store.spentByOwner(in: month)
        let checks = store.paychecks(in: month)

        VStack(alignment: .leading, spacing: 14) {
            Text(isPast ? month.formatted(.dateTime.month(.wide)).uppercased() : "THIS MONTH")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.leftToSpend >= 0
                     ? "\(Money.short(plan.leftToSpend)) \(isPast ? "under" : "left to spend")"
                     : "\(Money.short(-plan.leftToSpend)) over")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(subtitle(plan, isPast: isPast))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.86))
            }

            if plan.toSpend > 0 {
                SplitBar(fraction: Double(plan.everydaySpent) / Double(plan.toSpend),
                         segments: segments(byOwner), fill: .white, track: .black.opacity(0.3),
                         height: 10, overflow: Theme.over)
            }

            // The plan, top-down.
            VStack(spacing: 8) {
                line("Income", plan.income,
                     note: plan.incomeIsUsual ? "usual" : (checks.extra > 0 ? "+\(checks.extra) extra paycheck" : nil))
                NavigationLink(value: Route.bills) {
                    line("Bills", -plan.bills,
                         note: plan.billsDue > 0 ? "\(Money.short(plan.billsDue)) still due" : "paid", chevron: true)
                }
                .buttonStyle(.plain)
                Button { onSavings?() } label: {
                    line("Savings", -plan.savings,
                         note: plan.savings == 0 && onSavings != nil ? "set a goal" : nil, chevron: onSavings != nil)
                }
                .buttonStyle(.plain)
                .disabled(onSavings == nil)
                if plan.trips > 0 { line("Trips", -plan.trips, note: nil) }
                Divider().overlay(.white.opacity(0.4))
                line("To spend", plan.toSpend, note: nil, bold: true)
                line("Spent", -plan.everydaySpent, note: "everyday")
            }

            if store.people.isSetUp {
                let owners: [Owner] = [.p1] + (store.people.p2.isEmpty ? [] : [.p2]) + [.shared]
                    + ((byOwner[.unassigned] ?? 0) > 0 ? [.unassigned] : [])
                HStack {
                    ForEach(owners) { owner in
                        HStack(spacing: 6) {
                            Circle().fill(owner.color).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                            Text(store.people.name(owner))
                            Text(Money.short(byOwner[owner] ?? 0)).bold()
                        }
                        .font(.footnote)
                        if owner != owners.last { Spacer(minLength: 4) }
                    }
                }
            }

            if !isPast && plan.limitsOverBy > 0 {
                Button { withAnimation { store.fitLimitsToPlan(month) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your everyday limits are \(Money.short(plan.limitsOverBy)) more than you have")
                            .font(.subheadline.weight(.semibold))
                        Text("Tap to trim them to fit, mostly from shopping and dining.")
                            .font(.footnote).opacity(0.86)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plan.leftToSpend >= 0 ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Color(hex: 0x7F1D1D)),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func subtitle(_ plan: MonthPlan, isPast: Bool) -> String {
        if isPast { return "Spent \(Money.short(plan.everydaySpent)) of \(Money.short(plan.toSpend)) to spend" }
        if plan.leftToSpend < 0 { return "This comes out of savings and trips." }
        guard let days = plan.daysLeft, let perDay = plan.perDay else { return "" }
        return days <= 1 ? "Last day of the month" : "\(days) days · about \(Money.short(perDay)) a day"
    }

    private func line(_ label: String, _ value: Cents, note: String?, bold: Bool = false, chevron: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label).font(bold ? .subheadline.weight(.bold) : .subheadline)
            if let note {
                Text(note).font(.caption).opacity(0.75)
            }
            Spacer()
            Text(value < 0 ? "–\(Money.short(-value))" : Money.short(value))
                .font(bold ? .subheadline.weight(.bold).monospacedDigit() : .subheadline.monospacedDigit())
            if chevron {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).opacity(0.6)
            }
        }
        .contentShape(Rectangle())
    }
}
