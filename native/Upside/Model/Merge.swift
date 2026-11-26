import Foundation

/// Combining two phones' copies of the budget without losing either
/// person's changes. A three-way merge against the copy both last agreed
/// on (`base`), field by field: what only one phone changed is kept; what
/// both changed is merged deeper (purchases, accounts, categories and
/// trips one by one, then each of their fields), and only a true clash on
/// the same field goes to this phone.
///
/// Field by field matters because both phones sync with the bank on
/// their own, and that touches purchases (pending → posted, transfers,
/// guesses). Taking a whole purchase from one phone let that refresh
/// wipe out the other person's "business" or "Income".
enum BudgetMerge {
    static func merge(local: BudgetData, remote: BudgetData, base: BudgetData?) -> BudgetData {
        guard let l = dict(local), let r = dict(remote) else { return remote }
        var result: [String: Any]
        if let base, let b = dict(base) {
            result = (merge3(l, r, b) as? [String: Any]) ?? r
        } else {
            // No last sync (a new phone or a reinstall): iCloud's copy wins,
            // keeping purchases only this phone has.
            result = r
            result["transactions"] = mergeKeyed(l["transactions"] as? [[String: Any]] ?? [],
                                                r["transactions"] as? [[String: Any]] ?? [], nil)
        }
        guard let raw = try? JSONSerialization.data(withJSONObject: result),
              let merged = try? JSONDecoder.upside.decode(BudgetData.self, from: raw) else { return remote }
        return merged
    }

    /// Three-way merge of one JSON value. Nil means "not there".
    static func merge3(_ l: Any?, _ r: Any?, _ b: Any?) -> Any? {
        if same(l, b) { return r }      // only the other phone changed it (or nobody did)
        if same(r, b) || same(l, r) { return l }
        // Both changed it, differently: go deeper where there is a deeper.
        if let ld = l as? [String: Any], let rd = r as? [String: Any] {
            let bd = b as? [String: Any] ?? [:]
            var out: [String: Any] = [:]
            for key in Set(ld.keys).union(rd.keys) {
                if let v = merge3(ld[key], rd[key], bd[key]) { out[key] = v }
            }
            return out
        }
        if let la = l as? [[String: Any]], let ra = r as? [[String: Any]], keyed(la), keyed(ra) {
            return mergeKeyed(la, ra, b as? [[String: Any]])
        }
        if let la = l as? [String], let ra = r as? [String] {
            // A set of names (stores that aren't bills, alerts sent…): both
            // phones' additions, minus what either removed.
            let bs = Set(b as? [String] ?? [])
            let removed = bs.subtracting(la).union(bs.subtracting(ra))
            var seen = Set<String>()
            return (ra + la).filter { !removed.contains($0) && seen.insert($0).inserted }
        }
        return l                         // a true clash: this phone's edit
    }

    /// Lists of things with an identity (purchases, accounts, categories,
    /// trips, rules), merged one by one.
    private static func mergeKeyed(_ local: [[String: Any]], _ remote: [[String: Any]],
                                   _ base: [[String: Any]]?) -> [[String: Any]] {
        func byId(_ list: [[String: Any]]) -> [String: [String: Any]] {
            Dictionary(list.compactMap { t in key(t).map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        }
        let l = byId(local), r = byId(remote), b = byId(base ?? [])
        var order = remote.compactMap(key)
        order += local.compactMap(key).filter { r[$0] == nil }
        var seen = Set<String>()
        return order.filter { seen.insert($0).inserted }.compactMap { id in
            let lt = l[id], rt = r[id], bt = b[id]
            switch (lt, rt) {
            case let (lt?, rt?):
                return merge3(lt, rt, bt) as? [String: Any]
            case let (lt?, nil):
                // New here → keep. Deleted there and untouched here → drop.
                return bt == nil || !same(lt, bt) ? lt : nil
            case let (nil, rt?):
                // New there → keep. Deleted here and untouched there → drop.
                return bt == nil || !same(rt, bt) ? rt : nil
            default:
                return nil
            }
        }
    }

    private static func key(_ item: [String: Any]) -> String? {
        (item["id"] as? String) ?? (item["payeeKey"] as? String)
    }

    private static func keyed(_ list: [[String: Any]]) -> Bool {
        list.allSatisfy { key($0) != nil }
    }

    private static func dict(_ data: BudgetData) -> [String: Any]? {
        guard let raw = try? JSONEncoder.upside.encode(data) else { return nil }
        return (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return canonical(a) == canonical(b)
        default: return false
        }
    }

    private static func canonical(_ value: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject([value]) else { return nil }
        return try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
    }
}
