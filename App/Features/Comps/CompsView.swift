import SwiftUI

enum CompSort: String, CaseIterable, Identifiable {
    case opScore, avg, top1, pick, playable
    var id: String { rawValue }
    var title: String {
        switch self {
        case .opScore: return L("App.comp.sort.opScore")
        case .avg: return L("App.champion.sort.avg")
        case .top1: return L("App.comp.sort.top1")
        case .pick: return L("App.comp.sort.pick")
        case .playable: return L("App.comp.playable")
        }
    }
}

private enum TierFilter: Hashable {
    case all, tier(String)
    var label: String { self == .all ? L("App.comp.filter.allTiers") : L("App.comp.filter.tierFormat", rawTier) }
    var rawTier: String { if case .tier(let t) = self { return t }; return "" }

    static var options: [(value: TierFilter, title: String)] {
        ([TierFilter.all] + ["OP", "S", "A", "B", "C", "D"].map { TierFilter.tier($0) }).map { ($0, $0.label) }
    }
}

struct CompsView: View {
    @EnvironmentObject private var repository: Repository
    @State private var sort: CompSort = .opScore
    @State private var tier: TierFilter = .all
    @State private var level = 0
    @State private var searching = false
    @State private var query = ""
    @State private var showingChampionSelector = false
    @State private var lastOwnedCount = 0

    private var levels: [Int] {
        Array(Set(repository.dataset.comps.map { $0.reroll ?? 0 })).filter { $0 > 0 }.sorted()
    }

    private var playableComps: [Comp] {
        repository.dataset.comps.filter { comp in
            let score = repository.matchScore(for: comp)
            return score.owned > 0
        }
    }

    private var visible: [Comp] {
        let all = repository.dataset.comps
        return all
            .filter { tier == .all || $0.opTier == tier.rawTier }
            .filter { level == 0 || ($0.reroll ?? 0) == level }
            .filter { query.isEmpty || matches($0) }
            .sorted { lhs, rhs in
                switch sort {
                case .opScore: return (lhs.opScore ?? 0) > (rhs.opScore ?? 0)
                case .avg: return lhs.stats.avg < rhs.stats.avg
                case .top1: return lhs.stats.win > rhs.stats.win
                case .pick: return lhs.stats.pick > rhs.stats.pick
                case .playable:
                    let l = repository.matchScore(for: lhs)
                    let r = repository.matchScore(for: rhs)
                    // Core units first (weighted 2x), then total owned.
                    let lScore = l.coreOwned * 2 + l.owned
                    let rScore = r.coreOwned * 2 + r.owned
                    if lScore != rScore { return lScore > rScore }
                    return (lhs.opScore ?? 0) > (rhs.opScore ?? 0)
                }
            }
    }

    private func matches(_ comp: Comp) -> Bool {
        let haystack = ([comp.name, comp.nameEn ?? ""] + comp.traits.compactMap { repository.dataset.trait($0.k)?.n } + comp.units.compactMap { repository.dataset.champion($0.k)?.n })
            .joined(separator: " ")
            .folding(options: .diacriticInsensitive, locale: AppLanguage.current.format)
        return haystack.localizedCaseInsensitiveContains(query.folding(options: .diacriticInsensitive, locale: AppLanguage.current.format))
    }

    var body: some View {
        ScreenScaffold(title: L("App.comp.title"), subtitle: repository.dataset.meta.version) {
            UnderlineTabs(options: CompSort.allCases.map { ($0, $0.title) }, selection: $sort)
                .padding(.horizontal, Theme.gutter)
        } filters: {
            VStack(spacing: 10) {
                FilterBar {
                    FilterPill(title: L("App.comp.filter.allTiers"), options: TierFilter.options, selection: $tier)
                    if level > 0 {
                        Button { level = 0 } label: {
                            HStack(spacing: 5) {
                                Text(L("App.comp.level", level)).font(.system(size: 13, weight: .semibold))
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Theme.accentBright)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                        }.buttonStyle(PressStyle())
                    }
                    Spacer(minLength: 8)
                    Button {
                        showingChampionSelector = true
                    } label: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(repository.ownedChampions.isEmpty ? Theme.textSecondary : Theme.accentBright)
                            .frame(width: 38, height: 36)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                                    .strokeBorder(repository.ownedChampions.isEmpty ? Color.clear : Theme.accentBright, lineWidth: 1.5)
                            )
                            .overlay(alignment: .topTrailing) {
                                if !repository.ownedChampions.isEmpty {
                                    Text("\(repository.ownedChampions.count)")
                                        .font(.system(size: 8, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 14, height: 14)
                                        .background(Theme.accentBright, in: Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(PressStyle())
                    Button {
                        if searching { query = "" }
                        searching.toggle()
                    } label: {
                        Image(systemName: searching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 38, height: 36)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, Theme.gutter)

                if searching {
                    TextField(L("App.comp.searchPlaceholder"), text: $query)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .padding(.horizontal, Theme.gutter)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LevelChip(label: L("App.comp.allLevels"), active: level == 0) { level = 0 }
                        ForEach(levels, id: \.self) { value in
                            LevelChip(label: L("App.comp.level", value), active: level == value) { level = value }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
            // Filter chrome animates; the result list underneath re-renders instantly so a
            // interrupted transaction can never leave rows half-faded.
            .animation(.snappy, value: searching)
            .animation(.snappy, value: level)
        } content: {
            VStack(spacing: 14) {
                if sort == .opScore && tier == .all && level == 0 && query.isEmpty {
                    PodiumRow(comps: Array(visible.prefix(3)))
                }

                LazyVStack(spacing: 8) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, comp in
                    NavigationLink {
                        CompDetailView(compID: comp.id)
                    } label: {
                        CompRow(comp: comp, rank: index + 1)
                    }
                    .buttonStyle(PressStyle())
                }
                }
                .padding(.horizontal, Theme.gutter)

                if visible.isEmpty {
                    ContentUnavailableView(L("App.comp.noComps"), systemImage: "tray",
                                           description: Text(L("App.comp.noCompsDesc")))
                        .padding(.top, 40)
                }
            }
        }
        .sheet(isPresented: $showingChampionSelector) {
            ChampionSelectorView()
        }
        .onChange(of: repository.ownedChampions.count) { newCount in
            if newCount > 0 && lastOwnedCount == 0 {
                // User just selected champions — switch to playable sort.
                withAnimation(.snappy) { sort = .playable }
            }
            lastOwnedCount = newCount
        }
    }
}

private struct LevelChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: active ? .bold : .semibold))
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Top-3 showcase reproducing the reference's medal podium: one continuous
/// baseline through every avatar's bottom edge, medals pinned on top of it.
struct PodiumRow: View {
    static let avatarSide: CGFloat = 62
    static let heroSide: CGFloat = 70
    let comps: [Comp]

    var body: some View {
        guard comps.count == 3 else { return AnyView(EmptyView()) }
        let order = [1, 0, 2] // 2nd · 1st · 3rd, like the reference
        return AnyView(
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(order, id: \.self) { index in
                        PodiumColumn(comp: comps[index], rank: index + 1, hero: index == 1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.surface.opacity(0.95),
                                Theme.surface.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.4), Theme.accent.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Theme.accent.opacity(0.15), radius: 12, y: 6)
            .padding(.horizontal, Theme.gutter)
        )
    }
}

private struct PodiumColumn: View {
    @EnvironmentObject private var repository: Repository
    let comp: Comp
    let rank: Int
    let hero: Bool

    var body: some View {
        let lead = repository.dataset.champion(comp.units.first(where: \.core)?.k ?? comp.units.first?.k)
        NavigationLink {
            CompDetailView(compID: comp.id)
        } label: {
            VStack(spacing: 8) {
                PodiumAvatar(url: lead?.tile, cost: lead?.cost, marked: comp.opTier == "OP", rank: rank, hero: hero)
                VStack(spacing: 3) {
                    Text(comp.name)
                        .font(.system(size: hero ? 13 : 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 3) {
                        Text(Fmt.decimal(comp.stats.avg, digits: 2))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(rank == 1 ? Theme.gold : Theme.accentBright)
                        Text(L("App.champion.avg"))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: hero
                                ? [Theme.accent.opacity(0.15), Theme.accent.opacity(0.05)]
                                : [Theme.surfaceRaised.opacity(0.5), Theme.surfaceRaised.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        rank == 1 ? Theme.gold.opacity(0.4) : Theme.separator.opacity(0.3),
                        lineWidth: rank == 1 ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(PressStyle())
    }
}

private struct PodiumAvatar: View {
    let url: String?
    let cost: Int?
    let marked: Bool
    let rank: Int
    let hero: Bool

    var body: some View {
        let side = hero ? PodiumRow.heroSide : PodiumRow.avatarSide
        ZStack(alignment: .topLeading) {
            RemoteImage(url: url, contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.rarity(cost), lineWidth: 2.5)
                )
            if marked {
                Text(L("App.comp.opBadge"))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.opTier("OP"), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(x: -4, y: -4)
            }
        }
        .frame(width: side, height: side)
        // The medal is pinned to the artwork's own bottom edge, so it stays on the
        // shared baseline no matter how tall this column's avatar is.
        .overlay(alignment: .bottom) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(rank == 1 ? Color(hex: 0x2A1D00) : .white)
                .frame(width: 22, height: 22)
                .background(rank == 1 ? Theme.gold : (rank == 2 ? Theme.silver : Theme.bronze), in: Circle())
                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 3))
                .offset(y: 11)
        }
        .frame(width: PodiumRow.heroSide, height: PodiumRow.heroSide, alignment: .bottom)
        .padding(.bottom, 11)
    }
}

/// Row anatomy copied from the reference: avatar · #rank + name + tags · big metric.
struct CompRow: View {
    @EnvironmentObject private var repository: Repository
    let comp: Comp
    let rank: Int

    private var leadKey: String? { (comp.units.first(where: \.core) ?? comp.units.first)?.k }
    private var lead: ChampionRef? { repository.dataset.champion(leadKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteImage(url: lead?.tile, contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Theme.rarity(lead?.cost), lineWidth: 2)
                        )
                        .shadow(color: Theme.rarity(lead?.cost).opacity(0.3), radius: 4, y: 2)
                    if let level = comp.reroll {
                        Text(L("App.comp.level", level))
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(Theme.surfaceSunken.opacity(0.9), in: Capsule())
                            .offset(x: 3, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    RankLabel(rank: rank)
                    Text(comp.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 4) {
                        if let tier = comp.opTier {
                            Chip(text: tier, color: Theme.opTier(tier), filled: true)
                        }
                        Text("·").foregroundStyle(Theme.textTertiary)
                        Text(L("App.comp.totalCost", comp.cost)).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        if !repository.ownedChampions.isEmpty {
                            let score = repository.matchScore(for: comp)
                            if score.owned > 0 {
                                Text("\(score.owned)/\(score.total)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                                    .background(
                                        score.coreOwned == score.coreTotal && score.coreTotal > 0
                                            ? Theme.accentBright
                                            : Theme.accentBright.opacity(0.6),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    MetricValue(value: Fmt.decimal(comp.stats.avg, digits: 2), unit: L("App.comp.rankUnit"))
                    Text(Fmt.percent(comp.stats.top4, digits: 1) + L("App.stat.top4Suffix"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .contentTransition(.numericText())
                }
            }
            .padding(12)

            Divider().overlay(Theme.separator.opacity(0.5)).padding(.horizontal, 12)

            HStack(spacing: 0) {
                StatColumn(title: L("App.comp.sort.top1"), value: Fmt.percent(comp.stats.win, digits: 1))
                StatColumn(title: L("App.stat.top4"), value: Fmt.percent(comp.stats.top4, digits: 1))
                StatColumn(title: L("App.comp.sort.pick"), value: Fmt.percent(comp.stats.pick, digits: 2))
                StatColumn(title: L("App.comp.sort.opScore"), value: Fmt.decimal(comp.opScore, digits: 1), color: Theme.accentBright)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            UnitStrip(comp: comp)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.surface, Theme.surface.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

/// Compact champion + trait strip beneath the stat columns.
private struct UnitStrip: View {
    @EnvironmentObject private var repository: Repository
    let comp: Comp

    private var cores: [CompUnit] {
        comp.units.filter(\.core).sorted { ($0.prio ?? 9) < ($1.prio ?? 9) }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(cores.prefix(4), id: \.k) { unit in
                    let champ = repository.dataset.champion(unit.k)
                    RemoteImage(url: champ?.tile, contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.rarity(champ?.cost), lineWidth: 1.5))
                        .overlay(alignment: .bottomTrailing) {
                            if !unit.items.isEmpty {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(x: 1, y: 1)
                            }
                        }
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(comp.traits.sorted { ($0.style ?? -1) > ($1.style ?? -1) }.prefix(5), id: \.k) { trait in
                    let ref = repository.dataset.trait(trait.k)
                    let palette = Theme.traitStyle(trait.style)
                    ZStack(alignment: .bottomTrailing) {
                        RemoteImage(url: ref?.icon, contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .background(palette.color.opacity(0.25), in: Circle())
                            .clipShape(Circle())
                        Text("\(trait.num)")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(palette.text)
                            .frame(minWidth: 11)
                            .padding(.horizontal, 2)
                            .background(palette.color, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.surface, lineWidth: 1))
                            .offset(x: 4, y: 4)
                    }
                    .frame(width: 22, height: 22)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
