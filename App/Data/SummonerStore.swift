import Foundation
import SwiftUI

enum SummonerFailure: Error {
    case offline
    case notFound
    case badTag

    var displayText: String {
        switch self {
        case .offline: return L("App.error.summonerOffline")
        case .notFound: return L("App.error.summonerNotFound")
        case .badTag: return L("App.error.summonerBadTag")
        }
    }
}

@MainActor
final class SummonerStore: ObservableObject {
    static let shared = SummonerStore()

    @Published var region: SummonerRegion = .vn
    @Published var text = ""
    @Published private(set) var language = AppLanguage.current
    @Published private(set) var profile: SummonerProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var failure: SummonerFailure?
    @Published private(set) var suggestions: [SummonerSuggestion] = []
    @Published var queueID: String?
    @Published var costFilter = 0

    /// Same lookup twice should not cost another megabyte of HTML.
    private var cache: [String: SummonerProfile] = [:]
    private var running: Task<Void, Never>?

    private init() {}

    var queue: SummonerQueue? {
        guard let profile else { return nil }
        return profile.queues.first(where: { $0.id == queueID }) ?? profile.primary
    }

    var slug: String { "\(profile?.name ?? "")#\(profile?.tag ?? "")" }

    /// Tier, queue and match labels come from the page rather than from ids, so a language
    /// switch empties the page cache and re-reads whoever is on screen.
    func serve(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        cache = [:]
        running?.cancel()
        guard let profile else { return }
        load(name: profile.name, tag: profile.tag, keepProfileOnFailure: true)
    }

    /// Type-to-search, the way the site's header box answers: one action call per pause, not
    /// per keystroke. The view drives the pause with `.task(id:)`, which cancels this on the
    /// next character — so a fast typist never queues a stack of stale requests.
    func suggest() async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            suggestions = []
            return
        }
        let wanted = region
        do {
            let value = try await OpGG.autoSuggest.call(
                ["region": wanted.rawValue, "value": query, "locale": OpGG.locale],
                page: OpGG.page(region: wanted.rawValue, slug: nil)
            )
            guard !Task.isCancelled, wanted == region else { return }
            suggestions = value["summoners"]?.arrayValue.compactMap { row -> SummonerSuggestion? in
                guard let name = row["gameName"]?.stringValue, let tag = row["tagLine"]?.stringValue else { return nil }
                return SummonerSuggestion(name: name,
                                          tag: tag,
                                          region: wanted,
                                          icon: row["thumbnail"]?.stringValue,
                                          ranked: row["ranked"]?.stringValue)
            } ?? []
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
        }
    }

    func open(_ suggestion: SummonerSuggestion) {
        text = "\(suggestion.name)#\(suggestion.tag)"
        region = suggestion.region
        suggestions = []
        search()
    }

    /// The reference's "Cập nhật" button: drop the cached page and read the summoner again.
    func refresh() {
        guard let profile else { return }
        cache["\(profile.region.rawValue)|\(profile.name.lowercased())-\(profile.tag)"] = nil
        load(name: profile.name, tag: profile.tag, keepProfileOnFailure: true)
    }

    func search() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let tag = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        guard !name.isEmpty, !tag.isEmpty else {
            profile = nil
            failure = .badTag
            return
        }
        load(name: name, tag: tag)
    }

    /// A failed refresh should not erase the page already on screen — the profile view keys its
    /// navigation off this value, so nilling it would bounce the user back to the search form.
    func load(name: String, tag: String, keepProfileOnFailure: Bool = false) {
        let wanted = region
        let set = Repository.shared.dataset.meta.set
        let key = "\(wanted.rawValue)|\(name.lowercased())-\(tag)"

        running?.cancel()
        failure = nil
        if let hit = cache[key] {
            profile = hit
            queueID = hit.primary?.id
            isLoading = false
            return
        }

        isLoading = true
        running = Task { [weak self] in
            let outcome = await SummonerStore.load(name: name, tag: tag, region: wanted, set: set)
            guard let self, !Task.isCancelled else { return }
            self.isLoading = false
            switch outcome {
            case .success(let found):
                self.cache[key] = found
                self.profile = found
                self.queueID = found.primary?.id
                self.suggestions = []
            case .failure(let error):
                if !keepProfileOnFailure { self.profile = nil }
                self.failure = error
            }
        }
    }

    private nonisolated static func load(name: String, tag: String, region: SummonerRegion, set: Int) async -> Result<SummonerProfile, SummonerFailure> {
        let slug = OpGG.slug(name: name, tag: tag)
        guard let url = URL(string: OpGG.base + OpGG.page(region: region.rawValue, slug: slug)) else {
            return .failure(.notFound)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        OpGG.headers(&request)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return .failure(.offline) }

        // op.gg answers an unknown summoner with the search shell, not a payload.
        guard (response as? HTTPURLResponse)?.statusCode == 200, html.contains("summonerInfo") else {
            return .failure(.notFound)
        }
        guard let profile = SummonerMapper.profile(from: html, region: region, set: set) else {
            return .failure(.notFound)
        }
        return .success(profile)
    }
}
