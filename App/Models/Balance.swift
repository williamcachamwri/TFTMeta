import SwiftUI

/// op.gg route segment under `/vi/tft/buff-and-nerf/<route>`.
enum BalanceRoute: String, CaseIterable, Identifiable {
    case champion, synergy, item, augments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .champion: return L("BuffAndNerf.champion")
        case .synergy: return L("BuffAndNerf.synergy")
        case .item: return L("BuffAndNerf.item")
        case .augments: return L("BuffAndNerf.augment")
        }
    }
}

/// `balance` in the payload: +1 buff, −1 nerf, 0 reworded without a power shift.
enum BalanceKind: Int, CaseIterable, Identifiable {
    case buff = 1
    case adjust = 0
    case nerf = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .buff: return L("BuffAndNerf.buff")
        case .adjust: return L("BuffAndNerf.adjust")
        case .nerf: return L("BuffAndNerf.nerf")
        }
    }

    var short: String {
        switch self {
        case .buff: return L("App.badge.buff")
        case .adjust: return L("App.badge.adjust")
        case .nerf: return L("App.badge.nerf")
        }
    }

    var color: Color {
        switch self {
        case .buff: return Color(hex: 0x39B57A)
        case .adjust: return Theme.accentBright
        case .nerf: return Color(hex: 0xE85D75)
        }
    }

    var icon: String {
        switch self {
        case .buff: return "arrow.up.right"
        case .adjust: return "arrow.triangle.2.circlepath"
        case .nerf: return "arrow.down.right"
        }
    }
}

/// One before/after pair inside an entry.
struct BalanceChange: Identifiable {
    let id = UUID()
    let label: String
    let before: String
    let after: String

    /// Numbers get a compact `60 → 63` row; anything else is prose and gets the
    /// word-level highlight treatment.
    var numeric: (old: Double, new: Double)? {
        guard let old = Double(before), let new = Double(after) else { return nil }
        return (old, new)
    }

    var delta: Double? {
        guard let pair = numeric else { return nil }
        return pair.new - pair.old
    }

    /// Stat names op.gg keys by camelCase english in the payload.
    static func statTitle(_ key: String) -> String {
        switch key {
        case "hp", "health": return L("BuffAndNerf.health")
        case "mana", "skillMana": return L("App.stat.mana")
        case "initialMana", "startingMana": return L("App.stat.initialMana")
        case "armor": return L("BuffAndNerf.armor")
        case "magicResist", "magicalResistance": return L("BuffAndNerf.magicResist")
        case "damage", "attackDamage": return L("BuffAndNerf.attackDamage")
        case "damagePerSecond": return L("BuffAndNerf.dps")
        case "attackSpeed": return L("BuffAndNerf.attackSpeed")
        case "range", "attackRange": return L("BuffAndNerf.attackRange")
        case "critChance": return L("App.stat.critChance")
        case "critMultiplier": return L("App.stat.critMultiplier")
        case "manaRegen": return L("GameGuide.blackthornData.manaRegen")
        default: return key
        }
    }
}

struct BalanceEntry: Identifiable {
    let id: String
    let name: String
    let kind: BalanceKind
    let icon: String?
    let cost: Int?
    let tier: String?
    let category: String?
    let changes: [BalanceChange]
}

struct BalanceSnapshot {
    let route: BalanceRoute
    let version: String
    let prevVersion: String
    let versions: [String]
    let entries: [BalanceEntry]
    var total: Int

    static func empty(_ route: BalanceRoute) -> BalanceSnapshot {
        BalanceSnapshot(route: route, version: "", prevVersion: "", versions: [], entries: [], total: 0)
    }
}

extension BalanceEntry {
    /// op.gg ships `Missing-T2.png` placeholders for some augments; the bundled ref has real art.
    func icon(in dataset: TFTDataset) -> String? {
        if let icon, !icon.contains("Missing") { return icon }
        return dataset.champion(id)?.tile
            ?? dataset.item(id)?.icon
            ?? dataset.trait(id)?.icon
            ?? dataset.augment(id)?.icon
    }

    /// The small qualifier chip under the name: cost, augment tier, item/trait group.
    var detail: String? {
        if let cost { return L("GameGuide.blackthornData.costOption", ["cost": "\(cost)"]) }
        if let tier { return Theme.augmentTier(tier).label }
        guard let category else { return nil }
        switch category.lowercased() {
        case "origin": return L("MetaTrendsSynergy.origin")
        case "class": return L("MetaTrendsSynergy.class")
        case "unique": return L("GameGuide.portalId.Unique")
        default: return Theme.itemCategory(category).label
        }
    }
}

// MARK: - Text diffing

/// Balance notes change one number inside an otherwise identical paragraph, so
/// highlighting the diverging words reads far better than stacking both versions.
enum BalanceText {
    static let up = Color(hex: 0x39B57A)
    static let down = Color(hex: 0xE85D75)

    static func marked(before: String, after: String) -> AttributedString {
        let old = tokens(before)
        let new = tokens(after)

        var head = 0
        while head < old.count, head < new.count, old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < old.count - head, tail < new.count - head,
              old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }

        var shared = AttributeContainer()
        shared.foregroundColor = Theme.textSecondary
        shared.font = .system(size: 12)

        var result = AttributedString(old[0..<head].joined(), attributes: shared)

        let removed = old[head..<old.count - tail].joined()
        let added = new[head..<new.count - tail].joined()
        if !removed.isEmpty {
            var dropped = shared
            dropped.foregroundColor = down
            dropped.font = .system(size: 12, weight: .semibold)
            dropped.strikethroughStyle = .single
            result.append(AttributedString(removed, attributes: dropped))
        }
        if !added.isEmpty {
            var grown = shared
            grown.foregroundColor = up
            grown.font = .system(size: 12, weight: .bold)
            result.append(AttributedString(added, attributes: grown))
        }

        if tail > 0 {
            let sharedTail = old[(old.count - tail)...].joined()
            result.append(AttributedString(sharedTail, attributes: shared))
        }
        return result
    }

    /// Splits into alternating runs of non-whitespace and whitespace so the join
    /// round-trips exactly and line breaks survive.
    private static func tokens(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        var inSpace = false
        for character in text {
            let space = character.isWhitespace
            if !current.isEmpty, space != inSpace {
                runs.append(current)
                current = ""
            }
            current.append(character)
            inSpace = space
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
