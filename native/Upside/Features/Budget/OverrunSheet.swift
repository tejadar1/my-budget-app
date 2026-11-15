import SwiftUI

/// Overspending, called out: what went over and why, what it costs, and a
/// choice of what gives. Limits aren't raised to hide it.
struct OverrunSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let month: Date
    /// The category the row was about; nil for all of them.
    let focus: String?

    var body: some View {
        let cost = store.overrunCost(in: month)
        let overs = cost.overruns
        let monthName = month.formatted(.dateTime.month(.wide))
        let names = cost.options.map(\.source.noun)

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(overs.count == 1 ? "\(overs[0].category.name) is \(Money.short(cost.total)) over"
                             : overs.isEmpty ? "Nothing is over" : "\(overs.count) categories are \(Money.short(cost.total)) over")
                            .font(.title2.bold())
                        Text("Past the limits you set for \(monthName). It stays that way: the limit isn't raised to hide it.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    ForEach(overs) { over in
                        NavigationLink {
                            CategoryDetailView(categoryId: over.id, month: month)
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(categoryId: over.id, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(over.category.name)
                                    Text(detail(over.id)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(Money.short(over.over))").fontWeight(.semibold).foregroundStyle(Theme.over)
                            }
                        }
                    }
                }

                if cost.total > 0 {
                    Section {
                        if cost.fromUnassigned > 0 {
                            Label("Money not in a limit covers \(Money.short(cost.fromUnassigned)) of it. That's \(Money.short(cost.fromUnassigned)) less left at the end of \(monthName).",
                                  systemImage: "tray.fill")
                                .font(.subheadline)
                        }
                        ForEach(cost.cuts) { cut in
                            HStack {
                                Label("You " + cut.source.done(cut.amount) + " this month", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                                Button("Undo") { withAnimation { store.undoOverspendingCut(cut.id, in: month) } }
                                    .font(.footnote.weight(.semibold)).buttonStyle(.borderless)
                            }
                        }
                        if cost.needed > 0 {
                            Text(cost.fromUnassigned > 0 || cost.paid > 0
                                 ? "\(Money.short(cost.needed)) still has to come from somewhere."
                                 : "Your limits already use everything left after savings, cards and trips. To cover \(Money.short(cost.needed)) this month, something has to give:")
                                .font(.subheadline.weight(.semibold))
                            ForEach(cost.options) { option in
                                Button {
                                    withAnimation {
                                        store.payForOverspending(from: option.source, amount: option.amount,
                                                                 categoryId: focus ?? overs.first?.id, in: month)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.source.action(option.amount) + (option.amount < cost.needed ? " (all of it)" : ""))
                                            .fontWeight(.semibold)
                                        Text("\(Money.short(option.planned)) → \(Money.short(option.planned - option.amount)) this month")
                                            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spend less elsewhere").fontWeight(.semibold)
                                Text(elsewhere(cost.room))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } else if cost.paid > 0 || cost.fromUnassigned > 0 {
                            Text("It's paid for. It still shows as over, and the recap will name it.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("What it costs")
                    } footer: {
                        Text(cost.needed > 0
                             ? "Starts from the bottom of your plan: \(names.joined(separator: ", ")). Savings comes last and is never chosen for you. Only \(monthName) changes."
                             : "Only \(monthName) changes; next month is back to your plan.")
                    }
                }

                Section {
                    Text(store.businessOwed > 0
                         ? "\(Money.short(store.businessOwed)) of business purchases is waiting to be paid back. It isn't counted here, and nothing has to give for it."
                         : "Business purchases aren't counted. If one of these was for work, open it and turn on Business expense: you'll be paid back, so nothing has to give.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Over the plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// "14 purchases, biggest $95 at Nobu"
    private func detail(_ categoryId: String) -> String {
        let mine = store.spendingTransactions.filter {
            $0.categoryId == categoryId && store.isInMonth($0.date, month) && $0.amount < 0 && $0.tripId == nil
        }
        let spent = store.spent(categoryId, in: month)
        var line = "Spent \(Money.short(spent)) · \(mine.count) purchase\(mine.count == 1 ? "" : "s")"
        if mine.count > 1, let big = mine.min(by: { $0.amount < $1.amount }) {
            line += ", biggest \(Money.short(-big.amount)) at \(Merchant.clean(big.payee))"
        }
        return line
    }

    private func elsewhere(_ room: [BudgetStore.CoverSource]) -> String {
        guard !room.isEmpty else { return "No category has room left this month. Nothing changes; it stays called out." }
        let list = room.prefix(3).map { "\($0.name) has \(Money.short($0.room)) left" }
        return list.joined(separator: ", ") + ". Nothing changes; it stays called out."
    }
}
