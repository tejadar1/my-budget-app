import Foundation

/// Combining two phones' copies of the budget without losing either
/// person's changes. A three-way merge against the copy both last agreed
/// on (`base`): whatever this phone changed since then wins; everything
/// else comes from the other phone. Purchases merge one by one; other
/// parts (categories, plan, people, rules…) merge as whole sections.
enum BudgetMerge {
    static func merge(local: BudgetData, remote: BudgetData, base: BudgetData?) -> BudgetData {
        guard let l = dict(local), let r = dict(remote) else { return remote }
        let b = base.flatMap(dict) ?? [:]
        var result = r
        for key in Set(l.keys).union(r.keys) {
            if key == "transactions" {
                result[key] = mergeTransactions(l[key] as? [[String: Any]] ?? [],
                                                r[key] as? [[String: Any]] ?? [],
                                                b[key] as? [[String: Any]])
            } else if base != nil && !same(l[key], b[key]) {
                // This phone changed it since the last sync. With no last sync
                // (a new phone or a reinstall), iCloud's copy wins.
                result[key] = l[key]
            }
        }
        guard let raw = try? JSONSerialization.data(withJSONObject: result),
              let merged = try? JSONDecoder.upside.decode(BudgetData.self, from: raw) else { return remote }
        return merged
    }

    private static func mergeTransactions(_ local: [[String: Any]], _ remote: [[String: Any]],
                                          _ base: [[String: Any]]?) -> [[String: Any]] {
        func byId(_ list: [[String: Any]]) -> [String: [String: Any]] {
            Dictionary(list.compactMap { t in (t["id"] as? String).map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        }
        let l = byId(local), r = byId(remote), b = byId(base ?? [])
        var order = remote.compactMap { $0["id"] as? String }
        order += local.compactMap { $0["id"] as? String }.filter { r[$0] == nil }
        return order.compactMap { id in
            let lt = l[id], rt = r[id], bt = b[id]
            switch (lt, rt) {
            case let (lt?, rt?):
                // Edited here since the last sync → keep ours; otherwise theirs.
                return same(lt, bt) ? rt : lt
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
