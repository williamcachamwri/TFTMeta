//
//  CompWidget.swift
//  CompWidget
//
//  Created by William Cachamwri on 31/10/26.
//

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
    let leadTile: String?
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
            ownedCount: 0,
            leadTile: nil
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (CompEntry) -> Void) {
        let entry = CompEntry(date: Date(), comp: Self.loadTopComp())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompEntry>) -> Void) {
        let entry = CompEntry(date: Date(), comp: Self.loadTopComp())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static func loadTopComp() -> WidgetCompData {
        guard let data = UserDefaults(suiteName: "group.gg.opgg.tft")?.data(forKey: "widget.topComp"),
              let comp = try? JSONDecoder().decode(WidgetCompData.self, from: data) else {
            return WidgetCompData(
                name: "Open app to load",
                avgRank: "—",
                top4Rate: "—",
                opScore: "—",
                tier: "—",
                unitCount: 0,
                ownedCount: 0,
                leadTile: nil
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
        ZStack {
            // Card background - matches app style
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x2A2D3E),
                            Color(hex: 0x1E2030)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Content
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
        .padding(0)
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Small Widget (2x2)

struct SmallWidgetView: View {
    let comp: WidgetCompData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with rank and tier
            HStack {
                Text("#1")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(ThemeWidget.gold)

                Spacer(minLength: 0)

                TierBadge(tier: comp.tier)
            }

            // Champion avatar + name
            HStack(spacing: 8) {
                if let tile = comp.leadTile, let url = URL(string: tile) {
                    RemoteImage(url: url.absoluteString)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(ThemeWidget.accent.opacity(0.5), lineWidth: 1.5)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(comp.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ThemeWidget.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            // Stats
            HStack(spacing: 6) {
                StatBlock(label: "AVG", value: comp.avgRank)
                StatBlock(label: "TOP4", value: comp.top4Rate)
            }
        }
        .padding(10)
    }
}

// MARK: - Medium Widget (4x2)

struct MediumWidgetView: View {
    let comp: WidgetCompData

    var body: some View {
        HStack(spacing: 10) {
            // Champion avatar
            if let tile = comp.leadTile, let url = URL(string: tile) {
                RemoteImage(url: url.absoluteString)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ThemeWidget.accent.opacity(0.5), lineWidth: 2)
                    )
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#1")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(ThemeWidget.gold)

                    Spacer(minLength: 0)

                    TierBadge(tier: comp.tier)
                }

                Text(comp.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ThemeWidget.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    StatBlock(label: "AVG", value: comp.avgRank)
                    StatBlock(label: "TOP4", value: comp.top4Rate)
                    StatBlock(label: "OP", value: comp.opScore)
                }
            }
        }
        .padding(10)
    }
}

// MARK: - Large Widget (4x4)

struct LargeWidgetView: View {
    let comp: WidgetCompData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("#1")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(ThemeWidget.gold)

                Spacer(minLength: 0)

                TierBadge(tier: comp.tier)
            }

            // Champion avatar + name
            HStack(spacing: 12) {
                if let tile = comp.leadTile, let url = URL(string: tile) {
                    RemoteImage(url: url.absoluteString)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ThemeWidget.accent.opacity(0.5), lineWidth: 2)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(comp.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ThemeWidget.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(comp.unitCount) units")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ThemeWidget.textTertiary)
                }
            }

            // Stats row
            HStack(spacing: 8) {
                StatCard(label: "AVG", value: comp.avgRank, icon: "chart.bar.fill", color: ThemeWidget.accent)
                StatCard(label: "TOP4", value: comp.top4Rate, icon: "trophy.fill", color: ThemeWidget.gold)
                StatCard(label: "OP", value: comp.opScore, icon: "flame.fill", color: Color(hex: 0xE85D75))
            }

            Spacer(minLength: 0)

            // Footer
            HStack {
                if comp.ownedCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeWidget.accent)
                            .frame(width: 5, height: 5)

                        Text("\(comp.ownedCount)/\(comp.unitCount) owned")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(ThemeWidget.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Text("op.gg/tft")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(ThemeWidget.textTertiary)
            }
        }
        .padding(12)
    }
}

// MARK: - Remote Image for Widget

struct RemoteImage: View {
    let url: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ThemeWidget.surfaceRaised)

            if let url = url, let imageURL = URL(string: url) {
                ImageLoader(url: imageURL)
            }
        }
    }
}

struct ImageLoader: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(ThemeWidget.surfaceRaised)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
        Task {
            let result = try? await URLSession.shared.data(for: request)
            if let data = result?.0, let loaded = UIImage(data: data) {
                await MainActor.run { self.image = loaded }
            }
        }
    }
}

// MARK: - Shared Components

struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(ThemeWidget.textTertiary)

            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(ThemeWidget.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(ThemeWidget.textTertiary)
            }

            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct TierBadge: View {
    let tier: String

    var body: some View {
        Text(tier)
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ThemeWidget.opTier(tier))
            )
    }
}

// MARK: - Theme

enum ThemeWidget {
    static let textPrimary = Color(hex: 0xF0F0F0)
    static let textSecondary = Color(hex: 0xA0A0A0)
    static let textTertiary = Color(hex: 0x707070)
    static let accent = Color(hex: 0x5B8DEF)
    static let gold = Color(hex: 0xC9A84C)
    static let surfaceRaised = Color(hex: 0x2A2D3E)

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

struct CompWidget: Widget {
    let kind: String = "CompWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompProvider()) { entry in
            CompWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OP Comp")
        .description("Top team comp from current meta")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    CompWidget()
} timeline: {
    CompEntry(date: .now, comp: WidgetCompData(
        name: "Forest Bruiser",
        avgRank: "2.50",
        top4Rate: "87.9%",
        opScore: "3.9",
        tier: "OP",
        unitCount: 8,
        ownedCount: 5,
        leadTile: "https://c-tft-web.op.gg/assets/images/champion/tile/TFT18_Brambleback.png"
    ))
}
