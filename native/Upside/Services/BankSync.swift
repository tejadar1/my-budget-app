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

    /// Common US companies by category. Order matters, since the first
    /// match wins: subscriptions come before stores ("amazon prime" before
    /// "amazon"), dining before rides ("uber eats" before "uber"), and
    /// shopping last as the catch-all for big retailers. Keywords are
    /// lowercase substrings; short ones carry a space to avoid matching
    /// inside other words.
    private static let builtIn: [(String, [String])] = [
        // First, so "LATE FEE" on a card isn't read as something else.
        ("fees", ["interest charge", "finance charge", "purchase interest", "late fee", "annual fee",
                  "membership fee", "foreign transaction", "overdraft", "returned payment",
                  "cash advance fee", "monthly maintenance fee", "service charge"]),
        ("subscriptions", ["netflix", "spotify", "hulu", "disney+", "disney plus", "apple.com/bill", "youtube",
                           "icloud", "max.com", "hbo max", "peacock", "paramount", "amazon prime", "prime video",
                           "audible", "kindle unltd", "kindle unlimited", "uber one", "dashpass", "walmart+",
                           "instacart+", "siriusxm", "pandora", "tidal", "crunchyroll", "espn+", "fubo",
                           "sling tv", "youtube tv", "apple tv", "starz", "nytimes", "new york times", "wsj",
                           "washington post", "the atlantic", "patreon", "substack", "openai", "chatgpt",
                           "claude.ai", "anthropic", "adobe", "microsoft 365", "msft *", "dropbox",
                           "google one", "google storage", "duolingo", "headspace", "calm.com", "nordvpn",
                           "1password", "linkedin premium", "match.com", "hinge", "bumble"]),
        ("groceries", ["kroger", "trader joe", "whole foods", "wholefds", "publix", "aldi", "lidl", "safeway",
                       "wegmans", "costco", "sam's club", "sams club", "bj's wholesale", "h-e-b", "heb ",
                       "food lion", "giant", "instacart", "amazon fresh", "fresh direct", "freshdirect",
                       "stop & shop", "shoprite", "key food", "c-town", "ctown", "fairway", "food bazaar",
                       "h mart", "99 ranch", "sprouts", "harris teeter", "meijer", "hy-vee", "winco",
                       "albertsons", "vons", "ralphs", "fred meyer", "market basket", "hannaford",
                       "piggly wiggly", "winn-dixie", "food 4 less", "save a lot", "weis markets",
                       "gristedes", "d'agostino", "morton williams", "western beef", "supermarket", "grocery"]),
        ("dining", ["starbucks", "chipotle", "mcdonald", "dunkin", "doordash", "uber eats", "uber *eats", "ubereats", "grubhub",
                    "seamless", "postmates", "caviar", "restaurant", "cafe", "pizza", "taco", "burger",
                    "sweetgreen", "panera", "subway", "wendy's", "chick-fil-a", "kfc", "popeyes",
                    "shake shack", "five guys", "domino's", "papa john", "panda express", "jersey mike",
                    "jimmy john", "wingstop", "cava", "dig inn", "just salad", "pret a manger", "le pain",
                    "olive garden", "applebee", "chili's", "ihop", "denny's", "cheesecake factory",
                    "blue bottle", "peet's", "dutch bros", "tim hortons", "coffee", "bakery", "bagel",
                    "deli ", "diner", "grill", "bistro", "kitchen", "sushi", "ramen", "bar & ", "tavern",
                    "pub ", "brewery", "tst*", "sq *"]),
        ("gas", ["shell", "exxon", "chevron", "bp ", "sunoco", "marathon", "wawa", "speedway", "circle k",
                 "valero", "citgo", "sheetz", "quiktrip", "racetrac", "getty", "phillips 66", "conoco",
                 "arco ", "gulf oil", "uber", "lyft", "parking", "spothero", "parkwhiz", "toll", "ez pass",
                 "e-zpass", "ezpass", "zipcar", "tesla", "supercharger", "chargepoint", "electrify america",
                 "evgo", "ev charging", "autozone", "jiffy lube", "car wash", "dmv", "discount tire",
                 "goodyear", "firestone", "auto parts", "o'reilly auto", "advance auto", "napa auto",
                 "valvoline", "pep boys", "midas", "meineke", "monro", "safelite"]),
        ("housing", ["mortgage", "mr. cooper", "mr cooper", "bilt rent", "property management", "apartments",
                     "hoa ", "homeowners assoc", "condo assoc", "landlord", "realty mgmt"]),
        ("utilities", ["energy", "electric", "water", "gas co", "power", "utility", "utilities",
                       "con ed", "coned", "consolidated edison", "national grid", "pseg", "eversource",
                       "veolia", "suez water", "american water", "aqua america", "pg&e", "pge ", "sdg&e",
                       "socalgas", "dominion", "xcel", "ameren", "fpl ", "nicor", "national fuel", "peco ",
                       "pepco", "bge ", "comed ", "nyseg", "rg&e", "central hudson", "orange & rockland",
                       "jcp&l", "dte ", "piedmont natural", "sewer", "waste management", "republic services",
                       "trash", "sanitation"]),
        ("phone", ["verizon", "at&t", "att*", "t-mobile", "comcast", "xfinity", "spectrum", "optimum",
                   "cox comm", "frontier comm", "cricket wireless", "metro by t", "mint mobile",
                   "visible", "google fi", "boost mobile", "us mobile", "starlink", "internet"]),
        ("insurance", ["geico", "state farm", "progressive", "allstate", "lemonade", "liberty mutual",
                       "nationwide", "usaa", "farmers ins", "travelers ins", "metlife", "metropolitan life",
                       "new york life", "northwestern mutual", "prudential", "guardian life", "the hartford",
                       "erie ins", "mercury ins", "american family", "root ins", "hippo ins", "assurant",
                       "aetna", "cigna", "humana", "blue cross", "bcbs", "kaiser", "oscar health",
                       "unitedhealth", "insurance"]),
        ("health", ["cvs", "walgreens", "rite aid", "duane reade", "pharmacy", "dental", "dentist",
                    "orthodont", "medical", "clinic", "hospital", "urgent care", "citymd", "one medical",
                    "labcorp", "quest diag", "optometr", "lenscrafters", "warby parker", "zocdoc",
                    "physician", "pediatric", "dermatolog", "physical therapy", "hims", "goodrx"]),
        ("personal", ["salon", "barber", "spa ", "sephora", "ulta beauty", "great clips", "supercuts", "nails",
                      "massage", "drybar", "european wax", "dry clean", "laundromat", "cleaners"]),
        ("kids", ["toys", "buy buy baby", "carter's", "children's place", "gymboree", "petco", "petsmart",
                  "chewy", "banfield", "vca ", "veterinar"]),
        ("gifts", ["1-800-flowers", "ftd ", "edible arrangements", "gift card", "giftcard"]),
        ("travel", ["airline", "airways", "air lines", "delta air", "united air", "american air", "southwest",
                    "jetblue", "alaska air", "spirit air", "frontier air", "allegiant", "air canada",
                    "lufthansa", "emirates", "marriott", "hilton", "hyatt", "ihg", "holiday inn", "hampton inn",
                    "westin", "sheraton", "four seasons", "ritz-carlton", "best western", "wyndham", "motel",
                    "resort", "hotel", "airbnb", "vrbo", "expedia", "hotels.com", "booking.com", "priceline",
                    "kayak", "hopper", "viator", "getyourguide", "hertz", "avis ", "enterprise rent",
                    "national car", "budget rent", "sixt", "turo", "clearme", "tsa precheck", "global entry"]),
        ("entertainment", ["netflix theatre", "amc ", "regal", "fandango", "cinema", "theatre", "theater",
                           "ticketmaster", "live nation", "stubhub", "seatgeek", "vivid seats", "eventbrite",
                           "axs ", "telecharge", "broadway", "museum", "comedy", "bowling", "topgolf",
                           "dave & buster", "steampowered", "steam games", "playstation", "xbox", "nintendo",
                           "epic games"]),
        ("shopping", ["amazon", "amzn", "apple store", "apple.com/us", "target", "walmart", "best buy", "etsy",
                      "ebay", "nordstrom", "macy's", "kohl's", "jcpenney", "bloomingdale", "saks",
                      "tj maxx", "marshalls", "homegoods", "burlington", "ross store", "old navy", "gap ",
                      "h&m", "zara", "uniqlo", "nike", "adidas", "lululemon", "shein", "temu", "aliexpress",
                      "home depot", "lowe's", "ikea", "wayfair", "bed bath", "container store",
                      "williams sonoma", "crate & barrel", "pottery barn", "west elm", "michaels",
                      "hobby lobby", "joann", "staples", "office depot", "dollar tree", "dollar general",
                      "family dollar", "five below", "b&h photo", "newegg", "gamestop", "barnes & noble",
                      "rei ", "dick's sporting", "poshmark"]),
    ]
}
