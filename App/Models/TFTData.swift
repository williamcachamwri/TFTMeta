import Foundation

// MARK: - Reference dictionaries (shared entities keyed by op.gg apiName)

struct ChampionRef: Codable, Hashable {
    let n: String
    let tile: String?
    let splash: String?
    let skillIcon: String?
    let cost: Int?
    let role: String?
    let traits: [String]?
    let stats: ChampionStatsBlock?
    let abilityName: String?
    let ability: String?
    let abilityStats: [String]?
    let recommendItems: [String]?
}

struct ChampionStatsBlock: Codable, Hashable {
    let hp: Double?
    let mana: Double?
    let armor: Double?
    let range: Double?
    let damage: Double?
    let critChance: Double?
    let attackSpeed: Double?
    let initialMana: Double?
    let magicResist: Double?
    let critMultiplier: Double?
}

struct ItemRef: Codable, Hashable {
    let n: String
    let icon: String?
    let desc: String?
    let statDesc: String?
    let category: String?
    let unique: Bool?
    let radiant: Bool?
    let composition: [String]?
    let associatedTraits: [String]?
}

struct TraitRef: Codable, Hashable {
    let n: String
    let icon: String?
    let type: String?
    let desc: String?
    let tiers: [TraitTier]?
    let champions: [String]?
}

struct TraitTier: Codable, Hashable {
    let min: Int
    let max: Int?
    let style: Int?
    let desc: String?
}

struct AugmentRef: Codable, Hashable {
    let n: String
    let icon: String?
    let desc: String?
    let tier: String?
    let tags: [String]?
    let unique: Bool?
    let associatedTraits: [String]?
    let incompatibleTraits: [String]?
}

struct References: Codable {
    let champions: [String: ChampionRef]
    let items: [String: ItemRef]
    let traits: [String: TraitRef]
    let augments: [String: AugmentRef]
}

// MARK: - Comps

struct Cell: Codable, Hashable { let x: Int; let y: Int }

struct CompUnit: Codable, Hashable {
    let k: String
    let tier: Int?
    let cell: Cell?
    let core: Bool
    let prio: Int?
    let role: String?
    let items: [String]
}

struct CompTrait: Codable, Hashable {
    let k: String
    let num: Int
    let style: Int?
}

struct StageBoard: Codable, Hashable {
    struct Unit: Codable, Hashable {
        let k: String
        let cell: Cell?
        let items: [String]
    }
    struct Trait: Codable, Hashable {
        let k: String
        let num: Int
        let style: Int?
    }
    let level: Int?
    let play: Int?
    let win: Int?
    let lose: Int?
    let units: [Unit]
    let traits: [Trait]
}

struct CompStats: Codable, Hashable {
    let avg: Double
    let win: Double
    let top4: Double
    let pick: Double
    let count: Int?
    let total: Int?
}

struct Comp: Codable, Hashable {
    let id: String
    let name: String
    let nameEn: String?
    let cost: Int
    let teamCode: String?
    let opTier: String?
    let opScore: Double?
    let rep: Bool
    let stats: CompStats
    let labelStats: CompStats?
    let difficulty: Int?
    let tempo: Int?
    let reroll: Int?
    let honey: Bool?
    let ppm: String?
    let units: [CompUnit]
    let traits: [CompTrait]
    let early: StageBoard?
    let middle: StageBoard?

    // The bundled snapshot often lacks the reroll badge; the final board size is the level.
    var level: Int? {
        if let reroll, reroll > 0 { return reroll }
        return units.isEmpty ? nil : units.count
    }
}

// MARK: - Ranked entity stats

struct ChampionStat: Codable, Hashable {
    let k: String
    let total: Int
    let win: Int
    let top4: Int
    let winRate: Double
    let top4Rate: Double
    let avg: Double
}

struct ItemComboStat: Codable, Hashable {
    let keys: [String]
    let label: String
    let total: Int
    let win: Int
    let top4: Int
    let winRate: Double
    let top4Rate: Double
    let avg: Double
    let champs: [ChampUsage]
}

struct ChampUsage: Codable, Hashable {
    let k: String
    let total: Int
    let winRate: Double
    let top4Rate: Double
    let avg: Double
}

struct TraitStat: Codable, Hashable {
    let k: String
    let style: Int?
    let num: Int
    let total: Int
    let win: Int
    let top4: Int
    let winRate: Double
    let top4Rate: Double
    let avg: Double
}

struct AugmentStat: Codable, Hashable {
    let k: String
    let opTier: String
    let version: String?
}

// MARK: - Root

struct DatasetMeta: Codable, Hashable {
    let game: String
    let set: Int
    let version: String
    let language: String
    let source: String
    let totalGames: Int?
    let windowHours: Int?
    let generatedAt: String
}

struct TFTDataset: Codable {
    let meta: DatasetMeta
    let ref: References
    let comps: [Comp]
    let champions: [ChampionStat]
    let items: [ItemComboStat]
    let traits: [TraitStat]
    let augments: [AugmentStat]
}
