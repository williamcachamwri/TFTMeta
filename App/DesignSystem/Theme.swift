import SwiftUI

/// Palette sampled directly from the OP.GG mobile reference (page #1F2225, surface #262A2D).
enum Theme {
    static let background = Color(hex: 0x1F2225)
    static let surface = Color(hex: 0x262A2D)
    static let surfaceRaised = Color(hex: 0x2E3237)
    static let surfaceSunken = Color(hex: 0x191B1D)
    static let separator = Color(hex: 0x363C42)

    static let textPrimary = Color(hex: 0xF3F5F7)
    static let textSecondary = Color(hex: 0x9BA3AB)
    static let textTertiary = Color(hex: 0x6C757D)

    static let accent = Color(hex: 0x5B8DEF)
    static let accentBright = Color(hex: 0x63A8ED)
    static let gold = Color(hex: 0xE3B341)
    static let silver = Color(hex: 0xB9C2CB)
    static let bronze = Color(hex: 0xC07E43)

    static let radiusCard: CGFloat = 14
    static let radiusChip: CGFloat = 9
    static let gutter: CGFloat = 16

    static func rarity(_ cost: Int?) -> Color {
        switch cost ?? 0 {
        case 0: return Color(hex: 0x74808F)
        case 1: return Color(hex: 0x8FA0B5)
        case 2: return Color(hex: 0x2FA46B)
        case 3: return Color(hex: 0x3E82E0)
        case 4: return Color(hex: 0x9D55E8)
        case 5: return Color(hex: 0xE0A32E)
        default: return Color(hex: 0xE8547A)
        }
    }

    /// op.gg encodes trait activation tiers as integers (0 inactive … 4+ gold).
    static func traitStyle(_ style: Int?) -> (color: Color, text: Color) {
        switch style ?? 0 {
        case 0: return (Color(hex: 0x3A4046), textTertiary)
        case 1: return (Color(hex: 0x8A94A0), Color(hex: 0xE7EBEF))
        case 2: return (Color(hex: 0x4FA3E3), .white)
        case 3: return (Color(hex: 0x39B57A), .white)
        case 4: return (Color(hex: 0xE0A32E), Color(hex: 0x241B03))
        default: return (Color(hex: 0xE85D75), .white)
        }
    }

    static func opTier(_ tier: String?) -> Color {
        switch tier?.uppercased() {
        case "OP": return Color(hex: 0xF0576B)
        case "S": return Color(hex: 0xE0A32E)
        case "A": return Color(hex: 0x39B57A)
        case "B": return Color(hex: 0x4FA3E3)
        case "C": return Color(hex: 0x8A94A0)
        default: return textTertiary
        }
    }

    static func augmentTier(_ tier: String?) -> (label: String, color: Color) {
        switch tier?.lowercased() {
        case "prism", "prismatic": return (L("MetaTrendsAugments.prism"), Color(hex: 0x9D55E8))
        case "gold": return (L("MetaTrendsAugments.gold"), Color(hex: 0xE0A32E))
        case "silver": return (L("MetaTrendsAugments.silver"), Color(hex: 0xB9C2CB))
        case "bronze": return (L("GameGuide.rewardItem.bronze"), Color(hex: 0xC07E43))
        default: return ((tier ?? "").capitalized, textSecondary)
        }
    }

    static func itemCategory(_ category: String?) -> (label: String, color: Color) {
        switch category?.lowercased() {
        case "component": return (L("MetaTrendsItem.component"), Color(hex: 0x6C8FA8))
        case "core": return (L("MetaTrendsItem.core"), Color(hex: 0x4FA3E3))
        case "radiant": return (L("MetaTrendsItem.radiant"), Color(hex: 0xE8863C))
        case "artifact": return (L("MetaTrendsItem.artifact"), Color(hex: 0x9D55E8))
        case "emblem", "augmented", "conqueror", "radiant-emblem": return (L("MetaTrendsItem.emblem"), Color(hex: 0x39B57A))
        case "consumable": return (L("App.itemCategory.consumable"), Color(hex: 0xC07E43))
        default: return ((category ?? "").capitalized, textSecondary)
        }
    }

    static func difficulty(_ value: Int?) -> String {
        switch value {
        case 1: return L("Badge.easy")
        case 2: return L("Badge.normal")
        case 3: return L("Badge.hard")
        default: return L("Sample.case_2@other")
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Fmt {
    /// Grouping follows the language on screen — "3.418 LP" in Vietnamese, "3,418 LP" in English.
    private static var locale: Locale { AppLanguage.current.format }

    static func integer(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.locale(locale))
    }

    static func decimal(_ value: Double?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    static func percent(_ value: Double?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        return (value * 100).formatted(.number.precision(.fractionLength(digits)).locale(locale)) + "%"
    }
}
