import SwiftUI

/// Trips live outside everyday spending, so a vacation month doesn't look
/// like overspending and doesn't skew your averages.
struct TripsSection: View {
    @Environment(BudgetStore.self) private var store
    @State private var showNew = false

    var body: some View {
        SectionTitle(text: "Trips", trailing: "kept out of everyday")
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
