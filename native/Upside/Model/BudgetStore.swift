import Foundation
import Observation

/// Holds the budget and answers every question the screens ask:
/// what's left, what you usually spend, who spent it, what to show first.
@Observable
final class BudgetStore {
    var data: BudgetData {
        didSet { if !isDemo { save() } }
    }

    /// Demo mode (sample data, never saved).
    let isDemo: Bool
    var calendar = Calendar.current
    /// "Now" — overridable so tests and screenshots are stable.
    var now: () -> Date = Date.init

    static let averageMonths = 3
    static let topCount = 6

    init(data: BudgetData, isDemo: Bool = false) {
        self.data = data
        self.isDemo = isDemo
    }

    // MARK: Persistence (local file; iCloud sharing replaces this later)

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("budget.json")
    }

    static func load() -> BudgetStore {
        if let raw = try? Data(contentsOf: fileURL),
           let data = try? JSONDecoder.upside.decode(BudgetData.self, from: raw) {
            return BudgetStore(data: data)
        }
        return BudgetStore(data: BudgetData())
    }

    func save() {
        guard let raw = try? JSONEncoder.upside.encode(data) else { return }
        try? raw.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: Months

    var currentMonth: Date { monthStart(now()) }

    func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    func month(_ offset: Int, from month: Date) -> Date {
        calendar.date(byAdding: .month, value: offset, to: month)!
    }

    func isInMonth(_ date: Date, _ month: Date) -> Bool {
        calendar.isDate(date, equalTo: month, toGranularity: .month)
    }

    var daysLeftInMonth: Int {
        let today = now()
        let range = calendar.range(of: .day, in: .month, for: today)!
        return range.count - calendar.component(.day, from: today)
    }

    // MARK: Lookups

    var people: People { data.people }

    func account(_ id: String) -> Account? { data.accounts.first { $0.id == id } }
    func category(_ id: String?) -> Category? {
        guard let id else { return nil }
        return data.categories.first { $0.id == id }
    }

    var expenseCategories: [Category] {
        data.categories.filter { !$0.isIncome && !$0.isHidden }
    }

    var openAccounts: [Account] { data.accounts }

    /// Transactions that count as spending: on-budget accounts, not
    /// transfers, in a spending category.
    private var spendingTransactions: [Transaction] {
        let onBudget = Set(data.accounts.filter(\.isOnBudget).map(\.id))
        let expenseIds = Set(expenseCategories.map(\.id))
        return data.transactions.filter { t in
            guard let categoryId = t.categoryId else { return false }
            return onBudget.contains(t.accountId) && !t.isTransfer
                && expenseIds.contains(categoryId)
        }
    }

    // MARK: Spending

    /// Positive cents spent in a category during a month (refunds reduce it).
    func spent(_ categoryId: String, in month: Date) -> Cents {
        max(0, -spendingTransactions
            .filter { $0.categoryId == categoryId && isInMonth($0.date, month) }
            .reduce(0) { $0 + $1.amount })
    }

    func totalSpent(in month: Date, includeTrips: Bool = false) -> Cents {
        max(0, -spendingTransactions
            .filter { isInMonth($0.date, month) && (includeTrips || !isTripSpending($0)) }
            .reduce(0) { $0 + $1.amount })
    }

    /// Previous months that have any data at all, so a new budget doesn't
    /// average over empty months.
    private func averagingMonths(before month: Date) -> [Date] {
        let candidates = (1...Self.averageMonths).map { self.month(-$0, from: month) }
        let active = Set(data.transactions.map { monthStart($0.date) })
        return candidates.filter(active.contains)
    }

    func averageSpent(_ categoryId: String, before month: Date) -> Cents? {
        let months = averagingMonths(before: month)
        guard !months.isEmpty else { return nil }
        let total = months.reduce(0) { $0 + spent(categoryId, in: $1) }
        return total / months.count
    }

    func averageTotal(before month: Date) -> Cents? {
        let months = averagingMonths(before: month)
        guard !months.isEmpty else { return nil }
        return months.reduce(0) { $0 + totalSpent(in: $1) } / months.count
    }

    /// This month's spending split by whose account it came from.
    func spentByOwner(categoryId: String? = nil, in month: Date) -> [Owner: Cents] {
        var result: [Owner: Cents] = [:]
        for t in spendingTransactions where isInMonth(t.date, month) {
            if let categoryId, t.categoryId != categoryId { continue }
            if categoryId == nil && isTripSpending(t) { continue }
            let owner = account(t.accountId)?.owner ?? .unassigned
            result[owner, default: 0] -= t.amount
        }
        return result.mapValues { max(0, $0) }
    }

    // MARK: Limits

    var totalLimit: Cents {
        expenseCategories.filter { $0.group != "Trips" }.compactMap(\.limit).reduce(0, +)
    }

    var hasLimits: Bool { totalLimit > 0 }

    /// Fill every limit from the 3-month average (rounded up to $10).
    func setLimitsFromAverages() {
        for index in data.categories.indices where !data.categories[index].isIncome {
            let category = data.categories[index]
            guard category.group != "Trips" else { continue }
            if let avg = averageSpent(category.id, before: currentMonth), avg > 0 {
                data.categories[index].limit = Int((Double(avg) / 1000).rounded(.up)) * 1000
            }
        }
    }

    func setLimit(_ categoryId: String, _ limit: Cents?) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        data.categories[i].limit = limit
    }

    // MARK: What to show first

    /// The categories you actually spend in, biggest first: ranked by the
    /// larger of this month and your average, so both usual and new
    /// expenses rise to the top.
    func topCategories(in month: Date) -> [Category] {
        expenseCategories
            .filter { $0.group != "Trips" }
            .map { ($0, max(spent($0.id, in: month), averageSpent($0.id, before: month) ?? 0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.topCount)
            .map { $0.0 }
    }

    var groupedCategories: [CategoryGroup] {
        var order: [String] = []
        var byGroup: [String: [Category]] = [:]
        for c in expenseCategories {
            if byGroup[c.group] == nil { order.append(c.group) }
            byGroup[c.group, default: []].append(c)
        }
        return order.map { CategoryGroup(name: $0, categories: byGroup[$0] ?? []) }
    }

    // MARK: Review

    /// Bank transactions that still need a category.
    var uncategorized: [Transaction] {
        let onBudget = Set(data.accounts.filter(\.isOnBudget).map(\.id))
        return data.transactions
            .filter { $0.categoryId == nil && !$0.isTransfer && onBudget.contains($0.accountId) }
            .sorted { $0.date > $1.date }
    }

    /// Set a category and remember it for this payee from now on.
    func categorize(_ transactionId: String, as categoryId: String, remember: Bool = true) {
        guard let i = data.transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        data.transactions[i].categoryId = categoryId
        guard remember else { return }
        let key = Self.payeeKey(data.transactions[i].payee)
        data.rules.removeAll { $0.payeeKey == key }
        data.rules.append(PayeeRule(payeeKey: key, categoryId: categoryId))
        // Apply to every other uncategorized transaction from that payee.
        for j in data.transactions.indices
        where data.transactions[j].categoryId == nil
            && Self.payeeKey(data.transactions[j].payee) == key {
            data.transactions[j].categoryId = categoryId
        }
    }

    /// "KROGER #123 CINCINNATI OH" and "Kroger 456" both become "kroger".
    static func payeeKey(_ payee: String) -> String {
        let words = payee.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) && $0.count > 1 }
        return words.prefix(2).joined(separator: " ")
    }

    // MARK: Trips

    func isTripSpending(_ t: Transaction) -> Bool {
        t.tripId != nil || t.categoryId == "travel"
    }

    // MARK: People and owners

    func setNames(_ p1: String, _ p2: String) {
        data.people = People(p1: p1.trimmingCharacters(in: .whitespaces),
                             p2: p2.trimmingCharacters(in: .whitespaces))
        // Re-guess owners for accounts nobody has claimed yet.
        for i in data.accounts.indices where data.accounts[i].owner == .unassigned {
            data.accounts[i].owner = Self.guessOwner(data.accounts[i].name, people: data.people)
        }
    }

    func setOwner(_ accountId: String, _ owner: Owner) {
        guard let i = data.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        data.accounts[i].owner = owner
    }

    /// "Ron's Checking" → Ron, "Joint Checking" → Shared.
    static func guessOwner(_ accountName: String, people: People) -> Owner {
        let n = accountName.lowercased()
        if ["joint", "shared", "household", "family"].contains(where: { n.contains($0) }) {
            return .shared
        }
        for (owner, name) in [(Owner.p1, people.p1), (Owner.p2, people.p2)] {
            let first = name.lowercased().split(separator: " ").first.map(String.init) ?? ""
            if first.count >= 2 && n.contains(first) { return owner }
        }
        return .unassigned
    }

    var unclaimedAccounts: [Account] { data.accounts.filter { $0.owner == .unassigned } }

    var netWorth: Cents { data.accounts.reduce(0) { $0 + $1.balance } }
}

extension JSONEncoder {
    static var upside: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var upside: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
