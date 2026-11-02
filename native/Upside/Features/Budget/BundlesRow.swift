import SwiftUI

/// Two bundles with opposite goals: grow what you save and invest, keep
/// fees and interest at $0.
struct BundlesRow: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let saved = store.savedAndInvested(in: month)
        let payoff = store.extraCardPayoff(in: month)
        let usualSaved = store.usual({ store.savedAndInvested(in: $0) }, before: month)
        let fees = store.minimizeSpent(in: month)
        let usualFees = store.usual({ store.minimizeSpent(in: $0) }, before: month)
        let hasSavingsAccounts = store.visibleAccounts.contains { $0.kind == .savings || $0.kind == .investment }

        HStack(alignment: .top, spacing: 12) {
            if month != store.currentMonth && (hasSavingsAccounts || payoff > 0) {
                tile(caption: "MAXIMIZE", title: "Saved & invested",
                     value: Money.short(saved),
                     color: saved > 0 && saved >= (usualSaved ?? 0) ? Theme.accent : .primary,
                     notes: [usualSaved.map { "usual \(Money.short($0))" },
                             payoff > 0 ? "+\(Money.short(payoff)) paid down on cards" : nil].compactMap { $0 })
            }
            NavigationLink(value: Route.category(feesCategory(in: month), month)) {
                tile(caption: "MINIMIZE", title: "Fees & interest",
                     value: Money.short(fees),
                     color: fees > 0 ? Theme.over : Theme.accent,
                     notes: [fees == 0 ? "none this month" : usualFees.map { "usual \(Money.short($0))" }].compactMap { $0 },
                     chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens the fee category with the most this month.
    private func feesCategory(in month: Date) -> String {
        store.expenseCategories.filter(\.aimsForZero)
            .max { store.spent($0.id, in: month) < store.spent($1.id, in: month) }?.id ?? "fees"
    }

    private func tile(caption: String, title: String, value: String, color: Color,
                      notes: [String], chevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(caption).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            Text(title).font(.subheadline.weight(.semibold))
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(color)
                .monospacedDigit()
            ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}
