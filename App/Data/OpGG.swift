import Foundation

/// op.gg's Next.js server actions — the only API its TFT pages have.
///
/// An action is called by POSTing its argument object to the page that declares it, with the
/// action's build-hash id in the `next-action` header. The reply is a whole flight render, and
/// the return value is the JSON on the line that opens with `1:`. Nothing here needs cookies or
/// a session; the ids are what change, and only when op.gg redeploys.
enum OpGG {
    case autoSuggest
    case summonerMatches
    case matchDetail
    case lpHistory

    /// Read from `page-*.js` in the shipped bundle; see the note above about rotation.
    private var id: String {
        switch self {
        case .autoSuggest: return "40a3a833012ffee21bfb8b03a580a32106d44bc246"
        case .summonerMatches: return "40343ae676ae8bb9f6856a15496f769f07ecaf6f6c"
        case .matchDetail: return "4010ad245bb3c4967363e93385c3803ea2dbaaa10d"
        case .lpHistory: return "40f590b0eac3cec3582718c7563a882efcebb2080d"
        }
    }

    /// Every page and action rides the app's current language: English is op.gg's root, the rest
    /// hang behind their own path prefix.
    static var base: String { "https://op.gg" + AppLanguage.current.prefix }

    /// The `locale` argument each action expects.
    static var locale: String { AppLanguage.current.requestLocale }

    /// Headers a browser-like client has to send for the server to render the flight at all.
    static func headers(_ request: inout URLRequest, action: String? = nil) {
        request.setValue(Repository.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(AppLanguage.current.requestLocale, forHTTPHeaderField: "Accept-Language")
        if let action { request.setValue(action, forHTTPHeaderField: "next-action") }
    }

    /// `/tft` answers the header search; the summoner routes answer everything about a player.
    static func page(region: String, slug: String?, tab: String? = nil) -> String {
        guard let slug else { return "/tft" }
        let path = "/tft/summoners/\(region)/\(slug)"
        return tab.map { "\(path)/\($0)" } ?? path
    }

    static func slug(name: String, tag: String) -> String {
        let raw = "\(name)-\(tag)"
        return raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
    }

    func call(_ arg: [String: Any], page: String) async throws -> JSONValue {
        guard let url = URL(string: Self.base + page) else { throw SummonerFailure.notFound }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/x-component", forHTTPHeaderField: "Accept")
        Self.headers(&request, action: id)
        request.httpBody = try JSONSerialization.data(withJSONObject: [arg])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let value = Self.reply(String(decoding: data, as: UTF8.self)) else {
            throw SummonerFailure.offline
        }
        return value
    }

    /// The value is the JSON on the `1:` line; an action that threw answers `1:E{"digest":…}`,
    /// which is not JSON, so it decodes to nothing.
    private static func reply(_ flight: String) -> JSONValue? {
        for line in flight.split(whereSeparator: \.isNewline) where line.hasPrefix("1:") {
            guard let body = line.dropFirst(2).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: body)
        }
        return nil
    }

    /// React tags a `Date` argument as a `$D`-prefixed ISO string before it is put in the JSON
    /// body — a plain ISO string reaches the server as a string and the action then throws.
    static func tagged(_ moment: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "$D" + formatter.string(from: moment)
    }
}
