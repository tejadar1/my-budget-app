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

    /// Download what's new. The first sync reaches back 90 days so your
    /// averages have something to work with.
    @MainActor
    static func sync(store: BudgetStore, initial: Bool = false) async throws {
        guard !store.isDemo else { return }
        guard let raw = Keychain.get(accessKey), let access = URL(string: raw) else {
            throw SimpleFIN.Failure.notConnected
        }
        let lookback: TimeInterval = initial || store.data.lastBankSync == nil ? 90 : 14
        let since = Date().addingTimeInterval(-lookback * 24 * 3600)
        let set = try await SimpleFIN.fetch(accessURL: access, since: since)
        apply(set, to: store)
        store.data.lastBankSync = Date()
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
        store.data = data
    }

    static func cents(_ amount: String) -> Cents {
        Int(((Double(amount) ?? 0) * 100).rounded())
    }

    /// Card payments and moves between your own accounts aren't spending.
    static func looksLikeTransfer(_ payee: String) -> Bool {
        let p = payee.lowercased()
        return ["transfer", "payment thank you", "autopay", "online pymt", "credit card payment",
                "zelle to ron", "zelle to ana", "venmo cashout", "ach pmt"].contains { p.contains($0) }
    }

    /// Your rules first, then common stores.
    static func categorize(payee: String, amount: Cents, rules: [PayeeRule]) -> String? {
        let key = BudgetStore.payeeKey(payee)
        if let rule = rules.first(where: { $0.payeeKey == key }) { return rule.categoryId }
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
