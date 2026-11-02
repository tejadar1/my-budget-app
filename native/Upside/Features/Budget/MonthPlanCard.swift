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
        VStack(alignment: .leading, spacing: 14) {
            header(plan, isPast: isPast)
            bar(plan)
            lines(plan)
            ownerLegend
            if !isPast && plan.limitsOverBy > 0 { fitButton(plan) }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(plan), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func background(_ plan: MonthPlan) -> AnyShapeStyle {
        plan.leftToSpend >= 0 ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Color(hex: 0x7F1D1D))
    }

    private func header(_ plan: MonthPlan, isPast: Bool) -> some View {
        let caption = isPast ? month.formatted(.dateTime.month(.wide)).uppercased() : "THIS MONTH"
        let headline: String = plan.leftToSpend >= 0
            ? "\(Money.short(plan.leftToSpend)) \(isPast ? "under" : "left to spend")"
            : "\(Money.short(-plan.leftToSpend)) over"
        return VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.footnote.weight(.bold)).foregroundStyle(.white.opacity(0.82))
                .padding(.bottom, 10)
            Text(headline)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(subtitle(plan, isPast: isPast))
                .font(.subheadline).foregroundStyle(.white.opacity(0.86))
        }
    }

    @ViewBuilder private func bar(_ plan: MonthPlan) -> some View {
        if plan.toSpend > 0 {
            let fraction = Double(plan.everydaySpent) / Double(plan.toSpend)
            let parts = segments(store.spentByOwner(in: month))
            SplitBar(fraction: fraction, segments: parts, fill: .white, track: .black.opacity(0.3),
                     height: 10, overflow: Theme.over)
        }
    }

    private func lines(_ plan: MonthPlan) -> some View {
        let checks = store.paychecks(in: month)
        let incomeNote: String? = plan.incomeIsUsual ? "usual"
            : (checks.extra > 0 ? "+\(checks.extra) extra paycheck" : nil)
        let billsNote = plan.billsDue > 0 ? "\(Money.short(plan.billsDue)) still due" : "paid"
        let savingsNote: String? = plan.savings == 0 && onSavings != nil ? "set a goal" : nil
        return VStack(spacing: 8) {
            line("Income", plan.income, note: incomeNote)
            NavigationLink(value: Route.bills) {
                line("Bills", -plan.bills, note: billsNote, chevron: true)
            }
            .buttonStyle(.plain)
            Button { onSavings?() } label: {
                line("Savings", -plan.savings, note: savingsNote, chevron: onSavings != nil)
            }
            .buttonStyle(.plain)
            .disabled(onSavings == nil)
            if plan.trips > 0 { line("Trips", -plan.trips, note: nil) }
            Divider().overlay(Color.white.opacity(0.4))
            line("To spend", plan.toSpend, note: nil, bold: true)
            line("Spent", -plan.everydaySpent, note: "everyday")
        }
    }

    @ViewBuilder private var ownerLegend: some View {
        if store.people.isSetUp {
            let byOwner = store.spentByOwner(in: month)
            let owners = legendOwners(byOwner)
            HStack {
                ForEach(owners) { owner in
                    HStack(spacing: 6) {
                        Circle().fill(owner.color).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                        Text(store.people.name(owner))
                        Text(Money.short(byOwner[owner] ?? 0)).bold()
                    }
                    .font(.footnote)
                    if owner != owners.last { Spacer(minLength: 4) }
                }
            }
        }
    }

    private func legendOwners(_ byOwner: [Owner: Cents]) -> [Owner] {
        var owners: [Owner] = [.p1]
        if !store.people.p2.isEmpty { owners.append(.p2) }
        owners.append(.shared)
        if (byOwner[.unassigned] ?? 0) > 0 { owners.append(.unassigned) }
        return owners
    }

    private func fitButton(_ plan: MonthPlan) -> some View {
        Button { withAnimation { _ = store.fitLimitsToPlan(month) } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your everyday limits are \(Money.short(plan.limitsOverBy)) more than you have")
                    .font(.subheadline.weight(.semibold))
                Text("Tap to trim them to fit, mostly from shopping and dining.")
                    .font(.footnote).opacity(0.86)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ plan: MonthPlan, isPast: Bool) -> String {
        if isPast { return "Spent \(Money.short(plan.everydaySpent)) of \(Money.short(plan.toSpend)) to spend" }
        if plan.leftToSpend < 0 { return "This comes out of savings and trips." }
        guard let days = plan.daysLeft, let perDay = plan.perDay else { return "" }
        return days <= 1 ? "Last day of the month" : "\(days) days · about \(Money.short(perDay)) a day"
    }

    private func line(_ label: String, _ value: Cents, note: String?, bold: Bool = false, chevron: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label).font(bold ? Font.subheadline.weight(.bold) : Font.subheadline)
            if let note {
                Text(note).font(.caption).opacity(0.75)
            }
            Spacer()
            Text(amountText(value))
                .font(bold ? Font.subheadline.weight(.bold).monospacedDigit() : Font.subheadline.monospacedDigit())
            if chevron {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).opacity(0.6)
            }
        }
        .contentShape(Rectangle())
    }

    private func amountText(_ value: Cents) -> String {
        value < 0 ? "–" + Money.short(-value) : Money.short(value)
    }
}
