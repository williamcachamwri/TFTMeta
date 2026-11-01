import SwiftUI

/// The summoner page taken as far as op.gg takes it: identity and league, a summary of the
/// season's aggregates, and the match history with every game expandable to all eight boards.
struct SummonerProfileView: View {
    private enum Tab: Int, CaseIterable, Identifiable {
        case summary, history

        var id: Int { rawValue }
        var title: String { self == .summary ? L("Summoner.tabSummary") : L("Summoner.tabMatch") }
    }

    @EnvironmentObject private var repository: Repository
    @EnvironmentObject private var store: SummonerStore
    @StateObject private var history = SummonerHistoryStore()
    @State private var tab: Tab = .summary
    @State private var queueID: String?
    @State private var costFilter = 0

    /// The player this screen was opened for.
    let route: SummonerProfile

    private var dataset: TFTDataset { repository.dataset }

    /// Refreshing replaces the store's copy of the same player, so the screen follows that
    /// rather than the snapshot it was pushed with.
    private var profile: SummonerProfile {
        store.profile?.puuid == route.puuid ? store.profile ?? route : route
    }

    /// Ranked first when present — the reference opens on it.
    private var queue: SummonerQueue? {
        profile.queues.first(where: { $0.id == queueID }) ?? profile.primary
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header

                UnderlineTabs(options: Tab.allCases.map { ($0, $0.title) }, selection: $tab)
                    .background(Theme.background)

                Group {
                    switch tab {
                    case .summary: summary
                    case .history: historyTab
                    }
                }
                .transition(.opacity)

                Color.clear.frame(height: 40)
            }
            .padding(.top, 6)
        }
        .background(Theme.background)
        .pageReveal()
        .animation(.easeOut(duration: 0.22), value: tab)
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task { history.start(profile) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !profile.previousSeasons.isEmpty {
                SeasonBadgeRow(seasons: profile.previousSeasons)
            }
            ProfileCard(profile: profile,
                        showChartButton: true,
                        chart: { AnyView(RankChartView(profile: profile, history: history)) },
                        refresh: {
                            store.refresh()
                            history.refresh()
                        },
                        isBusy: store.isLoading)
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            if profile.queues.count > 1 {
                ChipRow(options: profile.queues.map { ($0.id, "\($0.title) · \($0.games)") },
                        selection: queueSelection)
            }

            if let queue, queue.stat.total > 0 {
                PlacementCard(stat: queue.stat, title: queue.title)
                    .padding(.horizontal, Theme.gutter)

                if !queue.stat.byTrait.isEmpty {
                    SectionBlock(title: L("Summoner.mostSynergies")) {
                        ForEach(Array(queue.stat.byTrait.prefix(8).enumerated()), id: \.element.id) { index, item in
                            AggRow(item: item, icon: dataset.trait(item.key)?.icon,
                                   name: dataset.trait(item.key)?.n ?? item.key, tint: Theme.accentBright,
                                   separated: index > 0)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }

                if !queue.stat.byChampion.isEmpty {
                    championSection(queue.stat.byChampion)
                }

                if !queue.stat.byAugment.isEmpty {
                    SectionBlock(title: L("App.summoner.mostAugments")) {
                        ForEach(Array(queue.stat.byAugment.prefix(8).enumerated()), id: \.element.id) { index, item in
                            AggRow(item: item, icon: dataset.augment(item.key)?.icon,
                                   name: dataset.augment(item.key)?.n ?? item.key,
                                   tint: Theme.augmentTier(dataset.augment(item.key)?.tier).color,
                                   separated: index > 0)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            } else {
                Text(L("App.summoner.noGames"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            if !profile.previousSeasons.isEmpty {
                SectionBlock(title: L("Summoner.moreSeasonTier")) {
                    ForEach(Array(profile.previousSeasons.enumerated()), id: \.offset) { index, season in
                        SeasonRow(season: season, separated: index > 0)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var queueSelection: Binding<String> {
        Binding(get: { queue?.id ?? profile.primary?.id ?? "" }, set: { queueID = $0 })
    }

    private func championSection(_ items: [SeasonStat.AggStat]) -> some View {
        let costs = Set(items.compactMap { dataset.champion($0.key)?.cost })
        let visible = items.filter { costFilter == 0 || costBucket(of: $0.key) == costFilter }
        return VStack(alignment: .leading, spacing: 10) {
            SectionBlock(title: L("Summoner.mostChampions")) {
                ForEach(Array(visible.prefix(12).enumerated()), id: \.element.id) { index, item in
                    AggRow(item: item,
                           icon: dataset.champion(item.key)?.tile,
                           name: dataset.champion(item.key)?.n ?? item.key,
                           tint: Theme.rarity(dataset.champion(item.key)?.cost),
                           separated: index > 0)
                }
            }
            if costs.count > 1 {
                ChipRow(options: costOptions(costs), selection: $costFilter)
            }
        }
    }

    private func costOptions(_ costs: Set<Int>) -> [(value: Int, title: String)] {
        var options: [(Int, String)] = [(0, L("Summoner.allCosts"))]
        for cost in (1...5) where costs.contains(cost) || (cost == 5 && costs.contains(where: { $0 >= 5 })) {
            options.append((cost, cost == 5 ? L("App.summoner.costFormat5Plus") : L("App.champion.filter.costFormat", "\(cost)")))
        }
        return options
    }

    private func costBucket(of key: String) -> Int {
        min(dataset.champion(key)?.cost ?? 0, 5)
    }

    // MARK: - History

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChipRow(options: SummonerFilters.all.map { ($0.queueType, "\($0.title) (\(history.games(in: $0)))") },
                    selection: $history.filter)

            if history.form.games > 0 {
                RecentFormCard(form: history.form)
            }

            if history.isLoading {
                MatchListSkeleton(rows: 4)
            }

            if let failure = history.failure {
                FailureCard(text: failure.displayText, systemImage: "clock.arrow.circlepath", retry: history.reload)
                    .padding(.horizontal, Theme.gutter)
            }

            ForEach(history.matches) { match in
                SummonerMatchRow(match: match,
                                 rivals: history.rivals(for: match),
                                 isLoadingRivals: history.loadingDetail == match.id,
                                 loadRivals: { Task { await history.loadRivals(for: match) } })
                    .padding(.horizontal, Theme.gutter)
                    .transition(.opacity)
                    .onAppear {
                        if match.id == history.matches.last?.id { history.loadOlder() }
                    }
            }

            if history.isOlderLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .padding(.vertical, 10)
            }

            if history.atEnd, !history.matches.isEmpty {
                Text(L("App.summoner.endOfHistory", Fmt.integer(history.matches.count)))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            if history.matches.isEmpty, !history.isLoading, history.failure == nil {
                ContentUnavailableView(L("App.summoner.noMatches"),
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text(L("App.summoner.noMatchesDesc")))
                    .padding(.top, 20)
            }
        }
    }
}

/// The reference's "30 trận gần đây" block: the donut, the two headline rates, and every
/// synergy with its top-4 rate plus the placements of the games it was played in.
private struct RecentFormCard: View {
    @EnvironmentObject private var repository: Repository
    let form: RecentForm

    private var dataset: TFTDataset { repository.dataset }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("Summoner.recentGamesTitle", "30"), detail: L("App.summoner.gameCount", Fmt.integer(form.games)))

            HStack(alignment: .center, spacing: 16) {
                PlacementDonut(counts: form.placements,
                               total: form.games,
                               center: Fmt.percent(form.top4Rate, digits: 0),
                               caption: L("App.summoner.top4"))
                VStack(spacing: 8) {
                    StatColumn(title: L("Summoner.top4Rate"),
                               value: "\(Fmt.integer(form.wins)) \(L("App.champion.winSuffix")) / \(Fmt.integer(form.losses)) \(L("App.summoner.loseSuffix")) (\(Fmt.percent(form.top4Rate, digits: 0)))",
                               color: Color(hex: 0x39B57A))
                    StatColumn(title: L("Summoner.avgPlacement"), value: L("App.summoner.avgPlacementFormat", Fmt.decimal(form.average, digits: 1)))
                }
            }

            if !form.traits.isEmpty {
                Divider().overlay(Theme.separator.opacity(0.7))
                SectionTitle(text: L("Summoner.recentSynergyTitle", "30"))
                ForEach(Array(form.traits.prefix(6).enumerated()), id: \.element.key) { index, item in
                    FormTraitRow(item: item, separated: index > 0)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
    }

    private struct FormTraitRow: View {
        @EnvironmentObject private var repository: Repository
        let item: RecentForm.FormTrait
        var separated = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    let ref = repository.dataset.trait(item.key)
                    RemoteImage(url: ref?.icon, contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                    Text(Fmt.percent(item.rate, digits: 2))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text("(\(Fmt.integer(item.top4)) \(L("App.champion.winSuffix")) / \(Fmt.integer(item.games - item.top4)) \(L("App.summoner.loseSuffix")))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }

                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(Array(item.recent.prefix(10).enumerated()), id: \.offset) { _, place in
                        PlacementChip(value: place)
                    }
                }
            }
            .padding(.top, separated ? 10 : 6)
            .padding(.bottom, 4)
            .overlay(alignment: .top) {
                if separated { Divider().overlay(Theme.separator.opacity(0.6)) }
            }
        }
    }
}

/// `#1`…`#8` in the medal palette, the reference's placement strip.
private struct PlacementChip: View {
    let value: Int

    var body: some View {
        Text("#\(value)")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(value <= 4 ? Color(hex: 0x1B1E21) : Theme.textPrimary)
            .frame(width: 26, height: 20)
            .background(PlacementDonut.color(index: value - 1).opacity(value <= 4 ? 0.95 : 0.45),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Destination-shaped placeholder so the list does not jump when a page lands.
private struct MatchListSkeleton: View {
    let rows: Int

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView(style: .rounded(width: 34, height: 17, cornerRadius: 4))
                        SkeletonView(style: .rounded(width: 52, height: 9, cornerRadius: 3))
                        SkeletonView(style: .rounded(width: 44, height: 9, cornerRadius: 3))
                    }
                    .frame(width: 68, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonView(style: .rounded(height: 22, cornerRadius: 6))
                        SkeletonView(style: .rounded(height: 42, cornerRadius: 8))
                    }
                    Spacer(minLength: 6)
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}
