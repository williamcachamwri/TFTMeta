import Foundation

/// Reads a summoner page. op.gg resolves most of the block server-side but leaves
/// `entry`/`matchStat` as lazy `"$…:props:…"` references, so each of those is taken
/// from the *resolved* copy elsewhere in the same flight.
enum SummonerMapper {
    private static let iconBase = "https://opgg-static.akamaized.net/meta/images/profile_icons/profileIcon"

    static func profile(from html: String, region: SummonerRegion, set: Int) -> SummonerProfile? {
        let flight = RSC.flight(from: html)
        guard flight.contains("\"summonerInfo\":") else { return nil }

        guard let infoData = RSC.jsonObjects(in: flight, anchor: "\"summonerInfo\":").first,
              let info = try? JSONDecoder().decode(JSONValue.self, from: infoData),
              let summoner = info["summoner"] else { return nil }

        let name = summoner["gameName"]?.stringValue ?? summoner["internalGameName"]?.stringValue ?? ""
        guard !name.isEmpty else { return nil }

        let standings = RSC.jsonObjects(in: flight, anchor: "\"entry\":")
            .compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            .compactMap { standing(from: $0["RANKED_TFT"]) }
        let live = standings.first { $0.setName == "TFTSet\(set)" }
        let current = live ?? standings.first

        let history = (summoner["previousSeasons"]?.arrayValue ?? [])
            .compactMap { standing(from: $0["entry"]?["RANKED_TFT"] ?? $0["entry"]) }
            .filter { $0.tier != nil }

        return SummonerProfile(
            name: name,
            tag: summoner["tagLine"]?.stringValue ?? summoner["internalTagLine"]?.stringValue ?? "0",
            region: region,
            puuid: summoner["puuid"]?.stringValue ?? "",
            icon: summoner["profileIconId"]?.intValue.map { iconURL($0) },
            level: summoner["summonerLevel"]?.intValue,
            updatedAt: summoner["updatedAt"]?.stringValue,
            standing: current,
            standingIsCurrent: live != nil,
            previousSeasons: history,
            seasons: seasons(in: flight),
            ladder: ladder(in: flight),
            queues: queues(in: flight)
        )
    }

    static func iconURL(_ id: Int) -> String { "\(iconBase)\(id).jpg" }

    /// `seasons[]` is the player's own season list — set number plus the patch versions the
    /// LP history and per-season summary actions are keyed on.
    private static func seasons(in flight: String) -> [SummonerSeason] {
        let parser = ISO8601DateFormatter()
        return RSC.jsonObjects(in: flight, anchor: "\"seasons\":")
            .compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            .flatMap(\.arrayValue)
            .compactMap { node -> SummonerSeason? in
                guard let set = node["set"]?.intValue else { return nil }
                let started = node["startedAt"]?.stringValue.flatMap(parser.date(from:))
                return SummonerSeason(set: set,
                                      startedAt: started,
                                      versions: (node["version"]?.arrayValue ?? []).compactMap { $0.stringValue })
            }
            .sorted { $0.set > $1.set }
    }

    // MARK: - Ladder share

    /// `ranking` sits next to `matchStat`, keyed by Riot queue *name* rather than id.
    private static func ladder(in flight: String) -> (current: Int?, total: Int?) {
        guard let block = RSC.jsonObjects(in: flight, anchor: "\"ranking\":")
            .compactMap({ try? JSONDecoder().decode(JSONValue.self, from: $0) })
            .first(where: { $0["RANKED_TFT"] != nil }),
              let ranked = block["RANKED_TFT"] else { return (nil, nil) }
        return (ranked["current"]?.intValue, ranked["total"]?.intValue)
    }

    // MARK: - Match statistics

    private static func queues(in flight: String) -> [SummonerQueue] {
        guard let block = RSC.jsonObjects(in: flight, anchor: "\"matchStat\":")
            .compactMap({ try? JSONDecoder().decode(JSONValue.self, from: $0) })
            .first(where: { $0["match"] != nil }),
              let match = block["match"]?.objectValue else { return [] }

        var merged: [String: Merged] = [:]
        for (queueID, entry) in match {
            let games = entry["total"]?.intValue ?? 0
            guard games > 0 else { continue }
            let title = SummonerQueue.title(for: queueID)
            var group = merged[title] ?? Merged(title: title)
            group.ids.append(queueID)
            group.total += games
            group.placement = add(group.placement, placements(entry["placement"]))
            merge(into: &group.traits, from: block["traits"]?[queueID]?.objectValue ?? [:])
            merge(into: &group.champions, from: block["units"]?[queueID]?.objectValue ?? [:])
            merge(into: &group.augments, from: block["augments"]?[queueID]?.objectValue ?? [:])
            merged[title] = group
        }

        return merged.values
            .map { $0.queue() }
            .sorted { lhs, rhs in
                if lhs.isRanked != rhs.isRanked { return lhs.isRanked }
                return lhs.stat.total > rhs.stat.total
            }
    }

    private struct Merged {
        let title: String
        var ids: [String] = []
        var total = 0
        var placement = [Int](repeating: 0, count: 8)
        var traits: [String: SeasonStat.AggStat] = [:]
        var champions: [String: SeasonStat.AggStat] = [:]
        var augments: [String: SeasonStat.AggStat] = [:]

        func queue() -> SummonerQueue {
            SummonerQueue(
                ids: ids.sorted(),
                title: title,
                stat: SeasonStat(
                    placement: placement,
                    total: total,
                    byTrait: Array(top(traits, 12)),
                    byChampion: Array(top(champions, 16)),
                    byAugment: Array(top(augments, 12))
                )
            )
        }

        private func top(_ source: [String: SeasonStat.AggStat], _ limit: Int) -> [SeasonStat.AggStat] {
            source.values.sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.key < rhs.key
            }.prefix(limit).map { $0 }
        }
    }

    private static func merge(into target: inout [String: SeasonStat.AggStat],
                              from source: [String: JSONValue]) {
        for (key, node) in source {
            let games = node["total"]?.intValue ?? 0
            guard games > 0 else { continue }
            let fresh = SeasonStat.AggStat(key: key, total: games, placement: placements(node["placement"]))
            if let existing = target[key] {
                target[key] = SeasonStat.AggStat(key: key,
                                                 total: existing.total + games,
                                                 placement: add(existing.placement, fresh.placement))
            } else {
                target[key] = fresh
            }
        }
    }

    private static func placements(_ node: JSONValue?) -> [Int] {
        var values = (node?.arrayValue ?? []).compactMap(\.intValue)
        values = Array(values.prefix(8))
        while values.count < 8 { values.append(0) }
        return values
    }

    private static func add(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
        zip(lhs, rhs).map(+)
    }

    // MARK: - League

    static func standing(from node: JSONValue?) -> LeagueStanding? {
        guard let node else { return nil }
        return LeagueStanding(
            tier: node["tier"]?.stringValue,
            division: node["rank"]?.stringValue,
            points: node["leaguePoints"]?.intValue,
            wins: node["wins"]?.intValue,
            losses: node["losses"]?.intValue,
            setName: node["tftSetCoreName"]?.stringValue ?? node["setName"]?.stringValue
        )
    }
}
