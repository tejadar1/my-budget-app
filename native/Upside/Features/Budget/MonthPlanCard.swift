import SwiftUI

/// The top of Budget: income, minus bills, savings and trips, leaves
/// "to spend"; the big number is what's left of it.
struct MonthPlanCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    var onSavings: (() -> Void)? = nil
    /// The plan lines fold away so the card leads with one number, like Wallet.
    @AppStorage("planLinesShown") private var showLines = false

    var body: some View {
        let plan = store.monthPlan(month)
        let isPast = month < store.currentMonth
        VStack(alignment: .leading, spacing: 14) {
            header(plan, isPast: isPast)
            bar(plan)
            ownerLegend
            planToggle(plan)
            if showLines {
                lines(plan).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !isPast && plan.limitsOverBy > 0 && onSavings != nil { fitButton(plan) }
            if !isPast, let onSavings {
                Button(action: onSavings) {
                    Label("Adjust plan", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
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
                .heroNumber(38)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(subtitle(plan, isPast: isPast))
                .font(.subheadline).foregroundStyle(.white.opacity(0.86))
        }
    }

    @ViewBuilder private func bar(_ plan: MonthPlan) -> some View {
        if plan.toSpend > 0 {
            let fraction = Double(plan.everydaySpent) / Double(plan.toSpend)
            let parts = segments(store.spentByOwner(in: month, everydayOnly: true))
            SplitBar(fraction: fraction, segments: parts, fill: .white, track: .black.opacity(0.3),
                     height: 10, overflow: Theme.over)
        }
    }

    private func planToggle(_ plan: MonthPlan) -> some View {
        Button { withAnimation(.snappy) { showLines.toggle() } } label: {
            HStack(spacing: 6) {
                Text("\(Money.short(plan.toSpend)) to spend this month")
                    .font(.subheadline)
                Spacer()
                Text(showLines ? "Hide" : "Details").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(showLines ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(showLines ? "Hides the plan" : "Shows income, bills, savings and trips")
    }

    private func lines(_ plan: MonthPlan) -> some View {
        let checks = store.paychecks(in: month)
        let incomeNote: String? = plan.aboveIncomePlan > 0 ? "+\(Money.short(plan.aboveIncomePlan)) more than planned"
            : plan.incomePlanned != nil ? (plan.incomeReceived < plan.income ? "planned · \(Money.short(plan.incomeReceived)) in" : "planned")
            : plan.incomeIsUsual ? "usual"
            : (checks.extra > 0 ? "+\(checks.extra) extra paycheck" : nil)
        let billsNote = plan.billsDue > 0 ? "\(Money.short(plan.billsDue)) left to pay" : "paid"
        let monthly = plan.savings - plan.savingsExtra
        let savingsNote: String? = plan.savings == 0 ? (onSavings != nil ? "pay yourself first" : nil)
            : plan.savingsExtra == 0 ? "every month"
            : monthly == 0 ? "this month only"
            : "\(Money.short(monthly)) monthly + \(Money.short(plan.savingsExtra)) extra"
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
            if plan.cardPaydown > 0 || !store.creditCards.isEmpty {
                NavigationLink(value: Route.cards) {
                    line("Card paydown", -plan.cardPaydown, note: cardsNote(plan), chevron: true)
                }
                .buttonStyle(.plain)
            }
            if plan.trips > 0 { line("Trips", -plan.trips, note: nil) }
            Divider().overlay(Color.white.opacity(0.4))
            line("To spend", plan.toSpend, note: nil, bold: true)
            if month == store.currentMonth && plan.everydayLimits > 0 && plan.toSpend - plan.everydayLimits >= 1000 {
                Button { onSavings?() } label: {
                    line("Not in any limit", plan.toSpend - plan.everydayLimits, note: "put it toward savings", chevron: true)
                        .opacity(0.85)
                }
                .buttonStyle(.plain)
            }
            line("Spent", -plan.everydaySpent, note: "everyday")
        }
    }

    @ViewBuilder private var ownerLegend: some View {
        if store.people.isSetUp {
            let byOwner = store.spentByOwner(in: month, everydayOnly: true)
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
        // Limits change in Plan only, where the trade-offs are shown.
        Button { onSavings?() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your everyday limits are \(Money.short(plan.limitsOverBy)) more than you have")
                    .font(.subheadline.weight(.semibold))
                Text("Open Plan to fix it.")
                    .font(.footnote).opacity(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "paid $420 of $500", or what was charged vs paid; flags a growing balance.
    private func cardsNote(_ plan: MonthPlan) -> String {
        let paid = store.creditCards.reduce(0) { $0 + store.cardMonth($1, month).paid }
        let charged = store.creditCards.reduce(0) { $0 + store.cardMonth($1, month).charged }
        guard plan.cardPaydown > 0 else {
            if !store.growingCards.isEmpty && month == store.currentMonth { return "balance growing" }
            return "charged \(Money.short(charged)) · paid \(Money.short(paid))"
        }
        // Paydown is what's paid beyond new charges.
        let extra = store.extraCardPayoff(in: month)
        let short = plan.cardPaydown - extra
        if short <= 0 { return "\(Money.short(plan.cardPaydown)) paid down ✓" }
        if let days = plan.daysLeft, days <= 10 {
            return "\(Money.short(short)) more to pay by month end"
        }
        return "\(Money.short(max(0, extra))) of \(Money.short(plan.cardPaydown)) paid down"
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
                Text(note).font(.caption).opacity(0.9)
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
