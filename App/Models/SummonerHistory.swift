import Foundation

/// A finished game, as `getSummonerMatches` reports it: everything the summary row and the
/// expanded card need, already reduced to the fields this app draws.
struct SummonerMatch: Identifiable {
    let id: String                 // op.gg match id, e.g. `VN2_1620185362`
    let queueType: String
    let queueName: String
    let createdAt: Date
    let seconds: Int
    let set: Int
    let placement: Int
    let level: Int
    let lastRound: Int
    let goldLeft: Int
    let eliminated: Int
    let damageToPlayers: Int
    let traits: [MatchTrait]
    let units: [MatchUnit]
    let augments: [String]
    /// The other seven plus this player, straight out of the row's own `metadata.participants` —
    /// the reference prints their names beside a collapsed game, so the list needs no detail call.
    let opponents: [MatchOpponent]

    var isTop4: Bool { placement <= 4 }

    /// op.gg packs the final round into one int — 53 reads as "5-3" on the site.
    var roundLabel: String { lastRound >= 10 ? "\(lastRound / 10)-\(lastRound % 10)" : "\(lastRound)" }
}

struct MatchOpponent {
    let puuid: String
    let name: String
    let tag: String
    let icon: String?
    let isSelf: Bool

    var displayName: String { "\(name)#\(tag)" }
}

struct MatchUnit {
    let key: String
    let star: Int
    let items: [String]
}

struct MatchTrait {
    let key: String
    let units: Int
    let style: Int
    let tier: Int
    let maxTier: Int

    /// op.gg only colours a synergy the game actually activated; the rest read as dead units.
    var isActive: Bool { tier > 0 }
}

/// One of the other seven players, from `getMatchDetail`. The detail row carries the whole
/// board, so the expanded card can reproduce the reference's per-player table.
struct MatchRival: Identifiable {
    let id: String                 // puuid
    let name: String
    let tag: String
    let icon: String?
    let level: Int?
    let placement: Int
    let lastRound: Int
    let goldLeft: Int
    let eliminated: Int
    let damage: Int
    let traits: [MatchTrait]
    let units: [MatchUnit]
    let augments: [String]
    let standing: LeagueStanding?

    var displayName: String { "\(name)#\(tag)" }
}

/// The five filters above op.gg's match list, in the order the page prints them.
/// `total` comes from the profile's own queue counts, which is what the reference shows in the chip.
struct SummonerFilter: Identifiable {
    let queueType: String
    let queueIDs: [String]

    var id: String { queueType }
    /// Computed, not stored: a `static let` list would freeze whichever language was current when
    /// it first ran.
    var title: String { SummonerFilters.title(forQueueType: queueType) }
}

enum SummonerFilters {
    static let all: [SummonerFilter] = [
        SummonerFilter(queueType: "ALL", queueIDs: []),
        SummonerFilter(queueType: "NORMAL_TFT", queueIDs: ["1090"]),
        SummonerFilter(queueType: "RANKED_TFT", queueIDs: ["1100"]),
        SummonerFilter(queueType: "RANKED_TFT_TURBO", queueIDs: ["1130"]),
        SummonerFilter(queueType: "RANKED_TFT_DOUBLE_UP", queueIDs: ["1160", "1170", "1180", "1190"])
    ]

    static func title(forQueueID id: String) -> String {
        all.first { $0.queueIDs.contains(id) }?.title ?? L("App.queue.other")
    }

    /// The chip label for a row's own `queueType`, which the mapper already resolved from the id.
    static func title(forQueueType type: String) -> String {
        switch type {
        case "ALL": return L("Summoner.all")
        case "NORMAL_TFT": return L("App.queue.normal")
        case "RANKED_TFT": return L("Summoner.ranked")
        case "RANKED_TFT_TURBO": return L("Summoner.hyperRoll")
        case "RANKED_TFT_DOUBLE_UP": return L("Summoner.doubleUp")
        default: return L("Summoner.all")
        }
    }

    static func queueType(forQueueID id: String) -> String {
        all.first { $0.queueIDs.contains(id) }?.queueType ?? "ALL"
    }
}

/// One point of `getLpHistory`. The action answers the whole ladder history of a season, and the
/// chart's granularity is chosen by the `type` argument, not by filtering client-side.
struct LpPoint: Identifiable {
    let date: Date
    let tier: String
    let rank: String
    let points: Int
    let games: Int

    var id: Date { date }
}

enum LpPeriod: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return LCap("SummonerLpHistory.day")
        case .week: return LCap("SummonerLpHistory.week")
        case .month: return L("SummonerLpHistory.month")
        }
    }
}

/// Recent-form block: the same 30 games the reference draws as a donut, a top-4 line, an
/// average-placement line and the three synergies that won most often.
struct RecentForm {
    let games: Int
    let wins: Int
    let losses: Int
    let top4Rate: Double
    let average: Double
    let placements: [Int]
    let traits: [FormTrait]

    struct FormTrait {
        let key: String
        let games: Int
        let top4: Int
        /// Placements of the games this synergy appeared in, newest first — the reference
        /// prints the last ten as a strip of `#1`…`#8` chips beside the rate.
        let recent: [Int]

        var rate: Double { games > 0 ? Double(top4) / Double(games) : 0 }
    }

    init(matches: [SummonerMatch]) {
        let recent = Array(matches.prefix(30))
        games = recent.count
        let counts = (0..<8).map { rank in recent.filter { $0.placement == rank + 1 }.count }
        placements = counts
        let top4 = counts.prefix(4).reduce(0, +)
        self.top4Rate = recent.isEmpty ? 0 : Double(top4) / Double(recent.count)
        wins = top4
        losses = recent.count - top4
        average = recent.isEmpty ? 0 : Double(recent.reduce(0) { $0 + $1.placement }) / Double(recent.count)

        var tally: [String: (games: Int, top4: Int, recent: [Int])] = [:]
        for game in recent {
            for trait in game.traits where trait.isActive {
                let hit = tally[trait.key] ?? (0, 0, [])
                tally[trait.key] = (hit.games + 1,
                                    hit.top4 + (game.isTop4 ? 1 : 0),
                                    hit.recent + [game.placement])
            }
        }
        traits = tally
            .map { key, value in FormTrait(key: key, games: value.games, top4: value.top4, recent: value.recent) }
            .sorted { lhs, rhs in
                if lhs.games != rhs.games { return lhs.games > rhs.games }
                return lhs.top4 > rhs.top4
            }
    }
}
