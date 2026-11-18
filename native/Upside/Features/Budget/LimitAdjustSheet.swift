import SwiftUI

/// Change one category's limit from its own screen. It has to fit what
/// there is to spend: going past it asks you to lower something else first.
struct LimitAdjustSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryId: String
    @State private var dollars = 0
    @State private var startDollars = 0
    @State private var thisMonthOnly = false
    /// Lowered elsewhere to make room: category id → cents.
    @State private var taking: [String: Cents] = [:]

    private var month: Date { store.currentMonth }

    var body: some View {
        let category = store.category(categoryId)
        let monthName = month.formatted(.dateTime.month(.wide))
        let value = dollars * 100
        let over = store.limitOver(categoryId, to: value, taking: taking, in: month)
        let spare = store.limitSpare(categoryId, to: value, taking: taking, in: month)
        let spent = store.spent(categoryId, in: month)
        let usual = store.averageSpent(categoryId, before: month)
        // Lowering is always fine; raising has to fit.
        let canSave = dollars != startDollars || !taking.isEmpty
        let fits = over == 0 || dollars <= startDollars

        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Limit")
                        Spacer()
                        TextField("No limit", value: $dollars, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold)).frame(maxWidth: 160)
                    }
                    Picker("Applies to", selection: $thisMonthOnly) {
                        Text("From now on").tag(false)
                        Text("Just \(monthName)").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(category?.name ?? "Limit")
                } footer: {
                    Text("Spent \(Money.short(spent)) so far" + (usual.map { " · usual \(Money.short($0))" } ?? "")
                         + (thisMonthOnly ? ". Next month goes back to \(Money.short((category?.limit ?? 0))).": "."))
                }

                Section {
                    if over == 0 {
                        Label(spare > 0 ? "Fits. \(Money.short(spare)) still not in any limit."
                                        : "Fits exactly: every dollar is in a limit.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    } else {
                        Label("\(Money.short(over)) more than you have", systemImage: "exclamationmark.circle.fill")
                            .font(.headline).foregroundStyle(Theme.over)
                        Text(dollars > startDollars
                             ? "To raise this, lower something else first:"
                             : "\(monthName) was already past what you have before this change. Lowering this helps.")
                            .font(.subheadline)
                        if dollars > startDollars {
                            let room = store.roomLeft(in: month, excluding: [categoryId])
                                .map { ($0, $0.room - (taking[$0.id] ?? 0)) }
                                .filter { $0.1 >= 1_000 }
                            if room.isEmpty {
                                Text("No category has room left this month. Raise it by less, or put less toward savings, cards or trips in Plan.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(room.prefix(5), id: \.0.id) { source, left in
                                let take = min(left, (over + 999) / 1_000 * 1_000)
                                Button {
                                    Haptics.tap()
                                    withAnimation { taking[source.id, default: 0] += take }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Take \(Money.short(take)) from \(source.name)").fontWeight(.semibold)
                                        Text("\(Money.short(left)) left there").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .tint(.primary)
                            }
                        }
                    }
                    if !taking.isEmpty {
                        ForEach(taking.sorted { $0.key < $1.key }, id: \.key) { id, amount in
                            LabeledContent(store.category(id)?.name ?? id, value: "−\(Money.short(amount))")
                        }
                        Button("Put those back") { withAnimation { taking = [:] } }
                            .font(.footnote.weight(.semibold))
                    }
                } header: {
                    Text("Does it fit?")
                } footer: {
                    Text("Limits share what's left after bills, savings, cards and trips (\(Money.short(store.monthPlan(month).toSpend)) in \(monthName)). Money already spent counts where it's more than a limit.")
                }
            }
            .navigationTitle("Adjust limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.adjustLimit(categoryId, to: value, taking: taking, thisMonthOnly: thisMonthOnly, in: month)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(!canSave || !fits)
                }
            }
            .onAppear {
                let current = store.category(categoryId).flatMap { store.plannedLimit($0, in: month) } ?? 0
                dollars = current / 100
                startDollars = dollars
                // Already changed for this month only: keep editing it that way.
                thisMonthOnly = store.plan(for: month)?.limits[categoryId] != nil
            }
        }
    }
}
