import SwiftUI

/// LP over time, the way the reference draws it: one point per day/week/season, the league
/// abbreviation and LP above the dot, the date and game count under it.
struct RankChartView: View {
    @EnvironmentObject private var repository: Repository
    let profile: SummonerProfile
    @ObservedObject var history: SummonerHistoryStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                chartCard
                if !profile.previousSeasons.isEmpty {
                    SectionBlock(title: L("Summoner.moreSeasonTier")) {
                        ForEach(Array(profile.previousSeasons.enumerated()), id: \.offset) { index, season in
                            SeasonRow(season: season, separated: index > 0)
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
            .padding(.top, 6)
        }
        .background(Theme.background)
        .pageReveal()
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .onAppear { history.start(profile) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !profile.previousSeasons.isEmpty {
                SeasonBadgeRow(seasons: profile.previousSeasons)
            }
            ProfileCard(profile: profile)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(L("SummonerLpHistory.tierGraph"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 6)
                PeriodTabs(selection: $history.period)
            }

            if history.points.isEmpty {
                EmptyChart(loading: history.isChartLoading)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                // Identity per granularity: a fresh view re-draws the line instead of sliding
                // one season's points into another's places.
                LPChart(points: history.points)
                    .id(history.period)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
        )
        .padding(.horizontal, Theme.gutter)
    }
}

/// The three granularities `getLpHistory` answers with — the reference's own pill row.
private struct PeriodTabs: View {
    @Binding var selection: LpPeriod
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LpPeriod.allCases) { period in
                Button {
                    selection = period
                } label: {
                    Text(period.title)
                        .font(.system(size: 11, weight: selection == period ? .bold : .semibold))
                        .foregroundStyle(selection == period ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background {
                            if selection == period {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                                    .matchedGeometryEffect(id: "period", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .animation(.snappy(duration: 0.24), value: selection)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EmptyChart: View {
    let loading: Bool

    var body: some View {
        VStack(spacing: 8) {
            if loading {
                ProgressView().tint(Theme.accent)
                Text(L("App.loading.lpHistory"))
            } else {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text(L("App.empty.lpHistory"))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textTertiary)
    }
}

/// Line + dots + the labels the reference hangs on every point.
struct LPChart: View {
    let points: [LpPoint]

    @State private var drawn: CGFloat = 0

    private let edge: CGFloat = 30
    private let topLabels: CGFloat = 42
    private let plot: CGFloat = 150
    private let axis: CGFloat = 40
    private var height: CGFloat { topLabels + plot + axis }

    var body: some View {
        GeometryReader { geo in
            let slot = max(72, (geo.size.width - edge * 2) / CGFloat(max(points.count - 1, 1)))
            let width = edge * 2 + slot * CGFloat(max(points.count - 1, 1))
            ScrollView(.horizontal, showsIndicators: false) {
                content(slot: slot, width: width)
                    .frame(width: width, height: height)
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
        .onAppear { animate() }
        .onChange(of: points.count) { _, _ in animate() }
    }

    private func animate() {
        drawn = 0
        withAnimation(.easeOut(duration: 0.75)) { drawn = 1 }
    }

    private func content(slot: CGFloat, width: CGFloat) -> some View {
        let values = points.map { Double(Elo.point($0)) }
        let low = (values.min() ?? 0) - 40
        let high = (values.max() ?? 100) + 40
        let span = max(high - low, 1)

        func y(_ value: Double) -> CGFloat {
            topLabels + plot - CGFloat((value - low) / span) * plot
        }
        func x(_ index: Int) -> CGFloat { edge + CGFloat(index) * slot }

        var line = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: x(index), y: y(value))
            if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        var area = line
        if let last = values.indices.last {
            area.addLine(to: CGPoint(x: x(last), y: topLabels + plot))
            area.addLine(to: CGPoint(x: x(0), y: topLabels + plot))
            area.closeSubpath()
        }

        return ZStack {
            ForEach(0..<4, id: \.self) { step in
                let fraction = CGFloat(step) / 3
                Rectangle()
                    .fill(Theme.separator.opacity(0.35))
                    .frame(height: 1)
                    .position(x: width / 2, y: topLabels + plot * (1 - fraction))
            }

            area.fill(
                LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            .opacity(Double(drawn))

            line
                .trim(from: 0, to: drawn)
                .stroke(Theme.accentBright, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let value = Double(Elo.point(point))
                Dot(tier: point.tier)
                    .position(x: x(index), y: y(value))
                    .opacity(drawn > CGFloat(index) / CGFloat(max(points.count, 1)) ? 1 : 0)

                VStack(spacing: 1) {
                    Text(Elo.short(point.tier) + " " + TierLocal.division(point.rank))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("App.summoner.lpFormat", "\(point.points)"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .fixedSize()
                .position(x: x(index), y: y(value) - 26)

                VStack(spacing: 1) {
                    Text(Self.day(point.date))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    if point.games > 0 {
                        Text(LPlural("SummonerLpHistory.games", point.games))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .fixedSize()
                .position(x: x(index), y: topLabels + plot + 18)
            }
        }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "m.dd"
        return formatter.string(from: date)
    }
}

private struct Dot: View {
    let tier: String

    var body: some View {
        Circle()
            .fill(Theme.surface)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(TierLocal.color(tier), lineWidth: 2.4))
    }
}

/// op.gg's own ladder scale: every division is 100 LP wide and a tier starts 400 above the last,
/// with the three master tiers sharing one floor. A point's height is this plus its LP.
enum Elo {
    private static let tiers = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND"]

    static func point(_ entry: LpPoint) -> Int {
        base(tier: entry.tier, rank: entry.rank) + entry.points
    }

    static func base(tier: String?, rank: String?) -> Int {
        guard let tier else { return 0 }
        let upper = tier.uppercased()
        if let index = tiers.firstIndex(of: upper) {
            let division: Int
            switch rank?.uppercased() {
            case "IV": division = 0
            case "III": division = 1
            case "II": division = 2
            default: division = 3
            }
            return index * 400 + division * 100
        }
        return 2800
    }

    /// The chart labels tiers by their short code — `C I`, `M I`, `GM I`.
    static func short(_ tier: String?) -> String {
        switch tier?.uppercased() {
        case "CHALLENGER": return "C"
        case "GRANDMASTER": return "GM"
        case "MASTER": return "M"
        case "DIAMOND": return "D"
        case "EMERALD": return "E"
        case "PLATINUM": return "P"
        case "GOLD": return "G"
        case "SILVER": return "S"
        case "BRONZE": return "B"
        case "IRON": return "I"
        default: return (tier ?? "").prefix(1).uppercased()
        }
    }
}
