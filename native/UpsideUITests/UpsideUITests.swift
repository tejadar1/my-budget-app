import XCTest

/// End to end: the real app, on the sample budget (`-demo`, nothing saved,
/// no bank or iCloud), driven the way a person would. Each test starts
/// fresh. Screens are found by what they say, so a test also checks wording.
final class UpsideUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ args: String...) {
        app.launchArguments = ["-demo", "-tab", "budget"] + args
        app.launch()
    }

    /// Anything on screen whose label contains `text`.
    private func any(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func button(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Scrolls the current screen until `element` is there (or gives up).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp() }
        return element.exists
    }

    func testStoppingABillThenRestartingIt() {
        launch("-open", "bills")
        XCTAssertTrue(app.navigationBars["Bills & subscriptions"].waitForExistence(timeout: 10))
        let netflix = any("Netflix")
        XCTAssertTrue(scrollTo(netflix), "Netflix is one of the sample subscriptions")
        netflix.swipeLeft()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "Stop is the first swipe action")
        stop.tap()
        // Paid this month: "After this month". Not yet: "It already stopped".
        let choice = [app.buttons["After this month"], app.buttons["It already stopped"]]
        XCTAssertTrue(choice[0].waitForExistence(timeout: 5) || choice[1].exists, "asks when it stops")
        (choice[0].exists ? choice[0] : choice[1]).tap()
        let restart = app.buttons["Restart"]
        XCTAssertTrue(scrollTo(restart), "listed under Stopped")
        restart.tap()
        XCTAssertFalse(restart.waitForExistence(timeout: 2), "back with the other bills")
    }

    func testChoosingWhatGivesThenUndoingIt() {
        launch("-open", "overrun", "-tight")
        XCTAssertTrue(app.navigationBars["Over the plan"].waitForExistence(timeout: 10))
        let cards = button("Pay ")
        XCTAssertTrue(scrollTo(cards), "cards is one of the choices")
        cards.tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(scrollTo(undo), "the choice shows, with Undo")
        XCTAssertTrue(any("less on cards this month").exists, "said once, as one line")
        undo.tap()
        XCTAssertTrue(scrollTo(button("Pay ")), "the choices are back")
    }

    func testIncomeOpensFromBudgetAndShowsTheMonth() {
        launch()
        let income = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Income'")).firstMatch
        XCTAssertTrue(scrollTo(income), "Income is on the Budget card")
        income.tap()
        XCTAssertTrue(app.navigationBars["Income"].waitForExistence(timeout: 5))
        XCTAssertTrue(any("in so far in").exists)
        XCTAssertTrue(scrollTo(any("Learn more")))
    }

    func testTripsAreOneCardThatOpensEveryTrip() {
        launch()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Trips'")).firstMatch
        XCTAssertTrue(scrollTo(card), "one Trips card on Budget")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Miami'")).count, 0,
                       "the trip is inside the card, not a card of its own")
        card.tap()
        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 5))
        XCTAssertTrue(any("Miami").exists, "every trip is listed")
        XCTAssertTrue(scrollTo(app.buttons["Add a trip"]))
    }

    func testLearnMoreOpensHowUpsideWorksAtItsTopic() {
        launch("-open", "help:overspending")
        XCTAssertTrue(app.navigationBars["How Upside works"].waitForExistence(timeout: 10))
        let title = app.staticTexts["When you go over"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.isHittable, "the topic's title isn't under the bar")
    }

    func testStoppingABillCanBeUndoneFromTheToast() {
        launch("-open", "bills")
        XCTAssertTrue(app.navigationBars["Bills & subscriptions"].waitForExistence(timeout: 10))
        let netflix = any("Netflix")
        XCTAssertTrue(scrollTo(netflix))
        netflix.swipeLeft()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        app.buttons["Stop"].tap()
        let choice = [app.buttons["After this month"], app.buttons["It already stopped"]]
        XCTAssertTrue(choice[0].waitForExistence(timeout: 5) || choice[1].exists)
        (choice[0].exists ? choice[0] : choice[1]).tap()
        XCTAssertTrue(any("stopped").waitForExistence(timeout: 3), "the toast says what happened")
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertFalse(app.buttons["Restart"].waitForExistence(timeout: 2), "nothing stopped after Undo")
    }

    func testAnIncomeSourceCanBeTakenOutAndPutBack() {
        launch("-open", "income")
        XCTAssertTrue(app.navigationBars["Income"].waitForExistence(timeout: 10))
        let source = any("Payroll Deposit")
        XCTAssertTrue(scrollTo(source))
        source.swipeLeft()
        let notIncome = app.buttons["Not income"]
        XCTAssertTrue(notIncome.waitForExistence(timeout: 5), "Not income is a swipe away")
        notIncome.tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(any("Payroll Deposit").waitForExistence(timeout: 3), "back after Undo")
    }

    func testStartTheMonthShowsThreeStepsAndCloses() {
        launch("-open", "monthstart")
        let bar = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Start '")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(any("Wrap up").exists)
        XCTAssertTrue(any("Income for").exists)
        XCTAssertTrue(any("Your plan").exists)
        app.buttons["Later"].tap()
        XCTAssertFalse(bar.waitForExistence(timeout: 2))
    }

    func testSavingAndTripsAreOneSection() {
        launch()
        XCTAssertTrue(scrollTo(app.staticTexts["Saving & trips"]), "one section for everything set aside")
        let savings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Savings'")).firstMatch
        XCTAssertTrue(scrollTo(savings))
        savings.tap()
        XCTAssertTrue(app.navigationBars["Savings"].waitForExistence(timeout: 5))
    }

    func testAdjustLimitOpensFromACategory() {
        launch("-open", "category:groceries")
        let adjust = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Adjust limit' OR label CONTAINS 'Set a limit'")).firstMatch
        XCTAssertTrue(adjust.waitForExistence(timeout: 10))
        adjust.tap()
        XCTAssertTrue(app.navigationBars["Adjust limit"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
    }

    func testASubscriptionQuestionIsAnsweredInOneTap() {
        launch()
        var question = any("went up")
        if !question.waitForExistence(timeout: 5) {
            let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show '")).firstMatch
            if scrollTo(more) { more.tap() }
            question = any("went up")
        }
        XCTAssertTrue(scrollTo(question), "Netflix's price increase is asked about")
        question.tap()
        let keep = app.buttons["Keep it"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3), "and can be undone")
    }

    func testHowUpsideWorksOpensFromSettings() {
        app.launchArguments = ["-demo", "-tab", "settings"]
        app.launch()
        let row = any("How Upside works")
        XCTAssertTrue(scrollTo(row))
        row.tap()
        XCTAssertTrue(app.navigationBars["How Upside works"].waitForExistence(timeout: 5))
    }
}
