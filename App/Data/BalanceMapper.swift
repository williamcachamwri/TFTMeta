import Foundation

/// Decodes one `/vi/tft/buff-and-nerf/<route>` payload.
///
/// op.gg lists balance changes as `data[key].diff = { path: [labels] }` where `path`
/// addresses the *current* blob (`stats.mana`, `ability.desc`, `level.9`,
/// `org.fromDesc`, `ability.variables.<name>`) and the matching `prevData[key]`
/// holds the previous patch. `balance` is +1 buff, −1 nerf, 0 reworded only.
enum BalanceMapper {
    private struct Payload: Decodable {
        let versions: [String]?
        let version: String?
        let prevVersion: String?
        let data: [String: JSONValue]
        let prevData: [String: JSONValue]?
    }

    /// Numeric-looking changes first, prose last — that is how the reference groups them.
    private static let pathOrder = ["stats", "ability.variables", "level", "desc", "ability.desc", "org.fromDesc"]

    static func snapshot(from flight: String, route: BalanceRoute) -> BalanceSnapshot? {
        guard let data = RSC.jsonEnclosing(in: flight, anchor: "\"versions\":[") else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        let previous = payload.prevData ?? [:]
        var entries: [BalanceEntry] = []
        entries.reserveCapacity(payload.data.count)

        for (key, entry) in payload.data {
            guard let balance = entry["balance"]?.numberValue,
                  let kind = BalanceKind(rawValue: Int(balance)) else { continue }
            let changes = changes(diff: entry["diff"] ?? .null, now: entry, before: previous[key] ?? .null)
            guard !changes.isEmpty else { continue }

            entries.append(BalanceEntry(
                id: key,
                name: entry["name"]?.stringValue ?? key,
                kind: kind,
                icon: (route == .champion ? entry["tileIcon"] : entry["icon"])?.stringValue ?? entry["icon"]?.stringValue,
                cost: entry["cost"]?.intValue,
                tier: entry["tier"]?.stringValue,
                category: entry["category"]?.stringValue,
                changes: changes
            ))
        }

        entries.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue > rhs.kind.rawValue }
            if (lhs.cost ?? 0) != (rhs.cost ?? 0) { return (lhs.cost ?? 0) > (rhs.cost ?? 0) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return BalanceSnapshot(
            route: route,
            version: payload.version ?? "",
            prevVersion: payload.prevVersion ?? "",
            versions: payload.versions ?? [],
            entries: entries,
            total: payload.data.count
        )
    }

    private static func changes(diff: JSONValue, now: JSONValue, before: JSONValue) -> [BalanceChange] {
        let paths = diff.objectValue
        var result: [BalanceChange] = []
        var handled: Set<String> = []

        for path in pathOrder where paths[path] != nil {
            handled.insert(path)
            result.append(contentsOf: changes(path: path, labels: paths[path] ?? .null, now: now, before: before))
        }
        for (path, labels) in paths where !handled.contains(path) {
            result.append(contentsOf: changes(path: path, labels: labels, now: now, before: before))
        }
        return result
    }

    private static func changes(path: String, labels: JSONValue, now: JSONValue, before: JSONValue) -> [BalanceChange] {
        switch path {
        case "desc":
            return pair(label: L("Community.Write.description"), at: "desc", now: now, before: before)
        case "ability.desc":
            return pair(label: L("BuffAndNerf.skill"), at: "ability.desc", now: now, before: before)
        case "org.fromDesc":
            return pair(label: L("App.balance.componentStats"), at: "org.fromDesc", now: now, before: before)

        case "stats":
            return labels.arrayValue.compactMap(\.stringValue).flatMap { label in
                pair(label: BalanceChange.statTitle(label), at: "stats.\(label)", now: now, before: before)
            }

        case "level":
            return labels.arrayValue.compactMap(\.stringValue).flatMap { level in
                pair(label: L("App.balance.threshold", level), at: "level.\(level)", now: now, before: before)
            }

        case "ability.variables":
            return labels.arrayValue.compactMap(\.stringValue).compactMap { name in
                let after = now.value(atPath: "ability.variables")?.named(name)?["value"]?.displayText
                let was = before.value(atPath: "ability.variables")?.named(name)?["value"]?.displayText
                guard let after, let was, after != was else { return nil }
                return BalanceChange(label: name, before: was, after: after)
            }

        default:
            return []
        }
    }

    private static func pair(label: String, at path: String, now: JSONValue, before: JSONValue) -> [BalanceChange] {
        let after = clean(now.value(atPath: path))
        let was = clean(before.value(atPath: path))
        guard after != was else { return [] }
        return [BalanceChange(label: label, before: was, after: after)]
    }

    private static func clean(_ value: JSONValue?) -> String {
        LiveMapper.clean(value?.displayText) ?? "—"
    }
}
