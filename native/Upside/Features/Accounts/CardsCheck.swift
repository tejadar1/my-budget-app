import SwiftUI

/// "Am I paying off what I charge?" — per card: charged vs paid this
/// month, and whether the balance is growing. Separate from the budget,
/// so nothing is counted twice.
struct CardsCheck: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        if !store.creditCards.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Credit cards").font(.headline)
                    Spacer()
                    Text("separate from spending").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(store.creditCards) { card in
                    CardCheckRow(card: card)
                    if card.id != store.creditCards.last?.id { Divider() }
                }
            }
            .card()
        }
    }
}

struct CardCheckRow: View {
    @Environment(BudgetStore.self) private var store
    let card: Account

    var body: some View {
        let health = store.cardHealth(card)
        let growing = health.growthSinceThreeMonths > BudgetStore.cardGrowthAlert
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                OwnerBadge(owner: card.owner, people: store.people, size: 24)
                Text(card.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("owe \(Money.short(health.owedNow))").font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 16) {
                stat("Charged", health.thisMonth.charged)
                stat("Paid", health.thisMonth.paid)
                stat("Last month", health.lastMonth.charged)
            }
            Label {
                Text(growing
                     ? "Balance up \(Money.short(health.growthSinceThreeMonths)) since \(health.since.formatted(.dateTime.month(.wide))) — payments aren’t keeping up."
                     : health.paysInFull ? "Paying in full" : "Not fully paid last cycle")
                    .font(.footnote)
            } icon: {
                Image(systemName: growing ? "exclamationmark.triangle.fill"
                      : health.paysInFull ? "checkmark.circle.fill" : "clock.fill")
            }
            .foregroundStyle(growing ? Theme.over : health.paysInFull ? Theme.accent : Theme.warning)
        }
    }

    private func stat(_ label: String, _ value: Cents) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Money.short(value)).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

/// Small warning on the Budget screen when a card balance keeps growing.
struct CardWarningRow: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let cards = store.growingCards
        if let first = cards.first {
            let growth = store.cardHealth(first).growthSinceThreeMonths
            HStack(spacing: 14) {
                Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.over, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cards.count == 1 ? "\(first.name) balance is growing" : "\(cards.count) card balances are growing")
                        .font(.headline)
                    Text("Up \(Money.short(growth)) in three months. See Accounts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .card()
        }
    }
}
