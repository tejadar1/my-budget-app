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
}
