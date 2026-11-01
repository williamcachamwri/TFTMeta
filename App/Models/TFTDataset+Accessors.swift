import Foundation

extension TFTDataset {
    static let empty = TFTDataset(
        meta: DatasetMeta(game: "tft", set: 18, version: "18.5", language: "vi", source: "",
                          totalGames: nil, windowHours: 24, generatedAt: ""),
        ref: References(champions: [:], items: [:], traits: [:], augments: [:]),
        comps: [], champions: [], items: [], traits: [], augments: []
    )
}

/// Convenience accessors shared by every screen.
extension TFTDataset {
    func champion(_ key: String?) -> ChampionRef? { key.flatMap { ref.champions[$0] } }
    func item(_ key: String?) -> ItemRef? { key.flatMap { ref.items[$0] } }
    func trait(_ key: String?) -> TraitRef? { key.flatMap { ref.traits[$0] } }
    func augment(_ key: String?) -> AugmentRef? { key.flatMap { ref.augments[$0] } }

    /// Every comp a champion appears in, best average placement first.
    func comps(forChampion key: String) -> [Comp] {
        comps.filter { $0.units.contains { $0.k == key } }
            .sorted { $0.stats.avg < $1.stats.avg }
    }

    func comps(forTrait key: String) -> [Comp] {
        comps.filter { $0.traits.contains { $0.k == key } }
            .sorted { $0.stats.avg < $1.stats.avg }
    }

    func stat(forChampion key: String) -> ChampionStat? {
        champions.first { $0.k == key }
    }

    func combos(forChampion key: String) -> [ItemComboStat] {
        items.filter { combo in combo.champs.contains { $0.k == key } }
            .sorted { $0.winRate > $1.winRate }
    }
}

// MARK: - Derived pairings

extension TFTDataset {
    /// Other decks built around the same traits.
    func similarComps(to comp: Comp) -> [CompMatch] {
        let keys = Set(comp.traits.map(\.k))
        var matches: [CompMatch] = []
        for other in comps where other.id != comp.id {
            let shared = other.traits.filter { keys.contains($0.k) }.count
            guard shared >= 3 else { continue }
            matches.append(CompMatch(comp: other, shared: shared))
        }
        return matches.sorted {
            if $0.shared != $1.shared { return $0.shared > $1.shared }
            return $0.comp.stats.avg < $1.comp.stats.avg
        }
    }
}

struct CompMatch {
    let comp: Comp
    let shared: Int
}
