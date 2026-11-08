import Foundation

// MARK: - Core data types
//
// Money is stored as Int cents. Spending is negative, income positive,
// the same sign convention banks (and SimpleFIN) use.

typealias Cents = Int

/// Who an account belongs to. Spending is credited to its account's owner.
enum Owner: String, Codable, CaseIterable, Identifiable, Hashable {
    case p1, p2, shared, unassigned
    var id: String { rawValue }

    /// The owners you can pick (unassigned is just "not set yet").
    static let pickable: [Owner] = [.p1, .p2, .shared]
}

struct People: Codable, Equatable {
    var p1: String = ""
    var p2: String = ""

    var isSetUp: Bool { !p1.trimmingCharacters(in: .whitespaces).isEmpty }

    func name(_ owner: Owner) -> String {
        switch owner {
        case .p1: return p1.isEmpty ? "You" : p1
        case .p2: return p2.isEmpty ? "Partner" : p2
        case .shared: return "Shared"
        case .unassigned: return "Not set"
        }
    }

    func initial(_ owner: Owner) -> String {
        switch owner {
        case .shared: return "S"
        case .unassigned: return "?"
        default: return String(name(owner).prefix(1)).uppercased()
        }
    }
}

enum AccountKind: String, Codable, CaseIterable {
    case checking, savings, credit, loan, investment, other

    var label: String {
        switch self {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .credit: return "Credit card"
        case .loan: return "Loan"
        case .investment: return "Investment"
        case .other: return "Account"
        }
    }

    /// Loans and investments don't count toward monthly spending.
    var isOnBudgetByDefault: Bool {
        switch self {
        case .loan, .investment: return false
        default: return true
        }
    }

    /// Best guess from the bank's account name, then the balance: banks
    /// report what you owe on a card as a negative balance.
    static func guess(from name: String, balance: Cents? = nil) -> AccountKind {
        let n = name.lowercased()
        if n.contains("credit") || n.contains("card") || n.contains("visa")
            || n.contains("mastercard") || n.contains("amex") || n.contains("gold") {
            return .credit
        }
        // College plans and brokerages before "savings": "Vanguard College Savings" is a 529.
        if n.contains("529") || n.contains("college") || n.contains("vanguard") || n.contains("fidelity")
            || n.contains("schwab") {
            return .investment
        }
        if n.contains("saving") || n.contains("money market") { return .savings }
        if n.contains("mortgage") || n.contains("loan") || n.contains("auto") || n.contains("heloc")
            || n.contains("home equity") || n.contains("student") {
            return .loan
        }
        if n.contains("401") || n.contains("ira") || n.contains("brokerage")
            || n.contains("invest") || n.contains("roth") || n.contains("529") || n.contains("college")
            || n.contains("vanguard") || n.contains("fidelity") || n.contains("schwab") {
            return .investment
        }
        if n.contains("checking") { return .checking }
        // Card products whose names don't say "card".
        let cardNames = ["freedom", "sapphire", "slate", "ink ", "amazon prime", "prime visa", "rewards",
                         "cash back", "cashback", "customized cash", "unlimited", "venture", "quicksilver",
                         "savor", "double cash", "custom cash", "costco anywhere", "discover it", "platinum",
                         "blue cash", "everyday", "delta skymiles", "united explorer", "marriott bonvoy",
                         "hilton honors", "southwest rapid", "bilt", "apple", "active cash", "autograph",
                         "elite", "signature", "preferred", "world of hyatt", "aadvantage"]
        if cardNames.contains(where: { n.contains($0) }) { return .credit }
        if let balance, balance < 0 { return .credit }
        return .other
    }
}

struct Account: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var institution: String
    var kind: AccountKind
    var balance: Cents
    var owner: Owner = .unassigned
    /// Off-budget accounts (mortgage, 401k…) show in net worth only.
    var isOnBudget: Bool = true
    var lastSynced: Date?
    /// Hidden accounts keep syncing but leave Accounts, net worth and the
    /// budget. Optional so budgets saved by older versions still load.
    var hidden: Bool? = nil
    /// When the bank itself last updated this account, which can lag
    /// days behind our own sync when a connection needs attention.
    var bankUpdated: Date? = nil

    var isHidden: Bool { hidden == true }
    /// Counts toward spending, income and Purchases to sort.
    var countsInBudget: Bool { isOnBudget && !isHidden }
}

struct Transaction: Identifiable, Codable, Hashable {
    var id: String
    var accountId: String
    var date: Date
    var amount: Cents
    var payee: String
    var categoryId: String?
    var tripId: String?
    var isPending: Bool = false
    /// Moving money between your own accounts (card payments, transfers)
    /// isn't spending.
    var isTransfer: Bool = false
    /// The bank's own category or merchant code, when the feed sends one.
    var bankCategory: String? = nil
    /// How Upside sorted it: "sure" (known store, merchant code), "hunch"
    /// (a guess you can check), nil (you chose, or older data).
    var autoSort: String? = nil

    /// A business expense you'll be paid back for (or the reimbursement
    /// itself): kept out of the budget and income.
    var business: Bool? = nil

    var isHunch: Bool { autoSort == "hunch" }
    var isBusiness: Bool { business == true }
}

struct Category: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var group: String
    /// Monthly limit; nil means no limit set.
    var limit: Cents?
    var isIncome: Bool = false
    var isHidden: Bool = false
    /// Unspent money carries into next month's limit, from this month on.
    var rolloverSince: Date? = nil

    /// The Minimize bundle: spending you want at $0 (fees, interest).
    var aimsForZero: Bool { group == Category.avoidGroup }
    static let avoidGroup = "Minimize"
}

/// A month where you cut flexible spending to save. Only that month's
/// limits change; the next month goes back to normal.
struct SavingsPlan: Codable, Equatable {
    var month: Date
    var goal: Cents
    /// Lowered limits for this month, by category id (0 = skip).
    var limits: [String: Cents]
    /// Last month's unspent money put toward cards this month.
    var cardExtra: Cents? = nil
}

struct CategoryGroup: Identifiable {
    var name: String
    var categories: [Category]
    var id: String { name }
}

struct CardMonth: Equatable {
    var charged: Cents
    var paid: Cents
}

struct CardHealth {
    var owedNow: Cents
    /// Positive = you owe more than three months ago.
    var growthSinceThreeMonths: Cents
    var since: Date
    var thisMonth: CardMonth
    var lastMonth: CardMonth
    var paysInFull: Bool
}

struct CategorySuggestion: Identifiable, Hashable {
    var name: String
    var group: String
    var transactionIds: [String]
    var example: String
    var id: String { name }
}

/// Learned from you: "this payee always goes in this category".
struct PayeeRule: Codable, Hashable {
    var payeeKey: String
    var categoryId: String
}

struct Trip: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var start: Date
    var end: Date
    var budget: Cents?
}

/// Everything Upside stores. One value, saved as a whole.
struct BudgetData: Codable {
    var people = People()
    var accounts: [Account] = []
    var transactions: [Transaction] = []
    var categories: [Category] = Category.defaults
    var rules: [PayeeRule] = []
    var trips: [Trip] = []
    var bankConnected = false
    var lastBankSync: Date?
    var plan: SavingsPlan?
    /// Alerts already sent ("2026-11:dining:80"), so each goes out once.
    /// Optional so budgets saved by older versions still load.
    var alertsSent: [String]?
    /// Money set aside each month for trips; trip purchases draw it down.
    var tripFund: TripFund?
    /// Paid first every month, before everyday spending.
    var priorities: Priorities?
    /// Stores you said aren't bills or subscriptions (payee keys).
    var notRecurring: [String]?
    /// Whose paycheck each income source is (by payer key), for paychecks
    /// into a joint account.
    var incomeOwners: [String: Owner]?
    /// Problems SimpleFIN reported on the last sync ("reconnect Bank of America").
    var syncErrors: [String]?
    /// Months whose unspent money you already decided about ("2026-10").
    var leftoverDone: [String]?
    /// Money set aside for things besides trips (emergency fund, yearly bills, big purchases).
    var goals: [Goal]?
    /// Trips turned off: no trip fund, no trip set-aside in the plan.
    var tripsOff: Bool?
}

/// "Pay yourself first": standing monthly amounts taken off the top.
struct Priorities: Codable, Hashable {
    var savings: Cents = 0
    var cardPaydown: Cents = 0
    /// Income you plan around; nil uses your usual. Optional so plans
    /// saved before this existed still load.
    var plannedIncome: Cents? = nil
}

/// A virtual fund: grows by `monthly` each month from `start`, shrinks
/// by everything tagged to a trip. Nothing actually moves between banks.
struct TripFund: Codable, Hashable {
    var monthly: Cents
    var start: Date
    var startingBalance: Cents = 0
}

// MARK: - Default categories

extension Category {
    static let defaults: [Category] = [
        Category(id: "groceries", name: "Groceries & Liquor", group: "Everyday"),
        Category(id: "dining", name: "Dining & Bars", group: "Everyday"),
        Category(id: "gas", name: "Gas & Auto", group: "Everyday"),
        Category(id: "commute", name: "Commuting & Rides", group: "Everyday"),
        Category(id: "shopping", name: "Shopping", group: "Everyday"),
        Category(id: "entertainment", name: "Entertainment", group: "Everyday"),
        Category(id: "health", name: "Health", group: "Everyday"),
        Category(id: "personal", name: "Personal Care", group: "Everyday"),
        Category(id: "kids", name: "Kids", group: "Everyday"),
        Category(id: "pets", name: "Pets", group: "Everyday"),
        Category(id: "fitness", name: "Fitness", group: "Everyday"),
        Category(id: "home", name: "Home & Repairs", group: "Everyday"),
        Category(id: "gifts", name: "Gifts", group: "Everyday"),
        Category(id: "housing", name: "Rent / Mortgage", group: "Bills"),
        Category(id: "carpayment", name: "Car payment", group: "Bills"),
        Category(id: "utilities", name: "Utilities", group: "Bills"),
        Category(id: "phone", name: "Phone & Internet", group: "Bills"),
        Category(id: "insurance", name: "Insurance", group: "Bills"),
        Category(id: "subscriptions", name: "Subscriptions", group: "Bills"),
        Category(id: "taxes", name: "Taxes", group: "Bills"),
        Category(id: "fees", name: "Card fees & interest", group: Category.avoidGroup),
        Category(id: "bankfees", name: "Bank fees", group: Category.avoidGroup),
        Category(id: "travel", name: "Travel", group: "Trips"),
        Category(id: "income", name: "Income", group: "Income", isIncome: true),
    ]
}

extension Account {
    /// "Chase Total Checking", but "Robinhood Gold Card" rather than
    /// "Robinhood Robinhood Gold Card".
    var fullName: String {
        let brand = institution.split(separator: " ").first.map(String.init) ?? institution
        return name.localizedCaseInsensitiveContains(brand) ? name : "\(institution) \(name)"
    }
}
