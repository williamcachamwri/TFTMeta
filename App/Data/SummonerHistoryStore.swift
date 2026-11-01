import Foundation
import SwiftUI

/// One player's match history, per-game detail and LP series.
///
/// Three actions feed it: `getSummonerMatches` answers a page of games backwards from a moment,
/// `getMatchDetail` answers one game's eight boards, and `getLpHistory` answers the ladder line.
/// The store owns them so a view can read `matches`, ask for `rivals(for:)` and be told when the
/// load landed.
@MainActor
final class SummonerHistoryStore: ObservableObject {
    static let pageSize = 30

    @Published var filter: String = "ALL" {
        didSet { if oldValue != filter { reload() } }
    }
    @Published var period: LpPeriod = .day {
        didSet { if oldValue != period { chart = Task { await loadChart() } } }
    }
    @Published private(set) var matches: [SummonerMatch] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isOlderLoading = false
    @Published private(set) var atEnd = false
    @Published private(set) var points: [LpPoint] = []
    @Published private(set) var isChartLoading = false
    /// Which game's detail is in flight — the row shows its own spinner while it lands.
    @Published private(set) var loadingDetail: String?
    @Published private(set) var failure: SummonerFailure?

    private var profile: SummonerProfile?
    private var pages: [SummonerMatch] = []
    private var boards: [String: [MatchRival]] = [:]
    private var running: Task<Void, Never>?
    private var chart: Task<Void, Never>?

    var form: RecentForm { RecentForm(matches: pages) }

    func start(_ profile: SummonerProfile) {
        guard self.profile?.puuid != profile.puuid || self.profile?.region != profile.region else { return }
        self.profile = profile
        pages = []
        matches = []
        boards = [:]
        points = []
        atEnd = false
        reload()
        chart = Task { await loadChart() }
    }

    /// The reference's "Cập nhật" re-reads the whole page, so the games and the ladder line
    /// follow the profile refresh instead of staying on the answers already on screen.
    func refresh() {
        guard profile != nil else { return }
        boards = [:]
        reload()
        chart = Task { await loadChart() }
    }

    /// Game count per filter, from the season aggregates the profile page already carries.
    func games(in filter: SummonerFilter) -> Int {
        guard let profile else { return 0 }
        if filter.queueType == "ALL" { return profile.queues.reduce(0) { $0 + $1.games } }
        return profile.queues
            .filter { queue in queue.ids.contains(where: filter.queueIDs.contains) }
            .reduce(0) { $0 + $1.games }
    }

    func reload() {
        running?.cancel()
        pages = []
        atEnd = false
        isLoading = true
        failure = nil
        running = Task { await fetch(before: nil) }
    }

    func loadOlder() {
        guard let last = pages.last, !isOlderLoading, !atEnd else { return }
        isOlderLoading = true
        Task { await fetch(before: last.createdAt) }
    }

    func rivals(for match: SummonerMatch) -> [MatchRival]? { boards[match.id] }

    /// Detail loads on open and stays: expanding the same game twice is free, and each answer
    /// carries eight full boards.
    func loadRivals(for match: SummonerMatch) async {
        guard boards[match.id] == nil, let profile else { return }
        loadingDetail = match.id
        defer { loadingDetail = nil }
        do {
            let value = try await OpGG.matchDetail.call(
                ["region": profile.region.rawValue, "puuid": profile.puuid, "matchId": match.id, "locale": OpGG.locale],
                page: matchesPage(profile)
            )
            boards[match.id] = SummonerHistoryMapper.rivals(value)
        } catch {
            boards[match.id] = []
        }
    }

    // MARK: - Loads

    private func fetch(before moment: Date?) async {
        guard let profile, !profile.puuid.isEmpty else {
            isLoading = false
            return
        }
        let wanted = filter
        do {
            let value = try await OpGG.summonerMatches.call(
                ["region": profile.region.rawValue,
                 "puuid": profile.puuid,
                 "startedAt": OpGG.tagged(moment ?? Date()),
                 "locale": OpGG.locale,
                 "queueType": wanted],
                page: matchesPage(profile)
            )
            let page = SummonerHistoryMapper.matches(value)
            guard !Task.isCancelled, wanted == filter else { return }
            if moment == nil { pages = page } else { pages += page }
            withAnimation(.easeOut(duration: 0.24)) { matches = pages }
            atEnd = page.count < Self.pageSize
        } catch {
            guard !Task.isCancelled, wanted == filter else { return }
            failure = .offline
        }
        isLoading = false
        isOlderLoading = false
    }

    private func loadChart() async {
        guard let profile, !profile.puuid.isEmpty else { return }
        let wanted = period
        isChartLoading = true
        defer { isChartLoading = false }
        do {
            let value = try await OpGG.lpHistory.call(
                ["region": profile.region.rawValue,
                 "puuid": profile.puuid,
                 "locale": OpGG.locale,
                 "version": profile.seasonVersion,
                 "type": wanted.rawValue,
                 "days": 12],
                page: OpGG.page(region: profile.region.rawValue,
                                slug: OpGG.slug(name: profile.name, tag: profile.tag))
            )
            guard !Task.isCancelled, wanted == period else { return }
            withAnimation(.easeOut(duration: 0.28)) { points = SummonerHistoryMapper.lpPoints(value) }
        } catch {
            guard !Task.isCancelled else { return }
            points = []
        }
    }

    private func matchesPage(_ profile: SummonerProfile) -> String {
        OpGG.page(region: profile.region.rawValue,
                  slug: OpGG.slug(name: profile.name, tag: profile.tag),
                  tab: "matches")
    }
}
