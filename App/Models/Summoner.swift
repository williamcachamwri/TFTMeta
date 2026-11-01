import SwiftUI

/// Server codes from op.gg's `Region` message, in the order the reference picker lists them.
enum SummonerRegion: String, CaseIterable, Identifiable {
    case na, eune, euw, lan, las, me, oce, sea, kr, jp, br, ru, tr, vn, tw

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }

    /// op.gg spells its server names out with the region code in brackets — `Region.name` is one
    /// ICU select block, and Tools/build_i18n.py splits it into one key per server.
    /// @i18n Region.name@
    var title: String { L("Region.name@\(rawValue)") }

    static let ordered: [SummonerRegion] = [.na, .eune, .euw, .lan, .las, .me, .oce, .sea, .kr, .jp, .br, .ru, .tr, .vn, .tw]
}

/// op.gg tier keys are Riot's uppercase tiers; the reference localises them with an ICU select.
enum TierLocal {
    static func name(_ tier: String?) -> String {
        switch tier?.lowercased() {
        case "iron": return L("Tier.tier@iron")
        case "bronze": return L("Tier.tier@bronze")
        case "silver": return L("Tier.tier@silver")
        case "gold": return L("Tier.tier@gold")
        case "platinum": return L("Tier.tier@platinum")
        case "emerald": return L("Tier.tier@emerald")
        case "diamond": return L("Tier.tier@diamond")
        case "master": return L("Tier.tier@master")
        case "grandmaster": return L("Tier.tier@grandmaster")
        case "challenger": return L("Tier.tier@challenger")
        case "unranked", "none", nil: return L("HomeSummary.unranked")
        default: return L("Tier.tier@other")
        }
    }

    static func color(_ tier: String?) -> Color {
        switch tier?.lowercased() {
        case "iron": return Color(hex: 0x8A94A0)
        case "bronze": return Color(hex: 0xC07E43)
        case "silver": return Color(hex: 0xB9C2CB)
        case "gold": return Color(hex: 0xE0A32E)
        case "platinum": return Color(hex: 0x57C7E3)
        case "emerald": return Color(hex: 0x39B57A)
        case "diamond": return Color(hex: 0x5B8DEF)
        case "master": return Color(hex: 0x9D55E8)
        case "grandmaster": return Color(hex: 0xE85D75)
        case "challenger": return Color(hex: 0x58D7C8)
        default: return Theme.textTertiary
        }
    }

    static func division(_ rank: String?) -> String {
        switch rank?.uppercased() {
        case "I": return "I"
        case "II": return "II"
        case "III": return "III"
        case "IV": return "IV"
        default: return ""
        }
    }
}

struct LeagueStanding {
    let tier: String?
    let division: String?
    let points: Int?
    let wins: Int?
    let losses: Int?
    let setName: String?

    var gameCount: Int { (wins ?? 0) + (losses ?? 0) }
    var seasonLabel: String? {
        setName.map { L("Layout.setGuide", ["season": $0.replacingOccurrences(of: "TFTSet", with: "")]) }
    }
    var winRate: Double? {
        guard let wins, let losses, wins + losses > 0 else { return nil }
        return Double(wins) / Double(wins + losses)
    }
}

/// Aggregated `matchStat` for one queue family, merged across op.gg's queue ids.
struct SeasonStat {
    let placement: [Int]        // index 0…7 == finished 1st…8th
    let total: Int
    let byTrait: [AggStat]
    let byChampion: [AggStat]
    let byAugment: [AggStat]

    struct AggStat: Identifiable {
        let key: String
        let total: Int
        let placement: [Int]
        var id: String { key }

        var average: Double? {
            guard total > 0 else { return nil }
            let sum = placement.enumerated().reduce(0.0) { $0 + Double($1.offset + 1) * Double($1.element) }
            return sum / Double(total)
        }

        var top4: Double? {
            guard total > 0 else { return nil }
            return Double(placement.prefix(4).reduce(0, +)) / Double(total)
        }
    }

    var average: Double? { Self.average(of: placement, total: total) }
    var top4: Double? { total > 0 ? Double(placement.prefix(4).reduce(0, +)) / Double(total) : nil }
    var top1: Double? { total > 0 ? Double(placement.first ?? 0) / Double(total) : nil }

    static func average(of placement: [Int], total: Int) -> Double? {
        guard total > 0 else { return nil }
        let sum = placement.enumerated().reduce(0.0) { $0 + Double($1.offset + 1) * Double($1.element) }
        return sum / Double(total)
    }
}

/// op.gg's queue ids, with the names its own i18n bundle gives each mode.
/// Ids sharing a name are merged, so a set's several ranked buckets read as one mode.
struct SummonerQueue: Identifiable {
    let ids: [String]
    let title: String
    let stat: SeasonStat

    var id: String { title }
    var isRanked: Bool { ids.contains(SummonerQueue.rankedID) }
    var games: Int { stat.total }

    /// Anything op.gg exposes under an unfamiliar id folds into one bucket, so a
    /// player's games never silently disappear from the picker.
    /// op.gg's own filter list keys these ids: 1130 is turbo, 1160 and up are double up.
    static func title(for id: String) -> String {
        switch id {
        case "1090": return L("App.queue.normal")
        case "1100": return L("Summoner.ranked")
        case "1130": return L("Summoner.hyperRoll")
        case "1160", "1170", "1180", "1190": return L("Summoner.doubleUp")
        default: return L("App.queue.other")
        }
    }

    static let rankedID = "1100"
}

/// One row of op.gg's header autocomplete (`getAutoSuggest`).
struct SummonerSuggestion: Identifiable, Hashable {
    let name: String
    let tag: String
    let region: SummonerRegion
    let icon: String?
    /// Already formatted by op.gg, e.g. `MASTER I - 28LP`.
    let ranked: String?

    var id: String { "\(region.rawValue)|\(name)-\(tag)" }
    var displayName: String { "\(name)#\(tag)" }
}

struct SummonerProfile {
    let name: String
    let tag: String
    let region: SummonerRegion
    /// Every summoner action — matches, detail, LP history — is keyed on this, not on the name.
    let puuid: String
    let icon: String?
    let level: Int?
    let updatedAt: String?
    let standing: LeagueStanding?
    /// False when the page only carries an older season's league entry — the badge
    /// then has to say which season it came from instead of pretending to be live.
    let standingIsCurrent: Bool
    let previousSeasons: [LeagueStanding]
    /// The seasons op.gg lists for this player, newest first; each carries the patch versions
    /// that `getLpHistory` and the season summary expect.
    let seasons: [SummonerSeason]
    let ladder: (current: Int?, total: Int?)
    let queues: [SummonerQueue]

    var displayName: String { "\(name)#\(tag)" }
    var slug: String { "\(name)-\(tag)" }

    /// Ranked first when present — that is what the reference opens on.
    var primary: SummonerQueue? {
        queues.first(where: \.isRanked) ?? queues.first
    }

    var topShare: Double? {
        guard let current = ladder.current, let total = ladder.total, total > 0 else { return nil }
        return Double(current) / Double(total)
    }

    /// Newest season's first patch — the version the LP chart is read against.
    var seasonVersion: String { seasons.first?.versions.first ?? "18.5" }
}

struct SummonerSeason {
    let set: Int
    let startedAt: Date?
    let versions: [String]

    var title: String { L("Layout.setGuide", ["season": "\(set)"]) }
}
