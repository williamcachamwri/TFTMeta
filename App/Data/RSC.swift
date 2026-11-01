import Foundation

/// Reads op.gg's Next.js App Router payload.
///
/// op.gg ships TFT meta-trends fully server-rendered: there is no separate JSON
/// endpoint, so every value lives inside `self.__next_f.push([1,"…"])` string
/// literals in the document. We unescape those literals, concatenate them into one
/// flight string, then brace-match the object we need.
enum RSC {
    static func flight(from html: String) -> String {
        let marker = "self.__next_f.push([1,\""
        var pieces: [String] = []
        pieces.reserveCapacity(64)
        var cursor = html.startIndex

        while let start = html.range(of: marker, range: cursor..<html.endIndex) {
            var index = start.upperBound
            var escaped = false
            var body = ""
            var closed = false
            while index < html.endIndex {
                let character = html[index]
                if escaped {
                    body.append(character)
                    escaped = false
                } else if character == "\\" {
                    body.append(character)
                    escaped = true
                } else if character == "\"" {
                    closed = true
                    break
                } else {
                    body.append(character)
                }
                index = html.index(after: index)
            }
            guard closed else { break }
            pieces.append(unescape(body))
            cursor = index
        }
        return pieces.joined()
    }

    /// JSON-string decoding of the payload body (`\n`, `\"`, `\uXXXX`, `\/`).
    static func unescape(_ raw: String) -> String {
        guard raw.contains("\\") else { return raw }
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: Data([0x22] + [UInt8](data) + [0x22])) {
            return decoded
        }
        return raw
    }

    /// Returns the balanced `{…}` / `[…]` literal that begins at `searchIndex`.
    static func jsonValue(in text: String, anchor: String) -> Data? {
        jsonObjects(in: text, anchor: anchor).first
    }

    /// Every balanced value that follows an occurrence of `anchor`, skipping hits whose
    /// value is a lazy `"$…:props:…"` reference — op.gg pages carry both forms.
    static func jsonObjects(in text: String, anchor: String) -> [Data] {
        var results: [Data] = []
        var cursor = text.startIndex
        while let found = text.range(of: anchor, range: cursor..<text.endIndex) {
            if let data = value(after: found.upperBound, in: text) { results.append(data) }
            cursor = found.upperBound
        }
        return results
    }

    private static func value(after start: String.Index, in text: String) -> Data? {
        var index = start
        while index < text.endIndex, text[index] == " " || text[index] == ":" || text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "{" || text[index] == "[" else { return nil }
        return slice(text, from: index)
    }

    /// Brace-matches the object that *opens* immediately before `anchor`. op.gg's
    /// balance payload puts `"versions"` first, so there is nothing between `{` and it.
    static func jsonEnclosing(in text: String, anchor: String) -> Data? {
        guard let found = text.range(of: anchor) else { return nil }
        return enclosingObject(in: text, before: found.lowerBound)
    }

    /// Same, for every occurrence — the summoner page repeats `"entry":{"RANKED_TFT"…}`
    /// once per season, so the caller has to pick the right one.
    static func jsonEnclosingAll(in text: String, anchor: String) -> [Data] {
        var results: [Data] = []
        var cursor = text.startIndex
        while let found = text.range(of: anchor, range: cursor..<text.endIndex) {
            if let data = enclosingObject(in: text, before: found.lowerBound) { results.append(data) }
            cursor = found.upperBound
        }
        return results
    }

    private static func enclosingObject(in text: String, before anchor: String.Index) -> Data? {
        guard anchor > text.startIndex else { return nil }
        var index = text.index(before: anchor)
        while index > text.startIndex, text[index].isWhitespace { index = text.index(before: index) }
        guard text[index] == "{" else { return nil }
        return slice(text, from: index)
    }

    private static func slice(_ text: String, from index: String.Index) -> Data? {
        let opening = text[index]
        let closing: Character = opening == "{" ? "}" : "]"

        var depth = 0
        var inString = false
        var escaped = false
        var scan = index
        while scan < text.endIndex {
            let character = text[scan]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return Data(String(text[index...scan]).utf8)
                }
            }
            scan = text.index(after: scan)
        }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, in text: String, anchor: String) -> T? {
        guard let data = jsonValue(in: text, anchor: anchor) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
