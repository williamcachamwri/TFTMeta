import Foundation

/// Raw shapes mirroring op.gg's server-rendered payload, plus the mapping into
/// the compact `TFTDataset` the UI consumes.
enum LiveMapper {
    // MARK: Raw DTOs

    struct RawDeck: Decodable {
        /// op.gg ships deck names in all six of its locales inside one object, so a comp's title can
    /// be read in any language without another request.
    struct Name: Decodable {
        let vi_VN: String?
        let en_US: String?
        let ko_KR: String?
        let ja_JP: String?
        let zh_TW: String?
        let zh_CN: String?

        func pick(_ language: AppLanguage) -> String? {
            let direct: String?
            switch language {
            case .vi: direct = vi_VN
            case .en: direct = en_US
            case .ko: direct = ko_KR
            case .ja: direct = ja_JP
            case .zhTW: direct = zh_TW ?? zh_CN
            }
            return direct ?? en_US
        }
    }
        struct Meta: Decodable { let apiName: String?; let name: String?; let imageUrl: String?; let cost: Int?; let category: String? }
        struct Unit: Decodable {
            let key: String
            let tier: Int?
            let cell: Cell?
            let isCore: Bool?
            let priority: Int?
            let role: String?
            let meta: Meta?
            let itemMetas: [Meta]?
        }
        struct Trait: Decodable { let key: String; let style: Int?; let numUnits: Int; let meta: Meta? }
        struct Badge: Decodable { let key: String; let value: JSONValue? }
        struct Bucket: Decodable {
            let totalCount: Int?; let compsCount: Int?; let avgPlacement: Double?
            let winCount: Int?; let top4Count: Int?; let winRate: Double?; let top4Rate: Double?; let pickRate: Double?
        }
        struct Stat: Decodable { let opTier: String?; let opScore: Double?; let deck: Bucket; let label: Bucket?; let representative: Bool? }
        struct Stage: Decodable {
            struct Unit: Decodable { let characterId: String; let cell: Cell?; let items: [String?]? }
            struct Trait: Decodable { let key: String; let style: Int?; let numUnits: Int }
            let level: String?
            let play: Int?; let win: Int?; let lose: Int?
            let units: [Unit]?; let traits: [Trait]?
        }

        let id: String
        let name: Name?
        let cost: Int?
        let teamCode: String?
        let units: [Unit]?
        let traits: [Trait]?
        let badge: [Badge]?
        let stat: Stat
        let early: Stage?
        let middle: Stage?
    }

    struct RawChampion: Decodable {
        struct Ability: Decodable { let desc: String? }
        struct TraitRef: Decodable { let name: String?; let apiName: String }
        struct Skill: Decodable { let name: String?; let stats: [String]? }
        struct Org: Decodable { let skill: Skill?; let recommendItems: [String]? }
        let name: String?
        let cost: Int?
        let role: String?
        let icon: String?
        let tileIcon: String?
        let skillImageUrl: String?
        let stats: ChampionStatsBlock?
        let traits: [TraitRef]?
        let ability: Ability?
        let org: Org?
    }

    struct RawItem: Decodable {
        struct Org: Decodable { let fromDesc: String? }
        let name: String?
        let icon: String?
        let desc: String?
        let category: String?
        let unique: Bool?
        let composition: [String]?
        let associatedTraits: [String]?
        let org: Org?
    }

    struct RawTrait: Decodable {
        struct Effect: Decodable { let minUnits: Int?; let maxUnits: Int?; let style: Int? }
        struct ChampionRef: Decodable { let name: String?; let apiName: String? }
        let name: String?
        let icon: String?
        let category: String?
        let desc: String?
        let level: [String: String]?
        let effects: [Effect]?
        let champions: [ChampionRef]?
    }

    struct RawAugment: Decodable {
        let name: String?
        let icon: String?
        let desc: String?
        let tier: String?
        let tags: [String]?
        let unique: Bool?
        let associatedTraits: [String]?
        let incompatibleTraits: [String]?
    }

    struct RawChampionStat: Decodable {
        let characterId: String
        let totalCount: Int; let winCount: Int; let top4Count: Int
        let winRate: Double; let top4Rate: Double; let avgPlacement: Double
    }

    struct RawItemStat: Decodable {
        struct Usage: Decodable {
            let characterId: String
            let totalCount: Int; let winRate: Double; let top4Rate: Double; let avgPlacement: Double
        }
        let items: String
        let totalCount: Int; let winCount: Int; let top4Count: Int
        let winRate: Double; let top4Rate: Double; let avgPlacement: Double
        let champions: [Usage]?
    }

    struct RawTraitStat: Decodable {
        let name: String
        let style: Int?
        let displayNumUnits: Int?
        let totalCount: Int; let winCount: Int; let top4Count: Int
        let winRate: Double; let top4Rate: Double; let avgPlacement: Double
    }

    struct RawAugmentTier: Decodable { let augments: String; let opTier: String?; let version: String? }

    // MARK: Mapping

    static func dataset(from text: String, version: String, language: AppLanguage = .vi) -> TFTDataset? {
        guard let rawDecks = RSC.decode([RawDeck].self, in: text, anchor: "\"decks\":") else { return nil }

        let rawChampions = RSC.decode([String: RawChampion].self, in: text, anchor: "\"CHAMPIONS\":") ?? [:]
        let rawItems = RSC.decode([String: RawItem].self, in: text, anchor: "\"ITEMS\":") ?? [:]
        let rawTraits = RSC.decode([String: RawTrait].self, in: text, anchor: "\"TRAITS\":") ?? [:]
        let rawAugments = RSC.decode([String: RawAugment].self, in: text, anchor: "\"AUGMENTS\":") ?? [:]
        let rawChampionStats = RSC.decode([RawChampionStat].self, in: text, anchor: "\"championStats\":") ?? []
        let rawItemStats = RSC.decode([RawItemStat].self, in: text, anchor: "\"itemStats\":") ?? []
        let rawTraitStats = RSC.decode([RawTraitStat].self, in: text, anchor: "\"traitStats\":") ?? []
        let rawAugmentTiers = RSC.decode([RawAugmentTier].self, in: text, anchor: "\"augmentTiers\":") ?? []

        var championRefs: [String: ChampionRef] = [:]
        var itemRefs: [String: ItemRef] = [:]
        var traitRefs: [String: TraitRef] = [:]
        var augmentRefs: [String: AugmentRef] = [:]

        // Skill numbers arrive as Riot tokens ("%i:scaleAP%") and every language resolves them
        // with its own wording, so the token map travels with the language of the capture.
        let clean: (String?) -> String? = { LiveMapper.clean($0, language: language) }

        func useChampion(_ key: String?) {
            guard let key, championRefs[key] == nil, let raw = rawChampions[key], let name = raw.name else { return }
            championRefs[key] = ChampionRef(
                n: name, tile: raw.tileIcon ?? raw.icon, splash: raw.icon, skillIcon: raw.skillImageUrl,
                cost: raw.cost, role: raw.role, traits: raw.traits?.map(\.apiName), stats: raw.stats,
                abilityName: raw.org?.skill?.name, ability: clean(raw.ability?.desc),
                abilityStats: raw.org?.skill?.stats?.compactMap { clean($0) }, recommendItems: raw.org?.recommendItems)
        }
        func useItem(_ key: String?) {
            guard let key, itemRefs[key] == nil, let raw = rawItems[key], let name = raw.name else { return }
            itemRefs[key] = ItemRef(
                n: name, icon: raw.icon, desc: clean(raw.desc), statDesc: clean(raw.org?.fromDesc),
                category: raw.category, unique: raw.unique, radiant: raw.category?.lowercased() == "radiant",
                composition: raw.composition, associatedTraits: raw.associatedTraits)
        }
        func useTrait(_ key: String?) {
            guard let key, traitRefs[key] == nil, let raw = rawTraits[key], let name = raw.name else { return }
            let tiers = (raw.effects ?? []).compactMap { effect -> TraitTier? in
                guard let min = effect.minUnits else { return nil }
                return TraitTier(min: min, max: effect.maxUnits.map { Swift.min($0, 14) }, style: effect.style,
                                 desc: clean(raw.level?[String(min)]))
            }
            traitRefs[key] = TraitRef(n: name, icon: raw.icon, type: raw.category, desc: clean(raw.desc),
                                      tiers: tiers, champions: raw.champions?.compactMap { $0.apiName })
        }
        func useAugment(_ key: String?) {
            guard let key, augmentRefs[key] == nil, let raw = rawAugments[key], let name = raw.name else { return }
            augmentRefs[key] = AugmentRef(n: name, icon: raw.icon, desc: clean(raw.desc), tier: raw.tier,
                                          tags: raw.tags, unique: raw.unique,
                                          associatedTraits: raw.associatedTraits, incompatibleTraits: raw.incompatibleTraits)
        }

        let knownChampions = Set(rawChampions.keys)
        let comps: [Comp] = rawDecks.map { deck in
            (deck.units ?? []).forEach { unit in
                useChampion(unit.key)
                (unit.itemMetas ?? []).forEach { useItem($0.apiName) }
            }
            (deck.traits ?? []).forEach { useTrait($0.key) }
            for stage in [deck.early, deck.middle].compactMap({ $0 }) {
                (stage.units ?? []).forEach { useChampion($0.characterId) }
                (stage.traits ?? []).forEach { useTrait($0.key) }
            }

            var difficulty: Int?, tempo: Int?, reroll: Int?
            var honey = false, ppm: String?
            for badge in deck.badge ?? [] {
                switch badge.key {
                case "difficulty": difficulty = badge.value?.intValue
                case "tempo": tempo = badge.value?.intValue
                case "reroll": reroll = badge.value?.intValue
                case "honey": honey = badge.value?.boolValue ?? false
                case "ppm": ppm = badge.value?.stringValue
                default: break
                }
            }

            let bucket: (RawDeck.Bucket) -> CompStats = { b in
                CompStats(avg: b.avgPlacement ?? 0, win: b.winRate ?? 0, top4: b.top4Rate ?? 0,
                          pick: b.pickRate ?? 0, count: b.compsCount, total: b.totalCount)
            }

            return Comp(
                id: deck.id,
                name: deck.name?.pick(language) ?? "—",
                nameEn: deck.name?.en_US,
                cost: deck.cost ?? 0,
                teamCode: deck.teamCode,
                opTier: deck.stat.opTier,
                opScore: deck.stat.opScore,
                rep: deck.stat.representative ?? false,
                stats: bucket(deck.stat.deck),
                labelStats: deck.stat.label.map(bucket),
                difficulty: difficulty, tempo: tempo, reroll: reroll, honey: honey, ppm: ppm,
                units: (deck.units ?? []).map {
                    CompUnit(k: $0.key, tier: $0.tier, cell: $0.cell, core: $0.isCore ?? false,
                             prio: $0.priority, role: $0.role, items: ($0.itemMetas ?? []).compactMap(\.apiName))
                },
                traits: (deck.traits ?? []).map { CompTrait(k: $0.key, num: $0.numUnits, style: $0.style) },
                early: deck.early.flatMap { stageView($0, knownChampions: knownChampions) },
                middle: deck.middle.flatMap { stageView($0, knownChampions: knownChampions) }
            )
        }

        let champions = rawChampionStats.compactMap { stat -> ChampionStat? in
            guard rawChampions[stat.characterId] != nil else { return nil }
            useChampion(stat.characterId)
            return ChampionStat(k: stat.characterId, total: stat.totalCount, win: stat.winCount, top4: stat.top4Count,
                                winRate: stat.winRate, top4Rate: stat.top4Rate, avg: stat.avgPlacement)
        }

        let items = rawItemStats.compactMap { stat -> ItemComboStat? in
            let keys = stat.items.split(whereSeparator: { $0 == "," || $0 == "|" })
                .map(String.init).filter { rawItems[$0] != nil }
            guard !keys.isEmpty else { return nil }
            keys.forEach(useItem)
            let champs = (stat.champions ?? []).compactMap { usage -> ChampUsage? in
                guard rawChampions[usage.characterId] != nil else { return nil }
                useChampion(usage.characterId)
                return ChampUsage(k: usage.characterId, total: usage.totalCount, winRate: usage.winRate,
                                  top4Rate: usage.top4Rate, avg: usage.avgPlacement)
            }
            return ItemComboStat(keys: keys, label: keys.compactMap { itemRefs[$0]?.n }.joined(separator: " + "),
                                 total: stat.totalCount, win: stat.winCount, top4: stat.top4Count,
                                 winRate: stat.winRate, top4Rate: stat.top4Rate, avg: stat.avgPlacement, champs: champs)
        }

        let traits = rawTraitStats.compactMap { stat -> TraitStat? in
            guard rawTraits[stat.name] != nil else { return nil }
            useTrait(stat.name)
            return TraitStat(k: stat.name, style: stat.style, num: stat.displayNumUnits ?? 0, total: stat.totalCount,
                             win: stat.winCount, top4: stat.top4Count, winRate: stat.winRate,
                             top4Rate: stat.top4Rate, avg: stat.avgPlacement)
        }

        let augments = rawAugmentTiers.compactMap { tier -> AugmentStat? in
            guard rawAugments[tier.augments] != nil else { return nil }
            useAugment(tier.augments)
            return AugmentStat(k: tier.augments, opTier: tier.opTier ?? "—", version: tier.version)
        }

        guard !comps.isEmpty else { return nil }

        return TFTDataset(
            meta: DatasetMeta(game: "tft", set: 18, version: version, language: language.code,
                              source: "op.gg\(language.prefix)/tft/meta-trends", totalGames: totalGames(from: text),
                              windowHours: 24, generatedAt: ISO8601DateFormatter().string(from: Date())),
            ref: References(champions: championRefs, items: itemRefs, traits: traitRefs, augments: augmentRefs),
            comps: comps, champions: champions, items: items, traits: traits, augments: augments
        )
    }

    /// op.gg boards include summons and alternate-form tokens with no champion
    /// record or art, so only real champions survive into the board.
    static func stageView(_ stage: RawDeck.Stage, knownChampions: Set<String>) -> StageBoard? {
        let units = (stage.units ?? []).filter { knownChampions.contains($0.characterId) }
        guard !units.isEmpty else { return nil }
        return StageBoard(
            level: stage.level.flatMap(Int.init),
            play: stage.play, win: stage.win, lose: stage.lose,
            units: units.map { StageBoard.Unit(k: $0.characterId, cell: $0.cell, items: ($0.items ?? []).compactMap { $0 }) },
            traits: (stage.traits ?? []).map { StageBoard.Trait(k: $0.key, num: $0.numUnits, style: $0.style) }
        )
    }

    /// The cohort size sits in a sentence op.gg translates whole ("… được phân tích từ 3,074,584
    /// trận", "최근 24시간 동안 3,074,584 게임을…"), so the words cannot be the anchor. The span's
    /// class is stable across locales and the number is always comma-grouped, which is what this
    /// reads.
    static func totalGames(from text: String) -> Int? {
        guard let mark = text.range(of: "hidden md:block md:text-right") else { return nil }
        let window = text[mark.upperBound...].prefix(320)
        guard let found = window.range(of: #"[0-9][0-9.,]{4,}[0-9]"#, options: .regularExpression) else { return nil }
        return Int(text[found].filter(\.isNumber))
    }

    /// Riot's skill-template tokens, resolved into the stat words op.gg prints for one language.
    /// The pages ship the tokens raw in every locale, so each capture needs its own map.
    static func statTokens(for language: AppLanguage) -> [String: String] {
        let labels: [String]
        switch language {
        case .vi:
            labels = ["sát thương từ SMPT", "sát thương từ SMCK", "sát thương từ SMCK", "tốc đánh",
                      "máu tối đa", "giáp", "kháng phép", "năng lượng", "hồi năng lượng", "hồi máu",
                      "hồi máu", "tỉ lệ chí mạng", "sát thương chí mạng", "tầm đánh", "giảm sát thương",
                      "hồi năng lượng mỗi giây", "SMCK cơ bản", "vàng"]
        case .en:
            labels = ["damage from AP", "damage from AD", "damage from AD", "attack speed",
                      "max health", "armor", "magic resist", "mana", "mana regen", "health regen",
                      "health regen", "crit chance", "crit damage", "range", "damage reduction",
                      "mana per second", "base AD", "gold"]
        case .ko:
            labels = ["주문력 기반 피해", "공격력 기반 피해", "공격력 기반 피해", "공격 속도",
                      "최대 체력", "방어력", "마법 저항력", "마나", "마나 재생", "체력 재생",
                      "체력 재생", "치명타 확률", "치명타 피해", "사거리", "피해 감소",
                      "초당 마나 재생", "기본 공격력", "골드"]
        case .ja:
            labels = ["APによるダメージ", "ADによるダメージ", "ADによるダメージ", "攻撃速度",
                      "最大HP", "装甲", "魔耐性", "マナ", "マナ回復", "HP回復",
                      "HP回復", "クリティカル率", "クリティカルダメージ", "射程", "ダメージ軽減",
                      "毎秒マナ回復", "基本AD", "ゴールド"]
        case .zhTW:
            labels = ["魔法傷害加成", "攻擊傷害加成", "攻擊傷害加成", "攻擊速度",
                      "生命值", "護甲", "魔法抗性", "魔力", "魔力回複", "生命值回複",
                      "生命值回複", "暴擊率", "暴擊傷害", "射程", "傷害減免",
                      "每秒魔力回複", "基礎攻擊力", "金幣"]
        }
        let tokens = ["%i:scaleAP%", "%i:scaleAD%", "%i:scaleDA%", "%i:scaleAS%", "%i:scaleHealth%",
                      "%i:scaleArmor%", "%i:scaleMR%", "%i:scaleMana%", "%i:scaleManaRegen%", "%i:scaleHPRegen%",
                      "%i:scaleSV%", "%i:scaleCrit%", "%i:scaleCritMult%", "%i:scaleRange%", "%i:scaleDR%",
                      "%i:TFTManaRegen%", "%i:TFTBaseAD%", "%i:goldCoins%"]
        return Dictionary(uniqueKeysWithValues: zip(tokens, labels))
    }

    /// Strips the HTML op.gg embeds inside description strings.
    static func clean(_ input: String?, language: AppLanguage = .current) -> String? {
        guard let input else { return nil }
        let replaced = input.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        var output = ""
        var insideTag = false
        for character in replaced {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; continue }
            if !insideTag { output.append(character) }
        }
        for (token, label) in statTokens(for: language) {
            output = output.replacingOccurrences(of: token, with: label)
        }
        // Tokens we have no label for would only render as noise.
        output = output.replacingOccurrences(of: "%[^%]%", with: "", options: .regularExpression)
        // "500(sát thương từ SMPT)" reads better with a space before the note.
        var spaced = ""
        for character in output {
            if character == " ", spaced.last == " " { continue }
            if character == "(", let last = spaced.last, !last.isWhitespace { spaced.append(" ") }
            spaced.append(character)
        }
        return spaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
