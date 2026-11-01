import Foundation

/// Brings bank data into the budget: accounts are added or updated,
/// transactions are de-duplicated by the bank's ID, and new purchases are
/// sorted into categories by what you've taught Upside (plus some common
/// stores out of the box).
enum BankSync {
    private static let accessKey = "simplefin-access-url"

    static var isConnected: Bool { Keychain.get(accessKey) != nil }

    @MainActor
    static func connect(setupToken: String, store: BudgetStore) async throws {
        let access = try await SimpleFIN.claim(setupToken: setupToken)
        Keychain.set(access.absoluteString, for: accessKey)
        store.data.bankConnected = true
        try await sync(store: store, initial: true)
    }

    /// How far back the first sync reaches, so averages and recaps have
    /// six full months to work with.
    static let historyDays = 186
    private static let historyKey = "historyDaysLoaded"

    /// Download what's new. Until six months of history have been loaded
    /// once (new connection, or data from an older version that only went
    /// back 90 days), it fetches the full six months in 60-day pieces.
    @MainActor
    static func sync(store: BudgetStore, initial: Bool = false) async throws {
        guard !store.isDemo else { return }
        guard let raw = Keychain.get(accessKey), let access = URL(string: raw) else {
            throw SimpleFIN.Failure.notConnected
        }
        let now = Date()
        let needsHistory = initial || store.data.lastBankSync == nil
            || UserDefaults.standard.integer(forKey: historyKey) < historyDays
        if needsHistory {
            for window in windows(from: now.addingTimeInterval(-Double(historyDays) * 86_400), to: now) {
                let set = try await SimpleFIN.fetch(accessURL: access, since: window.start, until: window.end)
                apply(set, to: store)
            }
            UserDefaults.standard.set(historyDays, forKey: historyKey)
        } else {
            let set = try await SimpleFIN.fetch(accessURL: access, since: now.addingTimeInterval(-14 * 86_400))
            apply(set, to: store)
        }
        store.data.lastBankSync = now
    }

    /// Splits a date range into pieces of at most `days` days (the Bridge
    /// caps a request at 90), newest first so recent data shows up soonest.
    static func windows(from start: Date, to end: Date, days: Int = 60) -> [DateInterval] {
        var result: [DateInterval] = []
        var upper = end
        while upper > start {
            let lower = max(start, upper.addingTimeInterval(-Double(days) * 86_400))
            result.append(DateInterval(start: lower, end: upper))
            upper = lower
        }
        return result
    }

    @MainActor
    static func apply(_ set: SimpleFIN.AccountSet, to store: BudgetStore) {
        var data = store.data
        for sf in set.accounts {
            let balance = cents(sf.balance)
            let institution = sf.org.name ?? sf.org.domain ?? "Bank"
            if let i = data.accounts.firstIndex(where: { $0.id == sf.id }) {
                data.accounts[i].balance = balance
                data.accounts[i].lastSynced = Date()
            } else {
                let kind = AccountKind.guess(from: sf.name)
                data.accounts.append(Account(
                    id: sf.id, name: sf.name, institution: institution, kind: kind,
                    balance: balance,
                    owner: BudgetStore.guessOwner(sf.name, people: data.people),
                    isOnBudget: kind.isOnBudgetByDefault, lastSynced: Date()))
            }

            let known = Set(data.transactions.map(\.id))
            for t in sf.transactions ?? [] {
                let id = "\(sf.id):\(t.id)"
                let payee = (t.payee?.isEmpty == false ? t.payee! : t.description)
                if known.contains(id) {
                    // Pending → posted: keep the category, update the amount.
                    if let j = data.transactions.firstIndex(where: { $0.id == id }) {
                        data.transactions[j].amount = cents(t.amount)
                        data.transactions[j].isPending = t.pending ?? false
                    }
                    continue
                }
                let amount = cents(t.amount)
                let isTransfer = looksLikeTransfer(payee)
                data.transactions.append(Transaction(
                    id: id, accountId: sf.id,
                    date: Date(timeIntervalSince1970: TimeInterval(t.transacted_at ?? t.posted)),
                    amount: amount, payee: payee,
                    categoryId: isTransfer ? nil
                        : categorize(payee: payee, amount: amount, rules: data.rules),
                    isPending: t.pending ?? false,
                    isTransfer: isTransfer))
            }
        }
        data.transactions.sort { $0.date > $1.date }
        markTransfers(&data)
        store.data = data
    }

    /// Payments between your own accounts aren't spending. Two signals:
    /// - the same amount leaving one account and arriving in another within
    ///   a few days (checking → credit card), and
    /// - bank wording for card payments and transfers.
    /// Only touches transactions you haven't categorized yourself.
    static func markTransfers(_ data: inout BudgetData) {
        let window: TimeInterval = 6 * 24 * 3600
        let kinds = Dictionary(data.accounts.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let transferRules = Set(data.rules.filter { $0.categoryId == transferCategory }.map(\.payeeKey))

        var matched = Set<String>()
        let candidates = data.transactions.indices.filter {
            !data.transactions[$0].isTransfer && data.transactions[$0].categoryId == nil
        }
        // 1. Matching pairs.
        let incoming = candidates.filter { data.transactions[$0].amount > 0 }
        for i in candidates where data.transactions[i].amount < 0 {
            let out = data.transactions[i]
            if let j = incoming.first(where: { j in
                let inn = data.transactions[j]
                return !matched.contains(inn.id) && inn.accountId != out.accountId
                    && inn.amount == -out.amount
                    && abs(inn.date.timeIntervalSince(out.date)) <= window
            }) {
                matched.insert(out.id)
                matched.insert(data.transactions[j].id)
            }
        }
        // 2. Wording, your "not spending" choices, and payments received on cards.
        for i in candidates {
            let t = data.transactions[i]
            let isCardCredit = kinds[t.accountId] == .credit && t.amount > 0
                && t.payee.lowercased().contains("pay")
            if matched.contains(t.id) || looksLikeTransfer(t.payee) || isCardCredit
                || transferRules.contains(BudgetStore.payeeKey(t.payee)) {
                data.transactions[i].isTransfer = true
            }
        }
    }

    /// Rule target meaning "not spending".
    static let transferCategory = "transfer"

    static func cents(_ amount: String) -> Cents {
        Int(((Double(amount) ?? 0) * 100).rounded())
    }

    /// Card payments and moves between your own accounts aren't spending.
    /// Bills paid from checking ("VERIZON AUTOPAY", "DUKE ENERGY ONLINE
    /// PAYMENT") are spending, so plain "autopay"/"payment" isn't enough:
    /// it has to be a transfer, or a payment that names a card issuer.
    static func looksLikeTransfer(_ payee: String) -> Bool {
        let p = payee.lowercased()
        let always = [
            "transfer", "xfer", "payment thank you", "payment - thank", "pymt thank",
            "payment received", "credit card payment", "card payment", "cc payment",
            "crcardpmt", "card pymt", "crd pmt", "card pmt", "epayment", "venmo cashout",
        ]
        if always.contains(where: { p.contains($0) }) { return true }
        let paymentWords = ["payment", "pymt", "pmt", "autopay", "auto pay", "epay"]
        let cardIssuers = [
            "chase card", "chase credit", "robinhood", "american express", "amex", "citi card",
            "citicard", "discover", "capital one", "apple card", "applecard", "gs bank",
            "barclay", "synchrony", "bk of amer visa", "bank of america card", "wells fargo card",
            "us bank card", "credit one", "card services",
        ]
        return paymentWords.contains(where: { p.contains($0) })
            && cardIssuers.contains(where: { p.contains($0) })
    }

    /// Your rules first, then common stores.
    static func categorize(payee: String, amount: Cents, rules: [PayeeRule]) -> String? {
        let key = BudgetStore.payeeKey(payee)
        if let rule = rules.first(where: { $0.payeeKey == key }) {
            return rule.categoryId == transferCategory ? nil : rule.categoryId
        }
        if amount > 0 {
            let p = payee.lowercased()
            return p.contains("payroll") || p.contains("salary") || p.contains("direct dep") ? "income" : nil
        }
        let p = payee.lowercased()
        for (category, words) in builtIn where words.contains(where: { p.contains($0) }) {
            return category
        }
        return nil
    }

    private static let builtIn: [(String, [String])] = [
        // First, so "LATE FEE" on a card isn't read as something else.
        ("fees", ["interest charge", "finance charge", "purchase interest", "late fee", "annual fee",
                  "membership fee", "foreign transaction", "overdraft", "returned payment",
                  "cash advance fee", "monthly maintenance fee", "service charge"]),
        ("groceries", ["kroger", "trader joe", "whole foods", "publix", "aldi", "safeway", "wegmans",
                       "costco", "sam's club", "h-e-b", "heb ", "food lion", "giant", "instacart"]),
        ("dining", ["starbucks", "chipotle", "mcdonald", "dunkin", "doordash", "uber eats", "grubhub",
                    "restaurant", "cafe", "pizza", "taco", "burger", "sweetgreen", "panera", "tst*", "sq *"]),
        ("gas", ["shell", "exxon", "chevron", "bp ", "sunoco", "marathon", "wawa", "uber", "lyft",
                 "parking", "toll", "ez pass", "e-zpass"]),
        ("shopping", ["amazon", "amzn", "target", "walmart", "best buy", "etsy", "nordstrom", "tj maxx",
                      "marshalls", "home depot", "lowe's", "ikea"]),
        ("entertainment", ["netflix theatre", "amc ", "regal", "ticketmaster", "steam", "playstation"]),
        ("subscriptions", ["netflix", "spotify", "hulu", "disney+", "apple.com/bill", "youtube",
                           "icloud", "max.com", "peacock", "paramount"]),
        ("health", ["cvs", "walgreens", "pharmacy", "dental", "medical", "clinic", "hospital"]),
        ("utilities", ["energy", "electric", "water", "gas co", "power", "utility"]),
        ("phone", ["verizon", "at&t", "t-mobile", "comcast", "xfinity", "spectrum", "internet"]),
        ("insurance", ["geico", "state farm", "progressive", "allstate", "insurance"]),
        ("travel", ["airline", "airways", "delta air", "united air", "american air", "southwest",
                    "jetblue", "marriott", "hilton", "hyatt", "airbnb", "expedia", "hotel"]),
    ]
}
