import SwiftUI

/// Blocks shared by the summoner screens: the identity card, the league badge, the placement
/// distribution and the aggregate rows. They live here because the search tab and the profile
/// screen both draw them, and the profile screen is the same page op.gg renders from the
/// summoner flight — just taken further.

/// Rows are stacked with hairlines between them, the reference's table look.
struct SectionBlock<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title, detail: detail)
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.surface)
            // Clipping to the rounded rect keeps a row separator from poking past the corners.
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            )
        }
    }
}

struct ProfileCard: View {
    let profile: SummonerProfile
    var showChartButton = false
    var chart: (() -> AnyView)?
    var refresh: (() -> Void)?
    var isBusy = false

    var body: some View {
        VStack(spacing: 0) {
            // Identity strip: icon bleeds into the tier band
            HStack(alignment: .bottom, spacing: 0) {
                RemoteImage(url: profile.icon, contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tierTint.opacity(0.6), lineWidth: 2.5))
                    .shadow(color: tierTint.opacity(0.3), radius: 8, y: 4)
                    .offset(y: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let standing = profile.standing {
                        Text("\(TierLocal.name(standing.tier)) \(TierLocal.division(standing.division))")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tierTint)
                    }
                }
                .padding(.leading, 12)
                .padding(.bottom, 12)

                Spacer(minLength: 8)

                if let standing = profile.standing, let points = standing.points {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.integer(points))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        Text("LP")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Stats ribbon: inline, not boxed
            if let standing = profile.standing, standing.gameCount > 0 {
                HStack(spacing: 0) {
                    statPill(label: L("App.champion.win"), value: Fmt.integer(standing.wins), color: Color(hex: 0x39B57A))
                    Divider().frame(height: 20).overlay(Theme.separator)
                    statPill(label: L("App.summoner.lose"), value: Fmt.integer(standing.losses), color: Color(hex: 0xE85D75))
                    Divider().frame(height: 20).overlay(Theme.separator)
                    statPill(label: "Top 4", value: Fmt.percent(standing.winRate, digits: 0), color: Theme.accentBright)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Theme.surfaceSunken.opacity(0.5))
            }

            // Actions: full-width, edge-to-edge
            if showChartButton || refresh != nil {
                HStack(spacing: 0) {
                    if let refresh {
                        Button(action: refresh) {
                            HStack(spacing: 6) {
                                if isBusy {
                                    ProgressView().controlSize(.small).scaleEffect(0.6).tint(Theme.accent)
                                } else {
                                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                                }
                                Text(isBusy ? L("App.summoner.updating") : L("Summoner.buttonRenew"))
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(Theme.accent)
                        }
                        .disabled(isBusy)
                    }

                    if showChartButton, let chart {
                        if refresh != nil {
                            Divider().frame(height: 24).overlay(Theme.separator)
                        }
                        NavigationLink { chart() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 11, weight: .bold))
                                Text(L("Summoner.buttonTierGraph")).font(.system(size: 12, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .background(Theme.surface)
            }

            // Metadata footer
            HStack {
                Text(L("App.summoner.serverLevel", profile.region.title, profile.level.map { "\($0)" } ?? ""))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if let updated = profile.updatedAt {
                    Text(Self.date(updated))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.surfaceSunken.opacity(0.3))
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
            .strokeBorder(Theme.separator.opacity(0.5), lineWidth: 1))
    }

    private var tierTint: Color { TierLocal.color(profile.standing?.tier) }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private static func date(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let moment = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let display = DateFormatter()
        display.locale = AppLanguage.current.format
        display.dateStyle = .short
        display.timeStyle = .short
        return display.string(from: moment)
    }
}

struct TierBadge: View {
    let standing: LeagueStanding?
    let ladder: Double?
    let caption: String

    private var tint: Color { TierLocal.color(standing?.tier) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Hexagon().fill(tint.opacity(0.18))
                Hexagon().stroke(tint.opacity(0.75), lineWidth: 1.6)
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 46, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(TierLocal.name(standing?.tier)) \(TierLocal.division(standing?.division))")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(tint)
                if let standing, standing.points != nil {
                    Text(L("App.summoner.badgeFormat", caption, Fmt.integer(standing.points)))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: 6)

            if let ladder, ladder > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.percent(ladder, digits: 3))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("App.summoner.ofServer"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(10)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PlacementCard: View {
    let stat: SeasonStat
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L("App.summoner.placementDistribution"), detail: "\(title) · \(Fmt.integer(stat.total)) \(L("HomeSummary.matches").lowercased())")

            HStack(alignment: .center, spacing: 16) {
                PlacementDonut(counts: stat.placement, total: stat.total, center: Fmt.decimal(stat.average, digits: 2))
                VStack(spacing: 8) {
                    StatColumn(title: L("HomeSummary.totalPlayed"), value: Fmt.integer(stat.total))
                    StatColumn(title: L("Summoner.top4Rate"), value: Fmt.percent(stat.top4, digits: 1), color: Color(hex: 0x39B57A))
                    StatColumn(title: L("Summoner.avgPlacement"), value: Fmt.decimal(stat.average, digits: 2))
                }
            }

            VStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { index in
                    let share = stat.total > 0 ? Double(stat.placement[index]) / Double(stat.total) : 0
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 16, alignment: .leading)
                        MeterBar(fraction: share, color: PlacementDonut.color(index: index), height: 6)
                        Text(Fmt.percent(share, digits: 1))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize()
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

/// The donut the reference draws for a set of games: eight placement buckets, average in the hole.
struct PlacementDonut: View {
    let counts: [Int]
    let total: Int
    /// Centre text — season views print average placement, recent form prints the top-4 rate.
    let center: String
    var caption = L("Summoner.avgPlacement")

    private struct Slice {
        let from: Double
        let to: Double
        let color: Color
    }

    /// Sweep 0→1 once on appear: the ring draws itself clockwise instead of snapping whole,
    /// the same gesture the LP chart uses.
    @State private var sweep = 0.0

    var body: some View {
        let slices = values
        return ZStack {
            Circle().stroke(Theme.surfaceRaised, lineWidth: 13)
            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                Circle()
                    .trim(from: slice.from * sweep, to: slice.to * sweep)
                    .stroke(slice.color, style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(center)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 112, height: 112)
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { sweep = 1 } }
    }

    private var values: [Slice] {
        guard total > 0 else { return [] }
        var cursor = 0.0
        var slices: [Slice] = []
        for index in 0..<8 {
            let share = Double(counts.indices.contains(index) ? counts[index] : 0) / Double(total)
            guard share > 0 else { continue }
            slices.append(Slice(from: cursor, to: cursor + share, color: Self.color(index: index)))
            cursor += share
        }
        return slices
    }

    /// Top-4 finishes keep the medal palette, everything below that fades to grey.
    static func color(index: Int) -> Color {
        switch index {
        case 0: return Theme.gold
        case 1: return Theme.silver
        case 2: return Theme.bronze
        case 3: return Color(hex: 0x39B57A)
        default: return Color(hex: 0x59616A)
        }
    }
}

struct AggRow: View {
    let item: SeasonStat.AggStat
    let icon: String?
    let name: String
    let tint: Color
    var separated = false

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: icon, contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.7), lineWidth: 1.4))

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                MeterBar(fraction: item.top4 ?? 0, color: tint, height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(L("App.summoner.gameCount", Fmt.integer(item.total)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L("App.summoner.avgSuffix", Fmt.decimal(item.average, digits: 2)))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if separated { Divider().overlay(Theme.separator.opacity(0.7)) }
        }
    }
}

struct SeasonRow: View {
    let season: LeagueStanding
    var separated = false

    var body: some View {
        HStack(spacing: 10) {
            Text(season.seasonLabel ?? "—")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            Text("\(TierLocal.name(season.tier)) \(TierLocal.division(season.division))")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TierLocal.color(season.tier))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(L("App.summoner.recordFormat", Fmt.integer(season.wins), Fmt.integer(season.losses), Fmt.integer(season.points)))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if separated { Divider().overlay(Theme.separator.opacity(0.7)) }
        }
    }
}

/// op.gg prints the seasons a player has climbed as a strip of dark badges above the name,
/// keeping the English tier words the site itself uses there.
struct SeasonBadgeRow: View {
    let seasons: [LeagueStanding]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(seasons.enumerated()), id: \.offset) { _, season in
                    Text("\(code(season)) \(season.tier?.capitalized ?? "?") \(TierLocal.division(season.division))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.bottom, 2)
        }
        .frame(height: 28)
    }

    private func code(_ season: LeagueStanding) -> String {
        "S" + (season.seasonLabel ?? "").filter(\.isNumber)
    }
}

/// op.gg's own relative wording: "15 giờ trước", "2 ngày trước".
enum When {
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        switch minutes {
        case 0: return L("App.summoner.justNow")
        case 1..<60: return L("App.summoner.minutesAgo", "\(minutes)")
        case 1..<24 * 60: return L("App.summoner.hoursAgo", "\(minutes / 60)")
        case 1..<24 * 60 * 7: return L("App.summoner.daysAgo", "\(minutes / (60 * 24))")
        default:
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.current.format
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    /// The reference spells a game's length out rather than using a clock: "27 phút 38 giây".
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        guard minutes > 0 else { return L("App.summoner.seconds", "\(seconds)") }
        return L("App.summoner.minutesSeconds", "\(minutes)", "\(seconds % 60)")
    }
}
