import Foundation

/// Rebuilds the bundled `tft-set18-<locale>.json` files from op.gg's server-rendered pages.
///
/// The app has no JSON API to pull from, so this tool does what `Repository.refresh()` does on
/// device — GET the five meta-trends pages, join their RSC flights, hand them to `LiveMapper` —
/// but for each locale at once, so every language ships real translated data instead of being
/// machine-glossed at runtime. Run it after op.gg rotates a set or the datasets drift.
///
/// Compiled ad hoc, never part of the app target:
///   xcrun -sdk macosx swiftc -o /tmp/extract Tools/ExtractLocale.swift \
///     App/Data/LiveMapper.swift App/Data/RSC.swift \
///     App/Models/TFTData.swift App/Models/JSONValue.swift \
///     App/Models/TFTDataset+Accessors.swift App/Models/AppLanguage.swift
@main
enum ExtractLocale {
    static let version = "18.5"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let pages = ["comps", "champion", "item", "synergy", "augments"]

    /// Positions are Riot-side odds, identical in every language, and re-deriving them costs one
    /// extra server action per champion, so they are copied out of the Vietnamese dataset.
    static let positionsSource = "App/Resources/tft-set18-vi.json"
    static let outDirectory = "App/Resources"

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let wanted = arguments.isEmpty ? AppLanguage.allCases : AppLanguage.allCases.filter {
            arguments.contains($0.code)
        }
        guard let positions = loadPositions() else {
            print("no positions block in \(positionsSource)")
            exit(1)
        }
        let session = URLSession(configuration: .ephemeral)

        for language in wanted {
            var flights: [String] = []
            for page in pages {
                let path = "https://op.gg\(language.prefix)/tft/meta-trends/\(page)?version=\(version)"
                guard let body = await get(session, path, language: language) else {
                    print("\(language.code): FAILED \(page)")
                    continue
                }
                let flight = RSC.flight(from: body)
                print("\(language.code): \(page) flight \(flight.count) bytes")
                if !flight.isEmpty { flights.append(flight) }
            }

            guard let dataset = LiveMapper.dataset(from: flights.joined(separator: "\n"),
                                                   version: version, language: language) else {
                print("\(language.code): no dataset built")
                continue
            }
            guard let data = encode(dataset, positions: positions) else {
                print("\(language.code): encode failed")
                continue
            }
            let url = URL(fileURLWithPath: "\(outDirectory)/\(language.resource).json")
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                print("\(language.code): write failed \(error)")
                continue
            }
            report(language, dataset)
        }
    }

    static func get(_ session: URLSession, _ path: String, language: AppLanguage) async -> String? {
        guard let url = URL(string: path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(language.requestLocale, forHTTPHeaderField: "Accept-Language")
        for attempt in 1...3 {
            if let (data, _) = try? await session.data(for: request),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000 * UInt64(attempt))
        }
        return nil
    }

    static func loadPositions() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: positionsSource)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let positions = root["positions"] as? [String: Any] else { return nil }
        return positions
    }

    static func encode(_ dataset: TFTDataset, positions: [String: Any]) -> Data? {
        guard let root = try? JSONEncoder().encode(dataset),
              var object = try? JSONSerialization.jsonObject(with: root) as? [String: Any] else { return nil }
        object["positions"] = positions
        // Foundation escapes forward slashes and non-ASCII as \uXXXX unless told not to; the
        // existing datasets are plain UTF-8 and CJK names would otherwise triple in size.
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if #available(macOS 10.15, *) { options.insert(.withoutEscapingSlashes) }
        return try? JSONSerialization.data(withJSONObject: object, options: options)
    }

    static func report(_ language: AppLanguage, _ dataset: TFTDataset) {
        print("\(language.code): comps \(dataset.comps.count), champions \(dataset.champions.count), "
            + "items \(dataset.items.count), traits \(dataset.traits.count), augments \(dataset.augments.count), "
            + "games \(dataset.meta.totalGames ?? -1)")
        print("   comp: \(dataset.comps.first?.name ?? "—")")
        print("   unit: \(dataset.ref.champions.first?.value.n ?? "—") / "
            + "\(dataset.ref.items.first?.value.n ?? "—") / "
            + "\(dataset.ref.traits.first?.value.n ?? "—")")
        print("   ability: \((dataset.ref.champions.first?.value.ability ?? "—").prefix(90))")
    }
}
