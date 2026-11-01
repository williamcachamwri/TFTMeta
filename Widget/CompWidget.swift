import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct CompEntry: TimelineEntry {
    let date: Date
    let comp: WidgetCompData
}

struct WidgetCompData: Codable {
    let name: String
    let avgRank: String
    let top4Rate: String
    let opScore: String
    let tier: String
    let unitCount: Int
    let ownedCount: Int
}

// MARK: - Provider

struct CompProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompEntry {
        CompEntry(date: Date(), comp: WidgetCompData(
            name: "Loading...",
            avgRank: "—",
            top4Rate: "—",
            opScore: "—",
            tier: "—",
            unitCount: 0,
            ownedCount: 0
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (CompEntry) -> Void) {
        let entry = CompEntry(date: Date(), comp: Self.loadTopComp())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompEntry>) -> Void) {
        let entry = CompEntry(date: Date(), comp: Self.loadTopComp())
        // Refresh every hour
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static func loadTopComp() -> WidgetCompData {
        // Load from shared defaults (app writes top comp here)
        guard let data = UserDefaults(suiteName: "group.gg.opgg.tft")?.data(forKey: "widget.topComp"),
              let comp = try? JSONDecoder().decode(WidgetCompData.self, from: data) else {
            return WidgetCompData(
                name: "No data yet",
                avgRank: "—",
                top4Rate: "—",
                opScore: "—",
                tier: "—",
                unitCount: 0,
                ownedCount: 0
            )
        }
        return comp
    }
}

// MARK: - Widget Views

struct CompWidgetEntryView: View {
    var entry: CompEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(comp: entry.comp)
        case .systemMedium:
            MediumWidgetView(comp: entry.comp)
        case .systemLarge:
            LargeWidgetView(comp: entry.comp)
        default:
            SmallWidgetView(comp: entry.comp)
        }
    }
}

// MARK: - Small Widget (2x2)

struct SmallWidgetView: View {
    let comp: WidgetCompData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TOP 1")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(ThemeWidget.gold)
                Spacer(minLength: 4)
                TierBadge(tier: comp.tier)
            }

            Text(comp.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ThemeWidget.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                StatBlock(label: "AVG", value: comp.avgRank)
                StatBlock(label: "TOP4", value: comp.top4Rate)
            }
        }
        .padding(12)
        .background(ThemeWidget.background)
    }
}

// MARK: - Medium Widget (4x2)

struct MediumWidgetView: View {
    let comp: WidgetCompData

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ĐỘI HÌNH TOP 1")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(ThemeWidget.gold)
                    Spacer(minLength: 4)
                    TierBadge(tier: comp.tier)
                }

                Text(comp.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ThemeWidget.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    StatBlock(label: "AVG", value: comp.avgRank)
                    StatBlock(label: "TOP4", value: comp.top4Rate)
                    StatBlock(label: "OP", value: comp.opScore)
                }
            }

            Spacer(minLength: 0)

            if comp.ownedCount > 0 {
                VStack(spacing: 4) {
                    Text("\(comp.ownedCount)/\(comp.unitCount)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(ThemeWidget.accent)
                    Text("tướng")
                        .font(.system(size: 9))
                        .foregroundStyle(ThemeWidget.textTertiary)
                }
            }
        }
        .padding(14)
        .background(ThemeWidget.background)
    }
}

// MARK: - Large Widget (4x4)

struct LargeWidgetView: View {
    let comp: WidgetCompData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ĐỘI HÌNH MẠNH NHẤT")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ThemeWidget.gold)
                Spacer()
                TierBadge(tier: comp.tier)
            }

            Text(comp.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ThemeWidget.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(ThemeWidget.separator)

            HStack(spacing: 12) {
                StatBlock(label: "AVG RANK", value: comp.avgRank, large: true)
                StatBlock(label: "TOP 4 RATE", value: comp.top4Rate, large: true)
                StatBlock(label: "OP SCORE", value: comp.opScore, large: true)
            }

            Spacer(minLength: 0)

            if comp.ownedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ThemeWidget.accent)
                    Text("\(comp.ownedCount)/\(comp.unitCount) tướng bạn có")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ThemeWidget.textSecondary)
                }
            }
        }
        .padding(16)
        .background(ThemeWidget.background)
    }
}

// MARK: - Shared Components

struct StatBlock: View {
    let label: String
    let value: String
    var large: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: large ? 9 : 8, weight: .semibold))
                .foregroundStyle(ThemeWidget.textTertiary)
            Text(value)
                .font(.system(size: large ? 16 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(ThemeWidget.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct TierBadge: View {
    let tier: String

    var body: some View {
        Text(tier)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ThemeWidget.opTier(tier))
            )
    }
}

// MARK: - Theme

enum ThemeWidget {
    static let background = Color(hex: 0x1A1D24)
    static let textPrimary = Color(hex: 0xF0F0F0)
    static let textSecondary = Color(hex: 0xA0A0A0)
    static let textTertiary = Color(hex: 0x707070)
    static let separator = Color(hex: 0x2A2D35)
    static let accent = Color(hex: 0x5B8DEF)
    static let gold = Color(hex: 0xC9A84C)

    static func opTier(_ tier: String) -> Color {
        switch tier {
        case "OP": return Color(hex: 0xE85D75)
        case "S": return Color(hex: 0xC9A84C)
        case "A": return Color(hex: 0x39B57A)
        case "B": return Color(hex: 0x5B8DEF)
        default: return Color(hex: 0x707070)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Widget

@main
struct CompWidget: Widget {
    let kind: String = "CompWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompProvider()) { entry in
            CompWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Đội hình OP")
        .description("Hiển thị đội hình mạnh nhất theo meta hiện tại")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
