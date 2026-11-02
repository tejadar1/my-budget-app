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
                let kind = AccountKind.guess(from: sf.name, balance: balance)
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
                let sorted = isTransfer ? (category: nil, autoSort: nil)
                    : sortSource(payee: payee, amount: amount, rules: data.rules, bankCategory: t.extra?.bankCategory)
                data.transactions.append(Transaction(
                    id: id, accountId: sf.id,
                    date: Date(timeIntervalSince1970: TimeInterval(t.transacted_at ?? t.posted)),
                    amount: amount, payee: payee,
                    categoryId: sorted.category,
                    isPending: t.pending ?? false,
                    isTransfer: isTransfer,
                    bankCategory: t.extra?.bankCategory,
                    autoSort: sorted.autoSort))
            }
        }
        data.transactions.sort { $0.date > $1.date }
        markTransfers(&data)
        BudgetStore.fillHunches(&data)
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
        // Unsorted purchases and hunches can turn out to be transfers.
        let candidates = data.transactions.indices.filter {
            !data.transactions[$0].isTransfer
                && (data.transactions[$0].categoryId == nil || data.transactions[$0].isHunch)
        }
        // 1. Matching pairs. The arriving side may already be known as a
        // payment ("PAYMENT THANK YOU" on the card); it still pairs.
        // Payments into a loan (mortgage, car) are bills, so they don't pair.
        let incoming = data.transactions.indices.filter {
            data.transactions[$0].amount > 0 && kinds[data.transactions[$0].accountId] != .loan
                && (data.transactions[$0].categoryId == nil || data.transactions[$0].isTransfer
                    || data.transactions[$0].isHunch)
        }
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
        // 2. Wording, your "not spending" choices, payments received on
        // cards, and payments from checking that name the bank of one of
        // your cards ("ROBINHOOD DES:PAYMENT" when you have a Robinhood card).
        let cardBanks = Set(data.accounts.filter { $0.kind == .credit }
            .compactMap { $0.institution.lowercased().split(separator: " ").first.map(String.init) }
            .filter { $0.count >= 3 && $0 != "bank" })
        for i in candidates {
            let t = data.transactions[i]
            let p = t.payee.lowercased()
            let isCardCredit = kinds[t.accountId] == .credit && t.amount > 0 && p.contains("pay")
            let paysOwnCard = t.amount < 0 && kinds[t.accountId] != .credit
                && cardBanks.contains(where: { p.contains($0) })
                && ["payment", "pymt", "pmt", "autopay", "epay", "crd", "card", "credit"].contains(where: { p.contains($0) })
                && !["zelle", "venmo", "paypal", "mortgage", "loan"].contains(where: { p.contains($0) })
                && !carLoanWords.contains(where: { p.contains($0) })
            if matched.contains(t.id) || looksLikeTransfer(t.payee) || isCardCredit || paysOwnCard
                || transferRules.contains(BudgetStore.payeeKey(t.payee)) {
                data.transactions[i].isTransfer = true
                data.transactions[i].categoryId = nil
                data.transactions[i].autoSort = nil
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
    /// Money sent to college savings, brokerages and retirement accounts:
    /// saved, not spent, even when that account isn't connected.
    static let investmentWords = [
        "vanguard", "529 plan", "529 college", "529 sav", "college 529", "college savings", "ny 529", "nysaves",
        "fidelity", "schwab", "betterment", "wealthfront", "acorns", "m1 finance", "etrade", "e*trade",
        "merrill edge", "tiaa", "ira contrib", "roth contrib",
    ]

    /// Car loans and leases: a bill, never a transfer.
    static let carLoanWords = [
        "tesla finance", "tesla motors fin", "ally auto", "toyota financial", "toyota motor cred", "honda financial",
        "american honda fin", "gm financial", "ford credit", "ford motor credit", "hyundai motor fin", "kia finance",
        "kia motors fin", "nissan motor acc", "nissan-infiniti", "bmw financial", "bmw fs", "mercedes-benz fin",
        "mb financial", "lexus financial", "vw credit", "audi financial", "subaru motors fin", "santander consumer",
        "chase auto", "capital one auto", "wells fargo auto", "carmax auto", "auto loan", "car loan", "car payment",
        "auto lease", "lease payment",
    ]

    static func isInvestmentPayee(_ payee: String) -> Bool {
        let p = payee.lowercased()
        return investmentWords.contains { p.contains($0) }
    }

    static func looksLikeTransfer(_ payee: String) -> Bool {
        let p = payee.lowercased()
        if isInvestmentPayee(p) { return true }
        if carLoanWords.contains(where: { p.contains($0) }) { return false }
        let always = [
            "transfer", "xfer", "payment thank you", "payment - thank", "pymt thank",
            "payment received", "credit card payment", "card payment", "cc payment",
            "crcardpmt", "card pymt", "crd pmt", "card pmt", "epayment", "venmo cashout",
            "payment, thank", "payment-thank", "pymt-thank", "payment to crd", "payment to card",
            "card ending in", "credit crd", "crd autopay", "crd epay", "ba electronic payment",
            "bill payment to crd", "mobile payment - thank",
        ]
        if always.contains(where: { p.contains($0) }) { return true }
        // Paying a person isn't paying your card, even through a bank app.
        if ["zelle", "venmo", "paypal", "cash app", "mortgage", "loan"].contains(where: { p.contains($0) }) { return false }
        let paymentWords = ["payment", "pymt", "pmt", "autopay", "auto pay", "epay"]
        let cardIssuers = [
            "chase card", "chase credit", "robinhood", "american express", "amex", "citi card",
            "citicard", "discover", "capital one", "apple card", "applecard", "gs bank",
            "barclay", "synchrony", "bk of amer visa", "bank of america card", "wells fargo card",
            "us bank card", "credit one", "card services", "chase", "bank of america", "bofa", "citi ", "citibank",
            "wells fargo", "capital one", "barclays", "goldman", "gsbank", "bilt", "navy federal",
        ]
        return paymentWords.contains(where: { p.contains($0) })
            && cardIssuers.contains(where: { p.contains($0) })
    }

    /// Your rules first, then common stores.
    static func categorize(payee: String, amount: Cents, rules: [PayeeRule], bankCategory: String? = nil) -> String? {
        sortSource(payee: payee, amount: amount, rules: rules, bankCategory: bankCategory).category
    }

    /// The category and how sure Upside is: your rules (nil = yours),
    /// known stores and merchant codes ("sure"), the bank's text category
    /// ("hunch"). Nil category when nothing matched.
    static func sortSource(payee: String, amount: Cents, rules: [PayeeRule],
                           bankCategory: String? = nil) -> (category: String?, autoSort: String?) {
        let key = BudgetStore.payeeKey(payee)
        if let rule = rules.first(where: { $0.payeeKey == key }) {
            return (rule.categoryId == transferCategory ? nil : rule.categoryId, nil)
        }
        if let c = builtInCategory(payee: payee, amount: amount) { return (c, "sure") }
        if let bank = bankCategory, let c = category(fromBank: bank) {
            return (c, bank.hasPrefix("mcc:") ? "sure" : "hunch")
        }
        return (nil, nil)
    }

    private static func builtInCategory(payee: String, amount: Cents) -> String? {
        if amount > 0 {
            let p = payee.lowercased()
            let isIncome = ["payroll", "salary", "direct dep", "tax ref", "taxrfd", "tax refund"].contains { p.contains($0) }
            return isIncome ? "income" : nil
        }
        // A trailing space lets "bar " match a name ending in BAR.
        let p = payee.lowercased() + " "
        for (category, words) in builtIn where words.contains(where: { p.contains($0) }) {
            return category
        }
        return nil
    }

    /// The bank's category or merchant code (MCC) mapped to Upside's, for
    /// stores the lists don't know. Bars (5813) and restaurants (5812) both
    /// land in Dining & Bars.
    static func category(fromBank raw: String) -> String? {
        let text = raw.lowercased()
        if text.hasPrefix("mcc:"), let code = Int(text.dropFirst(4)) {
            switch code {
            case 5811...5814: return "dining"
            case 5411, 5422, 5441, 5451, 5462, 5499: return "groceries"
            case 5541, 5542, 5172, 5531...5533, 7523, 7531...7549, 4121, 4784, 4111, 4131: return "gas"
            case 5912, 8011...8099, 5975, 5976, 8043: return "health"
            case 7230, 7297, 7298, 7210...7217: return "personal"
            case 3000...3299, 4511, 3501...3999, 7011, 4722, 7512, 3351...3441, 4411: return "travel"
            case 7832, 7841, 7922, 7929, 7932, 7933, 7941, 7991...7999: return "entertainment"
            case 4900: return "utilities"
            case 4812, 4814, 4816, 4899: return "phone"
            case 6300, 5960: return "insurance"
            case 5992, 5947: return "gifts"
            case 5995, 742: return "kids"
            case 5300...5399, 5600...5699, 5700...5799, 5200...5261, 5940...5999, 5045, 5732...5735: return "shopping"
            default: return nil
            }
        }
        // Order matters: "gas & electric" is a utility, "barber" isn't a bar.
        let map: [(String, [String])] = [
            ("insurance", ["insurance"]),
            ("utilities", ["utilit", "gas & electric", "electric company", "power company", "water & sewer"]),
            ("personal", ["personal care", "hair", "salon", "barber", "beauty", "laundry"]),
            ("dining", ["restaurant", "dining", "food & drink", "food and drink", "bars", "bar &", "nightlife",
                        "alcohol", "fast food", "coffee", "brewer"]),
            ("groceries", ["grocer", "supermarket"]),
            ("gas", ["gas station", "gasoline", "fuel", "petrol", "automotive", "automobile", "auto ", "parking",
                     "ride share", "rideshare", "taxi", "tolls", "transit"]),
            ("phone", ["phone", "internet", "mobile", "cable", "telecom"]),
            ("health", ["pharmac", "health", "medical", "doctor", "dentist", "vision"]),
            ("travel", ["travel", "airline", "air travel", "hotel", "lodging", "rental car"]),
            ("entertainment", ["entertainment", "movie", "music", "sporting event", "amusement"]),
            ("kids", ["pet supplies", "pets", "veterinar", "child", "toy store"]),
            ("gifts", ["gift", "florist", "charit"]),
            ("shopping", ["shopping", "clothing", "apparel", "electronics", "merchandise", "home improvement",
                          "department store"]),
        ]
        return map.first { _, words in words.contains { text.contains($0) } }?.0
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
                  "membership fee", "foreign transaction", "returned payment", "cash advance fee",
                  "plan fee", "my chase plan", "plan it fee", "planit fee", "flex pay fee", "citi flex",
                  "installment fee", "pay over time fee", "fixed monthly fee"]),
        ("bankfees", ["overdraft", "monthly maintenance fee", "maintenance fee", "service charge", "service fee",
                      "atm fee", "atm surcharge", "non-chase atm", "non-bofa atm", "insufficient funds", "nsf fee",
                      "returned item", "wire fee", "wire transfer fee", "stop payment fee", "paper statement fee"]),
        ("taxes", ["irs usataxpymt", "usataxpymt", "irs ", "us treasury tax", "treas tax", "eftps",
                   "nys dtf", "ny state dtf", "nys tax", "dept of revenue", "department of revenue",
                   "franchise tax", "state tax", "tax payment", "property tax", "nyc dof", "nyc finance",
                   "dept of taxation", "comptroller", "turbotax", "h&r block", "hrblock", "taxact",
                   "freetaxusa", "tax prep"]),
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
        // Tolls and bridges before transit: "MTA BRIDGES & TUNNELS" is driving.
        ("gas", ["mta bridges", "bridges and tunnels", "bridges & tunnels", "mta b&t", "e-zpass", "ezpass", "ez pass",
                 "tolls by mail", "toll ", "turnpike", "thruway", "port authority toll"]),
        // Fares that name the subway, before Subway the sandwich shop.
        ("commute", ["subway fare", "nyc subway", "mta subway", "subway mta", "mta*", "omny", "nyct", "metrocard"]),
        ("dining", ["starbucks", "chipotle", "mcdonald", "dunkin", "doordash", "uber eats", "uber *eats", "ubereats", "grubhub",
                    "seamless", "postmates", "caviar", "restaurant", "cafe", "pizza", "taco", "burger",
                    "sweetgreen", "panera", "subway", "wendy's", "chick-fil-a", "kfc", "popeyes",
                    "shake shack", "five guys", "domino's", "papa john", "panda express", "jersey mike",
                    "jimmy john", "wingstop", "cava", "dig inn", "just salad", "pret a manger", "le pain",
                    "olive garden", "applebee", "chili's", "ihop", "denny's", "cheesecake factory",
                    "blue bottle", "peet's", "dutch bros", "tim hortons", "coffee", "bakery", "bagel",
                    "deli ", "diner", "grill", "bistro", "kitchen", "sushi", "ramen", "bar & ", "tavern",
                    "pub ", "brewery", "brewing", "taproom", "bar ", "lounge", "saloon",
                    "steakhouse", "steak", "chophouse", "trattoria", "osteria", "ristorante", "pizzeria", "cantina",
                    "taqueria", "tacos", "burrito", "noodle", "pho ", "dumpling", "dim sum", "hot pot", "thai ",
                    "izakaya", "bbq", "barbecue", "wings", "chicken", "falafel", "halal", "kebab", "gyro", "shawarma",
                    "biryani", "curry", "masala", "tandoori", "donut", "doughnut", "creamery", "ice cream", "gelato",
                    "juice", "smoothie", "boba", "bubble tea", "tea house", "espresso", "roasters", "eatery",
                    "brasserie", "café", "canteen", "food hall", "oyster", "seafood", "crab", "lobster", "fish market",
                    "poke ", "poke bowl", "bakehouse", "patisserie", "crepe", "waffle", "pancake", "breakfast", "brunch", "luncheonette",
                    "dos toros", "chopt", "joe & the juice", "joe and the juice", "blank street", "bluestone lane",
                    "ess-a-bagel", "xi'an famous", "los tacos", "joe's pizza", "levain", "magnolia bakery",
                    "black tap", "bareburger", "pinkberry", "arby", "sonic drive", "jack in the box", "in-n-out",
                    "whataburger", "culver", "zaxby", "raising cane", "bojangles", "white castle", "dairy queen",
                    "baskin", "krispy kreme", "auntie anne", "cinnabon", "noodles & co", "p.f. chang", "red lobster",
                    "outback", "texas roadhouse", "longhorn", "buffalo wild", "hooters", "tgi friday", "cracker barrel",
                    "waffle house", "first watch", "potbelly", "qdoba", "moe's", "el pollo", "boston market",
                    "carrabba", "maggiano", "benihana", "nobu", "ruth's chris", "morton's", "wollensky", "eataly",
                    "panda", "wingstop", "dig ", "naya", "tous les jours", "paris baguette", "insomnia cookies",
                    "crumbl", "jamba", "playa bowls", "pressed juicery", "caribou", "tim horton", "mcdonalds",
                    "burger king", "five guys", "jollibee", "nando", "honeygrow", "just salad", "fresh&co",
                    "wine bar", "cocktail", "beer garden", "biergarten", "speakeasy", "tst*", "sq *"]),
        // Before gas & auto so "TESLA FINANCE" is the car payment, not charging.
        ("carpayment", carLoanWords),
        ("commute", ["mta*", "mta ", "nyct", "omny", "metrocard", "metropolitan trans", "lirr", "long island rail",
                     "metro-north", "metro north", "nj transit", "njt ", "path ", "panynj", "citi bike", "citibike",
                     "lyft", "uber", "curb ", "nyc taxi", "taxi", "yellow cab", "revel", "septa", "wmata", "mbta",
                     "bart ", "clipper", "ventra"]),
        ("gas", ["shell", "exxon", "chevron", "bp ", "sunoco", "marathon", "wawa", "speedway", "circle k",
                 "valero", "citgo", "sheetz", "quiktrip", "racetrac", "getty", "phillips 66", "conoco",
                 "arco ", "gulf oil", "parking", "spothero", "parkwhiz", "toll", "ez pass",
                 "e-zpass", "ezpass", "zipcar", "tesla", "supercharger", "chargepoint", "electrify america",
                 "evgo", "ev charging", "autozone", "jiffy lube", "car wash", "dmv", "discount tire",
                 "goodyear", "firestone", "auto parts", "o'reilly auto", "advance auto", "napa auto",
                 "valvoline", "pep boys", "midas", "meineke", "monro", "safelite",
                 "garage", "sp+", "sp plus", "icon parking", "laz parking", "parkmobile", "park mobile", "paybyphone",
                 "passport parking", "premium parking", "impark", "mpg parking", "flash parking", "metropolis",
                 "reef parking", "towne park", "abm parking", "parking meter", "nyc dot", "dot parking",
                 "municipal parking", "ez park", "park & ride", "park n ", "valet",
                 "nyc dmv", "inspection", "emissions", "oil change", "auto body", "collision", "brake",
                 "transmission", "auto repair", "auto service", "mechanic", "body shop", "tesla service",
                 "service center", "kwik kar", "take 5", "aamco", "maaco", "les schwab", "ntb ", "jiffy",
                 "car care", "detailing", "windshield", "tire ", "tires"]),
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
