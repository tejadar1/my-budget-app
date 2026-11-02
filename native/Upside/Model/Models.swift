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
        if n.contains("saving") || n.contains("money market") { return .savings }
        if n.contains("mortgage") || n.contains("loan") || n.contains("auto") || n.contains("heloc")
            || n.contains("home equity") || n.contains("student") {
            return .loan
        }
        if n.contains("401") || n.contains("ira") || n.contains("brokerage")
            || n.contains("invest") || n.contains("roth") {
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
}

struct Category: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var group: String
    /// Monthly limit; nil means no limit set.
    var limit: Cents?
    var isIncome: Bool = false
    var isHidden: Bool = false

    /// Spending you want at $0 (card fees, interest).
    var aimsForZero: Bool { group == Category.avoidGroup }
    static let avoidGroup = "Aim for $0"
}

/// A month where you cut flexible spending to save. Only that month's
/// limits change; the next month goes back to normal.
struct SavingsPlan: Codable, Equatable {
    var month: Date
    var goal: Cents
    /// Lowered limits for this month, by category id (0 = skip).
    var limits: [String: Cents]
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
}

// MARK: - Default categories

extension Category {
    static let defaults: [Category] = [
        Category(id: "groceries", name: "Groceries", group: "Everyday"),
        Category(id: "dining", name: "Dining & Bars", group: "Everyday"),
        Category(id: "gas", name: "Gas & Auto", group: "Everyday"),
        Category(id: "shopping", name: "Shopping", group: "Everyday"),
        Category(id: "entertainment", name: "Entertainment", group: "Everyday"),
        Category(id: "health", name: "Health", group: "Everyday"),
        Category(id: "personal", name: "Personal Care", group: "Everyday"),
        Category(id: "kids", name: "Kids & Pets", group: "Everyday"),
        Category(id: "gifts", name: "Gifts", group: "Everyday"),
        Category(id: "housing", name: "Rent / Mortgage", group: "Bills"),
        Category(id: "utilities", name: "Utilities", group: "Bills"),
        Category(id: "phone", name: "Phone & Internet", group: "Bills"),
        Category(id: "insurance", name: "Insurance", group: "Bills"),
        Category(id: "subscriptions", name: "Subscriptions", group: "Bills"),
        Category(id: "fees", name: "Card fees & interest", group: Category.avoidGroup),
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
