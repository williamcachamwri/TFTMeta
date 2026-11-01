import SwiftUI

struct ChampionDetailView: View {
    @EnvironmentObject private var repository: Repository
    let championKey: String

    var body: some View {
        let dataset = repository.dataset
        if let ref = dataset.champion(championKey) {
            ColumnScroll {
                VStack(alignment: .leading, spacing: 16) {
                    HeroBanner(ref: ref, stat: dataset.stat(forChampion: championKey))
                    if let stat = dataset.stat(championKey) { PerformanceBlock(stat: stat, total: stat.total) }
                    StatsBlock(ref: ref)
                    AbilityBlock(ref: ref)
                    TraitsBlock(keys: ref.traits ?? [])
                    ItemCombosBlock(championKey: championKey)
                    CompsBlock(championKey: championKey)
                    Color.clear.frame(height: 40)
                }
                .padding(.top, 6)
            }
            .background(Theme.background)
            .pageReveal()
            .navigationTitle(ref.n)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(L("App.champion.noData"), systemImage: "person.crop.circle.badge.questionmark")
                .background(Theme.background)
        }
    }
}

private extension TFTDataset {
    func stat(_ key: String) -> ChampionStat? { champions.first { $0.k == key } }
}

// MARK: - Hero

private struct HeroBanner: View {
    let ref: ChampionRef
    let stat: ChampionStat?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: ref.splash, contentMode: .fill)
                .frame(height: 230)
                .clipped()
            LinearGradient(colors: [Theme.background.opacity(0.15), Theme.background], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip(text: L("App.champion.filter.costFormat", ref.cost ?? 0), color: Theme.rarity(ref.cost), filled: true)
                    if let role = ref.role { Chip(text: roleLabel(role), color: Theme.textSecondary) }
                }
                Text(ref.n)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 10) {
                    RemoteImage(url: ref.tile, contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.rarity(ref.cost), lineWidth: 2))
                    Text(ref.abilityName.map { L("App.champion.abilityLabel", $0) } ?? L("App.champion.ability"))
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.gutter)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "APCarry": return L("App.champion.role.apCarry")
        case "ADCarry": return L("App.champion.role.adCarry")
        case "Tank": return L("App.champion.role.tank")
        case "APFighter": return L("App.champion.role.apFighter")
        case "ADFighter": return L("App.champion.role.adFighter")
        case "Support": return L("App.champion.role.support")
        case "Vanguard": return L("App.champion.role.vanguard")
        default: return role
        }
    }
}

// MARK: - Blocks

private struct PerformanceBlock: View {
    let stat: ChampionStat
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.performance"), detail: "\(Fmt.integer(total)) \(L("MetaTrendsChampion.games"))")
            Card {
                HStack(spacing: 0) {
                    StatColumn(title: L("App.champion.sort.avg"), value: Fmt.decimal(stat.avg))
                    StatColumn(title: L("App.champion.win"), value: Fmt.percent(stat.winRate, digits: 1), color: Color(hex: 0x39B57A))
                    StatColumn(title: L("App.stat.top4"), value: Fmt.percent(stat.top4Rate, digits: 1), color: Theme.accentBright)
                }
                VStack(spacing: 8) {
                    labeledMeter(L("HomeSummary.winRate"), stat.winRate, scale: 0.35, color: Color(hex: 0x39B57A))
                    labeledMeter(L("MetaTrendsChampion.top4Rate"), stat.top4Rate, scale: 0.8, color: Theme.accent)
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func labeledMeter(_ title: String, _ value: Double, scale: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.textTertiary).frame(width: 84, alignment: .leading)
            MeterBar(fraction: value / max(scale, 0.001), color: color, height: 6)
            Text(Fmt.percent(value, digits: 1)).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textPrimary).frame(width: 52, alignment: .trailing)
        }
    }
}

private struct StatsBlock: View {
    let ref: ChampionRef

    private var entries: [(String, String)] {
        guard let s = ref.stats else { return [] }
        return [
            (L("App.champion.stat.hp"), Fmt.integer(Int(s.hp ?? 0))),
            (L("App.champion.stat.damage"), Fmt.integer(Int(s.damage ?? 0))),
            (L("App.champion.stat.attackSpeed"), Fmt.decimal(s.attackSpeed, digits: 2)),
            (L("BuffAndNerf.armor"), Fmt.integer(Int(s.armor ?? 0))),
            (L("BuffAndNerf.magicResist"), Fmt.integer(Int(s.magicResist ?? 0))),
            (L("App.stat.mana"), Fmt.integer(Int(s.mana ?? 0))),
            (L("App.champion.stat.range"), Fmt.decimal(s.range, digits: 0) + " \(L("App.champion.stat.rangeUnit"))"),
            (L("App.stat.critChance"), Fmt.percent(s.critChance, digits: 0))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.baseStats"), detail: L("App.champion.starLevel"))
            Card {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(entries, id: \.0) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.0).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                            Text(entry.1).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct AbilityBlock: View {
    let ref: ChampionRef

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.ability"), detail: ref.abilityName)
            Card {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: ref.skillIcon, contentMode: .fit)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ref.ability ?? "—")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                        if let stats = ref.abilityStats, !stats.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(stats, id: \.self) { line in
                                    Text("• " + line).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct TraitsBlock: View {
    @EnvironmentObject private var repository: Repository
    let keys: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.traits"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keys, id: \.self) { key in
                        let ref = repository.dataset.trait(key)
                        NavigationLink {
                            TraitDetailView(traitKey: key)
                        } label: {
                            HStack(spacing: 7) {
                                RemoteImage(url: ref?.icon, contentMode: .fit).frame(width: 22, height: 22)
                                Text(ref?.n ?? key).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Theme.surface, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}

private struct ItemCombosBlock: View {
    @EnvironmentObject private var repository: Repository
    let championKey: String

    var body: some View {
        let combos = repository.dataset.combos(forChampion: championKey).prefix(8)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.recommendedItems"), detail: L("App.champion.byWinRate"))
            if combos.isEmpty {
                Card {
                    Text(L("App.champion.noComboData"))
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
            } else {
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(combos.enumerated()), id: \.offset) { index, combo in
                            NavigationLink {
                                ItemDetailView(keys: combo.keys)
                            } label: {
                                HStack(spacing: 10) {
                                    HStack(spacing: -5) {
                                        ForEach(Array(combo.keys.enumerated()), id: \.offset) { _, key in
                                            RemoteImage(url: repository.dataset.item(key)?.icon, contentMode: .fit)
                                                .frame(width: 28, height: 28)
                                        }
                                    }
                                    .frame(width: CGFloat(combo.keys.count) * 24 + 6)
                                    Text(combo.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 6)
                                    if let usage = combo.champs.first(where: { $0.k == championKey }) {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(Fmt.percent(usage.winRate, digits: 1))
                                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x39B57A))
                                            Text(Fmt.integer(usage.total) + " \(L("MetaTrendsChampion.games"))")
                                                .font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                }
                                .padding(9)
                            }
                            .buttonStyle(PressStyle())
                            if index < combos.count - 1 { Divider().overlay(Theme.separator.opacity(0.6)) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct CompsBlock: View {
    @EnvironmentObject private var repository: Repository
    let championKey: String

    var body: some View {
        let comps = repository.dataset.comps(forChampion: championKey).prefix(6)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.commonComps"), detail: L("App.champion.compCount", repository.dataset.comps(forChampion: championKey).count))
            ForEach(Array(comps.enumerated()), id: \.element.id) { _, comp in
                NavigationLink {
                    CompDetailView(compID: comp.id)
                } label: {
                    HStack(spacing: 10) {
                        if let tier = comp.opTier { Chip(text: tier, color: Theme.opTier(tier), filled: true) }
                        Text(comp.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        Text(Fmt.decimal(comp.stats.avg) + " \(L("App.champion.avg"))").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}
