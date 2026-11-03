import SwiftUI

/// Trips live outside everyday spending, so a vacation month doesn't look
/// like overspending and doesn't skew your averages.
struct TripsSection: View {
    @Environment(BudgetStore.self) private var store
    @State private var showNew = false
    @State private var editFund = false

    var body: some View {
        SectionTitle(text: "Trips", trailing: "kept out of everyday")
        Button { editFund = true } label: { TripFundCard() }
            .buttonStyle(.plain)
            .sheet(isPresented: $editFund) { TripFundEditor() }
        ForEach(store.data.trips) { trip in
            NavigationLink(value: Route.trip(trip.id)) {
                TripCard(trip: trip)
            }
            .buttonStyle(.plain)
        }
        Button { showNew = true } label: {
            Label("New trip", systemImage: "airplane.departure")
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .sheet(isPresented: $showNew) { TripEditor(trip: nil) }
    }
}

extension BudgetStore {
    /// Trip fund: what's been set aside since it started, minus every trip
    /// purchase since then (prepaid flights included).
    func tripFundBalance() -> Cents? {
        guard let fund = data.tripFund else { return nil }
        let start = monthStart(fund.start)
        let spent = -data.transactions
            .filter { $0.amount != 0 && $0.date >= start && $0.tripId != nil && !$0.isTransfer }
            .reduce(0) { $0 + $1.amount }
        return fund.startingBalance + tripFundAdded(since: start) - spent
    }

    /// What actually went into the fund: the monthly amount for this month
    /// (planned), and for finished months only what that month had left over.
    /// Overspending a month means less, or nothing, for trips.
    func tripFundAdded(since start: Date) -> Cents {
        guard let fund = data.tripFund else { return 0 }
        var total = 0
        var month = start
        while month <= currentMonth {
            if month == currentMonth {
                total += fund.monthly
            } else {
                let left = income(in: month) - totalSpent(in: month)
                total += min(fund.monthly, max(0, left))
            }
            month = self.month(1, from: month)
        }
        return total
    }

    /// Months since the fund started that couldn't put the full amount in.
    func tripFundShortMonths() -> Int {
        guard let fund = data.tripFund else { return 0 }
        var count = 0
        var month = monthStart(fund.start)
        while month < currentMonth {
            if income(in: month) - totalSpent(in: month) < fund.monthly { count += 1 }
            month = self.month(1, from: month)
        }
        return count
    }

    // MARK: Paying for a trip over time

    /// A trip is paid for evenly from the month of its first purchase (or
    /// now, if nothing's bought yet) through the month after it ends.
    /// Cost is its budget, or what's been spent if that's more.
    func tripSchedule(_ trip: Trip) -> (start: Date, end: Date, perMonth: Cents)? {
        let cost = max(trip.budget ?? 0, tripSpent(trip.id))
        guard cost > 0 else { return nil }
        let first = tripTransactions(trip.id).map(\.date).min()
        let start = monthStart(min(first ?? now(), now()))
        let end = month(1, from: monthStart(trip.end))
        let months = max(1, (calendar.dateComponents([.month], from: start, to: end).month ?? 0) + 1)
        return (start, end, cost / months)
    }

    /// What trips need set aside in a month: a fixed trip fund if you set
    /// one, otherwise each trip's share for months it's being paid off.
    func tripSetAside(in month: Date) -> Cents {
        if let fund = data.tripFund {
            return monthStart(fund.start) <= month ? fund.monthly : 0
        }
        return tripScheduleSetAside(in: month)
    }

    /// Each trip's own monthly share, ignoring any fixed trip fund.
    func tripScheduleSetAside(in month: Date) -> Cents {
        data.trips.compactMap(tripSchedule).filter { $0.start <= month && month <= $0.end }
            .reduce(0) { $0 + $1.perMonth }
    }

    // MARK: Keep first, then spend

    /// Savings goal plus trips for a month: kept before spending.
    func setAside(in month: Date) -> Cents {
        let saving = plan.map { isInMonth($0.month, month) ? $0.goal : 0 } ?? 0
        return saving + tripSetAside(in: month)
    }

    /// What can still be spent this month and keep the set-asides: income
    /// (your usual, until this month's is in) minus spending so far, bills
    /// still due, and the set-asides. Negative means it's eating into them.
    func safeToSpend(in month: Date) -> Cents? {
        let income = month == currentMonth ? max(self.income(in: month), averageIncome(before: month) ?? 0)
                                           : self.income(in: month)
        guard income > 0 else { return nil }
        let billsDue = month == currentMonth
            ? recurringCharges().filter { !$0.paidThisMonth }.reduce(0) { $0 + $1.amount } : 0
        return income - totalSpent(in: month) - billsDue - setAside(in: month)
    }

    /// For a trip with a budget that hasn't started: covered by the fund,
    /// or the monthly amount that would cover it by the start date.
    func tripFundNeed(_ trip: Trip) -> (covered: Bool, perMonth: Cents)? {
        guard let budget = trip.budget, let balance = tripFundBalance(), trip.start > now() else { return nil }
        let remaining = max(0, budget - tripSpent(trip.id))
        if balance >= remaining { return (true, 0) }
        let months = max(1, calendar.dateComponents([.month], from: currentMonth, to: monthStart(trip.start)).month ?? 1)
        return (false, (remaining - max(0, balance)) / months)
    }

    func tripTransactions(_ tripId: String) -> [Transaction] {
        data.transactions.filter { $0.tripId == tripId }
    }

    func tripSpent(_ tripId: String) -> Cents {
        max(0, -tripTransactions(tripId).reduce(0) { $0 + $1.amount })
    }

    /// Paid before the trip started (flights, hotels).
    func tripPrepaid(_ trip: Trip) -> Cents {
        let start = calendar.startOfDay(for: trip.start)
        return max(0, -tripTransactions(trip.id).filter { $0.date < start }.reduce(0) { $0 + $1.amount })
    }
}

struct TripCard: View {
    @Environment(BudgetStore.self) private var store
    let trip: Trip

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [Color(hex: 0xFF6B9A), Color(hex: 0xFF9F0A), Color(hex: 0xFFD60A)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 88)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "airplane")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(.headline)
                Text(dateRange(trip)).font(.footnote).foregroundStyle(.secondary)
                Text(trip.budget.map { "\(Money.short(store.tripSpent(trip.id))) of \(Money.short($0))" }
                     ?? "\(Money.short(store.tripSpent(trip.id))) spent")
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
                if let need = store.tripFundNeed(trip) {
                    Text(need.covered ? "The trip fund covers it" : "\(Money.short(need.perMonth))/month more to cover it")
                        .font(.caption)
                        .foregroundStyle(need.covered ? Theme.accent : Theme.warning)
                } else if store.data.tripFund == nil, let plan = store.tripSchedule(trip), plan.end >= store.currentMonth {
                    Text("Saving \(Money.short(plan.perMonth))/month · \(plan.start.formatted(.dateTime.month(.abbreviated)))–\(plan.end.formatted(.dateTime.month(.abbreviated)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 14)
        }
        .frame(minHeight: 88)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

func dateRange(_ trip: Trip) -> String {
    "\(trip.start.formatted(.dateTime.month(.abbreviated).day()))–\(trip.end.formatted(.dateTime.month(.abbreviated).day().year()))"
}

struct TripView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripId: String
    @State private var isEditing = false

    var body: some View {
        if let trip = store.data.trips.first(where: { $0.id == tripId }) {
            let spent = store.tripSpent(trip.id)
            let prepaid = store.tripPrepaid(trip)
            let during = store.purchasesDuring(trip)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(dateRange(trip)).foregroundStyle(.secondary)
                        Text(trip.budget.map { "\(Money.short(spent)) of \(Money.short($0))" } ?? "\(Money.short(spent)) spent")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                        if let budget = trip.budget, budget > 0 {
                            SplitBar(fraction: Double(spent) / Double(budget),
                                     fill: spent > budget ? Theme.over : .orange, height: 10)
                        }
                        HStack {
                            Text("Prepaid \(Money.short(prepaid))")
                            Spacer()
                            Text("During and after \(Money.short(spent - prepaid))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                if !during.isEmpty {
                    Section {
                        Button {
                            withAnimation { store.tagPurchases(during.map(\.id), to: trip.id) }
                        } label: {
                            Label("Add \(during.count) purchase\(during.count == 1 ? "" : "s") from \(dateRange(trip))",
                                  systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text("Purchases made during the trip, \(Money.short(-during.reduce(0) { $0 + $1.amount })) in total. Bills are left out.")
                    }
                }

                Section("Purchases") {
                    let purchases = store.tripTransactions(trip.id)
                    if purchases.isEmpty {
                        Text("Tag flights, hotels and anything bought on the trip. Tap a purchase anywhere in Upside and pick this trip.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(purchases) { t in
                        TransactionRow(transaction: t)
                            .swipeActions {
                                Button("Remove") { store.setTrip(t.id, nil) }
                            }
                    }
                }
            }
            .navigationTitle(trip.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { isEditing = true } }
            }
            .sheet(isPresented: $isEditing) { TripEditor(trip: trip) }
        } else {
            ContentUnavailableView("Trip deleted", systemImage: "airplane")
        }
    }
}

/// New or edit: name, dates and an optional budget.
struct TripEditor: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip?
    var onCreate: ((Trip) -> Void)? = nil

    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(4 * 86_400)
    @State private var budget = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Miami", text: $name)
                        .textInputAutocapitalization(.words)
                    DatePicker("Starts", selection: $start, displayedComponents: .date)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
                }
                Section {
                    HStack {
                        Text("Budget")
                        Spacer()
                        TextField("Optional", value: $budget, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Flights and hotels you prepay months ahead still count toward this trip.")
                }
                if let trip {
                    Section {
                        Button("Delete trip", role: .destructive) {
                            store.deleteTrip(trip.id)
                            dismiss()
                        }
                    } footer: {
                        Text("Its purchases go back to their everyday categories.")
                    }
                }
            }
            .navigationTitle(trip == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let trip {
                    name = trip.name
                    start = trip.start
                    end = trip.end
                    budget = (trip.budget ?? 0) / 100
                }
            }
        }
    }

    private func save() {
        let saved = Trip(id: trip?.id ?? UUID().uuidString,
                         name: name.trimmingCharacters(in: .whitespaces),
                         start: start, end: max(start, end),
                         budget: budget > 0 ? budget * 100 : nil)
        store.saveTrip(saved)
        if trip == nil { onCreate?(saved) }
        dismiss()
    }
}

/// "Trip fund $1,450 · +$300 a month", or an offer to start one.
struct TripFundCard: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "suitcase.fill")
                .font(.title3).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if let fund = store.data.tripFund, let balance = store.tripFundBalance() {
                    Text(balance >= 0 ? "Trip fund \(Money.short(balance))" : "Trip fund short \(Money.short(-balance))")
                        .font(.headline)
                        .foregroundStyle(balance >= 0 ? Color.primary : Theme.over)
                    let short = store.tripFundShortMonths()
                    Text(short == 0 ? "+\(Money.short(fund.monthly)) a month · trip purchases come out of it"
                                    : "+\(Money.short(fund.monthly)) a month · \(short) month\(short == 1 ? "" : "s") overspent, so less went in")
                        .font(.footnote).foregroundStyle(short == 0 ? Color.secondary : Theme.warning)
                } else {
                    Text("Start a trip fund").font(.headline)
                    Text("Set money aside each month; trips draw it down.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .card()
    }
}

struct TripFundEditor: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var monthly = 0
    @State private var starting = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Each month")
                        Spacer()
                        TextField("Amount", value: $monthly, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
                    }
                    HStack {
                        Text("Already saved")
                        Spacer()
                        TextField("$0", value: $starting, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
                    }
                } footer: {
                    Text("Kept before spending on the Budget page. A month only adds what it actually has left over, so overspending means less for trips. Anything tagged to a trip comes out of the fund, flights booked months ahead included.")
                }
                if store.data.tripFund != nil {
                    Section {
                        Button("Stop the trip fund", role: .destructive) {
                            store.data.tripFund = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Trip fund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let start = store.data.tripFund?.start ?? store.currentMonth
                        store.data.tripFund = TripFund(monthly: monthly * 100, start: start, startingBalance: starting * 100)
                        dismiss()
                    }
                    .disabled(monthly <= 0)
                }
            }
            .onAppear {
                monthly = (store.data.tripFund?.monthly ?? 0) / 100
                starting = (store.data.tripFund?.startingBalance ?? 0) / 100
            }
        }
    }
}
