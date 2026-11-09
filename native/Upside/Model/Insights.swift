import Foundation

struct MonthSpend: Identifiable, Equatable {
    var month: Date
    var spent: Cents
    var id: Date { month }
}

// MARK: - Bills and subscriptions

/// A charge that comes back about once a month at about the same price.
struct Recurring: Identifiable, Equatable {
    var id: String            // payee key
    var name: String
    var categoryId: String?
    var amount: Cents         // latest charge, positive
    var previous: Cents?      // the charge before, when the price was steady
    var lastDate: Date
    var firstDate: Date
    var paidThisMonth: Bool
    var dueDate: Date?        // this month, when not paid yet
    var isSubscription: Bool
    var isNew: Bool           // started in the last couple of months

    var priceIncrease: Cents? {
        guard let previous, amount - previous >= 100, amount * 100 >= previous * 105 else { return nil }
        return amount - previous
    }
}

extension BudgetStore {
    /// Looks back six months for payees charged about once a month, on about
    /// the same day, for about the same amount, and still active.
    func recurringCharges() -> [Recurring] {
        let thisMonth = currentMonth
        let since = month(-6, from: thisMonth)
        let today = now()
        let charges = spendingTransactions.filter { !$0.id.contains("#") }.filter {
            $0.amount < 0 && $0.tripId == nil && $0.date >= since && $0.date <= today
        }
        let groups = Dictionary(grouping: charges) { BudgetStore.payeeKey($0.payee) }
        let historyStart = firstMonth

        let dismissed = Set(data.notRecurring ?? [])
        // One store can bill several things (Apple: iCloud and Apple One;
        // Tesla: charging and Connectivity). When the store as a whole isn't
        // monthly, each steady price is checked on its own.
        return groups.flatMap { key, list -> [Recurring] in
            guard !dismissed.contains(key) else { return [] }
            if let whole = recurring(key, list, historyStart: historyStart) { return [whole] }
            return Self.byPrice(list).compactMap { price, sub in
                recurring("\(key)|\(price)", sub, historyStart: historyStart)
            }
        }
        .sorted { ($0.dueDate ?? $0.lastDate) < ($1.dueDate ?? $1.lastDate) }
    }

    /// Charges split by whole-dollar price, for stores that bill several things.
    static func byPrice(_ list: [Transaction]) -> [(Int, [Transaction])] {
        Dictionary(grouping: list) { -$0.amount / 100 }.filter { $0.value.count >= 2 }.map { ($0.key, $0.value) }
    }

    /// The store key a recurring charge (or one of its prices) belongs to.
    static func storeKey(_ recurringId: String) -> String {
        String(recurringId.split(separator: "|").first ?? "")
    }

    private func recurring(_ key: String, _ list: [Transaction], historyStart: Date) -> Recurring? {
        let thisMonth = currentMonth
        let today = now()
        do {
            let sorted = list.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            let months = Set(sorted.map { monthStart($0.date) })
            // Twice or more, about once a month, charged in the last 45 days.
            guard months.count >= 2, sorted.count <= months.count + 1,
                  today.timeIntervalSince(last.date) <= 45 * 86_400 else { return nil }

            let amounts = sorted.map { -$0.amount }
            let median = amounts.sorted()[amounts.count / 2]
            guard amounts.allSatisfy({ abs($0 - median) * 100 <= median * 35 }) || steadyThenChanged(amounts)
            else { return nil }

            // Bills categories, or the exact same price 3+ times (a gym).
            // A breakfast spot you visit monthly isn't a bill.
            let isBillCategory = category(last.categoryId)?.group == "Bills"
            guard isBillCategory || (amounts.count >= 3 && Set(amounts).count == 1) else { return nil }

            let days = sorted.map { calendar.component(.day, from: $0.date) }
            guard (days.max() ?? 0) - (days.min() ?? 0) <= 10 else { return nil }

            // Price change only counts when it was steady before.
            let earlier = amounts.dropLast()
            let previous = earlier.last.flatMap { p in earlier.allSatisfy { $0 == p } ? p : nil }

            let paid = isInMonth(last.date, thisMonth)
            var due: Date? = nil
            if !paid {
                let dayCount = calendar.range(of: .day, in: .month, for: thisMonth)!.count
                let day = min(calendar.component(.day, from: last.date), dayCount)
                due = calendar.date(byAdding: .day, value: day - 1, to: thisMonth)
            }
            let categoryId = last.categoryId
            // A fixed price outside Bills (Tesla Connectivity in Gas & Auto) is a subscription too.
            let fixedPrice = !isBillCategory && Set(amounts).count == 1
            return Recurring(
                id: key, name: last.payee, categoryId: categoryId,
                amount: -last.amount, previous: previous,
                lastDate: last.date, firstDate: first.date,
                paidThisMonth: paid, dueDate: due,
                isSubscription: categoryId == "subscriptions" || fixedPrice,
                isNew: monthStart(first.date) >= month(-2, from: thisMonth)
                    && historyStart < month(-2, from: thisMonth))
        }
    }

    /// A steady price with one change at the end (e.g. $15.49 → $22.99).
    private func steadyThenChanged(_ amounts: [Cents]) -> Bool {
        let earlier = amounts.dropLast()
        guard let p = earlier.first, earlier.count >= 2 else { return false }
        return earlier.allSatisfy { $0 == p }
    }

    // MARK: - Trends

    /// Spending in a category for the six months ending at `month`
    /// (fewer if the history doesn't go back that far).
    func monthlySpent(_ categoryId: String, endingAt month: Date, count: Int = 6) -> [MonthSpend] {
        (0..<count).reversed()
            .map { self.month(-$0, from: month) }
            .filter { $0 >= firstFullMonth }
            .map { MonthSpend(month: $0, spent: spent(categoryId, in: $0)) }
    }

    /// One plain sentence about the shape of finished months, oldest first.
    static func trendNote(_ points: [MonthSpend]) -> String? {
        guard points.count >= 3 else { return nil }
        let values = points.map(\.spent)
        let last3 = values.suffix(3)
        if zip(last3, last3.dropFirst()).allSatisfy({ $0 < $1 }), let a = last3.first, let b = last3.last,
           b * 10 > a * 11 {
            return "Up three months in a row."
        }
        if zip(last3, last3.dropFirst()).allSatisfy({ $0 > $1 }), let a = last3.first, let b = last3.last,
           b * 11 < a * 10 {
            return "Down three months in a row."
        }
        if let peak = values.indices.max(by: { values[$0] < values[$1] }) {
            var others = values; others.remove(at: peak)
            let median = others.sorted()[others.count / 2]
            if median > 0, values[peak] * 10 > median * 14 {
                return "\(points[peak].month.formatted(.dateTime.month(.wide))) was unusually high; the other months were steadier."
            }
        }
        return nil
    }

    // MARK: - Search

    /// Purchases whose store contains the text, or whose amount matches
    /// ("84.12", "$84.12", "1,200"). Newest first.
    func search(_ query: String) -> [Transaction] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let amount = BudgetStore.parseAmount(text)
        return data.transactions.filter { t in
            if let amount, abs(t.amount) == amount { return true }
            return t.payee.localizedCaseInsensitiveContains(text)
        }
    }

    static func parseAmount(_ text: String) -> Cents? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard cleaned.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: cleaned) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}

// MARK: - Recommended categories

extension BudgetStore {
    /// Kinds of spending you have (gym, pets, transit…) that don't have a
    /// category yet, from the last six months. Purchases already in one of
    /// your own categories stay put; ones in a built-in category or unsorted
    /// would move.
    func recommendedCategories() -> [CategorySuggestion] {
        let since = month(-6, from: currentMonth)
        let defaultIds = Set(Category.defaults.map(\.id))
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        let existing = Set(data.categories.filter { !$0.isHidden }.map { $0.name.lowercased() })
        let candidates = data.transactions.filter { t in
            t.amount < 0 && !t.isTransfer && t.tripId == nil && t.date >= since && onBudget.contains(t.accountId)
                && (t.categoryId == nil || defaultIds.contains(t.categoryId!))
                && t.categoryId != "fees" && category(t.categoryId)?.group != "Bills"
        }
        return Self.suggestionKinds.compactMap { name, group, words in
            guard !existing.contains(name.lowercased()) else { return nil }
            let hits = candidates.filter { t in
                let p = t.payee.lowercased()
                return words.contains { p.contains($0) }
            }
            // A habit (3+ purchases), or a bill like tuition, which is big enough from one.
            guard let first = hits.first, hits.count >= 3 || group == "Bills" else { return nil }
            return CategorySuggestion(name: name, group: group, transactionIds: hits.map(\.id), example: first.payee)
        }
        .sorted { $0.transactionIds.count > $1.transactionIds.count }
    }

    /// Spending per month across a suggestion's purchases.
    func monthlyAverage(of suggestion: CategorySuggestion) -> Cents {
        let ids = Set(suggestion.transactionIds)
        let list = data.transactions.filter { ids.contains($0.id) }
        let months = Set(list.map { monthStart($0.date) }).count
        return months == 0 ? 0 : -list.reduce(0) { $0 + $1.amount } / months
    }
}

// MARK: - Maximize and minimize

extension BudgetStore {
    /// Money moved into savings and investment accounts, minus what came
    /// back out. Only moves between your own accounts count, not interest
    /// or trades inside the account.
    func savedAndInvested(in month: Date) -> Cents {
        savingsMoves(in: month).reduce(0) { $0 + savingsAmount($1) }
    }

    /// What one move adds to savings: arrivals count as they are (a
    /// withdrawal from savings is negative); money sent out counts positive.
    func savingsAmount(_ t: Transaction) -> Cents {
        let saving = visibleAccounts.contains { $0.id == t.accountId && ($0.kind == .savings || $0.kind == .investment)
            && $0.id != data.tripFund?.accountId }
        return saving ? t.amount : -t.amount
    }

    /// The transactions behind "saved so far": money arriving in savings or
    /// investment accounts, and money sent to investing that isn't connected.
    func savingsMoves(in month: Date) -> [Transaction] {
        // The trip fund's own account holds trip money, not savings.
        let tripAccount = data.tripFund?.accountId
        let saving = visibleAccounts.filter { ($0.kind == .savings || $0.kind == .investment) && $0.id != tripAccount }
        let ids = Set(saving.map(\.id))
        // Money arriving in a savings or investment account counts, matched to
        // the other side or not (a brokerage deposit often isn't), except
        // what the account earned or sold: interest, dividends, sales.
        // Money taken back out of savings counts against it.
        let investing = Set(saving.filter { $0.kind == .investment }.map(\.id))
        let into = data.transactions.filter { t in
            guard ids.contains(t.accountId) && isInMonth(t.date, month) else { return false }
            if Self.isTrade(t.payee) { return false }
            // Inside a brokerage, only money leaving the account counts
            // against savings; buying a stock keeps the money invested.
            if t.amount < 0 && investing.contains(t.accountId) { return Self.isWithdrawal(t.payee) }
            return t.isTransfer || (t.amount > 0 && !Self.isEarnings(t.payee))
        }
        let connected = saving.map { $0.institution.lowercased() }
        let sentOut = data.transactions.filter { t in
            guard t.amount < 0 && t.isTransfer && !ids.contains(t.accountId) && isInMonth(t.date, month) else { return false }
            // Sent to a savings or investing account that's connected here?
            // Its arrival already counts above.
            let payee = t.payee.lowercased()
            if connected.contains(where: { inst in
                inst.split(separator: " ").first.map { payee.contains($0) } ?? false
            }) { return false }
            if isMarkedSaving(t) { return true }
            return BankSync.isInvestmentPayee(t.payee)
                && !connected.contains { inst in BankSync.investmentWords.contains { inst.contains($0) && t.payee.lowercased().contains($0) } }
        }
        return (into + sentOut).sorted { $0.date > $1.date }
    }

    /// Buying or selling inside a brokerage: the money stays invested.
    static func isTrade(_ payee: String) -> Bool {
        let p = payee.lowercased()
        return ["buy ", "bought", "shares of", "share of", "sell ", "sold", "market order", "limit order",
                "recurring investment", "crypto"].contains { p.contains($0) }
    }

    /// Money taken out of a brokerage to a bank.
    static func isWithdrawal(_ payee: String) -> Bool {
        let p = payee.lowercased()
        return ["withdraw", "transfer to", "ach out", "instant transfer", "debit"].contains { p.contains($0) }
    }

    /// Interest, dividends and sales inside an account: growth, not saving.
    static func isEarnings(_ payee: String) -> Bool {
        let p = payee.lowercased()
        return ["interest", "dividend", " div", "reinvest", "capital gain", "sell", "sold", "sale ",
                "cash back", "cashback", "reward", "bonus", "stock lending", "fee rebate"].contains { p.contains($0) }
    }

    /// A transfer you said is saving or investing (or one with the same wording).
    func isMarkedSaving(_ t: Transaction) -> Bool {
        (data.savingPayees ?? []).contains(Self.payeeKey(t.payee))
    }

    /// "This went to savings / investing": counts it (and transfers worded
    /// the same way) toward savings instead of as a card payment.
    func setSaving(_ transactionId: String, _ on: Bool) {
        guard let t = data.transactions.first(where: { $0.id == transactionId }) else { return }
        let key = Self.payeeKey(t.payee)
        var keys = Set(data.savingPayees ?? [])
        if on { keys.insert(key) } else { keys.remove(key) }
        data.savingPayees = keys.isEmpty ? nil : keys.sorted()
        if on && !t.isTransfer { setTransfer(transactionId, true) }
    }

    /// Paid to cards beyond what was charged, so balances went down.
    func extraCardPayoff(in month: Date) -> Cents {
        creditCards.reduce(0) { total, card in
            let m = cardMonth(card, month)
            return total + max(0, m.paid - m.charged)
        }
    }

    /// Everything in the Minimize bundle (card fees, interest, bank fees).
    func minimizeSpent(in month: Date) -> Cents {
        expenseCategories.filter(\.aimsForZero).reduce(0) { $0 + spent($1.id, in: month) }
    }

    func usual(_ value: (Date) -> Cents, before month: Date) -> Cents? {
        let months = (1...3).map { self.month(-$0, from: month) }.filter { $0 >= firstFullMonth }
        guard !months.isEmpty else { return nil }
        return months.reduce(0) { $0 + value($1) } / months.count
    }
}

// MARK: - Transactions tab

extension BudgetStore {
    enum TransactionFilter: Hashable { case all, toCheck, transfers, business }

    /// The Transactions tab: visible accounts only, newest first, narrowed
    /// by search text (store or amount), a filter, a category and a person.
    func transactions(matching query: String, filter: TransactionFilter,
                      categoryId: String? = nil, owner: Owner? = nil) -> [Transaction] {
        let visible = Dictionary(uniqueKeysWithValues: visibleAccounts.map { ($0.id, $0) })
        let text = query.trimmingCharacters(in: .whitespaces)
        let amount = Self.parseAmount(text)
        return data.transactions.filter { t in
            guard let account = visible[t.accountId] else { return false }
            if !text.isEmpty {
                let hit = (amount.map { abs(t.amount) == $0 } ?? false) || t.payee.localizedCaseInsensitiveContains(text)
                if !hit { return false }
            }
            switch filter {
            case .all: break
            case .toCheck: if t.isBusiness || !(t.isHunch || (t.categoryId == nil && !t.isTransfer && t.amount < 0)) { return false }
            case .transfers: if !t.isTransfer { return false }
            case .business: if !t.isBusiness { return false }
            }
            if let categoryId, t.categoryId != categoryId || t.isTransfer { return false }
            if let owner, account.owner != owner { return false }
            return true
        }
        .sorted { $0.date > $1.date }
    }
}

// MARK: - Finding subscriptions

extension BudgetStore {
    /// Categories a subscription can be hiding in. Groceries, dining and
    /// gas are left alone: a monthly breakfast spot isn't a subscription.
    private static let subscriptionHideouts: Set<String> = ["shopping", "entertainment", "personal", "kids", "gifts", "gas", "commute"]

    /// Same price, about the same day, every month for two months or more,
    /// still active: a subscription, whatever the name. Moves those charges
    /// to Subscriptions as a hunch so they show up in Check these. Choices
    /// you made yourself are never changed. Returns how many it moved.
    @discardableResult
    func detectSubscriptions() -> Int {
        let since = month(-6, from: currentMonth)
        let today = now()
        let onBudget = Set(data.accounts.filter(\.countsInBudget).map(\.id))
        let candidates = data.transactions.filter { t in
            t.amount < 0 && !t.isTransfer && t.tripId == nil && t.date >= since && onBudget.contains(t.accountId)
        }
        var moved = 0
        var updated = data
        let dismissed = Set(data.notRecurring ?? [])
        func monthly(_ list: [Transaction]) -> Bool {
            let sorted = list.sorted { $0.date < $1.date }
            guard let last = sorted.last, sorted.count >= 2 else { return false }
            let months = Set(sorted.map { monthStart($0.date) })
            let amounts = sorted.map { -$0.amount }
            let days = sorted.map { calendar.component(.day, from: $0.date) }
            return months.count >= 2 && sorted.count <= months.count
                && (amounts.max() ?? 0) - (amounts.min() ?? 0) <= 100
                && (days.max() ?? 0) - (days.min() ?? 0) <= 6
                && today.timeIntervalSince(last.date) <= 45 * 86_400
        }
        for (key, list) in Dictionary(grouping: candidates, by: { Self.payeeKey($0.payee) }) where !dismissed.contains(key) {
            // A store that bills several things is checked one price at a time.
            let groups = monthly(list) ? [list] : Self.byPrice(list).map(\.1).filter(monthly)
            for t in groups.joined() {
                // Only Upside's own sorting is changed, and only out of shopping-type categories.
                guard t.categoryId != "subscriptions", t.autoSort != nil || t.categoryId == nil,
                      t.categoryId.map(Self.subscriptionHideouts.contains) ?? true,
                      let i = updated.transactions.firstIndex(where: { $0.id == t.id }) else { continue }
                updated.transactions[i].categoryId = "subscriptions"
                updated.transactions[i].autoSort = "hunch"
                moved += 1
            }
        }
        if moved > 0 { data = updated }
        return moved
    }
}

// MARK: - Business expenses

extension BudgetStore {
    /// Words on a deposit that mean you're being paid back for work costs.
    static let reimbursementWords = ["expensify", "concur", "navan", "reimb", "expense report", "expense rpt",
                                     "ramp reimbursement", "brex reimbursement", "emburse", "certify expense"]

    static func looksLikeReimbursement(_ t: Transaction) -> Bool {
        t.amount > 0 && reimbursementWords.contains { t.payee.lowercased().contains($0) }
    }

    func setBusiness(_ transactionId: String, _ on: Bool) {
        guard let i = data.transactions.firstIndex(where: { $0.id == transactionId }) else { return }
        data.transactions[i].business = on ? true : nil
        if on { data.transactions[i].autoSort = nil }
    }

    /// Business purchases and reimbursements, newest first (visible accounts).
    var businessTransactions: [Transaction] {
        let visible = Set(visibleAccounts.map(\.id))
        return data.transactions.filter { $0.isBusiness && visible.contains($0.accountId) }.sorted { $0.date > $1.date }
    }

    /// Spent on business minus what's been paid back (never below $0).
    var businessOwed: Cents {
        let all = businessTransactions
        let spent = -all.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }
        let back = all.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        return max(0, spent - back)
    }
}

// MARK: - Not a bill

extension BudgetStore {
    /// "Not a bill / not a subscription": hides the store from Bills &
    /// subscriptions for good. Purchases Upside had moved to Subscriptions
    /// by pattern go back to how they'd be sorted otherwise.
    /// "Not a bill": the store's purchases leave Bills for an everyday
    /// category (a best guess, shown in Check these), so the bills total
    /// drops and the spending counts against everyday limits.
    func dismissRecurring(_ id: String) {
        let key = Self.storeKey(id)
        var keys = Set(data.notRecurring ?? [])
        keys.insert(key)
        var updated = data
        updated.notRecurring = keys.sorted()
        Self.keepNotBillsOutOfBills(&updated)
        data = updated
    }

    /// Stores you said aren't bills stay out of Bills, even after a sync
    /// or a remembered rule would put them back.
    static func keepNotBillsOutOfBills(_ data: inout BudgetData) {
        let keys = Set(data.notRecurring ?? [])
        guard !keys.isEmpty else { return }
        let bills = Set(data.categories.filter { $0.group == "Bills" }.map(\.id))
        data.rules.removeAll { keys.contains($0.payeeKey) && bills.contains($0.categoryId) }
        for i in data.transactions.indices {
            let t = data.transactions[i]
            guard let c = t.categoryId, bills.contains(c), keys.contains(payeeKey(t.payee)) else { continue }
            let sorted = BankSync.sortSource(payee: t.payee, amount: t.amount, rules: data.rules, bankCategory: t.bankCategory)
            let guess = sorted.category.flatMap { bills.contains($0) ? nil : $0 }
            data.transactions[i].categoryId = guess
            data.transactions[i].autoSort = "hunch"
        }
        fillHunches(&data)
    }

    func restoreRecurring(_ key: String) {
        data.notRecurring = (data.notRecurring ?? []).filter { $0 != key }
        detectSubscriptions()
    }

    /// "It's a bill": files the purchase (and the store's others, via the
    /// usual prompt) under a Bills category, undoing any "Not a bill".
    func markAsBill(_ id: String, as categoryId: String) -> SortPrompt? {
        if let t = data.transactions.first(where: { $0.id == id }) { restoreRecurring(Self.payeeKey(t.payee)) }
        return sort(id, as: categoryId)
    }
}
