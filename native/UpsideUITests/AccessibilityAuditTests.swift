import XCTest

/// Apple's own accessibility audit (the one in Xcode's Accessibility
/// Inspector), run on every main screen of the sample budget: missing
/// VoiceOver labels, low contrast, tap targets smaller than 44 points, text
/// that doesn't grow with Text Size, and text cut off at the largest sizes.
///
/// Each issue is printed as an `AUDIT |` line in the test log so it can be
/// found and fixed. Issues listed in `known` are reported but don't fail;
/// anything new fails the test.
final class AccessibilityAuditTests: XCTestCase {
    /// Screens to audit: (name, launch arguments).
    static let screens: [(String, [String])] = [
        ("budget", ["-tab", "budget"]),
        ("accounts", ["-tab", "accounts"]),
        ("transactions", ["-tab", "transactions"]),
        ("settings", ["-tab", "settings"]),
        ("bills", ["-tab", "budget", "-open", "bills"]),
        ("income", ["-tab", "budget", "-open", "income"]),
        ("trips", ["-tab", "budget", "-open", "trips"]),
        ("category", ["-tab", "budget", "-open", "category:groceries"]),
        ("limits", ["-tab", "budget", "-open", "limits"]),
        ("plan", ["-tab", "budget", "-open", "priorities"]),
        ("overrun", ["-tab", "budget", "-open", "overrun", "-tight"]),
        ("monthstart", ["-tab", "budget", "-open", "monthstart"]),
        ("savings", ["-tab", "budget", "-open", "savings"]),
        ("recap", ["-tab", "budget", "-open", "recap"]),
        ("trends", ["-tab", "budget", "-open", "trends"]),
        ("account", ["-tab", "accounts", "-open", "account:ron-card"]),
        ("purchase", ["-tab", "budget", "-open", "purchase:dining"]),
        ("help", ["-tab", "budget", "-open", "help:overspending"]),
    ]

    /// Issues accepted for now, as "screen|type|label" (label may be empty).
    static let known: Set<String> = []

    override func setUp() { continueAfterFailure = true }

    func testEveryScreenPassesAppleAccessibilityAudit() throws {
        try audit(textSize: nil, screens: Self.screens, types: .all)
    }

    /// At the largest accessibility Text Size, nothing important is cut off.
    func testEveryScreenWorksAtTheLargestTextSize() throws {
        let main = ["budget", "accounts", "transactions", "settings", "bills", "income", "category", "plan", "purchase"]
        try audit(textSize: "UIContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                  screens: Self.screens.filter { main.contains($0.0) },
                  types: [.textClipped, .dynamicType])
    }

    private func audit(textSize: String?, screens: [(String, [String])],
                       types: XCUIAccessibilityAuditType) throws {
        var new: [String] = []
        for (name, args) in screens {
            let app = XCUIApplication()
            app.launchArguments = ["-demo"] + args
                + (textSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            sleep(2) // let the screen settle (sheets slide up)
            let size = textSize == nil ? "standard" : "largest"
            try app.performAccessibilityAudit(for: types) { issue in
                let label = issue.element?.label ?? ""
                let type = Self.name(issue.auditType)
                let key = "\(name)|\(type)|\(label)"
                print("AUDIT | \(size) | \(name) | \(type) | \(label) | \(issue.compactDescription)")
                if !Self.known.contains(key) { new.append("\(size) \(key): \(issue.compactDescription)") }
                return true // collect every issue; fail once below with the full list
            }
            app.terminate()
        }
        print("AUDIT | total new: \(new.count)")
        XCTAssertTrue(new.isEmpty, "Accessibility issues:\n" + new.joined(separator: "\n"))
    }

    private static func name(_ t: XCUIAccessibilityAuditType) -> String {
        switch t {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "description"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "other"
        }
    }
}
