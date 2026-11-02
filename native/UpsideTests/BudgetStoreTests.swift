import XCTest
@testable import Upside

final class BudgetStoreTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func makeStore() -> BudgetStore {
        var data = BudgetData()
        data.people = People(p1: "Ron", p2: "Ana")
        data.accounts = [
            Account(id: "r", name: "Ron Checking", institution: "Chase", kind: .checking, balance: 0, owner: .p1),
            Account(id: "a", name: "Checking", institution: "BofA", kind: .checking, balance: 0, owner: .p2),
            Account(id: "m", name: "Mortgage", institution: "Chase", kind: .loan, balance: 0,
                    owner: .shared, isOnBudget: false),
        ]
        data.transactions = [
            // Three previous months of groceries: $300, $600, $900 → usual $600.
            Transaction(id: "1", accountId: "r", date: date(2026, 7, 5), amount: -30_000, payee: "Kroger", categoryId: "groceries"),
            Transaction(id: "2", accountId: "a", date: date(2026, 8, 5), amount: -60_000, payee: "Kroger", categoryId: "groceries"),
            Transaction(id: "3", accountId: "r", date: date(2026, 9, 5), amount: -90_000, payee: "Kroger", categoryId: "groceries"),
            // This month (October): Ron $100, Ana $50, a $20 refund.
            Transaction(id: "4", accountId: "r", date: date(2026, 10, 2), amount: -10_000, payee: "Kroger", categoryId: "groceries"),
            Transaction(id: "5", accountId: "a", date: date(2026, 10, 3), amount: -5_000, payee: "Trader Joe's", categoryId: "groceries"),
            Transaction(id: "6", accountId: "a", date: date(2026, 10, 4), amount: 2_000, payee: "Trader Joe's", categoryId: "groceries"),
            // Off-budget, transfers and income don't count as spending.
            Transaction(id: "7", accountId: "m", date: date(2026, 10, 1), amount: -200_000, payee: "Mortgage", categoryId: "housing"),
            Transaction(id: "8", accountId: "r", date: date(2026, 10, 1), amount: -50_000, payee: "Transfer", categoryId: "groceries", isTransfer: true),
            Transaction(id: "9", accountId: "r", date: date(2026, 10, 1), amount: 300_000, payee: "Payroll", categoryId: "income"),
            // Needs sorting.
            Transaction(id: "10", accountId: "a", date: date(2026, 10, 5), amount: -1_200, payee: "SQ *BLUE BOTTLE #12", categoryId: nil),
            Transaction(id: "11", accountId: "r", date: date(2026, 10, 6), amount: -900, payee: "SQ *BLUE BOTTLE #7", categoryId: nil),
        ]
        let store = BudgetStore(data: data, isDemo: true)
        store.calendar = calendar
        store.now = { self.date(2026, 10, 15) }
        return store
    }

    func testSpentThisMonthNetsRefundsAndIgnoresTransfersAndOffBudget() {
        let store = makeStore()
        XCTAssertEqual(store.spent("groceries", in: store.currentMonth), 13_000)
        XCTAssertEqual(store.spent("housing", in: store.currentMonth), 0)
    }

    func testUsualIsThreeMonthAverage() {
        let store = makeStore()
        XCTAssertEqual(store.averageSpent("groceries", before: store.currentMonth), 60_000)
    }

    func testWhoSpent() {
        let store = makeStore()
        let byOwner = store.spentByOwner(categoryId: "groceries", in: store.currentMonth)
        XCTAssertEqual(byOwner[.p1], 10_000)
        XCTAssertEqual(byOwner[.p2], 3_000)
    }

    func testLimitsFromAveragesRoundUpToTenDollars() {
        let store = makeStore()
        store.setLimitsFromAverages()
        XCTAssertEqual(store.category("groceries")?.limit, 60_000)
        XCTAssertTrue(store.hasLimits)
    }

    func testTopCategoriesSkipUnusedOnes() {
        let store = makeStore()
        XCTAssertEqual(store.topCategories(in: store.currentMonth).map(\.id), ["groceries"])
    }

    func testCategorizingRemembersTheStore() {
        let store = makeStore()
        XCTAssertEqual(store.uncategorized.count, 2)
        store.categorize("10", as: "dining")
        XCTAssertEqual(store.uncategorized.count, 0, "the other Blue Bottle purchase is sorted too")
        XCTAssertEqual(BankSync.categorize(payee: "SQ *BLUE BOTTLE #99", amount: -500, rules: store.data.rules), "dining")
    }


    func testSortingOneOffersTheOthersWithTheSameName() {
        let store = makeStore()
        // Another Blue Bottle purchase already sitting in Shopping.
        store.data.transactions.append(Transaction(id: "12", accountId: "a", date: date(2026, 9, 9), amount: -800,
                                                   payee: "SQ *BLUE BOTTLE #3", categoryId: "shopping"))
        let prompt = store.sort("10", as: "dining")
        XCTAssertEqual(Set(prompt?.otherIds ?? []), ["11", "12"])
        XCTAssertEqual(store.uncategorized.count, 1, "the others wait for your answer")

        store.sortAll(prompt!)
        XCTAssertEqual(store.data.transactions.first { $0.id == "12" }?.categoryId, "dining")
        XCTAssertTrue(store.uncategorized.isEmpty)
        XCTAssertEqual(BankSync.categorize(payee: "SQ *BLUE BOTTLE #99", amount: -500, rules: store.data.rules), "dining")
        XCTAssertNil(store.sort("12", as: "dining"), "nothing left to offer")
    }
    func testPayeeKeyIgnoresStoreNumbers() {
        XCTAssertEqual(BudgetStore.payeeKey("KROGER #123 CINCINNATI OH"), "kroger cincinnati")
        XCTAssertEqual(BudgetStore.payeeKey("Kroger 456"), "kroger")
    }

    func testOwnerGuessing() {
        let people = People(p1: "Ron", p2: "Ana Tejada")
        XCTAssertEqual(BudgetStore.guessOwner("Joint Checking", people: people), .shared)
        XCTAssertEqual(BudgetStore.guessOwner("RON'S CHECKING", people: people), .p1)
        XCTAssertEqual(BudgetStore.guessOwner("Ana Savings", people: people), .p2)
        XCTAssertEqual(BudgetStore.guessOwner("Total Checking", people: people), .unassigned)
    }

    func testBuiltInCategories() {
        XCTAssertEqual(BankSync.categorize(payee: "STARBUCKS STORE 1234", amount: -650, rules: []), "dining")
        XCTAssertEqual(BankSync.categorize(payee: "PAYROLL DEPOSIT ACME", amount: 250_000, rules: []), "income")
        XCTAssertTrue(BankSync.looksLikeTransfer("CHASE CREDIT CARD PAYMENT THANK YOU"))
    }

    func testDemoDataLooksRealistic() {
        let data = DemoData.make()
        let store = BudgetStore(data: data, isDemo: true)
        XCTAssertGreaterThan(store.totalSpent(in: store.currentMonth), 0)
        XCTAssertFalse(store.topCategories(in: store.currentMonth).isEmpty)
        XCTAssertEqual(store.uncategorized.count, 3)
    }


    func testAccountFullNameSkipsRepeatedBank() {
        let card = Account(id: "c", name: "Robinhood Gold Card", institution: "Robinhood", kind: .credit, balance: 0, owner: .p1)
        let checking = Account(id: "k", name: "Total Checking", institution: "Chase", kind: .checking, balance: 0, owner: .p1)
        XCTAssertEqual(card.fullName, "Robinhood Gold Card")
        XCTAssertEqual(checking.fullName, "Chase Total Checking")
    }

    func testSixMonthsOfHistoryIsFetchedInPiecesUnder90Days() {
        let end = date(2026, 11, 1)
        let start = end.addingTimeInterval(-Double(BankSync.historyDays) * 86_400)
        let pieces = BankSync.windows(from: start, to: end)
        XCTAssertEqual(pieces.count, 4)
        XCTAssertEqual(pieces.first?.end, end)
        XCTAssertEqual(pieces.last?.start, start)
        XCTAssertTrue(pieces.allSatisfy { $0.duration <= 90 * 86_400 })
        for (a, b) in zip(pieces, pieces.dropFirst()) { XCTAssertEqual(a.start, b.end) } // no gaps
    }

    // MARK: Bills, trends, search

    func testFindsBillsPriceIncreasesAndNewSubscriptions() {
        let store = makeStore()
        func add(_ payee: String, _ category: String, _ m: Int, _ d: Int, _ cents: Cents) {
            store.data.transactions.append(Transaction(id: "\(payee)\(m)", accountId: "r", date: date(2026, m, d),
                                                       amount: -cents, payee: payee, categoryId: category))
        }
        for m in 7...9 { add("Netflix", "subscriptions", m, 8, 1_549) }
        add("Netflix", "subscriptions", 10, 8, 1_799)
        for m in 7...9 { add("Verizon Wireless", "phone", m, 18, 14_000) }
        for m in 8...9 { add("Peacock", "subscriptions", m, 22, 799) }
        add("Lenny's Bagels", "dining", 7, 6, 1_450); add("Lenny's Bagels", "dining", 8, 9, 1_380)
        add("Lenny's Bagels", "dining", 9, 7, 1_520); add("Lenny's Bagels", "dining", 10, 5, 1_410)
        for m in 7...10 { add("Planet Fitness", "personal", m, 3, 2_499) }

        let bills = Dictionary(uniqueKeysWithValues: store.recurringCharges().map { ($0.name, $0) })
        XCTAssertNil(bills["Kroger"], "groceries vary too much to be a bill")
        XCTAssertNil(bills["Lenny's Bagels"], "a monthly breakfast spot isn't a bill")
        XCTAssertNotNil(bills["Planet Fitness"], "same price every month is")

        XCTAssertEqual(bills["Netflix"]?.paidThisMonth, true)
        XCTAssertEqual(bills["Netflix"]?.priceIncrease, 250)
        XCTAssertEqual(bills["Netflix"]?.isNew, false)

        XCTAssertEqual(bills["Verizon Wireless"]?.paidThisMonth, false)
        XCTAssertEqual(bills["Verizon Wireless"]?.dueDate.map { calendar.component(.day, from: $0) }, 18)
        XCTAssertNil(bills["Verizon Wireless"]?.priceIncrease)

        XCTAssertEqual(bills["Peacock"]?.isNew, true)
        XCTAssertEqual(bills["Peacock"]?.isSubscription, true)
    }

    func testMonthlySpentStopsAtTheStartOfHistory() {
        let store = makeStore()
        let points = store.monthlySpent("groceries", endingAt: store.currentMonth)
        XCTAssertEqual(points.map(\.spent), [30_000, 60_000, 90_000, 13_000])
    }

    func testTrendNoteTellsATrendFromAOneOff() {
        func points(_ values: [Cents]) -> [MonthSpend] {
            values.enumerated().map { MonthSpend(month: date(2026, $0.offset + 1, 1), spent: $0.element) }
        }
        XCTAssertEqual(BudgetStore.trendNote(points([10_000, 20_000, 30_000])), "Up three months in a row.")
        XCTAssertEqual(BudgetStore.trendNote(points([30_000, 20_000, 10_000])), "Down three months in a row.")
        XCTAssertTrue(BudgetStore.trendNote(points([10_000, 10_000, 50_000, 10_000, 11_000]))?
            .hasPrefix("March was unusually high") ?? false)
        XCTAssertNil(BudgetStore.trendNote(points([10_000, 10_500, 10_000, 10_200])))
    }

    func testSearchByStoreOrAmount() {
        let store = makeStore()
        XCTAssertEqual(Set(store.search("kroger").map(\.id)), ["1", "2", "3", "4"])
        XCTAssertEqual(store.search("$50.00").map(\.id), ["5"])
        XCTAssertEqual(BudgetStore.parseAmount("1,200"), 120_000)
        XCTAssertEqual(BudgetStore.parseAmount("84.12"), 8_412)
        XCTAssertNil(BudgetStore.parseAmount("84.123"))
        XCTAssertTrue(store.search("  ").isEmpty)
    }

    func testRecommendedCategoriesFromWhatYouBuy() {
        let store = makeStore()
        store.data.transactions += [
            Transaction(id: "t1", accountId: "r", date: date(2026, 9, 3), amount: -290, payee: "MTA*NYCT PAYGO", categoryId: nil),
            Transaction(id: "t2", accountId: "r", date: date(2026, 10, 3), amount: -290, payee: "MTA*NYCT PAYGO", categoryId: nil),
            Transaction(id: "f1", accountId: "a", date: date(2026, 10, 1), amount: -4_000, payee: "PLANET FITNESS", categoryId: "personal"),
            Transaction(id: "c1", accountId: "a", date: date(2026, 10, 2), amount: -5_000, payee: "TESLA SUPERCHARGER", categoryId: "gas"),
            Transaction(id: "g1", accountId: "r", date: date(2026, 10, 4), amount: -9_500, payee: "BETHPAGE STATE PARK GOLF", categoryId: nil),
            Transaction(id: "g2", accountId: "r", date: date(2026, 9, 12), amount: -18_900, payee: "PGA TOUR SUPERSTORE", categoryId: "shopping"),
            Transaction(id: "g3", accountId: "r", date: date(2026, 9, 20), amount: -6_400, payee: "GOLFNOW*TEE TIME", categoryId: nil),
        ]
        let recommended = store.recommendedCategories()
        XCTAssertEqual(Set(recommended.map(\.name)), ["Transit", "Coffee", "Fitness", "Golf"]) // Blue Bottle → Coffee
        XCTAssertEqual(recommended.first { $0.name == "Golf" }?.transactionIds.count, 3)
        let transitSuggestion = recommended.first { $0.name == "Transit" }!
        XCTAssertEqual(store.monthlyAverage(of: transitSuggestion), 290)

        store.accept(transitSuggestion)
        let transit = store.data.categories.first { $0.name == "Transit" }
        XCTAssertNotNil(transit)
        XCTAssertEqual(store.data.transactions.first { $0.id == "t1" }?.categoryId, transit?.id)
        XCTAssertFalse(store.recommendedCategories().contains { $0.name == "Transit" })
        XCTAssertEqual(BankSync.categorize(payee: "TESLA SUPERCHARGER US", amount: -1_000, rules: []), "gas")
        let expected: [(String, String)] = [
            ("VEOLIA WATER NEW YORK", "utilities"), ("AMAZON PRIME*2K4", "subscriptions"), ("AMZN Mktp US", "shopping"),
            ("UBER *EATS", "dining"), ("UBER *TRIP", "gas"), ("UBER EATS PENDING", "dining"),
            ("COMEDY CELLAR", "entertainment"), ("STOP & SHOP 0412", "groceries"), ("SHAKE SHACK 1102", "dining"),
            ("METLIFE AUTO", "insurance"), ("DUANE READE #14", "health"), ("GREAT CLIPS", "personal"),
            ("PETSMART 1234", "kids"), ("HERTZ RENT-A-CAR", "travel"), ("T-MOBILE AUTOPAY", "phone"),
            ("MR. COOPER MORTGAGE", "housing"), ("BOOKING.COM HOTEL", "travel"), ("TICKETMASTER", "entertainment"),
        ]
        for (payee, category) in expected {
            XCTAssertEqual(BankSync.categorize(payee: payee, amount: -2_000, rules: []), category, payee)
        }
        XCTAssertNotEqual(BankSync.categorize(payee: "ACME CONSULTANTS", amount: -2_000, rules: []), "personal")
        XCTAssertEqual(store.transferLabel(Transaction(id: "x", accountId: "r", date: date(2026, 10, 1), amount: -5_000,
                                                       payee: "CHASE CREDIT CRD AUTOPAY", isTransfer: true)), "Credit card payment")
        XCTAssertEqual(store.transferLabel(Transaction(id: "y", accountId: "r", date: date(2026, 10, 1), amount: -5_000,
                                                       payee: "ONLINE TRANSFER TO SAV 1234", isTransfer: true)), "Transfer")
        for bill in ["CON ED OF NY", "CONSOLIDATED EDISON CO", "CONEDISON BILL PAYMENT", "NATIONAL GRID NY", "PSEG LI"] {
            XCTAssertEqual(BankSync.categorize(payee: bill, amount: -9_000, rules: []), "utilities", bill)
        }
    }

    func testResortForgetsChoicesButKeepsTrips() {
        let store = makeStore()
        store.saveTrip(Trip(id: "t", name: "Miami", start: date(2026, 10, 2), end: date(2026, 10, 4)))
        store.setTrip("4", "t")
        store.categorize("10", as: "shopping") // Blue Bottle, wrongly
        XCTAssertFalse(store.data.rules.isEmpty)

        store.resortAllPurchases()
        XCTAssertTrue(store.data.rules.isEmpty)
        XCTAssertEqual(store.data.transactions.first { $0.id == "10" }?.categoryId, "dining")
        XCTAssertEqual(store.data.transactions.first { $0.id == "4" }?.categoryId, "groceries")
        XCTAssertEqual(store.data.transactions.first { $0.id == "4" }?.tripId, "t")
        XCTAssertEqual(store.data.transactions.first { $0.id == "8" }?.isTransfer, true)
        XCTAssertEqual(store.data.transactions.first { $0.id == "9" }?.categoryId, "income")
    }

    func testEveryCardIsRecognized() {
        for name in ["Freedom Unlimited", "Sapphire Preferred", "Customized Cash Rewards", "Venture X",
                     "Robinhood Gold Card", "Amazon Prime Visa", "Discover it Cash Back"] {
            XCTAssertEqual(AccountKind.guess(from: name), .credit, name)
        }
        XCTAssertEqual(AccountKind.guess(from: "Account 1234", balance: -45_000), .credit)
        XCTAssertEqual(AccountKind.guess(from: "Online Savings"), .savings)
        XCTAssertEqual(AccountKind.guess(from: "Total Checking"), .checking)
        XCTAssertEqual(AccountKind.guess(from: "Home Mortgage", balance: -30_000_000), .loan)
        XCTAssertEqual(AccountKind.guess(from: "Account 5678", balance: 12_000), .other)
    }

    func testPartialFirstMonthIsLeftOutOfAveragesAndCharts() {
        let store = makeStore()
        // History now starts June 20: June is partial.
        store.data.transactions.append(Transaction(id: "jun", accountId: "r", date: date(2026, 6, 20), amount: -1_000,
                                                   payee: "Kroger", categoryId: "groceries"))
        XCTAssertEqual(store.firstFullMonth, store.monthStart(date(2026, 7, 1)))
        XCTAssertEqual(store.monthlySpent("groceries", endingAt: store.currentMonth).count, 4)
    }

    func testUsualIncome() {
        let store = makeStore()
        for m in 7...9 {
            store.data.transactions.append(Transaction(id: "pay\(m)", accountId: "r", date: date(2026, m, 15),
                                                       amount: 280_000 + m * 1_000, payee: "Payroll", categoryId: "income"))
        }
        XCTAssertEqual(store.averageIncome(before: store.currentMonth), 288_000)
    }
    // MARK: Income, trips, alerts

    func testIncomeAndLeftOver() {
        let store = makeStore()
        let month = store.currentMonth
        XCTAssertEqual(store.income(in: month), 300_000)
        XCTAssertEqual(store.leftOver(in: month), 300_000 - store.totalSpent(in: month, includeTrips: true))
    }

    func testTripPurchasesLeaveTheirCategoryButStillCountAsSpent() {
        let store = makeStore()
        let month = store.currentMonth
        let before = store.totalSpent(in: month, includeTrips: true)
        store.saveTrip(Trip(id: "t", name: "Miami", start: date(2026, 10, 2), end: date(2026, 10, 4)))
        store.setTrip("4", "t")
        XCTAssertEqual(store.spent("groceries", in: month), 3_000)
        XCTAssertEqual(store.totalSpent(in: month, includeTrips: true), before)
    }

    func testPurchasesDuringTripSkipRefundsTransfersAndOffBudget() {
        let store = makeStore()
        let trip = Trip(id: "t", name: "Miami", start: date(2026, 10, 2), end: date(2026, 10, 4))
        XCTAssertEqual(Set(store.purchasesDuring(trip).map(\.id)), ["4", "5"])
        store.saveTrip(trip)
        store.tagPurchases(["4", "5"], to: "t")
        XCTAssertTrue(store.purchasesDuring(trip).isEmpty)
    }

    func testLimitAlertsFireOncePerLevel() {
        let store = makeStore()
        store.setLimit("groceries", 15_000) // $130 of $150 = 86%
        let first = store.pendingLimitAlerts()
        XCTAssertEqual(first.map(\.percent), [80])
        store.markAlertsSent(first.map(\.key))
        XCTAssertTrue(store.pendingLimitAlerts().isEmpty)

        store.setLimit("groceries", 12_000) // now over
        let over = store.pendingLimitAlerts()
        XCTAssertEqual(over.map(\.percent), [100])
        XCTAssertEqual(over.first?.left, -1_000)
        store.markAlertsSent(over.map(\.key))
        XCTAssertTrue(store.pendingLimitAlerts().isEmpty)
    }

    func testWeeklySummaryIsSundayEveningOnce() {
        let sunday6pm = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 18))!
        let sundayNoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
        XCTAssertTrue(Alerts.isSummaryDue(now: sunday6pm, calendar: calendar, last: nil))
        XCTAssertFalse(Alerts.isSummaryDue(now: sundayNoon, calendar: calendar, last: nil))
        XCTAssertFalse(Alerts.isSummaryDue(now: sunday6pm, calendar: calendar, last: sunday6pm.addingTimeInterval(-3600)))
        XCTAssertTrue(Alerts.isSummaryDue(now: sunday6pm, calendar: calendar, last: sunday6pm.addingTimeInterval(-7 * 86_400)))
    }
}

final class TransferTests: XCTestCase {
    func testCardPaymentWordingFromBanks() {
        for payee in ["Payment to Chase card ending in 1234 11/01", "CHASE CREDIT CRD AUTOPAY", "CHASE CREDIT CRD EPAY",
                      "Online Banking payment to CRD 1234", "BA ELECTRONIC PAYMENT", "ONLINE PAYMENT, THANK YOU",
                      "AUTOMATIC PAYMENT - THANK YOU", "CITI AUTOPAY PAYMENT", "AMEX EPAYMENT ACH PMT",
                      "CAPITAL ONE MOBILE PMT", "DISCOVER E-PAYMENT", "APPLECARD GSBANK PAYMENT"] {
            XCTAssertTrue(BankSync.looksLikeTransfer(payee), payee)
        }
        for bill in ["VERIZON AUTOPAY", "DUKE ENERGY ONLINE PAYMENT", "CON ED OF NY BILL PAYMENT",
                     "ELECTRICITY PAYMENT", "CONED ONLINE PYMT", "GEICO ACH PMT", "STATE FARM AUTOMATIC PAYMENT",
                     "ZELLE PAYMENT TO CHASE SMITH"] {
            XCTAssertFalse(BankSync.looksLikeTransfer(bill), bill)
        }
    }

    func testPaymentPairsEvenWhenTheCardSideIsAlreadyKnown() {
        var data = BudgetData()
        data.accounts = [
            Account(id: "chk", name: "Checking", institution: "Ally Bank", kind: .checking, balance: 0),
            Account(id: "card", name: "Gold", institution: "Robinhood", kind: .credit, balance: 0),
        ]
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        data.transactions = [
            Transaction(id: "out", accountId: "chk", date: day, amount: -48_312, payee: "ACH DEBIT 0099 WEB", categoryId: nil),
            Transaction(id: "in", accountId: "card", date: day.addingTimeInterval(86_400), amount: 48_312,
                        payee: "Payment Thank You", categoryId: nil, isTransfer: true),
            Transaction(id: "rh", accountId: "chk", date: day, amount: -20_000, payee: "ROBINHOOD DES:CARD PYMT", categoryId: nil),
            Transaction(id: "zelle", accountId: "chk", date: day, amount: -5_000, payee: "ZELLE PAYMENT TO ROBINHOOD FAN", categoryId: nil),
        ]
        BankSync.markTransfers(&data)
        let marked = Set(data.transactions.filter(\.isTransfer).map(\.id))
        XCTAssertEqual(marked, ["out", "in", "rh"])
    }

    private func t(_ id: String, _ account: String, _ day: Int, _ amount: Cents, _ payee: String) -> Transaction {
        Transaction(id: id, accountId: account,
                    date: Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400),
                    amount: amount, payee: payee, categoryId: nil)
    }

    func testCardPaymentsAreNotSpending() {
        var data = BudgetData()
        data.accounts = [
            Account(id: "chk", name: "Checking", institution: "Chase", kind: .checking, balance: 0),
            Account(id: "card", name: "Gold Card", institution: "Robinhood", kind: .credit, balance: 0),
        ]
        data.transactions = [
            // Matching pair with bank-specific wording nobody could guess.
            t("1", "chk", 0, -123_456, "ONLINE TRANSFER TO XXXX9921"),
            t("2", "card", 2, 123_456, "PYMT RCVD"),
            // Pair without any keywords at all: matched by amount and dates.
            t("3", "chk", 10, -98_765, "WEB ID 0012345"),
            t("4", "card", 11, 98_765, "THANKS"),
            // Card payment wording.
            t("5", "chk", 20, -50_000, "ROBINHOOD DES:CARD PYMT ID:123"),
            // Bills paid from checking stay spending.
            t("6", "chk", 21, -8_800, "VERIZON WIRELESS AUTOPAY"),
            t("7", "chk", 22, -12_000, "DUKE ENERGY ONLINE PAYMENT"),
            // A refund equal to a purchase weeks apart is not a pair.
            t("8", "card", 40, -4_200, "TARGET"),
            t("9", "chk", 80, 4_200, "TARGET REFUND"),
        ]
        BankSync.markTransfers(&data)
        let transfers = Set(data.transactions.filter(\.isTransfer).map(\.id))
        XCTAssertEqual(transfers, ["1", "2", "3", "4", "5"])
    }

    func testNotSpendingChoiceIsRemembered() {
        var data = BudgetData()
        data.accounts = [Account(id: "chk", name: "Checking", institution: "Chase", kind: .checking, balance: 0)]
        data.transactions = [t("1", "chk", 0, -1_000, "ZELLE TO MOM"), t("2", "chk", 30, -2_000, "ZELLE TO MOM")]
        let store = BudgetStore(data: data, isDemo: true)
        store.categorize("1", as: BankSync.transferCategory)
        XCTAssertTrue(store.data.transactions.allSatisfy(\.isTransfer))
        XCTAssertTrue(store.uncategorized.isEmpty)
    }
}

final class CategoryTests: XCTestCase {
    func testSuggestionsAndCreatingCategories() {
        var data = BudgetData()
        data.accounts = [Account(id: "c", name: "Card", institution: "X", kind: .credit, balance: 0)]
        let day: TimeInterval = 86_400
        data.transactions = [
            Transaction(id: "1", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000), amount: -4_000, payee: "PLANET FITNESS #12", categoryId: nil),
            Transaction(id: "2", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000 + day), amount: -2_500, payee: "CHEWY.COM", categoryId: nil),
            Transaction(id: "3", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000 + 2 * day), amount: -1_000, payee: "LOCAL BAKERY", categoryId: nil),
            Transaction(id: "4", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000 + 3 * day), amount: -1_100, payee: "LOCAL BAKERY", categoryId: nil),
            Transaction(id: "5", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000 + 4 * day), amount: -1_200, payee: "LOCAL BAKERY", categoryId: nil),
        ]
        let store = BudgetStore(data: data, isDemo: true)
        let names = Set(store.suggestedCategories.map(\.name))
        XCTAssertEqual(names, ["Fitness", "Pets"], "a repeated store is not a category")

        // Cleaning up a store-named category from 0.28.
        var old = data
        old.categories.append(Category(id: "tesla-ab12", name: "Tesla", group: "Everyday"))
        old.categories.append(Category(id: "pets-cd34", name: "Pets", group: "Everyday"))
        old.rules = [PayeeRule(payeeKey: "tesla supercharger", categoryId: "tesla-ab12")]
        old.transactions += [
            Transaction(id: "6", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000), amount: -1_000,
                        payee: "TESLA SUPERCHARGER", categoryId: "tesla-ab12"),
            Transaction(id: "7", accountId: "c", date: Date(timeIntervalSince1970: 1_790_000_000), amount: -2_000,
                        payee: "PETSMART", categoryId: "pets-cd34"),
        ]
        BudgetStore.removeStoreNamedCategories(&old)
        XCTAssertNil(old.categories.first { $0.name == "Tesla" })
        XCTAssertNotNil(old.categories.first { $0.name == "Pets" }, "kinds of spending stay")
        XCTAssertTrue(old.rules.isEmpty)
        XCTAssertEqual(old.transactions.first { $0.id == "6" }?.categoryId, "gas", "Tesla charging is gas & auto")
        XCTAssertEqual(old.transactions.first { $0.id == "7" }?.categoryId, "pets-cd34")

        let fitness = store.suggestedCategories.first { $0.name == "Fitness" }!
        store.accept(fitness)
        XCTAssertNotNil(store.data.categories.first { $0.name == "Fitness" })
        XCTAssertEqual(store.uncategorized.count, 4)

        let id = store.addCategory("Pets", group: "Everyday")
        XCTAssertEqual(store.addCategory("pets", group: "Everyday"), id, "no duplicates")
        store.hideCategory(id)
        XCTAssertFalse(store.expenseCategories.contains { $0.id == id })
    }
}

final class CardTests: XCTestCase {
    func testCardChargedPaidAndGrowth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: 12))! }
        var data = BudgetData()
        // Owes $900 today.
        data.accounts = [Account(id: "card", name: "Gold Card", institution: "Robinhood", kind: .credit, balance: -90_000)]
        data.transactions = [
            Transaction(id: "a", accountId: "card", date: d(7, 10), amount: -30_000, payee: "Target", categoryId: "shopping"),
            Transaction(id: "b", accountId: "card", date: d(8, 10), amount: -40_000, payee: "Target", categoryId: "shopping"),
            Transaction(id: "c", accountId: "card", date: d(9, 10), amount: -50_000, payee: "Target", categoryId: "shopping"),
            Transaction(id: "d", accountId: "card", date: d(9, 20), amount: 30_000, payee: "PAYMENT THANK YOU", categoryId: nil, isTransfer: true),
            Transaction(id: "e", accountId: "card", date: d(10, 5), amount: -20_000, payee: "Kroger", categoryId: "groceries"),
            Transaction(id: "f", accountId: "card", date: d(10, 8), amount: 10_000, payee: "PAYMENT THANK YOU", categoryId: nil, isTransfer: true),
        ]
        let store = BudgetStore(data: data, isDemo: true)
        store.calendar = cal
        store.now = { d(10, 15) }
        let card = store.creditCards[0]
        XCTAssertEqual(store.cardMonth(card, store.currentMonth), CardMonth(charged: 20_000, paid: 10_000))
        let health = store.cardHealth(card)
        XCTAssertEqual(health.owedNow, 90_000)
        XCTAssertFalse(health.paysInFull, "paid $100 against $500 charged in September")
        XCTAssertGreaterThan(health.growthSinceThreeMonths, 10_000)
        XCTAssertEqual(store.growingCards.count, 1)
        // Payments are not spending; card purchases count once, in their categories.
        XCTAssertEqual(store.spent("shopping", in: store.month(-1, from: store.currentMonth)), 50_000)
    }
}

final class SavingsTests: XCTestCase {
    private func store() -> BudgetStore {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: 12))! }
        var data = BudgetData()
        data.accounts = [Account(id: "c", name: "Card", institution: "X", kind: .credit, balance: 0)]
        var txns: [Transaction] = []
        // Usual: shopping $400, dining $300, rent $2000 (bills are never cut).
        for m in 7...9 {
            txns.append(Transaction(id: "s\(m)", accountId: "c", date: d(m, 5), amount: -40_000, payee: "Target", categoryId: "shopping"))
            txns.append(Transaction(id: "d\(m)", accountId: "c", date: d(m, 6), amount: -30_000, payee: "Chipotle", categoryId: "dining"))
            txns.append(Transaction(id: "r\(m)", accountId: "c", date: d(m, 1), amount: -200_000, payee: "Rent", categoryId: "housing"))
        }
        data.transactions = txns
        let s = BudgetStore(data: data, isDemo: true)
        s.calendar = cal
        s.now = { d(10, 2) }
        return s
    }

    func testSuggestionsCutOnlyFlexibleSpendingAndMeetTheGoal() {
        let s = store()
        let limits = s.suggestedLimits(toSave: 21_000, in: s.currentMonth)
        XCTAssertNil(limits["housing"], "bills aren't cut")
        // Shopping and dining are equally flexible: $210 split in proportion.
        XCTAssertEqual(limits["shopping"], 28_000)
        XCTAssertEqual(limits["dining"], 21_000)
        XCTAssertGreaterThanOrEqual(s.savings(of: limits, in: s.currentMonth), 21_000)
    }

    func testCutsNeverExceedSixtyPercentUnlessSkipped() {
        let s = store()
        let limits = s.suggestedLimits(toSave: 1_000_000, in: s.currentMonth)
        XCTAssertEqual(limits["shopping"], 16_000) // 40% of $400 kept
    }

    func testPlanOnlyChangesItsMonth() {
        let s = store()
        s.setLimit("shopping", 40_000)
        s.data.plan = SavingsPlan(month: s.currentMonth, goal: 40_000, limits: ["shopping": 0])
        let shopping = s.category("shopping")!
        XCTAssertEqual(s.limit(shopping, in: s.currentMonth), 0)
        XCTAssertEqual(s.limit(shopping, in: s.month(1, from: s.currentMonth)), 40_000)
        XCTAssertEqual(s.savings(of: s.plan!.limits, in: s.currentMonth), 40_000)
    }

    func testCardFeesAreSortedAndAimForZero() {
        XCTAssertEqual(BankSync.categorize(payee: "INTEREST CHARGE ON PURCHASES", amount: -1_234, rules: []), "fees")
        XCTAssertEqual(BankSync.categorize(payee: "LATE FEE", amount: -3_900, rules: []), "fees")
        let s = store()
        XCTAssertTrue(s.category("fees")!.aimsForZero)
        XCTAssertFalse(s.topCategories(in: s.currentMonth).contains { $0.id == "fees" })
    }
}
