import Foundation

/// Readable store names from bank text: "SQ *BLUE BOTTLE #12" → "Blue Bottle".
/// Display only; matching and rules keep using the bank's text.
enum Merchant {
    /// Payment processors and card-network words banks put in front.
    private static let prefixes = [
        "sq *", "sq*", "tst* ", "tst *", "tst*", "paypal *", "paypal*", "pp*", "pp *", "sp *", "sp*",
        "pos debit ", "pos purchase ", "pos ", "debit card purchase ", "purchase authorized on ", "checkcard ",
        "check card ", "recurring payment ", "in *", "py *", "dd *", "dd*", "ckc*", "lsp*", "fs *", "sumup *",
        "zettle_*", "ec *", "bt*", "wpy*", "gglpay ", "apl*", "apl *",
    ]

    /// Well-known billers whose bank text never reads well.
    private static let known: [(String, String)] = [
        ("apple.com/bill", "Apple"), ("apple.com bill", "Apple"), ("applecom bill", "Apple"),
        ("amzn mktp", "Amazon"), ("amazon mktpl", "Amazon"), ("amazon.com", "Amazon"), ("amzn", "Amazon"),
        ("google *", "Google"), ("uber *eats", "Uber Eats"), ("uber eats", "Uber Eats"), ("uber *trip", "Uber"),
        ("lyft *", "Lyft"), ("doordash", "DoorDash"), ("mta*nyct", "MTA"), ("nyct paygo", "MTA"),
        ("con ed", "Con Edison"), ("coned", "Con Edison"),
    ]

    /// Words kept in capitals.
    private static let acronyms: Set<String> = ["amc", "mta", "cvs", "ups", "usps", "atm", "nyc", "bp", "hbo",
                                               "tj", "ikea", "h&m", "kfc", "jfk", "lga", "ewr", "nj", "ny", "llc"]

    static func clean(_ payee: String) -> String {
        var text = payee.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        if let hit = known.first(where: { lower.hasPrefix($0.0) }) { return hit.1 }
        // Names the bank already wrote in mixed case are left alone.
        guard text == text.uppercased() else { return text }

        // Processor prefixes, possibly more than one ("POS SQ *").
        var stripped = true
        while stripped {
            stripped = false
            for p in prefixes where text.lowercased().hasPrefix(p) {
                text = String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                stripped = true
            }
        }
        // Store numbers, phone numbers and trailing state codes.
        text = text.replacingOccurrences(of: #"\s*#\s*\d+.*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+\d{3}[-.]?\d{3}[-.]?\d{4}.*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+\d{3,}\b.*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+[A-Z]{2}$"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " *-.,"))
        guard !text.isEmpty else { return payee }

        // Shouted bank text becomes Title Case.
        return text.split(separator: " ").enumerated().map { index, word -> String in
            let w = word.lowercased()
            if acronyms.contains(w) { return w.uppercased() }
            if index > 0 && ["and", "of", "the", "at"].contains(w) { return w }
            return w.prefix(1).uppercased() + w.dropFirst()
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "'S ", with: "'s ")
    }
}
