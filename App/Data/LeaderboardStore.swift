import Foundation
import SwiftUI

/// One row of op.gg's ranked ladder.
struct LeaderboardEntry: Identifiable {
    let rank: Int
    let name: String
    let tag: String
    let icon: String?
    let standing: LeagueStanding?

    var id: Int { rank }
    var displayName: String { "\(name)#\(tag)" }
}

/// op.gg ships the ladder fully server-rendered at `/tft/leaderboards/ranked?region=…&page=…`
/// — a hundred players per page inside the flight payload, same as every other TFT page here.
@MainActor
final class LeaderboardStore: ObservableObject {
    static let shared = LeaderboardStore()

    private static let pageSize = 100

    @Published var region: SummonerRegion = .vn {
        didSet {
            guard region != oldValue else { return }
            reload()
        }
    }
    @Published private(set) var entries: [LeaderboardEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false

    private var pagesLoaded = 0
    private var running: Task<Void, Never>?
    private var language = AppLanguage.current

    private init() {}

    /// The ladder's tier names ride the page's language, so a switch restarts it.
    func serve(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        reload()
    }

    func reload() {
        running?.cancel()
        entries = []
        pagesLoaded = 0
        failed = false
        loadPage(1)
    }

    /// Pulls the next page once the last ten rows scroll into view.
    func loadMoreIfNeeded(current entry: LeaderboardEntry) {
        guard !isLoading, !failed, entry.rank > entries.count - 10 else { return }
        loadPage(pagesLoaded + 1)
    }

    func reloadAsync() async {
        running?.cancel()
        isLoading = true
        let wanted = region
        let rows = await Self.fetch(region: wanted, page: 1)
        guard !Task.isCancelled, region == wanted else { return }
        isLoading = false
        entries = rows ?? []
        pagesLoaded = rows == nil ? 0 : 1
        failed = rows == nil
    }

    private func loadPage(_ page: Int) {
        isLoading = true
        let wanted = region
        running = Task { [weak self] in
            let rows = await Self.fetch(region: wanted, page: page)
            guard let self, !Task.isCancelled, self.region == wanted else { return }
            self.isLoading = false
            if let rows {
                self.pagesLoaded = page
                self.failed = false
                if page == 1 { self.entries = rows } else { self.entries.append(contentsOf: rows) }
            } else if page == 1 {
                self.failed = true
            }
        }
    }

    private nonisolated static func fetch(region: SummonerRegion, page: Int) async -> [LeaderboardEntry]? {
        guard let url = URL(string: OpGG.base + "/tft/leaderboards/ranked?region=\(region.rawValue)&page=\(page)") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        OpGG.headers(&request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }

        // The ladder component receives its page of players as the `data` prop that follows
        // its own `"type":"ladder"` marker; earlier `data` keys belong to other components.
        let flight = RSC.flight(from: html)
        guard let marker = flight.range(of: "\"type\":\"ladder\""),
              let array = RSC.jsonValue(in: String(flight[marker.lowerBound...]), anchor: "\"data\":"),
              let raw = try? JSONDecoder().decode([RawLadderPlayer].self, from: array) else { return nil }

        let base = (page - 1) * pageSize
        return raw.enumerated().compactMap { offset, player -> LeaderboardEntry? in
            guard let name = player.gameName, let tag = player.tagLine else { return nil }
            let standing = player.entry?.RANKED_TFT
            return LeaderboardEntry(
                rank: base + offset + 1,
                name: name,
                tag: tag,
                icon: player.profileIconId.map(SummonerMapper.iconURL),
                standing: LeagueStanding(tier: standing?.tier, division: standing?.rank,
                                         points: standing?.leaguePoints, wins: standing?.wins,
                                         losses: standing?.losses, setName: standing?.tftSetCoreName)
            )
        }
    }
}

private struct RawLadderPlayer: Decodable {
    struct League: Decodable {
        let tier: String?
        let rank: String?
        let leaguePoints: Int?
        let wins: Int?
        let losses: Int?
        let tftSetCoreName: String?
    }
    struct Entry: Decodable { let RANKED_TFT: League? }

    let gameName: String?
    let tagLine: String?
    let profileIconId: Int?
    let entry: Entry?
}
