import XCTest
@testable import Upside

/// Property tests: many made-up households, each put through a run of
/// random everyday actions, checking after every step that every screen
/// agrees on the money and the sums add up. A failure names the household
/// (seed) and the step, so it can be replayed.
final class BudgetInvariantTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// A repeatable random source (SplitMix64).
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private let everyday = ["groceries", "dining", "gas", "shopping", "entertainment", "kids"]
    private let today = (2026, 10, 20)

    /// A household: two paychecks into two checking accounts, a joint card,
    /// savings, rent and bills, a subscription, everyday purchases on card
    /// and checking, a refund, moves to savings, card payments, the odd
    /// business purchase, some limits, savings and card paydown, maybe a
    /// trip fund and a trip. June through today, October 20.
    private func household(_ seed: UInt64) -> BudgetStore {
        var rng = Seeded(state: seed)
        func r(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
        var data = BudgetData()
        data.people = People(p1: "Ron", p2: "Jadira")
        data.accounts = [
            Account(id: "r", name: "Ron Checking", institution: "Chase", kind: .checking, balance: 0, owner: .p1),
            Account(id: "j", name: "Jadira Checking", institution: "BofA", kind: .checking, balance: 0, owner: .p2),
            Account(id: "s", name: "Savings", institution: "Ally", kind: .savings, balance: 0, owner: .shared),
            Account(id: "k", name: "Sapphire", institution: "Chase", kind: .credit, balance: 0, owner: .shared),
        ]
        var n = 0
        func add(_ acct: String, _ m: Int, _ d: Int, _ amount: Cents, _ payee: String, _ cat: String?,
                 transfer: Bool = false, business: Bool = false, trip: String? = nil) {
            let when = date(2026, m, d)
            guard when <= date(today.0, today.1, today.2) else { return }
            n += 1
            var t = Transaction(id: "t\(n)", accountId: acct, date: when, amount: amount, payee: payee,
                                categoryId: cat, tripId: trip, isTransfer: transfer)
            if business { t.business = true }
            data.transactions.append(t)
        }
        let ronPay = r(25...45) * 10_000, jadiraPay = r(15...35) * 10_000
        let rent = r(15...30) * 10_000
        for m in 6...10 {
            add("r", m, 1, ronPay, "CON EDISON PAYROLL", "income")
            add("r", m, 15, ronPay, "CON EDISON PAYROLL", "income")
            add("j", m, 5, jadiraPay, "DISNEY PAYROLL", "income")
            add("j", m, 19, jadiraPay, "DISNEY PAYROLL", "income")
            add("r", m, 1, -rent, "LANDLORD LLC", "housing")
            add("r", m, 12, -r(80...200) * 100, "CON ED UTILITY", "utilities")
            add("j", m, 9, -r(150...250) * 100, "VERIZON WIRELESS", "phone")
            add("k", m, 8, -1_799, "NETFLIX.COM", "subscriptions")
            for c in everyday {
                for _ in 0..<r(1...5) {
                    add(["k", "r", "j"][r(0...2)], m, r(1...28), -r(5...150) * 100, "\(c.uppercased()) STORE \(r(1...9))", c)
                }
            }
            // A refund smaller than what was bought.
            if r(0...1) == 1 { add("k", m, r(2...27), r(1...5) * 100, "SHOPPING STORE 1", "shopping") }
            let move = r(2...8) * 10_000
            add("r", m, 3, -move, "ONLINE TRANSFER TO SAV", nil, transfer: true)
            add("s", m, 3, move, "ONLINE TRANSFER FROM CHK", nil, transfer: true)
            let pay = r(10...40) * 10_000
            add("r", m, 22, -pay, "CHASE CREDIT CRD AUTOPAY", nil, transfer: true)
            add("k", m, 22, pay, "PAYMENT THANK YOU", nil, transfer: true)
            if r(0...3) == 0 { add("k", m, r(1...28), -r(50...400) * 100, "DELTA AIR", "travel", business: true) }
        }
        let store = BudgetStore(data: data, isDemo: true)
        store.calendar = calendar
        store.now = { self.date(self.today.0, self.today.1, self.today.2) }
        for c in everyday where r(0...3) > 0 {
            let usual = store.averageSpent(c, before: store.currentMonth) ?? 0
            store.setLimit(c, max(1_000, usual * r(60...130) / 100 / 1_000 * 1_000))
        }
        store.data.priorities = Priorities(savings: r(0...30) * 10_000, cardPaydown: r(0...5) * 10_000)
        if r(0...1) == 1 { store.data.tripFund = TripFund(monthly: r(1...5) * 10_000, start: date(2026, r(7...10), 1)) }
        if r(0...1) == 1 {
            store.data.trips = [Trip(id: "x", name: "Aruba", start: date(2027, 2, 24), end: date(2027, 2, 28),
                                     budget: r(20...90) * 10_000)]
            store.data.transactions.append(Transaction(id: "flight", accountId: "k", date: date(2026, 10, 2),
                                                       amount: -r(30...90) * 1_000, payee: "JETBLUE", categoryId: "travel",
                                                       tripId: "x"))
        }
        return store
    }

    // MARK: - What must always hold

    private func check(_ s: BudgetStore, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let month = s.currentMonth
        let plan = s.monthPlan(month)
        let cost = s.overrunCost(in: month)
        // One "to spend" and one "committed", whichever screen asks.
        XCTAssertEqual(cost.toSpend, plan.toSpend, "\(label): Over the plan and Budget agree on to spend", file: file, line: line)
        XCTAssertEqual(s.committedSpending(in: month), cost.committed, "\(label): Budget and Over the plan agree on what limits use", file: file, line: line)
        // What has to give is the shortfall, to the nearest dollar.
        XCTAssertEqual(cost.needed, (max(0, cost.committed - cost.toSpend) + 50) / 100 * 100,
                       "\(label): what has to give", file: file, line: line)
        // A choice never takes more than it was showing.
        for option in cost.options {
            XCTAssertLessThanOrEqual(option.amount, max(option.planned, (cost.needed + 999) / 1_000 * 1_000),
                                     "\(label): \(option.source) asks for no more than it has", file: file, line: line)
            XCTAssertGreaterThan(option.amount, 0, "\(label): no empty choices", file: file, line: line)
        }
        if cost.needed == 0 { XCTAssertTrue(cost.options.isEmpty, "\(label): nothing to choose when nothing's short", file: file, line: line) }
        // Needs attention says "limits are more than you have" only when they are.
        let attention = s.attention()
        let overs = Dictionary(uniqueKeysWithValues: s.overruns(in: month).map { ($0.id, $0.over) })
        for item in attention {
            if case .over(let id, let amount) = item {
                XCTAssertEqual(overs[id], amount, "\(label): Needs attention and Over the plan agree on \(id)", file: file, line: line)
            }
            if case .limitsOver(let amount) = item {
                XCTAssertGreaterThan(cost.needed, 0, "\(label): limits over only when short", file: file, line: line)
                XCTAssertLessThanOrEqual(amount, cost.needed, "\(label): never more than what's short", file: file, line: line)
            }
        }
        // Every amount is whole and the month adds up.
        XCTAssertEqual(plan.leftToSpend, plan.toSpend - plan.everydaySpent, "\(label)", file: file, line: line)
        XCTAssertEqual(plan.everydaySpent + plan.billsPaid, s.totalSpent(in: month), "\(label): bills and everyday make up spending", file: file, line: line)
        // Spending is the sum of its categories (trips aside); no transfer,
        // business purchase or paycheck is in it.
        let byCategory = s.expenseCategories.filter { $0.group != "Trips" }.reduce(0) { $0 + s.spent($1.id, in: month) }
        XCTAssertEqual(byCategory, s.totalSpent(in: month), "\(label): categories add up to spending", file: file, line: line)
        let leaks = s.spendingTransactions.filter { $0.isTransfer || $0.isBusiness || $0.amount > 0 && $0.categoryId == "income" }
        XCTAssertTrue(leaks.isEmpty, "\(label): nothing but spending is spending", file: file, line: line)
        let incomeLeaks = s.incomeTransactions.filter { $0.isTransfer || $0.isBusiness || $0.amount <= 0 }
        XCTAssertTrue(incomeLeaks.isEmpty, "\(label): nothing but income is income", file: file, line: line)
        // Bills: nothing still to come is negative, and paid adds up.
        for b in s.billLines(month) {
            XCTAssertGreaterThanOrEqual(b.expected, b.paid, "\(label): \(b.category.id) expects at least what's paid", file: file, line: line)
        }
        XCTAssertEqual(s.billLines(month).reduce(0) { $0 + $1.paid }, plan.billsPaid, "\(label)", file: file, line: line)
    }

    private func json(_ d: BudgetData) -> NSObject {
        let raw = try! JSONEncoder.upside.encode(d)
        return try! JSONSerialization.jsonObject(with: raw) as! NSObject
    }

    // MARK: - Tests

    func testEveryHouseholdAddsUpBeforeAnythingIsDone() {
        for seed in 1...200 as ClosedRange<UInt64> {
            check(household(seed), "household \(seed)")
        }
    }

    func testRandomEverydayActionsKeepEveryScreenInAgreement() {
        for seed in 1...80 as ClosedRange<UInt64> {
            let s = household(seed)
            var rng = Seeded(state: seed &* 7_919)
            let month = s.currentMonth
            for step in 1...25 {
                let label = "household \(seed), step \(step)"
                let before = s.monthPlan(month)
                let beforeCost = s.overrunCost(in: month)
                let beforeLimits = s.everydayCategories.map { s.limit($0, in: month) }
                switch Int.random(in: 0...7, using: &rng) {
                case 0:
                    // Choose what gives, any choice offered.
                    guard let option = beforeCost.options.randomElement(using: &rng) else { break }
                    let overs = s.overruns(in: month).map { "\($0.id)=\($0.over)" }
                    s.payForOverspending(from: option.source, amount: option.amount, categoryId: s.overruns(in: month).first?.id, in: month)
                    XCTAssertLessThan(s.overrunCost(in: month).needed, beforeCost.needed, "\(label): a choice helps")
                    XCTAssertEqual(s.overruns(in: month).map { "\($0.id)=\($0.over)" }, overs, "\(label): what went over stays over")
                case 1:
                    // Choose, then undo: exactly as before.
                    guard let option = beforeCost.options.randomElement(using: &rng),
                          !s.overrunCuts(in: month).contains(where: { $0.source == option.source }) else { break }
                    s.payForOverspending(from: option.source, amount: option.amount, categoryId: nil, in: month)
                    s.undoOverspending(from: option.source, in: month)
                    XCTAssertEqual(s.monthPlan(month).toSpend, before.toSpend, "\(label): undo puts to-spend back")
                    XCTAssertEqual(s.everydayCategories.map { s.limit($0, in: month) }, beforeLimits, "\(label): undo puts limits back")
                case 2:
                    // Raise or lower a limit, only if Adjust limit would let you.
                    let c = s.everydayCategories.randomElement(using: &rng)!
                    let value = Int.random(in: 0...60, using: &rng) * 1_000
                    if s.limitOver(c.id, to: value, in: month) == 0 {
                        let predicted = s.limitSpare(c.id, to: value, in: month)
                        s.adjustLimit(c.id, to: value, thisMonthOnly: Bool.random(using: &rng), in: month)
                        let after = s.overrunCost(in: month)
                        XCTAssertLessThanOrEqual(after.committed - after.toSpend, 50, "\(label): it fits, as Adjust limit said")
                        XCTAssertEqual(after.toSpend - after.committed, predicted, "\(label): what's left is what it said")
                    }
                case 3:
                    // Stop a bill, then restart it: nothing changes.
                    guard let bill = s.recurringCharges().randomElement(using: &rng) else { break }
                    s.stopBill(bill, afterThisMonth: Bool.random(using: &rng))
                    XCTAssertLessThanOrEqual(s.monthPlan(month).bills, before.bills, "\(label): stopping never adds bills")
                    s.restartBill(bill.id)
                    XCTAssertEqual(s.monthPlan(month).toSpend, before.toSpend, "\(label): restart puts it back")
                case 4:
                    // A sync's transfer check: running it again changes nothing,
                    // and it never touches income.
                    let income = s.income(in: month)
                    BankSync.markTransfers(&s.data)
                    let once = json(s.data)
                    BankSync.markTransfers(&s.data)
                    XCTAssertEqual(json(s.data), once, "\(label): the transfer check settles")
                    XCTAssertEqual(s.income(in: month), income, "\(label): income untouched")
                case 5:
                    // More overspending comes from the last choice; again does nothing.
                    s.keepPayingOverspending(in: month)
                    XCTAssertEqual(s.keepPayingOverspending(in: month), 0, "\(label): settles after one go")
                    let after = s.overrunCost(in: month)
                    if let keep = s.plan(for: month)?.keepFrom, after.needed > 0 {
                        XCTAssertFalse(after.options.contains { $0.source == keep }, "\(label): only short when \(keep) ran out")
                    }
                case 6:
                    // The other phone: merging with an unchanged or identical copy changes nothing.
                    let base = s.data
                    XCTAssertEqual(json(BudgetMerge.merge(local: s.data, remote: s.data, base: base)), json(s.data), "\(label)")
                    var other = s.data
                    other.transactions[0].categoryId = "gifts"
                    let merged = BudgetMerge.merge(local: s.data, remote: other, base: base)
                    XCTAssertEqual(json(merged), json(other), "\(label): their only change arrives")
                    XCTAssertEqual(json(BudgetMerge.merge(local: other, remote: s.data, base: base)), json(other), "\(label): my only change stays")
                default:
                    // A transfer or a business purchase never changes the money.
                    let spent = s.totalSpent(in: month), income = s.income(in: month)
                    s.data.transactions.append(Transaction(id: "x\(step)", accountId: "r", date: s.now(), amount: -12_300,
                                                           payee: "ONLINE TRANSFER TO SAV", categoryId: nil, isTransfer: true))
                    var b = Transaction(id: "b\(step)", accountId: "k", date: s.now(), amount: -45_600,
                                        payee: "HILTON", categoryId: "shopping")
                    b.business = true
                    s.data.transactions.append(b)
                    XCTAssertEqual(s.totalSpent(in: month), spent, "\(label): not spending")
                    XCTAssertEqual(s.income(in: month), income, "\(label): not income")
                }
                check(s, label)
            }
        }
    }

    func testARefundWithNothingBoughtYetDoesntMakeCategoriesDisagreeWithTheTotal() {
        // Found by household 116: shopping's only October entry was a $1
        // refund (the purchases came later), so Shopping showed $0 while
        // the month's total took the $1 off.
        let s = household(116)
        let month = s.currentMonth
        s.data.transactions.removeAll { $0.categoryId == "gifts" }
        s.data.transactions.append(Transaction(id: "giftRefund", accountId: "k", date: s.now(), amount: 2_500,
                                               payee: "ETSY REFUND", categoryId: "gifts"))
        XCTAssertEqual(s.spent("gifts", in: month), 0)
        let byCategory = s.expenseCategories.filter { $0.group != "Trips" }.reduce(0) { $0 + s.spent($1.id, in: month) }
        XCTAssertEqual(s.totalSpent(in: month), byCategory)
        check(s, "refund with nothing bought")
    }

    func testAZeroLimitIsZeroWhetherForThisMonthOrFromNowOn() {
        for thisMonthOnly in [true, false] {
            let s = household(3)
            let month = s.currentMonth
            let c = "entertainment"
            guard s.limitOver(c, to: 0, in: month) == 0 else { continue }
            let predicted = s.limitSpare(c, to: 0, in: month)
            s.adjustLimit(c, to: 0, thisMonthOnly: thisMonthOnly, in: month)
            XCTAssertEqual(s.limit(s.category(c)!, in: month), 0, "a $0 limit, not \"no limit\"")
            let cost = s.overrunCost(in: month)
            XCTAssertEqual(cost.toSpend - cost.committed, predicted, "fits as the sheet said (this month only: \(thisMonthOnly))")
            check(s, "zero limit, this month only: \(thisMonthOnly)")
        }
    }

    func testAPurchaseAddsExactlyItsAmountEverywhere() {
        for seed in 1...100 as ClosedRange<UInt64> {
            let s = household(seed)
            let month = s.currentMonth
            let c = everyday[Int(seed) % everyday.count]
            let plan = s.monthPlan(month), spent = s.spent(c, in: month)
            s.data.transactions.append(Transaction(id: "new", accountId: "k", date: s.now(), amount: -4_321,
                                                   payee: "NEW STORE", categoryId: c))
            XCTAssertEqual(s.spent(c, in: month), spent + 4_321, "household \(seed)")
            XCTAssertEqual(s.monthPlan(month).everydaySpent, plan.everydaySpent + 4_321, "household \(seed)")
            XCTAssertEqual(s.monthPlan(month).leftToSpend, plan.leftToSpend - 4_321, "household \(seed)")
            check(s, "household \(seed) after a purchase")
        }
    }
}
