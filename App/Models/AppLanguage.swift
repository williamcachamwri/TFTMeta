import Foundation

/// The five locales op.gg really renders TFT pages for.
///
/// One value drives everything the app would otherwise hardcode: the path prefix in front of
/// every page, the `locale` argument its server actions expect, the key its deck payloads use
/// for a translated name, the number/date format, and the `.lproj` folder the String Catalog is
/// compiled into. English is the site's root, so it is the one case with no prefix.
enum AppLanguage: String, CaseIterable, Identifiable {
    case vi
    case en
    case ko
    case ja
    case zhTW

    var id: String { rawValue }

    /// op.gg's code as it appears in a URL.
    var code: String {
        switch self {
        case .zhTW: return "zh-tw"
        default: return rawValue
        }
    }

    /// Leading path segment, empty for English.
    var prefix: String { self == .en ? "" : "/\(code)" }

    /// Mark for the header chip — the menu itself spells each language out.
    var chip: String { self == .zhTW ? "zh" : rawValue }

    /// The `locale` the server actions take, and the `Accept-Language` header they answer with.
    var requestLocale: String {
        switch self {
        case .zhTW: return "zh-tw"
        default: return rawValue
        }
    }

    /// Key of the multi-locale name object op.gg ships with each deck.
    var flightKey: String {
        switch self {
        case .vi: return "vi_VN"
        case .en: return "en_US"
        case .ko: return "ko_KR"
        case .ja: return "ja_JP"
        case .zhTW: return "zh_TW"
        }
    }

    /// Bundled dataset resource name — one file per language so the app is translated offline.
    var resource: String { "tft-set18-\(code)" }

    /// Folder Xcode compiles the String Catalog into.
    var lproj: String {
        switch self {
        case .zhTW: return "zh-Hant"
        default: return rawValue
        }
    }

    /// Number and date grouping (`3.074.584` in Vietnamese, `3,074,584` in English).
    var format: Locale {
        switch self {
        case .vi: return Locale(identifier: "vi_VN")
        case .en: return Locale(identifier: "en_US")
        case .ko: return Locale(identifier: "ko_KR")
        case .ja: return Locale(identifier: "ja_JP")
        case .zhTW: return Locale(identifier: "zh_TW")
        }
    }

    /// Endonym, the way op.gg's own language menu lists them.
    var title: String {
        switch self {
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .zhTW: return "繁體中文"
        }
    }
}

extension AppLanguage {
    /// The language the app is serving right now. Set at launch from the store and again on every
    /// switch; the data mappers read it the way Foundation reads `Locale.current`.
    static var current: AppLanguage = .vi
}
