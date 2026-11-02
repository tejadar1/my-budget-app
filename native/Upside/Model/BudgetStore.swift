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
           var data = try? JSONDecoder.upside.decode(BudgetData.self, from: raw) {
            // Newer transfer detection also cleans up what's already here.
            BankSync.markTransfers(&data)
            // Categories added in later versions (e.g. card fees).
            for category in Category.defaults where !data.categories.contains(where: { $0.id == category.id }) {
                data.categories.append(category)
            }
            if let i = data.categories.firstIndex(where: { $0.id == "gas" && $0.name == "Gas & Transport" }) {
                data.categories[i].name = "Gas & Auto"
            }
            // Once: card names like "Freedom Unlimited" used to be missed.
            if !UserDefaults.standard.bool(forKey: "reguessedCards") {
                for i in data.accounts.indices where data.accounts[i].kind == .other {
                    data.accounts[i].kind = AccountKind.guess(from: data.accounts[i].name,
                                                              balance: data.accounts[i].balance)
                }
                BankSync.markTransfers(&data)
                UserDefaults.standard.set(true, forKey: "reguessedCards")
            }
            if let i = data.categories.firstIndex(where: { $0.id == "dining" && $0.name == "Dining" }) {
                data.categories[i].name = "Dining & Bars"
            }
            mergeBarsIntoDining(&data)
            for i in data.categories.indices
            where ["education", "tuition", "school", "childcare", "daycare"].contains(data.categories[i].name.lowercased())
                && data.categories[i].group == "Everyday" {
                data.categories[i].group = "Bills"
            }
            if !UserDefaults.standard.bool(forKey: "splitCommute") {
                splitCommuteFromGas(&data)
                UserDefaults.standard.set(true, forKey: "splitCommute")
            }
            for i in data.categories.indices where data.categories[i].group == "Aim for $0" {
                data.categories[i].group = Category.avoidGroup
            }
            // Once: undo categories an older version named after stores.
            if !UserDefaults.standard.bool(forKey: "removedStoreCategories") {
                removeStoreNamedCategories(&data)
                UserDefaults.standard.set(true, forKey: "removedStoreCategories")
            }
            for i in data.transactions.indices
            where data.transactions[i].categoryId == nil && !data.transactions[i].isTransfer {
                let t = data.transactions[i]
                let sorted = BankSync.sortSource(payee: t.payee, amount: t.amount, rules: data.rules,
                                                 bankCategory: t.bankCategory)
                data.transactions[i].categoryId = sorted.category
                data.transactions[i].autoSort = sorted.autoSort
            }
            // Better store lists turn earlier hunches into sure matches.
            for i in data.transactions.indices where data.transactions[i].isHunch {
                let t = data.transactions[i]
                let sorted = BankSync.sortSource(payee: t.payee, amount: t.amount, rules: data.rules,
                                                 bankCategory: t.bankCategory)
                if let c = sorted.category, sorted.autoSort != "hunch" {
                    data.transactions[i].categoryId = c
                    data.transactions[i].autoSort = sorted.autoSort
                }
            }
            BankSync.markTransfers(&data)
            fillHunches(&data)
            let store = BudgetStore(data: data)
            store.detectSubscriptions()
            return store
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

    /// The earliest month with any transactions (can't go back further).
    var firstMonth: Date {
        data.transactions.map(\.date).min().map(monthStart) ?? currentMonth
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
    var visibleAccounts: [Account] { data.accounts.filter { !$0.isHidden } }
    var hiddenAccounts: [Account] { data.accounts.filter(\.isHidden) }

    func setHidden(_ accountId: String, _ hidden: Bool) {
        guard let i = data.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        data.accounts[i].hidden = hidden ? true : nil
    }

    /// Transactions that count as spending: on-budget accounts, not
    /// transfers, in a spending category.
    var spendingTransactions: [Transaction] {
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        let expenseIds = Set(expenseCategories.map(\.id))
        return data.transactions.filter { t in
            guard let categoryId = t.categoryId else { return false }
            return onBudget.contains(t.accountId) && !t.isTransfer
                && expenseIds.contains(categoryId)
        }
    }

    // MARK: Spending

    /// Positive cents spent in a category during a month (refunds reduce
    /// it). Purchases tagged to a trip count toward the trip, not the
    /// everyday category, so a vacation doesn't blow up Dining.
    func spent(_ categoryId: String, in month: Date) -> Cents {
        max(0, -spendingTransactions
            .filter { $0.categoryId == categoryId && isInMonth($0.date, month)
                && ($0.tripId == nil || categoryId == "travel") }
            .reduce(0) { $0 + $1.amount })
    }

    /// Paychecks and other income (positive amounts in Income).
    /// Paychecks for this month, counting an early "paid on the 1st"
    /// deposit toward the month it's for (see Income.swift).
    func income(in month: Date) -> Cents {
        let all = payers()
        return incomeTransactions
            .filter { isInMonth(incomeMonth($0, payers: all), month) }
            .reduce(0) { $0 + $1.amount }
    }

    /// Income minus everything spent (bills and trips included).
    func leftOver(in month: Date) -> Cents {
        income(in: month) - totalSpent(in: month, includeTrips: true)
    }

    func totalSpent(in month: Date, includeTrips: Bool = false) -> Cents {
        max(0, -spendingTransactions
            .filter { isInMonth($0.date, month) && (includeTrips || !isTripSpending($0)) }
            .reduce(0) { $0 + $1.amount })
    }

    /// Previous months that have any data at all, so a new budget doesn't
    /// average over empty months.
    /// The months "usual" averages: up to the last 3 with data, skipping a
    /// partial first month.
    func averagingMonths(before month: Date) -> [Date] {
        let candidates = (1...Self.averageMonths).map { self.month(-$0, from: month) }
        let active = Set(data.transactions.map { monthStart($0.date) })
        return candidates.filter { active.contains($0) && $0 >= firstFullMonth }
    }

    /// Bank history usually starts mid-month; a month missing more than its
    /// first week would make averages and charts look low, so it's skipped.
    var firstFullMonth: Date {
        guard let earliest = data.transactions.map(\.date).min() else { return currentMonth }
        return calendar.component(.day, from: earliest) > 7 ? month(1, from: monthStart(earliest)) : monthStart(earliest)
    }

    /// The first full month each account has history for. A bank that
    /// only sent 30 or 60 days starts later than the others.
    var accountHistoryStart: [String: Date] {
        var earliest: [String: Date] = [:]
        for t in data.transactions where earliest[t.accountId].map({ t.date < $0 }) ?? true {
            earliest[t.accountId] = t.date
        }
        return earliest.mapValues { date in
            calendar.component(.day, from: date) > 7 ? month(1, from: monthStart(date)) : monthStart(date)
        }
    }

    /// Usual per month, averaged account by account: each account counts
    /// only the months it has history for, so a bank that sent a month of
    /// data doesn't read as $0 the months before. Nil without any history.
    private func perAccountAverage(_ transactions: [Transaction], before month: Date) -> Cents? {
        let months = (1...Self.averageMonths).map { self.month(-$0, from: month) }
        let starts = accountHistoryStart
        let byAccount = Dictionary(grouping: transactions) { $0.accountId }
        var total = 0
        var anyCovered = false
        for (accountId, start) in starts {
            let covered = months.filter { $0 >= start }
            guard !covered.isEmpty else { continue }
            anyCovered = true
            let sum = (byAccount[accountId] ?? [])
                .filter { t in covered.contains { isInMonth(t.date, $0) } }
                .reduce(0) { $0 + $1.amount }
            total += sum / covered.count
        }
        return anyCovered ? total : nil
    }

    func averageIncome(before month: Date) -> Cents? {
        averageIncomeSmoothed(before: month)
    }

    func averageSpent(_ categoryId: String, before month: Date) -> Cents? {
        let txns = spendingTransactions.filter { $0.categoryId == categoryId && ($0.tripId == nil || categoryId == "travel") }
        return perAccountAverage(txns, before: month).map { max(0, -$0) }
    }

    func averageTotal(before month: Date) -> Cents? {
        perAccountAverage(spendingTransactions.filter { !isTripSpending($0) }, before: month).map { max(0, -$0) }
    }

    /// This month's spending split by whose account it came from.
    func spentByOwner(categoryId: String? = nil, in month: Date, everydayOnly: Bool = false) -> [Owner: Cents] {
        var result: [Owner: Cents] = [:]
        let bills = everydayOnly ? billCategoryIds : []
        for t in spendingTransactions where isInMonth(t.date, month) {
            if let categoryId, t.categoryId != categoryId { continue }
            if let c = t.categoryId, bills.contains(c) { continue }
            if categoryId == nil && isTripSpending(t) { continue }
            if categoryId != nil && categoryId != "travel" && t.tripId != nil { continue }
            let owner = account(t.accountId)?.owner ?? .unassigned
            result[owner, default: 0] -= t.amount
        }
        return result.mapValues { max(0, $0) }
    }

    // MARK: Limits

    /// The limit for a month: a savings plan's lowered limit if one is set
    /// for that month, otherwise the normal limit.
    func limit(_ category: Category, in month: Date) -> Cents? {
        if let plan = data.plan, isInMonth(plan.month, month), let lowered = plan.limits[category.id] {
            return lowered
        }
        return category.limit
    }

    func totalLimit(in month: Date) -> Cents {
        expenseCategories.filter { $0.group != "Trips" }.compactMap { limit($0, in: month) }.reduce(0, +)
    }

    var totalLimit: Cents { totalLimit(in: currentMonth) }

    var hasLimits: Bool { totalLimit > 0 }

    /// Fill every limit from the 3-month average (rounded up to $10).
    func setLimitsFromAverages() {
        for index in data.categories.indices where !data.categories[index].isIncome {
            let category = data.categories[index]
            guard category.group != "Trips" else { continue }
            // A reset: categories with no recent spending lose their limit.
            data.categories[index].limit = limitFromAverage(category)
        }
    }

    /// Usual spending rounded up to the next $10: what "Use my averages" sets.
    func limitFromAverage(_ category: Category) -> Cents? {
        guard let avg = averageSpent(category.id, before: currentMonth), avg > 0 else { return nil }
        return Int((Double(avg) / 1000).rounded(.up)) * 1000
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
            // Bills live in the month plan; top categories are everyday spending.
            .filter { $0.group != "Trips" && $0.group != "Bills" && !$0.aimsForZero }
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

    /// Purchases Upside sorted on a hunch (plus any it couldn't place):
    /// the Check these list.
    var toCheck: [Transaction] {
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        return data.transactions
            .filter { !$0.isTransfer && $0.amount < 0 && onBudget.contains($0.accountId)
                && ($0.isHunch || $0.categoryId == nil) }
            .sorted { $0.date > $1.date }
    }

    /// "Yes, that's right": keeps the category and remembers the store.
    func confirm(_ transactionId: String) {
        guard let t = data.transactions.first(where: { $0.id == transactionId }), let c = t.categoryId else { return }
        _ = sort(transactionId, as: c)
        remember(payee: t.payee, as: c)
        // Others from the same store that were hunches in this category are right too.
        let key = Self.payeeKey(t.payee)
        for i in data.transactions.indices
        where data.transactions[i].isHunch && data.transactions[i].categoryId == c
            && Self.payeeKey(data.transactions[i].payee) == key {
            data.transactions[i].autoSort = nil
        }
    }

    /// Every purchase gets a category. Ones nothing matched get a hunch:
    /// the category you've used most for stores starting with the same
    /// word, otherwise Shopping. Hunches show up in Check these.
    static func fillHunches(_ data: inout BudgetData) {
        var byFirstWord: [String: [String: Int]] = [:]
        for t in data.transactions where !t.isTransfer && !t.isHunch && t.amount < 0 {
            guard let c = t.categoryId, let word = payeeKey(t.payee).split(separator: " ").first else { continue }
            byFirstWord[String(word), default: [:]][c, default: 0] += 1
        }
        for i in data.transactions.indices {
            let t = data.transactions[i]
            guard t.categoryId == nil, !t.isTransfer, t.amount < 0 else { continue }
            let word = payeeKey(t.payee).split(separator: " ").first.map(String.init) ?? ""
            let guess = byFirstWord[word]?.max { $0.value < $1.value }?.key ?? "shopping"
            data.transactions[i].categoryId = guess
            data.transactions[i].autoSort = "hunch"
        }
    }

    /// Bank transactions that still need a category.
    var uncategorized: [Transaction] {
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        return data.transactions
            .filter { $0.categoryId == nil && !$0.isTransfer && onBudget.contains($0.accountId) }
            .sorted { $0.date > $1.date }
    }

    /// Set a category and remember it for this payee from now on.
    /// `as: BankSync.transferCategory` marks it "not spending".
    func categorize(_ transactionId: String, as categoryId: String, remember: Bool = true) {
        guard let i = data.transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        var updated = data
        let isTransfer = categoryId == BankSync.transferCategory
        updated.transactions[i].categoryId = isTransfer ? nil : categoryId
        updated.transactions[i].isTransfer = isTransfer
        updated.transactions[i].autoSort = nil
        if remember {
            let key = Self.payeeKey(updated.transactions[i].payee)
            updated.rules.removeAll { $0.payeeKey == key }
            updated.rules.append(PayeeRule(payeeKey: key, categoryId: categoryId))
            // Apply to every other unsorted transaction from that payee.
            for j in updated.transactions.indices
            where updated.transactions[j].categoryId == nil && !updated.transactions[j].isTransfer
                && Self.payeeKey(updated.transactions[j].payee) == key {
                updated.transactions[j].categoryId = isTransfer ? nil : categoryId
                updated.transactions[j].isTransfer = isTransfer
            }
        }
        data = updated
    }

    /// "KROGER #123 CINCINNATI OH" and "Kroger 456" both become "kroger".
    static func payeeKey(_ payee: String) -> String {
        let words = payee.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) && $0.count > 1 }
        return words.prefix(2).joined(separator: " ")
    }

    // MARK: Saving money

    /// How much of a category's usual spending is fair game when saving
    /// (1 = very flexible). Bills, health and "aim for $0" aren't cut.
    static let flexibility: [String: Double] = [
        "shopping": 1, "dining": 1, "entertainment": 1, "gifts": 0.8,
        "personal": 0.5, "kids": 0.3, "gas": 0.3, "groceries": 0.3, "commute": 0.5,
    ]

    /// The most a plan will cut from a category without you choosing to skip it.
    static let maxCutShare = 0.6

    var plan: SavingsPlan? {
        guard let plan = data.plan, isInMonth(plan.month, currentMonth) else { return nil }
        return plan
    }

    /// What a category normally gets: your usual spending, else its limit.
    func baseline(_ category: Category, before month: Date) -> Cents {
        averageSpent(category.id, before: month) ?? category.limit ?? 0
    }

    func flexibility(of category: Category) -> Double {
        if let known = Self.flexibility[category.id] { return known }
        // Your own everyday categories are treated as fairly flexible.
        return category.group == "Everyday" && !category.isIncome ? 0.6 : 0
    }

    /// Suggested lowered limits to save `goal` this month: cuts are shared
    /// across flexible categories in proportion to how much each can give,
    /// never more than 60% of usual. Returns limits in whole dollars ×100.
    func suggestedLimits(toSave goal: Cents, in month: Date) -> [String: Cents] {
        let candidates = expenseCategories.compactMap { c -> (Category, Cents, Double)? in
            let base = baseline(c, before: month)
            let room = Double(base) * flexibility(of: c) * Self.maxCutShare
            return room >= 500 ? (c, base, room) : nil
        }
        let totalRoom = candidates.reduce(0) { $0 + $1.2 }
        guard totalRoom > 0, goal > 0 else { return [:] }
        let share = min(1, Double(goal) / totalRoom)
        var limits: [String: Cents] = [:]
        for (category, base, room) in candidates {
            let cut = room * share
            // Round the new limit down to $10 so the goal is met, not missed by cents.
            let newLimit = max(0, Int((Double(base) - cut) / 1000) * 1000)
            limits[category.id] = newLimit
        }
        return limits
    }

    /// The most a plan can free up: every flexible category cut as far as
    /// Upside allows (never bills, never more than 60% of usual).
    func maxSavings(in month: Date) -> Cents {
        savings(of: suggestedLimits(toSave: Int.max / 4, in: month), in: month)
    }

    /// What a plan's limits free up compared with usual.
    func savings(of limits: [String: Cents], in month: Date) -> Cents {
        limits.reduce(0) { total, entry in
            guard let category = category(entry.key) else { return total }
            return total + max(0, baseline(category, before: month) - entry.value)
        }
    }

    // MARK: Credit cards
    //
    // A separate check from the budget: purchases already count in their
    // categories and payments are "not spending", so nothing here is added
    // to spending. It answers "am I paying off what I charge?"

    var creditCards: [Account] { visibleAccounts.filter { $0.kind == .credit } }

    /// What you owed on a card at the start of `date` (positive = owed),
    /// worked back from today's balance.
    func owed(_ card: Account, at date: Date) -> Cents {
        let later = data.transactions
            .filter { $0.accountId == card.id && $0.date >= date }
            .reduce(0) { $0 + $1.amount }
        return -(card.balance - later)
    }

    func cardMonth(_ card: Account, _ month: Date) -> CardMonth {
        let txns = data.transactions.filter { $0.accountId == card.id && isInMonth($0.date, month) }
        let charged = max(0, -txns.filter { !$0.isTransfer }.reduce(0) { $0 + $1.amount })
        let paid = max(0, txns.filter { $0.isTransfer && $0.amount > 0 }.reduce(0) { $0 + $1.amount })
        return CardMonth(charged: charged, paid: paid)
    }

    func cardHealth(_ card: Account) -> CardHealth {
        let thisMonth = currentMonth
        let lastMonth = month(-1, from: thisMonth)
        let threeAgo = month(-3, from: thisMonth)
        let owedNow = -card.balance
        let owedThen = owed(card, at: threeAgo)
        let last = cardMonth(card, lastMonth)
        let now = cardMonth(card, thisMonth)
        let twoAgo = cardMonth(card, month(-2, from: thisMonth))
        // A month's charges are usually paid the next month. Early in the
        // month this month's payment may not have happened yet, so either
        // "this month paid last month's" or "last month paid the month
        // before's" counts.
        let paysInFull = (last.charged == 0 || now.paid >= last.charged)
            || (twoAgo.charged > 0 && last.paid >= twoAgo.charged)
        let growth = owedNow - owedThen
        let hasHistory = data.transactions.contains { $0.accountId == card.id && $0.date < thisMonth }
        return CardHealth(owedNow: owedNow, growthSinceThreeMonths: hasHistory ? growth : 0,
                          since: threeAgo, thisMonth: now, lastMonth: last, paysInFull: paysInFull)
    }

    /// Growth over three months that counts as "payments aren't keeping up".
    static let cardGrowthAlert: Cents = 10_000

    var growingCards: [Account] {
        creditCards.filter { cardHealth($0).growthSinceThreeMonths > Self.cardGrowthAlert }
    }

    // MARK: Editing a purchase

    /// Change a purchase's category; optionally remember it for the store.
    func setCategory(_ transactionId: String, _ categoryId: String, remember: Bool) {
        categorize(transactionId, as: categoryId, remember: remember)
    }

    /// After you sort one purchase: other purchases with the same name
    /// that aren't sorted that way yet, so Upside can offer to sort them too.
    struct SortPrompt: Identifiable {
        var id: String { transactionId }
        var transactionId: String
        var categoryId: String
        var otherIds: [String]
        var storeName: String
        var categoryName: String
    }

    /// Sorts one purchase and, when others share its name, returns a
    /// prompt instead of changing them silently. With no others, the choice
    /// is remembered for future purchases right away.
    func sort(_ transactionId: String, as categoryId: String) -> SortPrompt? {
        guard let t = data.transactions.first(where: { $0.id == transactionId }) else { return nil }
        categorize(transactionId, as: categoryId, remember: false)
        let key = Self.payeeKey(t.payee)
        let isTransfer = categoryId == BankSync.transferCategory
        let others = data.transactions.filter { o in
            o.id != transactionId && !key.isEmpty && Self.payeeKey(o.payee) == key
                && (isTransfer ? !o.isTransfer : (o.isTransfer || o.categoryId != categoryId))
        }
        guard !others.isEmpty else {
            remember(payee: t.payee, as: categoryId)
            return nil
        }
        return SortPrompt(transactionId: transactionId, categoryId: categoryId, otherIds: others.map(\.id),
                          storeName: t.payee,
                          categoryName: isTransfer ? "card payments or transfers" : (category(categoryId)?.name ?? "that"))
    }

    /// "Sort all": the others follow, and so do future purchases.
    func sortAll(_ prompt: SortPrompt) {
        for id in prompt.otherIds { categorize(id, as: prompt.categoryId, remember: false) }
        if let t = data.transactions.first(where: { $0.id == prompt.transactionId }) {
            remember(payee: t.payee, as: prompt.categoryId)
        }
    }

    private func remember(payee: String, as categoryId: String) {
        let key = Self.payeeKey(payee)
        guard !key.isEmpty else { return }
        data.rules.removeAll { $0.payeeKey == key }
        data.rules.append(PayeeRule(payeeKey: key, categoryId: categoryId))
    }

    /// Starts sorting over: forgets every category choice and payee rule,
    /// then sorts with the built-in store lists and transfer detection.
    /// Trip tags stay. Returns how many purchases are left to check.
    @discardableResult
    func resortAllPurchases() -> Int {
        var updated = data
        updated.rules = []
        for i in updated.transactions.indices {
            let t = updated.transactions[i]
            updated.transactions[i].isTransfer = BankSync.looksLikeTransfer(t.payee)
            let sorted = updated.transactions[i].isTransfer ? (category: nil, autoSort: nil)
                : BankSync.sortSource(payee: t.payee, amount: t.amount, rules: [], bankCategory: t.bankCategory)
            updated.transactions[i].categoryId = sorted.category
            updated.transactions[i].autoSort = sorted.autoSort
        }
        BankSync.markTransfers(&updated)
        Self.fillHunches(&updated)
        data = updated
        return toCheck.count
    }

    /// "Credit card payment" when a card is involved, otherwise "Transfer".
    func transferLabel(_ t: Transaction) -> String {
        if BankSync.isInvestmentPayee(t.payee) { return "Saved & invested" }
        let p = t.payee.lowercased()
        let cardWords = ["card", "crcardpmt", "payment", "pymt", "pmt", "autopay", "robinhood", "amex"]
        let isCard = account(t.accountId)?.kind == .credit || cardWords.contains { p.contains($0) }
        return isCard ? "Credit card payment" : "Transfer"
    }

    /// Mark a purchase as moving money (card payment or transfer) or undo that.
    func setTransfer(_ transactionId: String, _ isTransfer: Bool) {
        guard let i = data.transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        var t = data.transactions[i]
        t.isTransfer = isTransfer
        if isTransfer { t.categoryId = nil }
        if !isTransfer && t.categoryId == nil {
            t.categoryId = BankSync.categorize(payee: t.payee, amount: t.amount,
                                               rules: data.rules.filter { $0.categoryId != BankSync.transferCategory })
        }
        data.transactions[i] = t
    }

    func setTrip(_ transactionId: String, _ tripId: String?) {
        guard let i = data.transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        data.transactions[i].tripId = tripId
    }

    // MARK: Trips

    func saveTrip(_ trip: Trip) {
        if let i = data.trips.firstIndex(where: { $0.id == trip.id }) {
            data.trips[i] = trip
        } else {
            data.trips.append(trip)
        }
        data.trips.sort { $0.start > $1.start }
    }

    /// Removes the trip; its purchases go back to their everyday categories.
    func deleteTrip(_ id: String) {
        var updated = data
        updated.trips.removeAll { $0.id == id }
        for i in updated.transactions.indices where updated.transactions[i].tripId == id {
            updated.transactions[i].tripId = nil
        }
        data = updated
    }

    /// Spending made during the trip's dates that isn't tagged yet.
    func purchasesDuring(_ trip: Trip) -> [Transaction] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.end)) ?? trip.end
        let start = calendar.startOfDay(for: trip.start)
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        return data.transactions.filter {
            $0.tripId == nil && !$0.isTransfer && $0.amount < 0 && onBudget.contains($0.accountId)
                && $0.date >= start && $0.date < end
                && category($0.categoryId)?.group != "Bills"
        }
    }

    func tagPurchases(_ ids: [String], to tripId: String) {
        var updated = data
        for i in updated.transactions.indices where ids.contains(updated.transactions[i].id) {
            updated.transactions[i].tripId = tripId
        }
        data = updated
    }

    // MARK: Alerts

    struct LimitAlert: Equatable {
        var key: String
        var categoryName: String
        var percent: Int
        var left: Cents
    }

    /// Categories that crossed 80% or 100% of this month's limit and
    /// haven't been alerted yet.
    func pendingLimitAlerts() -> [LimitAlert] {
        let month = currentMonth
        let parts = calendar.dateComponents([.year, .month], from: month)
        let monthKey = "\(parts.year ?? 0)-\(parts.month ?? 0)"
        let sent = Set(data.alertsSent ?? [])
        var result: [LimitAlert] = []
        for category in expenseCategories where !category.aimsForZero {
            guard let limit = limit(category, in: month), limit > 0 else { continue }
            let spent = spent(category.id, in: month)
            for level in [100, 80] where spent * 100 >= limit * level {
                let key = "\(monthKey):\(category.id):\(level)"
                if !sent.contains(key) {
                    result.append(LimitAlert(key: key, categoryName: category.name, percent: level, left: limit - spent))
                }
                break // only the highest level reached
            }
        }
        return result
    }

    func markAlertsSent(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        // Remember the lower level too so a 100% alert doesn't later
        // trigger a stale 80% one.
        let all = keys.flatMap { [$0, $0.replacingOccurrences(of: ":100", with: ":80")] }
        data.alertsSent = Array(Set((data.alertsSent ?? []) + all))
    }

    // MARK: Your own categories

    /// Adds a category and returns its id.
    @discardableResult
    func addCategory(_ name: String, group: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = data.categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            if existing.isHidden, let i = data.categories.firstIndex(where: { $0.id == existing.id }) {
                data.categories[i].isHidden = false
            }
            return existing.id
        }
        let slug = trimmed.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let id = "\(slug.isEmpty ? "category" : slug)-\(UUID().uuidString.prefix(4).lowercased())"
        data.categories.append(Category(id: id, name: trimmed, group: group))
        return id
    }

    func renameCategory(_ id: String, to name: String) {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { data.categories[i].name = trimmed }
    }

    /// Hidden categories keep their history but leave the budget.
    func hideCategory(_ id: String) {
        guard let i = data.categories.firstIndex(where: { $0.id == id }) else { return }
        data.categories[i].isHidden = true
    }

    var groupNames: [String] {
        var seen: [String] = []
        for c in data.categories where !c.isIncome && !seen.contains(c.group) { seen.append(c.group) }
        return seen
    }

    /// New categories worth creating, based on what's waiting to be sorted:
    /// known kinds of spending you don't have a category for yet, and
    /// stores you buy from often.
    var suggestedCategories: [CategorySuggestion] {
        let unsorted = toCheck
        guard !unsorted.isEmpty else { return [] }
        let existing = Set(data.categories.filter { !$0.isHidden }.map { $0.name.lowercased() })
        var result: [CategorySuggestion] = []
        var used = Set<String>()

        for (name, group, words) in Self.suggestionKinds where !existing.contains(name.lowercased()) {
            let hits = unsorted.filter { t in
                let p = t.payee.lowercased()
                return !used.contains(t.id) && words.contains(where: { p.contains($0) })
            }
            if !hits.isEmpty {
                hits.forEach { used.insert($0.id) }
                result.append(CategorySuggestion(name: name, group: group,
                                                 transactionIds: hits.map(\.id),
                                                 example: hits[0].payee))
            }
        }

        // Only kinds of spending become suggestions, never a store's name:
        // a store you buy from often belongs in a category like Dining.
        return result.sorted { $0.transactionIds.count > $1.transactionIds.count }
    }

    /// Version 0.28 suggested categories named after a store ("Tesla",
    /// "Booking"). Removes those, forgets their rules, and re-sorts their
    /// purchases with the built-in matching; anything it can't place goes
    /// back to Purchases to sort.
    static func removeStoreNamedCategories(_ data: inout BudgetData) {
        let defaultIds = Set(Category.defaults.map(\.id))
        let kindNames = Set(suggestionKinds.map { $0.0.lowercased() })
        let storeNamed = data.categories.filter { category in
            guard !defaultIds.contains(category.id), !kindNames.contains(category.name.lowercased()) else { return false }
            return data.transactions.contains { t in
                t.categoryId == category.id
                    && payeeKey(t.payee).split(separator: " ").first.map(String.init) == category.name.lowercased()
            }
        }
        let ids = Set(storeNamed.map(\.id))
        guard !ids.isEmpty else { return }
        data.rules.removeAll { ids.contains($0.categoryId) }
        data.categories.removeAll { ids.contains($0.id) }
        for i in data.transactions.indices where data.transactions[i].categoryId.map(ids.contains) == true {
            let t = data.transactions[i]
            data.transactions[i].categoryId = BankSync.categorize(payee: t.payee, amount: t.amount, rules: data.rules,
                                                                  bankCategory: t.bankCategory)
        }
        BankSync.markTransfers(&data)
    }

    /// Dining and bars are one category. A separate "Bars" category you
    /// made is folded in: its purchases and rules move to Dining & Bars.
    static func mergeBarsIntoDining(_ data: inout BudgetData) {
        let names: Set<String> = ["bars", "bar", "drinks", "nightlife", "bars & nightlife", "alcohol"]
        let ids = Set(data.categories.filter { $0.id != "dining" && names.contains($0.name.lowercased()) }.map(\.id))
        guard !ids.isEmpty else { return }
        for i in data.transactions.indices where data.transactions[i].categoryId.map(ids.contains) == true {
            data.transactions[i].categoryId = "dining"
        }
        for i in data.rules.indices where ids.contains(data.rules[i].categoryId) {
            data.rules[i].categoryId = "dining"
        }
        let movedLimit = data.categories.filter { ids.contains($0.id) }.compactMap(\.limit).reduce(0, +)
        if movedLimit > 0, let d = data.categories.firstIndex(where: { $0.id == "dining" }),
           let current = data.categories[d].limit {
            data.categories[d].limit = current + movedLimit
        }
        data.categories.removeAll { ids.contains($0.id) }
    }

    /// Rides and transit used to land in Gas & Auto. Moves them (and any
    /// "Transit" category you made) to Commuting & Rides, and car loan
    /// payments to Car payment.
    static func splitCommuteFromGas(_ data: inout BudgetData) {
        let transitIds = Set(data.categories.filter { ["transit", "commuting", "commute", "rides"].contains($0.name.lowercased()) }.map(\.id))
        for i in data.transactions.indices {
            let t = data.transactions[i]
            guard let c = t.categoryId, c == "gas" || transitIds.contains(c) || c == "housing" || c == "travel" else { continue }
            let fresh = BankSync.categorize(payee: t.payee, amount: t.amount, rules: [])
            if transitIds.contains(c) || ((fresh == "commute" || fresh == "carpayment") && c != fresh) {
                data.transactions[i].categoryId = transitIds.contains(c) ? "commute" : fresh
            }
        }
        for i in data.rules.indices {
            let r = data.rules[i]
            let fresh = BankSync.categorize(payee: r.payeeKey, amount: -100, rules: [])
            if transitIds.contains(r.categoryId) || (r.categoryId == "gas" && (fresh == "commute" || fresh == "carpayment")) {
                data.rules[i].categoryId = transitIds.contains(r.categoryId) ? "commute" : fresh!
            }
        }
        data.categories.removeAll { transitIds.contains($0.id) }
    }

    /// Creates the suggested category and sorts its purchases into it.
    func accept(_ suggestion: CategorySuggestion) {
        let id = addCategory(suggestion.name, group: suggestion.group)
        for transactionId in suggestion.transactionIds {
            categorize(transactionId, as: id)
        }
    }

    static let suggestionKinds: [(String, String, [String])] = [
        ("Fitness", "Everyday", ["gym", "fitness", "peloton", "yoga", "crossfit", "orangetheory", "equinox", "ymca"]),
        ("Pets", "Everyday", ["petco", "petsmart", "chewy", "vet ", "veterinary", "animal hosp", "rover"]),
        ("Childcare", "Bills", ["daycare", "childcare", "kindercare", "preschool", "babysit", "nanny"]),
        // Tuition is owed, not optional: a bill the savings plan never cuts.
        ("Education", "Bills", ["tuition", "university", "college of", "school", "academy", "montessori",
                                "factsmgt", "facts tuition", "smart tuition", "smarttuition", "flywire",
                                "blackbaud", "coursera", "udemy"]),
        ("Golf", "Everyday", ["golf", "country club", "golfnow", "teeoff", "tee time", "driving range",
                              "pga tour superstore", "titleist", "callaway", "taylormade", "ping golf",
                              "footjoy", "club champ", "links at", "greens fee"]),
        ("Home", "Everyday", ["wayfair", "bed bath", "crate & barrel", "pottery barn", "west elm", "furniture"]),
        ("Clothing", "Everyday", ["zara", "h&m", "old navy", "gap ", "uniqlo", "nike", "lululemon", "j.crew"]),
        ("Giving", "Everyday", ["donation", "charity", "church", "red cross", "gofundme", "unicef"]),
        ("Coffee", "Everyday", ["coffee", "blue bottle", "peet", "dutch bros", "tim hortons"]),
    ]

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

    var unclaimedAccounts: [Account] { visibleAccounts.filter { $0.owner == .unassigned } }

    var netWorth: Cents { visibleAccounts.reduce(0) { $0 + $1.balance } }
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
