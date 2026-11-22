import SwiftUI

/// Every "why" in one place. Screens say what's true and what to do; this
/// page says how Upside thinks. Screens link here with Learn more.
enum HelpTopic: String, CaseIterable, Identifiable {
    case month, planning, overspending, income, sorting, people, transfers, tripsGoals, savings, monthEnd, alerts, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Your month"
        case .planning: return "Planning"
        case .overspending: return "When you go over"
        case .income: return "Income"
        case .sorting: return "Sorting purchases"
        case .people: return "Zelle, Venmo and Cash App"
        case .transfers: return "Transfers"
        case .tripsGoals: return "Trips and goals"
        case .savings: return "Savings"
        case .monthEnd: return "Month end"
        case .alerts: return "Alerts"
        case .privacy: return "Your data"
        }
    }

    var symbol: String {
        switch self {
        case .month: return "calendar"
        case .planning: return "list.bullet.clipboard"
        case .overspending: return "exclamationmark.circle"
        case .income: return "dollarsign.circle"
        case .sorting: return "tray.full"
        case .people: return "person.2"
        case .transfers: return "arrow.left.arrow.right"
        case .tripsGoals: return "airplane"
        case .savings: return "banknote"
        case .monthEnd: return "checkmark.seal"
        case .alerts: return "bell"
        case .privacy: return "lock"
        }
    }

    /// Short paragraphs, plain words.
    var body: [String] {
        switch self {
        case .month:
            return [
                "Some money comes first: bills, savings, card paydown, trips and goals. What's left is your spending money, and your everyday limits share it.",
                "Income − bills − savings − cards − trips − goals = spending money.",
                "Money not in any limit is still yours. It covers surprises, or you can save it.",
                "Bills count at least their usual until they're paid, so a bill that hasn't come yet is never spending money.",
                "When a bill ends (cancelled, paid off), stop it in Bills: swipe left, then Stop, now or after a month you pick. From then on it isn't expected and its money is spending money again right away. If it charges again, it comes back.",
                "A regular bill with no charge for six weeks shows in Needs attention: did it end?",
                "Bills are in your spending totals; trips aren't, so a vacation never looks like a trend.",
            ]
        case .planning:
            return [
                "Plan the month at its start: from the month's wrap-up, on the 1st–5th, or before anything's spent. Savings first, then cards, then trips and goals, then limits.",
                "Start from what you usually spend fills every limit from your usual (the average of your last three months), fit to what's left.",
                "After that, changes are adjustments. Your recap compares the month with the plan you started with, so you can see where it went off plan.",
                "Just this month changes only this month. From now on changes your plan going forward.",
                "A limit far below what you usually spend can step down instead: it starts 10% under your usual and drops 10% each month you stay within it.",
                "Under $10 left reads Used up. A few dollars isn't really anything left.",
            ]
        case .overspending:
            return [
                "When a category goes past its limit, it stays over. Upside never raises the limit to hide it.",
                "Money not in any limit covers it first, and you'll have that much less at month end.",
                "If there isn't any, something has to give, and you choose: limits that still have room, then goals, trips, cards, and savings last. Savings is never chosen for you.",
                "Your choice changes this month only and can be undone. Once it's paid for, it leaves Needs attention, still shows as over in Categories, and the recap names it.",
                "Limits that add up to more than you have work the same way: Choose what gives.",
                "After the first week, Upside warns when a category is on pace to go over.",
            ]
        case .income:
            return [
                "Your usual income is a typical paycheck from the last six months, leaning low, so bonuses and overtime don't set the plan.",
                "Until this month's checks arrive, the plan counts on your usual. You can also type the income to plan on in Plan.",
                "Extra income (a bonus, a third paycheck) waits for a job: save it, put it toward cards, or spend it.",
                "A lower paycheck is noticed after the first one, and you choose whether to plan on it. A raise counts once it keeps arriving.",
            ]
        case .sorting:
            return [
                "Upside sorts a purchase by what you chose for that store before, then by stores it knows, then by your bank's hint.",
                "Anything it isn't sure about goes to Check these. Confirm it once and the store is remembered.",
                "Fix any purchase in place: swipe it for Move or Business, or long-press to move it straight to a category.",
                "Business purchases stay out of your budget, and money paid back for them isn't income.",
            ]
        case .people:
            return [
                "Payments to people are sorted by who they're for. Sort a Zelle to your sitter as child care once, and her next ones follow. Nobody else's do.",
                "Money a person sends you is kept apart from money you send them. Sort it into what it paid you back for, and that category goes down.",
                "A Zelle between people in your household is your own money moving. If a name only looks like one of you, Budget asks once.",
                "Settings › People you pay shows what Upside learned, and lets you change or forget anyone.",
            ]
        case .transfers:
            return [
                "Money moving between your own accounts isn't spending: the same amount leaving one account and arriving in another, card payments, and transfers the bank names.",
                "Paying a person is never a transfer, even when the bank calls it one.",
            ]
        case .tripsGoals:
            return [
                "Trips: money is set aside each month, from a trip fund or from each trip's own share. Trip purchases come out of the trip, never your everyday limits.",
                "Goals (an emergency fund, a yearly bill, a big purchase) take what they need each month off the top: what's left to save, spread over the months until it's due.",
            ]
        case .savings:
            return [
                "Saved & invested counts money moved into savings and investment accounts, plus transfers you mark Saved & invested. Interest and dividends don't count: that's growth, not saving.",
                "On payday, if this month's savings aren't done, Upside reminds you to move that paycheck's share.",
            ]
        case .monthEnd:
            return [
                "Wrap up the month: what you planned to save and what went in, and what was left over. Choose what to do with it, then plan the new month.",
                "The recap compares the month with the plan you started with, names what went over and what paid for it, and lists what went well.",
                "Trends compares months; the year view adds them up.",
            ]
        case .alerts:
            return [
                "A category at 80% or past its limit, bills two days before they're due, checking running low, large purchases, and payday savings.",
                "A limit you lowered yourself doesn't alert until spending goes past it.",
                "Hide a warning on Budget with ✕; it comes back only if it grows.",
            ]
        case .privacy:
            return [
                "Your budget lives on your phones and in your iCloud. There's no Upside server.",
                "Banks connect through SimpleFIN, read-only. Upside never moves money.",
                "Turn on Face ID in Settings to lock the app.",
            ]
        }
    }
}

/// The whole page; opens at `focus` when a screen's Learn more sent you.
struct HowItWorksView: View {
    var focus: HelpTopic? = nil
    /// A little below the top: the list runs under the bar, so `.top`
    /// would leave the topic's title behind it.
    private static let landing = UnitPoint(x: 0.5, y: 0.15)

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(HelpTopic.allCases) { topic in
                    Section {
                        ForEach(topic.body, id: \.self) { paragraph in
                            Text(paragraph).font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 2)
                        }
                    } header: {
                        // The id is on the header so a Learn more lands with
                        // the topic's title showing, not under the bar.
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.headline).foregroundStyle(.primary).textCase(nil)
                            .id(topic)
                    }
                }
            }
            .navigationTitle("How Upside works")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard let focus else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(focus, anchor: Self.landing) }
            }
        }
    }
}

/// "Learn more": opens How Upside works at one topic, pushed in the
/// current screen (a sheet hung off a list footer can close itself).
struct LearnMore: View {
    let topic: HelpTopic
    var label = "Learn more"

    var body: some View {
        NavigationLink {
            HowItWorksView(focus: topic)
        } label: {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .buttonStyle(.borderless)
    }
}
