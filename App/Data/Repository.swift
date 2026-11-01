import Foundation
import SwiftUI

enum DataOrigin: String {
    case bundled
    case live
    case cached
}

/// Per-hex odds for a single champion, from op.gg's team-builder position action: how often the
/// unit is played from a cell and how often it wins from there. Bundled rather than fetched —
/// the action's id is a build hash that rotates on every op.gg deploy, and one call costs a
/// 1.4 MB render for a single champion.
final class PositionTable {
    /// champion key → "x,y" → [wins, games]
    private let cells: [String: [String: [Int]]]
    private let totals: [String: Int]

    init(cells: [String: [String: [Int]]]) {
        self.cells = cells
        self.totals = cells.mapValues { $0.values.reduce(0) { $0 + ($1.count > 1 ? $1[1] : 0) } }
    }

    func stat(champion: String, at cell: Cell) -> (winRate: Double, frequency: Double)? {
        guard let row = cells[champion]?["\(cell.x),\(cell.y)"], row.count == 2, row[1] > 0,
              let total = totals[champion], total > 0 else { return nil }
        return (Double(row[0]) / Double(row[1]), Double(row[1]) / Double(total))
    }
}

private struct BundledPositions: Decodable {
    let positions: [String: [String: [Int]]]
}

@MainActor
final class Repository: ObservableObject {
    static let shared = Repository()

    /// Patch/set the reference screens were captured for.
    static let version = "18.5"

    /// op.gg only server-renders the flight payload for browser-like clients.
    nonisolated static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static let languageKey = "app.language"

    /// The language the app serves, and the locale every op.gg request is sent with.
    ///
    /// Setting it swaps the whole data layer: the bundled dataset and the per-hex table come
    /// from that locale's own file, the caches are keyed by locale, and the stores that hold
    /// server-rendered text drop their pages so nothing stays in the previous language.
    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            apply(language)
        }
    }

    @Published var dataset: TFTDataset
    @Published var origin: DataOrigin
    @Published var isRefreshing = false
    @Published var notice: String?

    /// Champions the user owns — persisted so the "playable with my champs" filter survives
    /// relaunches. Stored as a set of champion keys (the same `k` the dataset uses).
    @Published var ownedChampions: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(ownedChampions), forKey: Self.ownedChampionsKey)
        }
    }

    private static let ownedChampionsKey = "app.ownedChampions"

    /// Rebuilt on a language switch, but never by a refresh: a live fetch rebuilds the meta
    /// tables, not the per-hex odds.
    private(set) var positions: PositionTable

    private static func cacheURL(_ language: AppLanguage) -> URL {
        let folder = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let name = "\(language.resource)-live.json"
        return folder?.appendingPathComponent(name)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    private init() {
        let stored = Self.storedLanguage()
        AppLanguage.current = stored
        language = stored
        positions = Self.readPositions(stored)
        dataset = TFTDataset.empty
        origin = .bundled
        if let saved = UserDefaults.standard.array(forKey: Self.ownedChampionsKey) as? [String] {
            ownedChampions = Set(saved)
        } else {
            ownedChampions = []
        }
        loadBundled(stored)
    }

    /// The device's own language when op.gg serves it, otherwise Vietnamese — the language
    /// the reference itself falls back to, and the one this app was built around.
    private static func storedLanguage() -> AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: languageKey),
           let restored = AppLanguage(rawValue: saved) {
            return restored
        }
        for identifier in Locale.preferredLanguages {
            let lower = identifier.lowercased()
            if lower.hasPrefix("vi") { return .vi }
            if lower.hasPrefix("ko") { return .ko }
            if lower.hasPrefix("ja") { return .ja }
            if lower.hasPrefix("en") { return .en }
            if lower.hasPrefix("zh") { return lower.contains("hant") || lower.contains("-tw") ? .zhTW : .en }
        }
        return .vi
    }

    private func apply(_ language: AppLanguage) {
        AppLanguage.current = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        positions = Self.readPositions(language)
        loadBundled(language)
        // Server-rendered pages and profile lookups are text, not numbers: a page cached in the
        // previous language would keep answering in it.
        BalanceStore.shared.serve(language)
        SummonerStore.shared.serve(language)
        LeaderboardStore.shared.serve(language)
        Task { await refresh() }
    }

    /// Cached copy wins only when it is newer than what shipped in the bundle, per locale.
    private func loadBundled(_ language: AppLanguage) {
        guard let bundled = Self.readBundle(language) else {
            dataset = TFTDataset.empty; origin = .bundled
            return
        }
        if let cached = Self.readCache(language), cached.meta.generatedAt > bundled.meta.generatedAt {
            dataset = cached; origin = .cached
        } else {
            dataset = bundled; origin = .bundled
        }
    }

    private static func readBundle(_ language: AppLanguage) -> TFTDataset? {
        guard let url = Bundle.main.url(forResource: language.resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TFTDataset.self, from: data)
    }

    private static func readPositions(_ language: AppLanguage) -> PositionTable {
        guard let url = Bundle.main.url(forResource: language.resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let packed = try? JSONDecoder().decode(BundledPositions.self, from: data)
        else { return PositionTable(cells: [:]) }
        return PositionTable(cells: packed.positions)
    }

    private static func readCache(_ language: AppLanguage) -> TFTDataset? {
        guard let data = try? Data(contentsOf: cacheURL(language)) else { return nil }
        return try? JSONDecoder().decode(TFTDataset.self, from: data)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        notice = nil
        let language = self.language
        defer { isRefreshing = false }

        // Pinned to the language this pass started with: a switch mid-flight would otherwise
        // mix two locales into one payload.
        let pages = ["comps", "champion", "item", "synergy", "augments"].map {
            "https://op.gg\(language.prefix)/tft/meta-trends/\($0)?version=\(Self.version)"
        }

        var flights: [String] = []
        let session = URLSession(configuration: .ephemeral)
        for page in pages {
            guard let url = URL(string: page) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 30)
            OpGG.headers(&request)
            request.setValue(language.requestLocale, forHTTPHeaderField: "Accept-Language")
            guard let (data, _) = try? await session.data(for: request),
                  let html = String(data: data, encoding: .utf8) else { continue }
            let flight = RSC.flight(from: html)
            if !flight.isEmpty { flights.append(flight) }
        }

        guard language == self.language else { return }

        guard !flights.isEmpty else {
            notice = L("App.notice.offline")
            return
        }

        guard let rebuilt = LiveMapper.dataset(from: flights.joined(separator: "\n"),
                                               version: Self.version, language: language) else {
            notice = L("App.notice.structureChanged")
            return
        }

        dataset = rebuilt
        origin = .live
        notice = L("App.notice.updated", rebuilt.comps.count, rebuilt.champions.count)
        if let encoded = try? JSONEncoder().encode(rebuilt) {
            try? encoded.write(to: Self.cacheURL(language), options: .atomic)
        }
        // Update widget with top comp
        Self.updateWidgetData()
    }

    /// Write the current top comp to shared UserDefaults so the widget can display it.
    private static func updateWidgetData() {
        guard let topComp = shared.dataset.comps.first else { return }
        let score = shared.matchScore(for: topComp)
        let leadKey = topComp.units.first(where: { $0.core })?.k ?? topComp.units.first?.k
        let leadTile = leadKey.flatMap { shared.dataset.ref.champions[$0]?.tile }
        let widgetData = WidgetData(
            name: topComp.name,
            avgRank: String(format: "%.2f", topComp.stats.avg),
            top4Rate: String(format: "%.1f%%", topComp.stats.top4 * 100),
            opScore: String(format: "%.1f", topComp.opScore ?? 0),
            tier: topComp.opTier ?? "—",
            unitCount: topComp.units.count,
            ownedCount: score.owned,
            leadTile: leadTile
        )
        if let encoded = try? JSONEncoder().encode(widgetData) {
            UserDefaults(suiteName: "group.gg.opgg.tft")?.set(encoded, forKey: "widget.topComp")
        }
    }

    struct WidgetData: Codable {
        let name: String
        let avgRank: String
        let top4Rate: String
        let opScore: String
        let tier: String
        let unitCount: Int
        let ownedCount: Int
        let leadTile: String?
    }

    // MARK: - Champion ownership

    func toggleOwnership(_ championKey: String) {
        if ownedChampions.contains(championKey) {
            ownedChampions.remove(championKey)
        } else {
            ownedChampions.insert(championKey)
        }
    }

    func owns(_ championKey: String) -> Bool {
        ownedChampions.contains(championKey)
    }

    /// How many of a comp's units the user owns. Core units count double — they are the
    /// anchor the comp revolves around, so missing one hurts more than a filler slot.
    func matchScore(for comp: Comp) -> (owned: Int, total: Int, coreOwned: Int, coreTotal: Int) {
        let units = comp.units
        var owned = 0
        var coreOwned = 0
        for unit in units {
            if ownedChampions.contains(unit.k) {
                owned += 1
                if unit.core { coreOwned += 1 }
            }
        }
        return (owned, units.count, coreOwned, units.filter(\.core).count)
    }
}
