import Foundation

/// Reads the two match payloads and the LP series into models the views can draw.
enum SummonerHistoryMapper {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func matches(_ value: JSONValue) -> [SummonerMatch] {
        value.arrayValue.compactMap { row -> SummonerMatch? in
            guard let info = row["info"], let summary = row["summary"],
                  let id = info["matchId"]?.stringValue,
                  let created = milliseconds(info["gameCreation"]) else { return nil }

            return SummonerMatch(
                id: id,
                queueType: SummonerFilters.queueType(forQueueID: info["queueId"]?.intValue.map { String($0) } ?? ""),
                queueName: info["queueName"]?.stringValue ?? "",
                createdAt: created,
                seconds: info["gameLength"]?.numberValue.map { Int($0.rounded()) } ?? 0,
                set: info["tftSetNumber"]?.intValue ?? 0,
                placement: summary["placement"]?.intValue ?? 8,
                level: summary["level"]?.intValue ?? 0,
                lastRound: summary["lastRound"]?.intValue ?? 0,
                goldLeft: summary["goldLeft"]?.intValue ?? 0,
                eliminated: summary["playersEliminated"]?.intValue ?? 0,
                damageToPlayers: summary["totalDamageToPlayers"]?.intValue ?? 0,
                traits: traits(summary["traits"]),
                units: units(summary["units"]),
                augments: augmentKeys(summary["augments"]),
                opponents: opponents(row["metadata"]?["participants"],
                                     selfPuuid: summary["puuid"]?.stringValue)
            )
        }
    }

    /// `metadata.participants` is the eight-account roster of the game, names included.
    private static func opponents(_ node: JSONValue?, selfPuuid: String?) -> [MatchOpponent] {
        (node?.arrayValue ?? []).compactMap { row -> MatchOpponent? in
            guard let puuid = row["puuid"]?.stringValue, let name = row["gameName"]?.stringValue else { return nil }
            return MatchOpponent(puuid: puuid,
                                 name: name,
                                 tag: row["tagLine"]?.stringValue ?? "",
                                 icon: row["profileIconId"]?.intValue.map { SummonerMapper.iconURL($0) },
                                 isSelf: puuid == selfPuuid)
        }
    }

    static func rivals(_ value: JSONValue) -> [MatchRival] {
        (value["match"]?["info"]?["participants"]?.arrayValue ?? []).compactMap { row -> MatchRival? in
            guard let summoner = row["summoner"], let puuid = summoner["puuid"]?.stringValue else { return nil }
            return MatchRival(
                id: puuid,
                name: summoner["gameName"]?.stringValue ?? summoner["internalGameName"]?.stringValue ?? "?",
                tag: summoner["tagLine"]?.stringValue ?? summoner["internalTagLine"]?.stringValue ?? "",
                icon: summoner["profileIconId"]?.intValue.map { SummonerMapper.iconURL($0) },
                level: summoner["summonerLevel"]?.intValue,
                placement: row["placement"]?.intValue ?? 8,
                lastRound: row["lastRound"]?.intValue ?? 0,
                goldLeft: row["goldLeft"]?.intValue ?? 0,
                eliminated: row["playersEliminated"]?.intValue ?? 0,
                damage: row["totalDamageToPlayers"]?.intValue ?? 0,
                traits: traits(row["traits"]),
                units: units(row["units"]),
                augments: augmentKeys(row["augments"]),
                standing: SummonerMapper.standing(from: summoner["entry"]?["RANKED_TFT"])
            )
        }
        .sorted { lhs, rhs in
            if lhs.placement != rhs.placement { return lhs.placement < rhs.placement }
            return lhs.name < rhs.name
        }
    }

    /// op.gg only writes a league row on the days the ladder actually moved; a date without one
    /// carries the previous standing, not a gap. Dropping those rows would cut today off the end
    /// of the chart, which is where the reference puts it.
    static func lpPoints(_ value: JSONValue) -> [LpPoint] {
        let dated = value.arrayValue.compactMap { row -> (Date, JSONValue)? in
            guard let text = row["date"]?.stringValue, let date = dayFormatter.date(from: text) else { return nil }
            return (date, row)
        }
        var last: LpPoint?
        return dated.sorted { $0.0 < $1.0 }.compactMap { date, row in
            let games = row["matchCounts"]?.intValue ?? 0
            if let tier = row["tier"]?.stringValue, let rank = row["rank"]?.stringValue {
                last = LpPoint(date: date, tier: tier, rank: rank,
                               points: row["leaguePoints"]?.intValue ?? 0, games: games)
            } else if let previous = last {
                last = LpPoint(date: date, tier: previous.tier, rank: previous.rank,
                               points: previous.points, games: games)
            }
            return last
        }
    }

    // MARK: - Pieces

    /// op.gg answers augments as objects in some payloads and bare ids in others.
    private static func augmentKeys(_ node: JSONValue?) -> [String] {
        (node?.arrayValue ?? []).compactMap { $0["name"]?.stringValue ?? $0.stringValue }
    }

    private static func traits(_ node: JSONValue?) -> [MatchTrait] {
        (node?.arrayValue ?? []).compactMap { item in
            guard let key = item["name"]?.stringValue else { return nil }
            return MatchTrait(key: key,
                              units: item["numUnits"]?.intValue ?? 0,
                              style: item["style"]?.intValue ?? 0,
                              tier: item["tierCurrent"]?.intValue ?? 0,
                              maxTier: item["tierTotal"]?.intValue ?? 0)
        }
        // Active synergies first, then the strongest: that is the order the reference prints.
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            if lhs.units != rhs.units { return lhs.units > rhs.units }
            return lhs.key < rhs.key
        }
    }

    private static func units(_ node: JSONValue?) -> [MatchUnit] {
        (node?.arrayValue ?? []).compactMap { item in
            guard let key = item["characterId"]?.stringValue else { return nil }
            return MatchUnit(key: key,
                             star: item["tier"]?.intValue ?? 1,
                             items: (item["itemNames"]?.arrayValue ?? []).compactMap { $0.stringValue })
        }
    }

    private static func milliseconds(_ node: JSONValue?) -> Date? {
        guard let value = node?.numberValue else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
}
