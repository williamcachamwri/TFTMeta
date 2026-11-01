import Foundation
import SwiftUI

/// Balance payloads are ~1 MB of server-rendered HTML each, so every
/// (route, version, language) triple is fetched once and kept for the session.
@MainActor
final class BalanceStore: ObservableObject {
    static let shared = BalanceStore()

    @Published var route: BalanceRoute = .champion
    @Published var version = Repository.version
    @Published private(set) var language = AppLanguage.current
    @Published private(set) var versions: [String] = []
    @Published private(set) var snapshots: [String: BalanceSnapshot] = [:]
    @Published private(set) var isLoading = false
    @Published var notice: String?

    private var inFlight: [String: Task<BalanceSnapshot?, Never>] = [:]

    private init() {}

    var current: BalanceSnapshot? { snapshots[key(route, version)] }

    /// Called when the app's language changes. The change notes are prose, not numbers, so the
    /// session's pages are dropped and the new locale simply misses the cache.
    func serve(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        snapshots = [:]
        isLoading = false
    }

    func load() async {
        let target = key(route, version)
        guard snapshots[target] == nil else { return }

        let task = inFlight[target] ?? Task { await Self.fetch(route: route, version: version) }
        inFlight[target] = task
        isLoading = true
        notice = nil

        let result = await task.value
        inFlight[target] = nil
        isLoading = !inFlight.isEmpty

        // The user may have switched tabs while the page was in flight.
        let stillCurrent = key(route, version) == target
        guard let result else {
            if stillCurrent { notice = L("App.error.balanceLoadFailed", route.title, version) }
            return
        }
        snapshots[target] = result
        if !result.versions.isEmpty { versions = result.versions }
    }

    func reload() async {
        snapshots[key(route, version)] = nil
        await load()
    }

    private func key(_ route: BalanceRoute, _ version: String) -> String {
        "\(route.rawValue)|\(version)|\(language.code)"
    }

    private nonisolated static func fetch(route: BalanceRoute, version: String) async -> BalanceSnapshot? {
        let path = OpGG.base + "/tft/buff-and-nerf/\(route.rawValue)?version=\(version)"
        guard let url = URL(string: path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        OpGG.headers(&request)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return BalanceMapper.snapshot(from: RSC.flight(from: html), route: route)
    }
}
