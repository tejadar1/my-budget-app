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
        // Ron's account: Jul $300, Aug $0, Sep $900 → $400. Ana's starts in
        // August: Aug $600, Sep $0 → $300. Usual $700.
        XCTAssertEqual(store.averageSpent("groceries", before: store.currentMonth), 70_000)
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
        XCTAssertEqual(store.category("groceries")?.limit, 70_000)
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
        XCTAssertEqual(store.toCheck.count, 3)
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
        // MTA now has a home (Commuting & Rides), so no Transit suggestion.
        XCTAssertEqual(Set(recommended.map(\.name)), ["Coffee", "Fitness", "Golf"]) // Blue Bottle → Coffee
        let golfSuggestion = recommended.first { $0.name == "Golf" }!
        XCTAssertEqual(golfSuggestion.transactionIds.count, 3)
        XCTAssertEqual(store.monthlyAverage(of: golfSuggestion), 17_400)

        store.accept(golfSuggestion)
        let golf = store.data.categories.first { $0.name == "Golf" }
        XCTAssertNotNil(golf)
        XCTAssertEqual(store.data.transactions.first { $0.id == "g2" }?.categoryId, golf?.id)
        XCTAssertFalse(store.recommendedCategories().contains { $0.name == "Golf" })
        XCTAssertEqual(BankSync.categorize(payee: "TESLA SUPERCHARGER US", amount: -1_000, rules: []), "gas")
        let expected: [(String, String)] = [
            ("VEOLIA WATER NEW YORK", "utilities"), ("AMAZON PRIME*2K4", "subscriptions"), ("AMZN Mktp US", "shopping"),
            ("UBER *EATS", "dining"), ("UBER *TRIP", "commute"), ("UBER EATS PENDING", "dining"),
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

    func testBarsFoldIntoDining() {
        var data = BudgetData()
        data.categories.append(Category(id: "bars-1a2b", name: "Bars", group: "Everyday", limit: 10_000))
        if let d = data.categories.firstIndex(where: { $0.id == "dining" }) { data.categories[d].limit = 30_000 }
        data.rules = [PayeeRule(payeeKey: "dead rabbit", categoryId: "bars-1a2b")]
        data.transactions = [Transaction(id: "b", accountId: "x", date: date(2026, 10, 3), amount: -4_200,
                                         payee: "DEAD RABBIT", categoryId: "bars-1a2b")]
        BudgetStore.mergeBarsIntoDining(&data)
        XCTAssertNil(data.categories.first { $0.name == "Bars" })
        XCTAssertEqual(data.transactions[0].categoryId, "dining")
        XCTAssertEqual(data.rules[0].categoryId, "dining")
        XCTAssertEqual(data.categories.first { $0.id == "dining" }?.limit, 40_000)
        XCTAssertEqual(data.categories.first { $0.id == "dining" }?.name, "Dining & Bars")
        XCTAssertEqual(BankSync.categorize(payee: "THE PEOPLES WINE BAR", amount: -6_000, rules: []), "dining")
        XCTAssertEqual(BankSync.categorize(payee: "OTHER HALF BREWING", amount: -3_000, rules: []), "dining")
        XCTAssertEqual(BankSync.categorize(payee: "DEAD RABBIT BAR", amount: -3_000, rules: []), "dining")
        XCTAssertEqual(BankSync.categorize(payee: "BARNES & NOBLE #2675", amount: -3_000, rules: []), "shopping")
    }

    func testBankCategoryOrMerchantCodeSortsUnknownStores() throws {
        XCTAssertEqual(BankSync.categorize(payee: "ZZ UNKNOWN 44", amount: -2_000, rules: [], bankCategory: "mcc:5813"), "dining")
        XCTAssertEqual(BankSync.categorize(payee: "ZZ UNKNOWN 44", amount: -2_000, rules: [], bankCategory: "Bars & Nightlife"), "dining")
        XCTAssertEqual(BankSync.categorize(payee: "ZZ UNKNOWN 44", amount: -2_000, rules: [], bankCategory: "mcc:5411"), "groceries")
        XCTAssertNil(BankSync.categorize(payee: "ZZ UNKNOWN 44", amount: -2_000, rules: [], bankCategory: nil))
        // Store lists and your rules come first.
        XCTAssertEqual(BankSync.categorize(payee: "KROGER", amount: -2_000, rules: [], bankCategory: "mcc:5813"), "groceries")

        let json = #"{"id":"t1","posted":1790000000,"amount":"-12.00","description":"X","extra":{"category":"Restaurants","mcc":5812,"nested":{"a":1}}}"#
        let t = try JSONDecoder().decode(SimpleFIN.SFTransaction.self, from: Data(json.utf8))
        XCTAssertEqual(t.extra?.bankCategory, "mcc:5812")
        let plain = try JSONDecoder().decode(SimpleFIN.SFTransaction.self,
                                             from: Data(#"{"id":"t2","posted":1,"amount":"-1","description":"Y"}"#.utf8))
        XCTAssertNil(plain.extra)
    }

    func testHiddenAccountLeavesTheBudget() {
        let store = makeStore()
        store.data.accounts[1].balance = 50_000 // Ana's checking
        let netBefore = store.netWorth
        store.setHidden("a", true)
        XCTAssertEqual(store.spent("groceries", in: store.currentMonth), 10_000, "Ana's groceries no longer count")
        XCTAssertFalse(store.uncategorized.contains { $0.accountId == "a" })
        XCTAssertEqual(store.netWorth, netBefore - 50_000)
        XCTAssertEqual(store.hiddenAccounts.map(\.id), ["a"])
        store.setHidden("a", false)
        XCTAssertEqual(store.spent("groceries", in: store.currentMonth), 13_000)
        XCTAssertNil(store.data.accounts[1].hidden)
    }

    func testMaximizeSavedAndCardPayoffMinimizeFees() {
        let store = makeStore()
        store.data.accounts.append(Account(id: "s", name: "Online Savings", institution: "Ally", kind: .savings, balance: 0))
        store.data.accounts.append(Account(id: "c", name: "Gold", institution: "Robinhood", kind: .credit, balance: 0))
        store.data.transactions += [
            Transaction(id: "s1", accountId: "s", date: date(2026, 10, 2), amount: 50_000, payee: "From CHK", isTransfer: true),
            Transaction(id: "s2", accountId: "s", date: date(2026, 10, 9), amount: -10_000, payee: "To CHK", isTransfer: true),
            Transaction(id: "s3", accountId: "s", date: date(2026, 10, 31), amount: 120, payee: "Interest Paid"),
            Transaction(id: "c1", accountId: "c", date: date(2026, 10, 3), amount: -20_000, payee: "Target", categoryId: "shopping"),
            Transaction(id: "c2", accountId: "c", date: date(2026, 10, 20), amount: 35_000, payee: "Payment Thank You", isTransfer: true),
            Transaction(id: "f1", accountId: "r", date: date(2026, 10, 5), amount: -300, payee: "NON-CHASE ATM FEE", categoryId: "bankfees"),
            Transaction(id: "f2", accountId: "c", date: date(2026, 10, 25), amount: -1_500, payee: "INTEREST CHARGE", categoryId: "fees"),
        ]
        let month = store.currentMonth
        XCTAssertEqual(store.savedAndInvested(in: month), 40_000, "in minus out, interest doesn't count")
        XCTAssertEqual(store.extraCardPayoff(in: month), 13_500, "paid $350 vs $215 charged (incl. interest)")
        XCTAssertEqual(store.minimizeSpent(in: month), 1_800)
        XCTAssertEqual(BankSync.categorize(payee: "NON-CHASE ATM FEE", amount: -300, rules: []), "bankfees")
        XCTAssertEqual(BankSync.categorize(payee: "MONTHLY MAINTENANCE FEE", amount: -1_200, rules: []), "bankfees")
        XCTAssertEqual(BankSync.categorize(payee: "PURCHASE INTEREST CHARGE", amount: -900, rules: []), "fees")
        for plan in ["MY CHASE PLAN FEE", "PLAN IT FEE", "MONTHLY PLAN FEE", "CITI FLEX PAY FEE"] {
            XCTAssertEqual(BankSync.categorize(payee: plan, amount: -1_299, rules: []), "fees", plan)
        }
        XCTAssertTrue(store.category("bankfees")?.aimsForZero ?? false)
    }

    func testTaxes() {
        for payee in ["IRS USATAXPYMT 2026", "NYS DTF PIT TAX PAYMENT", "INTUIT *TURBOTAX", "NYC DOF PROPERTY TAX"] {
            XCTAssertEqual(BankSync.categorize(payee: payee, amount: -50_000, rules: []), "taxes", payee)
        }
        XCTAssertFalse(BankSync.looksLikeTransfer("IRS USATAXPYMT 2026"))
        XCTAssertEqual(BankSync.categorize(payee: "IRS TREAS 310 TAX REF", amount: 120_000, rules: []), "income")
        XCTAssertEqual(makeStore().category("taxes")?.group, "Bills")
    }

    func testCollegeSavingsCountsAsSavedNotSpent() {
        let store = makeStore()
        let t = Transaction(id: "v", accountId: "r", date: date(2026, 10, 6), amount: -25_000,
                            payee: "VANGUARD COLLEGE 529 PLAN", isTransfer: BankSync.looksLikeTransfer("VANGUARD COLLEGE 529 PLAN"))
        XCTAssertTrue(t.isTransfer)
        store.data.transactions.append(t)
        XCTAssertEqual(store.savedAndInvested(in: store.currentMonth), 25_000)
        XCTAssertEqual(store.transferLabel(t), "Saved & invested")
        XCTAssertEqual(AccountKind.guess(from: "Vanguard College Savings"), .investment)

        // Once the 529 account is connected, its deposit counts instead (not twice).
        store.data.accounts.append(Account(id: "529", name: "NY 529 College Savings", institution: "Vanguard",
                                           kind: .investment, balance: 0))
        store.data.transactions.append(Transaction(id: "v2", accountId: "529", date: date(2026, 10, 7), amount: 25_000,
                                                   payee: "Contribution", isTransfer: true))
        XCTAssertEqual(store.savedAndInvested(in: store.currentMonth), 25_000)
    }

    func testCommutingAndCarPayments() {
        for (payee, category) in [("MTA*NYCT PAYGO", "commute"), ("LIRR ETIX", "commute"), ("CITI BIKE", "commute"),
                                  ("LYFT *RIDE SUN", "commute"), ("CURB NYC TAXI", "commute"), ("NYC SUBWAY FARE", "commute"), ("SUBWAY 41022", "dining"),
                                  ("TESLA SUPERCHARGER", "gas"), ("E-ZPASS NY", "gas"),
                                  ("TESLA FINANCE PAYMENT", "carpayment"), ("ALLY AUTO PMT", "carpayment"),
                                  ("CHASE AUTO LOAN PMT", "carpayment")] {
            XCTAssertEqual(BankSync.categorize(payee: payee, amount: -3_000, rules: []), category, payee)
        }
        XCTAssertFalse(BankSync.looksLikeTransfer("CHASE AUTO PMT"), "a car payment isn't a card payment")

        // Old data: Uber and MTA were in Gas & Auto; a Transit category existed.
        var data = BudgetData()
        data.categories.append(Category(id: "transit-9", name: "Transit", group: "Everyday"))
        data.rules = [PayeeRule(payeeKey: "uber trip", categoryId: "gas")]
        data.transactions = [
            Transaction(id: "1", accountId: "x", date: date(2026, 10, 1), amount: -2_000, payee: "UBER *TRIP", categoryId: "gas"),
            Transaction(id: "2", accountId: "x", date: date(2026, 10, 1), amount: -290, payee: "OMNY", categoryId: "transit-9"),
            Transaction(id: "3", accountId: "x", date: date(2026, 10, 1), amount: -4_000, payee: "SHELL OIL", categoryId: "gas"),
            Transaction(id: "4", accountId: "x", date: date(2026, 10, 1), amount: -60_000, payee: "TESLA FINANCE", categoryId: "gas"),
        ]
        BudgetStore.splitCommuteFromGas(&data)
        XCTAssertEqual(data.transactions.map { $0.categoryId }, ["commute", "commute", "gas", "carpayment"])
        XCTAssertEqual(data.rules.first?.categoryId, "commute")
        XCTAssertNil(data.categories.first { $0.name == "Transit" })
    }

    func testLoanPaymentsDontPairAsTransfers() {
        var data = BudgetData()
        data.accounts = [
            Account(id: "chk", name: "Checking", institution: "Chase", kind: .checking, balance: 0),
            Account(id: "car", name: "Auto Loan", institution: "Tesla", kind: .loan, balance: 0, isOnBudget: false),
        ]
        let day = date(2026, 10, 1)
        data.transactions = [
            Transaction(id: "out", accountId: "chk", date: day, amount: -60_000, payee: "ACH DEBIT 1234", categoryId: nil),
            Transaction(id: "in", accountId: "car", date: day, amount: 60_000, payee: "Payment", categoryId: nil),
        ]
        BankSync.markTransfers(&data)
        XCTAssertEqual(data.transactions.first { $0.id == "out" }?.isTransfer, false)
    }

    func testEverythingGetsSortedAndHunchesWaitForAQuickCheck() {
        let store = makeStore()
        store.data.transactions += [
            Transaction(id: "l1", accountId: "r", date: date(2026, 9, 2), amount: -900, payee: "LUNA BAKERY BROOKLYN", categoryId: "dining"),
            Transaction(id: "l2", accountId: "r", date: date(2026, 10, 2), amount: -1_100, payee: "LUNA BAKERY BROOKLYN", categoryId: nil),
            Transaction(id: "z", accountId: "a", date: date(2026, 10, 3), amount: -4_000, payee: "ZZQX HOLDINGS LLC", categoryId: nil),
        ]
        BudgetStore.fillHunches(&store.data)
        XCTAssertTrue(store.data.transactions.filter { $0.amount < 0 && !$0.isTransfer }.allSatisfy { $0.categoryId != nil },
                      "every purchase has a category")
        XCTAssertEqual(store.data.transactions.first { $0.id == "l2" }?.categoryId, "dining", "same store, sorted like before")
        XCTAssertEqual(store.data.transactions.first { $0.id == "z" }?.categoryId, "shopping", "nothing to go on")
        XCTAssertTrue(Set(store.toCheck.map(\.id)).isSuperset(of: ["l2", "z"]))

        store.confirm("l2")
        XCTAssertFalse(store.toCheck.contains { $0.id == "l2" })
        XCTAssertEqual(BankSync.categorize(payee: "LUNA BAKERY BROOKLYN", amount: -500, rules: store.data.rules), "dining")

        // A known store is sure, the bank's text category is a hunch, a merchant code is sure.
        XCTAssertEqual(BankSync.sortSource(payee: "KROGER", amount: -1, rules: []).autoSort, "sure")
        XCTAssertEqual(BankSync.sortSource(payee: "ZZ", amount: -1, rules: [], bankCategory: "Restaurants").autoSort, "hunch")
        XCTAssertEqual(BankSync.sortSource(payee: "ZZ", amount: -1, rules: [], bankCategory: "mcc:5812").autoSort, "sure")
    }

    func testRecalculatingLimitsResetsFromTheLastThreeMonths() {
        let store = makeStore()
        store.setLimit("groceries", 99_900)
        store.setLimit("gifts", 5_000) // nothing spent on gifts lately
        store.setLimitsFromAverages()
        XCTAssertEqual(store.category("groceries")?.limit, 70_000, "usual $700")
        XCTAssertNil(store.category("gifts")?.limit)
        XCTAssertEqual(store.averagingMonths(before: store.currentMonth).count, 3)
    }

    func testABankWithShortHistoryIsntCountedAsZero() {
        let store = makeStore()
        // A card connected with only 30 days of history: $450 of dining in October so far,
        // $300 in September (from the 20th on, so September is partial for this card).
        store.data.accounts.append(Account(id: "new", name: "New Card", institution: "Amex", kind: .credit, balance: 0))
        store.data.transactions += [
            Transaction(id: "n1", accountId: "new", date: date(2026, 9, 20), amount: -30_000, payee: "Chipotle", categoryId: "dining"),
            Transaction(id: "n2", accountId: "new", date: date(2026, 10, 3), amount: -45_000, payee: "Chipotle", categoryId: "dining"),
        ]
        // Old way: $300 over 3 months = $100. The card has no full month yet, so it adds nothing
        // rather than dragging the usual down.
        XCTAssertEqual(store.averageSpent("dining", before: store.currentMonth), 0)

        // A month later (November), its October counts on its own: $450.
        store.now = { self.date(2026, 11, 15) }
        XCTAssertEqual(store.averageSpent("dining", before: store.currentMonth), 45_000)
    }

    func testPaidOnTheFirstButDepositedEarlyCountsForTheRightMonth() {
        let store = makeStore()
        // Usually paid on the 1st; August 1, 2026 is a Saturday, so it arrived July 31.
        for (id, m, d) in [("p1", 7, 1), ("p2", 7, 31), ("p3", 9, 1), ("p4", 10, 1)] {
            store.data.transactions.append(Transaction(id: id, accountId: "r", date: date(2026, m, d), amount: 100_000,
                                                       payee: "ACME CORP PAYROLL", categoryId: "income"))
        }
        XCTAssertEqual(store.income(in: store.monthStart(date(2026, 7, 1))), 100_000, "not two paychecks in July")
        XCTAssertEqual(store.income(in: store.monthStart(date(2026, 8, 1))), 100_000, "August's arrived July 31")
    }

    func testBiweeklyPayHasExtraPaychecksAndASteadyUsual() {
        let store = makeStore()
        store.data.transactions.removeAll { $0.categoryId == "income" }
        var day = date(2026, 7, 3)
        var n = 0
        while day < date(2026, 10, 15) {
            n += 1
            store.data.transactions.append(Transaction(id: "b\(n)", accountId: "r", date: day, amount: 200_000,
                                                       payee: "BIWEEKLY INC PAYROLL", categoryId: "income"))
            day = day.addingTimeInterval(14 * 86_400)
        }
        let july = store.monthStart(date(2026, 7, 1))
        XCTAssertEqual(store.paychecks(in: july).count, 3) // Jul 3, 17, 31
        XCTAssertEqual(store.paychecks(in: july).extra, 1)
        XCTAssertEqual(store.averageIncome(before: store.currentMonth), 433_333, "$2,000 × 26 ÷ 12")
    }

    func testTwiceAMonthPayIsNotMistakenForBiweekly() {
        let store = makeStore()
        store.data.transactions.removeAll { $0.categoryId == "income" }
        for m in 7...10 {
            for d in [1, 15] {
                store.data.transactions.append(Transaction(id: "s\(m)-\(d)", accountId: "r", date: date(2026, m, d),
                                                           amount: 150_000, payee: "PAYROLL DEPOSIT", categoryId: "income"))
            }
        }
        XCTAssertEqual(store.paychecks(in: store.currentMonth).extra, 0)
        XCTAssertEqual(store.averageIncome(before: store.currentMonth), 300_000)
    }

    func testTuitionIsABillTheSavingsPlanLeavesAlone() {
        let store = makeStore()
        store.data.transactions.append(Transaction(id: "t", accountId: "r", date: date(2026, 9, 5), amount: -150_000,
                                                   payee: "FACTSMGT TUITION", categoryId: nil))
        let education = store.recommendedCategories().first { $0.name == "Education" }
        XCTAssertEqual(education?.group, "Bills")
        store.accept(education!)
        let category = store.data.categories.first { $0.name == "Education" }!
        XCTAssertEqual(store.flexibility(of: category), 0, "never trimmed")
    }

    func testMoreRestaurantsAndCarCosts() {
        let dining = ["JOE'S PIZZA BROADWAY", "LOS TACOS NO 1", "XI'AN FAMOUS FOODS", "THAI VILLA", "PHO BANG",
                      "PEKING DUCK HOUSE DIM SUM", "HALAL GUYS", "VAN LEEUWEN ICE CREAM", "RAISING CANES 123",
                      "KEENS STEAKHOUSE", "OSTERIA MORINI", "BLANK STREET COFFEE", "DOS TOROS TAQUERIA"]
        for payee in dining {
            XCTAssertEqual(BankSync.categorize(payee: payee, amount: -2_000, rules: []), "dining", payee)
        }
        let auto = ["SP+ PARKING 0412", "ICON PARKING SYSTEMS", "PARKMOBILE", "LAZ PARKING 22", "NYC DOT PARKING METER",
                    "MTA BRIDGES AND TUNNELS", "NJ TURNPIKE", "MIDTOWN AUTO BODY", "TAKE 5 OIL CHANGE",
                    "TESLA SERVICE CENTER", "DISCOUNT TIRE 1234", "MAIN ST GARAGE"]
        for payee in auto {
            XCTAssertEqual(BankSync.categorize(payee: payee, amount: -2_000, rules: []), "gas", payee)
        }
        XCTAssertEqual(BankSync.categorize(payee: "MTA*NYCT PAYGO", amount: -290, rules: []), "commute")
        XCTAssertNotEqual(BankSync.categorize(payee: "VANGUARD RETIREMENT", amount: -2_000, rules: []), "gas")
    }

    func testTripFundFillsMonthlyAndTripsDrawItDown() {
        let store = makeStore()
        for m in 8...9 {
            store.data.transactions.append(Transaction(id: "pay\(m)", accountId: "r", date: date(2026, m, 15),
                                                       amount: 300_000, payee: "Payroll", categoryId: "income"))
        }
        store.data.tripFund = TripFund(monthly: 30_000, start: date(2026, 8, 1))
        XCTAssertEqual(store.tripFundBalance(), 90_000, "Aug, Sep, Oct")
        store.saveTrip(Trip(id: "m", name: "Miami", start: date(2027, 1, 10), end: date(2027, 1, 14), budget: 250_000))
        store.data.transactions.append(Transaction(id: "f", accountId: "r", date: date(2026, 9, 20), amount: -82_000,
                                                   payee: "JetBlue", categoryId: "travel", tripId: "m"))
        XCTAssertEqual(store.tripFundBalance(), 8_000)
        // $1,680 left to cover, $80 in the fund, 3 months to January → $533 a month.
        let need = store.tripFundNeed(store.data.trips[0])
        XCTAssertEqual(need?.covered, false)
        XCTAssertEqual(need?.perMonth, 53_333)
    }

    func testOverspendingAMonthMeansLessForTrips() {
        let store = makeStore()
        // August: $3,000 in, $600 groceries + $2,300 shopping = $100 left.
        store.data.transactions += [
            Transaction(id: "pay8", accountId: "r", date: date(2026, 8, 15), amount: 300_000, payee: "Payroll", categoryId: "income"),
            Transaction(id: "big", accountId: "r", date: date(2026, 8, 20), amount: -230_000, payee: "Best Buy", categoryId: "shopping"),
        ]
        store.data.tripFund = TripFund(monthly: 30_000, start: date(2026, 8, 1))
        // Aug adds $100 (all that was left), Sep adds $0 (no income), Oct adds the planned $300.
        XCTAssertEqual(store.tripFundBalance(), 40_000)
        XCTAssertEqual(store.tripFundShortMonths(), 2)
    }

    func testSafeToSpendKeepsSavingsAndTripsFirst() {
        let store = makeStore()
        store.data.tripFund = TripFund(monthly: 30_000, start: date(2026, 10, 1))
        store.data.plan = SavingsPlan(month: store.currentMonth, goal: 25_000, limits: [:])
        // $3,000 in; $130 groceries spent; no bills due; $550 kept → $2,320.
        XCTAssertEqual(store.setAside(in: store.currentMonth), 55_000)
        XCTAssertEqual(store.safeToSpend(in: store.currentMonth), 300_000 - 13_000 - 55_000)
    }

    func testATripIsPaidForFromFirstPurchaseUntilAfterIt() {
        let store = makeStore()
        store.saveTrip(Trip(id: "m", name: "Miami", start: date(2027, 1, 10), end: date(2027, 1, 14), budget: 250_000))
        store.data.transactions.append(Transaction(id: "f", accountId: "r", date: date(2026, 9, 20), amount: -82_000,
                                                   payee: "JetBlue", categoryId: "travel", tripId: "m"))
        let plan = store.tripSchedule(store.data.trips[0])!
        // September (flights) through February (the month after): 6 months.
        XCTAssertEqual(plan.perMonth, 41_666)
        XCTAssertEqual(store.tripSetAside(in: store.currentMonth), 41_666)
        XCTAssertEqual(store.tripSetAside(in: store.monthStart(date(2027, 3, 1))), 0, "done after February")
        // A fixed trip fund replaces the per-trip plan.
        store.data.tripFund = TripFund(monthly: 30_000, start: date(2026, 10, 1))
        XCTAssertEqual(store.tripSetAside(in: store.currentMonth), 30_000)
    }

    func testTransactionsTabFilters() {
        let store = makeStore()
        XCTAssertEqual(store.transactions(matching: "kroger", filter: .all).map(\.id), ["4", "3", "2", "1"])
        XCTAssertEqual(store.transactions(matching: "", filter: .transfers).map(\.id), ["8"])
        XCTAssertEqual(Set(store.transactions(matching: "", filter: .toCheck).map(\.id)), ["10", "11"])
        XCTAssertEqual(Set(store.transactions(matching: "", filter: .all, categoryId: "groceries", owner: .p2).map(\.id)),
                       ["2", "5", "6"])
        XCTAssertFalse(store.transactions(matching: "", filter: .all).contains { $0.accountId == "m" } == false,
                       "off-budget accounts still show; only hidden ones don't")
        store.setHidden("m", true)
        XCTAssertFalse(store.transactions(matching: "", filter: .all).contains { $0.accountId == "m" })
    }

    func testMonthPlanIsIncomeMinusBillsSavingsTripsThenSpending() {
        let store = makeStore()
        store.data.transactions.append(Transaction(id: "rent", accountId: "r", date: date(2026, 10, 1), amount: -150_000,
                                                   payee: "Rent", categoryId: "housing"))
        store.data.plan = SavingsPlan(month: store.currentMonth, goal: 25_000, limits: [:])
        store.data.tripFund = TripFund(monthly: 30_000, start: date(2026, 10, 1))
        let plan = store.monthPlan(store.currentMonth)
        XCTAssertEqual(plan.income, 300_000)
        XCTAssertEqual(plan.bills, 150_000)
        XCTAssertEqual(plan.toSpend, 300_000 - 150_000 - 25_000 - 30_000)
        XCTAssertEqual(plan.everydaySpent, 13_000, "groceries; rent is a bill")
        XCTAssertEqual(plan.leftToSpend, 95_000 - 13_000)
        let everyday = store.spentByOwner(in: store.currentMonth, everydayOnly: true)
        XCTAssertEqual(everyday.values.reduce(0, +), plan.everydaySpent, "per person matches Spent")
        XCTAssertFalse(store.topCategories(in: store.currentMonth).contains { $0.id == "housing" })

        // Limits bigger than what there is to spend get trimmed to fit.
        store.setLimit("groceries", 60_000); store.setLimit("shopping", 80_000)
        XCTAssertEqual(store.monthPlan(store.currentMonth).limitsOverBy, 45_000)
        let stillOver = store.fitLimitsToPlan(store.currentMonth)
        XCTAssertLessThan(stillOver, 45_000, "trimmed, though never more than 40% of a limit")
        XCTAssertLessThan(store.category("shopping")!.limit!, 80_000)
    }

    func testBillsCountAtLeastTheirUsualAmount() {
        let store = makeStore()
        // Electric: $120, $90, $150 the last three months; nothing paid yet in October.
        for (m, amount) in [(7, 12_000), (8, 9_000), (9, 15_000)] {
            store.data.transactions.append(Transaction(id: "e\(m)", accountId: "r", date: date(2026, m, 20),
                                                       amount: -amount, payee: "Con Ed", categoryId: "utilities"))
        }
        let line = store.billLines(store.currentMonth).first { $0.category.id == "utilities" }
        XCTAssertEqual(line?.paid, 0)
        // Con Ed is a known monthly bill still due; its latest bill ($150) beats the $120 usual.
        XCTAssertEqual(line?.stillToCome, 15_000, "planned before it's paid, at the higher of usual and the latest bill")
        XCTAssertEqual(store.monthPlan(store.currentMonth).bills, 15_000)
    }

    func testFindsSubscriptionsByPattern() {
        let store = makeStore()
        for (m, d) in [(8, 3), (9, 4), (10, 3)] {
            store.data.transactions.append(Transaction(id: "z\(m)", accountId: "r", date: date(2026, m, d), amount: -1_299,
                                                       payee: "ZZQ MEDIA LLC", categoryId: "shopping", autoSort: "hunch"))
        }
        // A breakfast spot: monthly-ish but the amount changes. Stays in Dining.
        for (m, amount) in [(8, 1_450), (9, 1_380), (10, 1_520)] {
            store.data.transactions.append(Transaction(id: "l\(m)", accountId: "r", date: date(2026, m, 6), amount: -amount,
                                                       payee: "LENNYS BAGELS", categoryId: "dining", autoSort: "sure"))
        }
        // You put this one in Shopping yourself (no autoSort): left alone.
        for m in 8...10 {
            store.data.transactions.append(Transaction(id: "y\(m)", accountId: "r", date: date(2026, m, 9), amount: -999,
                                                       payee: "YARN CLUB", categoryId: "shopping"))
        }
        XCTAssertEqual(store.detectSubscriptions(), 3)
        XCTAssertEqual(store.data.transactions.first { $0.id == "z9" }?.categoryId, "subscriptions")
        XCTAssertTrue(store.toCheck.contains { $0.id == "z10" }, "shows in Check these")
        XCTAssertEqual(store.data.transactions.first { $0.id == "l9" }?.categoryId, "dining")
        XCTAssertEqual(store.data.transactions.first { $0.id == "y9" }?.categoryId, "shopping")
        XCTAssertEqual(BankSync.categorize(payee: "APPLE MUSIC", amount: -1_099, rules: []), "subscriptions")
    }

    func testPrioritiesComeFirstAndLimitsFollow() {
        let store = makeStore()
        // Shopping has been $1,200 a month; groceries come from makeStore.
        for m in 7...9 {
            store.data.transactions.append(Transaction(id: "sh\(m)", accountId: "r", date: date(2026, m, 10), amount: -120_000,
                                                       payee: "Target", categoryId: "shopping"))
        }
        store.data.priorities = Priorities(savings: 100_000, cardPaydown: 50_000)
        let plan = store.monthPlan(store.currentMonth)
        XCTAssertEqual(plan.toSpend, 300_000 - 100_000 - 50_000, "income − savings − card paydown")
        // Habit says $1,200 shopping + $700 groceries = $1,900, more than the $1,500 to spend.
        store.setLimitsToPlan(store.currentMonth)
        let shopping = store.category("shopping")!.limit!
        XCTAssertLessThan(shopping, 120_000, "shopping is trimmed")
        XCTAssertLessThanOrEqual(store.monthPlan(store.currentMonth).everydayLimits, plan.toSpend)
        XCTAssertGreaterThan(store.category("groceries")!.limit!, 60_000, "groceries trimmed far less than shopping")
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
    func testMostYouCanSaveIsTheCapOnFlexibleSpending() {
        let s = store()
        let most = s.maxSavings(in: s.currentMonth)
        XCTAssertGreaterThan(most, 0)
        let limits = s.suggestedLimits(toSave: most + 100_000, in: s.currentMonth)
        XCTAssertLessThanOrEqual(s.savings(of: limits, in: s.currentMonth), most)
    }

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
