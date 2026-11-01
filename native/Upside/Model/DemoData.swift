import Foundation

/// Realistic sample data: two people, a shared bills account, four months
/// of spending. Used for "Try the demo" and for screenshots.
enum DemoData {
    static func make(now: Date = Date(), calendar: Calendar = .current) -> BudgetData {
        var rng = SeededGenerator(seed: 42)
        var data = BudgetData()
        data.people = People(p1: "Ron", p2: "Ana")
        data.bankConnected = true
        data.lastBankSync = now.addingTimeInterval(-3600)

        data.accounts = [
            Account(id: "ron-checking", name: "Total Checking", institution: "Chase",
                    kind: .checking, balance: 482_013, owner: .p1),
            Account(id: "ron-card", name: "Robinhood Gold Card", institution: "Robinhood",
                    kind: .credit, balance: -61_244, owner: .p1),
            Account(id: "ana-checking", name: "Advantage Checking", institution: "Bank of America",
                    kind: .checking, balance: 361_550, owner: .p2),
            Account(id: "joint", name: "Joint Checking", institution: "Chase",
                    kind: .checking, balance: 214_020, owner: .shared),
            Account(id: "ally", name: "Online Savings", institution: "Ally Bank",
                    kind: .savings, balance: 1_390_000, owner: .shared),
        ]

        let limits: [String: Cents] = [
            "groceries": 60_000, "dining": 30_000, "gas": 25_000, "shopping": 40_000,
            "entertainment": 15_000, "health": 10_000, "housing": 220_000,
            "utilities": 18_000, "phone": 19_000, "subscriptions": 6_000,
        ]
        for i in data.categories.indices {
            data.categories[i].limit = limits[data.categories[i].id]
        }

        // (category, payees, owners, per-month count, typical amount $)
        let patterns: [(String, [String], [String], Int, Double)] = [
            ("groceries", ["Kroger", "Trader Joe's", "Whole Foods", "Costco"],
             ["ron-card", "ana-checking", "joint"], 9, 62),
            ("dining", ["Chipotle", "Starbucks", "Sweetgreen", "Local Diner"],
             ["ron-card", "ana-checking"], 10, 24),
            ("gas", ["Shell", "Exxon", "Uber"], ["ron-card", "ana-checking"], 5, 42),
            ("shopping", ["Amazon", "Target", "Nordstrom"], ["ana-checking", "ron-card"], 5, 58),
            ("entertainment", ["AMC Theatres", "Ticketmaster"], ["ron-card", "ana-checking"], 2, 38),
            ("health", ["CVS Pharmacy", "Walgreens"], ["ana-checking"], 2, 28),
            ("subscriptions", ["Netflix", "Spotify", "iCloud"], ["joint"], 3, 14),
            ("utilities", ["Duke Energy", "City Water"], ["joint"], 2, 82),
            ("phone", ["Verizon", "Spectrum Internet"], ["joint"], 2, 88),
            ("housing", ["Rent - Parkview Apts"], ["joint"], 1, 2200),
        ]

        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let today = calendar.component(.day, from: now)
        var transactions: [Transaction] = []
        var counter = 0

        for monthOffset in -3...0 {
            let month = calendar.date(byAdding: .month, value: monthOffset, to: thisMonth)!
            let days = calendar.range(of: .day, in: .month, for: month)!.count
            let lastDay = monthOffset == 0 ? max(1, today) : days

            // Paychecks into each person's checking, then transfers to joint.
            for (account, amount) in [("ron-checking", 3_850.0), ("ana-checking", 3_420.0)] {
                for payday in [1, 15] where payday <= lastDay {
                    counter += 1
                    transactions.append(Transaction(
                        id: "demo-\(counter)", accountId: account,
                        date: calendar.date(byAdding: .day, value: payday - 1, to: month)!,
                        amount: Int(amount * 100), payee: "Payroll Deposit",
                        categoryId: "income"))
                }
            }

            for (category, payees, accounts, count, typical) in patterns {
                // The current month is only partly done.
                let n = monthOffset == 0 ? max(1, count * lastDay / days) : count
                for k in 0..<n {
                    counter += 1
                    let day = category == "housing" ? 1 : Int.random(in: 1...lastDay, using: &rng)
                    let variation = Double.random(in: 0.6...1.45, using: &rng)
                    let amount = category == "housing" ? typical : (typical * variation)
                    transactions.append(Transaction(
                        id: "demo-\(counter)",
                        accountId: accounts[k % accounts.count],
                        date: calendar.date(byAdding: .day, value: day - 1, to: month)!,
                        amount: -Int((amount * 100).rounded()),
                        payee: payees[Int.random(in: 0..<payees.count, using: &rng)],
                        categoryId: category))
                }
            }
        }

        // A few new ones the bank couldn't categorize yet.
        for (payee, amount, account) in [("SQ *BLUE BOTTLE", 7.25, "ron-card"),
                                         ("PAYPAL *ETSY", 34.10, "ana-checking"),
                                         ("TST* HARBOR GRILL", 61.80, "ron-card")] {
            counter += 1
            transactions.append(Transaction(
                id: "demo-\(counter)", accountId: account,
                date: calendar.date(byAdding: .day, value: max(0, today - 2), to: thisMonth)!,
                amount: -Int(amount * 100), payee: payee, categoryId: nil))
        }

        // A prepaid trip.
        let trip = Trip(id: "miami", name: "Miami",
                        start: calendar.date(byAdding: .month, value: 4, to: thisMonth)!,
                        end: calendar.date(byAdding: .day, value: 4,
                                           to: calendar.date(byAdding: .month, value: 4, to: thisMonth)!)!,
                        budget: 250_000)
        data.trips = [trip]
        counter += 1
        transactions.append(Transaction(
            id: "demo-\(counter)", accountId: "ron-card",
            date: calendar.date(byAdding: .day, value: max(0, today - 5), to: thisMonth)!,
            amount: -82_000, payee: "JetBlue Airways", categoryId: "travel", tripId: "miami"))

        data.transactions = transactions.sorted { $0.date > $1.date }
        data.rules = patterns.flatMap { pattern in
            pattern.1.map { PayeeRule(payeeKey: BudgetStore.payeeKey($0), categoryId: pattern.0) }
        }
        return data
    }
}

/// Deterministic random numbers so demo screenshots are stable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
