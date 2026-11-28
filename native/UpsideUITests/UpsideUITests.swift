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
}
