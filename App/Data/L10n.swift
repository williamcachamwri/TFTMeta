import Foundation

/// The app's own strings, in op.gg's words.
///
/// `i18n.json` is generated (Tools/harvest_i18n.py pulls the reference's message catalogue,
/// Tools/build_i18n.py prunes it to the keys the sources actually name), so a label here is the
/// same widget's label on the site rather than a paraphrase of it — in all five languages.
/// Vietnamese is the fallback for anything the reference does not carry; those live under `App.`.
enum L10n {
    static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "i18n", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return decoded
    }()

    static func text(_ key: String) -> String {
        guard let entry = table[key] else { return key }
        return entry[AppLanguage.current.code] ?? entry["vi"] ?? key
    }
}

/// A localized label. Unresolved keys come back verbatim, which keeps a missing string readable
/// instead of blank.
func L(_ key: String) -> String { L10n.text(key) }

/// The same label in chip/column-head case. op.gg writes some of these as sentence fragments
/// ("theo ngày", because the site reads "xem theo ngày"), and a filter chip is not a sentence.
func LCap(_ key: String) -> String {
    let text = L(key)
    guard let first = text.first, first.isLowercase else { return text }
    return text.prefix(1).uppercased() + String(text.dropFirst())
}

/// Positional arguments, `%1$@`, `%2$@` — positional because the slots move between languages
/// ("X trận trong Y giờ" and "In Y hours, X games" are the same fact in opposite order).
func L(_ key: String, _ args: Any...) -> String {
    var text = L10n.text(key)
    for (index, argument) in args.enumerated() {
        text = text.replacingOccurrences(of: "%\(index + 1)$@", with: String(describing: argument))
    }
    return text
}

/// `{season}`-style tokens, the shape op.gg's own catalogue entries use.
func L(_ key: String, _ tokens: [String: String]) -> String {
    var text = L10n.text(key)
    for (name, value) in tokens {
        text = text.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return text
}

/// Fill a sentence, then cut the value we substituted back out of it — the reference writes the
/// cohort line as one sentence, and the app sets its number in the loudest weight on the page.
func LSplit(_ key: String, _ tokens: [String: String], emphasising value: String)
    -> (head: String, value: String, tail: String) {
    let text = L(key, tokens)
    guard let found = text.range(of: value) else { return (text, "", "") }
    return (String(text[..<found.lowerBound]), value, String(text[found.upperBound...]))
}

/// A count inside one of the reference's ICU plural blocks.
///
/// Tools/build_i18n.py splits those blocks into `key@=5`, `key@one`, `key@other`, so the caller
/// asks for the plural concept and this picks the branch the current language actually has —
/// English is the only one that distinguishes one from more, and `Sample.case_1` overrides single
/// kill counts (2 → "Hạ gục đôi") for every language.
func LPlural(_ key: String, _ count: Int) -> String {
    let candidates = ["\(key)@=\(count)", count == 1 ? "\(key)@one" : nil, "\(key)@other"]
        .compactMap { $0 }
    guard let entry = candidates.first(where: { L10n.table[$0] != nil }) else { return key }
    return L10n.text(entry).replacingOccurrences(of: "#", with: Fmt.integer(count))
}
