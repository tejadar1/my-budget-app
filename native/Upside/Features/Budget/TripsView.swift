import SwiftUI

/// Trips live outside everyday spending, so a vacation month doesn't look
/// like overspending and doesn't skew your averages.
struct TripsSection: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        if !store.data.trips.isEmpty {
            SectionTitle(text: "Trips", trailing: "kept out of everyday")
            ForEach(store.data.trips) { trip in
                NavigationLink(value: Route.trip(trip.id)) {
                    TripCard(trip: trip)
                }
                .buttonStyle(.plain)
            }
        }
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
        max(0, -tripTransactions(trip.id).filter { $0.date < trip.start }.reduce(0) { $0 + $1.amount })
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
                Text("\(Money.short(store.tripSpent(trip.id))) of \(Money.short(trip.budget ?? 0))")
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
    let tripId: String

    var body: some View {
        if let trip = store.data.trips.first(where: { $0.id == tripId }) {
            let spent = store.tripSpent(trip.id)
            let prepaid = store.tripPrepaid(trip)
            let budget = trip.budget ?? 0
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(dateRange(trip)).foregroundStyle(.secondary)
                        Text("\(Money.short(spent)) of \(Money.short(budget))")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                        if budget > 0 {
                            SplitBar(fraction: Double(spent) / Double(budget), fill: .orange, height: 10)
                        }
                        HStack {
                            Text("Prepaid \(Money.short(prepaid))")
                            Spacer()
                            Text("During trip \(Money.short(spent - prepaid))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Purchases") {
                    ForEach(store.tripTransactions(trip.id)) { t in
                        TransactionRow(transaction: t)
                    }
                }
            }
            .navigationTitle(trip.name)
        }
    }
}
