import SwiftUI

/// op.gg's ranked ladder as the site renders it: one server page per hundred players,
/// region-switched, endless-scrolled, and every row one tap from the full profile.
struct LeaderboardView: View {
    @EnvironmentObject private var summoners: SummonerStore
    @StateObject private var store = LeaderboardStore.shared
    @State private var wantDetail = false
    @State private var picked: LeaderboardEntry?

    var body: some View {
        CustomRefreshable {
            VStack(alignment: .leading, spacing: 12) {
                FilterBar {
                    FilterPill(title: L("App.summoner.server"),
                               options: SummonerRegion.ordered.map { ($0, $0.title) },
                               selection: $store.region)
                    Spacer()
                }
                .padding(.horizontal, Theme.gutter)

                ladder

                Color.clear.frame(height: 40)
            }
            .padding(.top, 6)
        } action: {
            await store.reloadAsync()
        }
        .background(Theme.background)
        .pageReveal()
        .navigationTitle(L("App.leaderboard.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task {
            if store.entries.isEmpty && !store.isLoading { store.reload() }
        }
        .navigationDestination(isPresented: detailRoute) {
            if let profile = summoners.profile {
                SummonerProfileView(route: profile)
            }
        }
    }

    /// Opens only once the profile asked for has landed — the same gate the search screen
    /// uses, so a second tap cannot push the previous player's screen mid-flight.
    private var detailRoute: Binding<Bool> {
        Binding(get: {
            guard let picked, wantDetail else { return false }
            return summoners.profile.map { isSame($0.displayName, picked.displayName) } == true
        }, set: { if !$0 { wantDetail = false } })
    }

    private func isSame(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ value: String) -> String {
            value.lowercased().replacingOccurrences(of: " ", with: "")
        }
        return key(lhs) == key(rhs)
    }

    private func open(_ entry: LeaderboardEntry) {
        summoners.open(SummonerSuggestion(name: entry.name, tag: entry.tag,
                                          region: store.region, icon: entry.icon, ranked: nil))
        picked = entry
        wantDetail = true
    }

    @ViewBuilder
    private var ladder: some View {
        if store.isLoading && store.entries.isEmpty {
            LadderSkeleton()
                .padding(.horizontal, Theme.gutter)
        } else if store.failed && store.entries.isEmpty {
            FailureCard(text: L("App.error.summonerOffline"),
                        systemImage: "trophy.slash",
                        retry: { store.reload() })
                .padding(.horizontal, Theme.gutter)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        open(entry)
                    } label: {
                        LeaderboardRow(entry: entry)
                    }
                    .buttonStyle(PressStyle())
                    .onAppear { store.loadMoreIfNeeded(current: entry) }
                    if index < store.entries.count - 1 || store.isLoading {
                        Divider().overlay(Theme.separator.opacity(0.6))
                    }
                }
                if store.isLoading {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small).tint(Theme.accent)
                            .padding(.vertical, 12)
                        Spacer()
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            )
            .padding(.horizontal, Theme.gutter)
            .animation(.easeOut(duration: 0.2), value: store.entries.count)
        }
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(rankColor)
                .frame(width: 30, alignment: .leading)

            RemoteImage(url: entry.icon, contentMode: .fill)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tierTint.opacity(0.6), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if entry.standing?.tier != nil {
                    Text("\(TierLocal.name(entry.standing?.tier)) \(TierLocal.division(entry.standing?.division))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tierTint)
                }
            }

            Spacer(minLength: 6)

            if let standing = entry.standing, let points = standing.points {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.integer(points))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    if let rate = standing.winRate {
                        Text(Fmt.percent(rate, digits: 0))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var tierTint: Color { TierLocal.color(entry.standing?.tier) }

    private var rankColor: Color {
        switch entry.rank {
        case 1: return Color(hex: 0xE0A32E)
        case 2: return Color(hex: 0xB9C2CB)
        case 3: return Color(hex: 0xC07E43)
        default: return Theme.textTertiary
        }
    }
}

/// Destination-shaped loading block: the same card the ladder will become.
private struct LadderSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 10) {
                    SkeletonView(style: .text(width: 18, height: 14))
                    SkeletonView(style: .rounded(width: 38, height: 38, cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView(style: .text(width: 110, height: 12))
                        SkeletonView(style: .text(width: 70, height: 10))
                    }
                    Spacer()
                    SkeletonView(style: .text(width: 40, height: 14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                Divider().overlay(Theme.separator.opacity(0.4))
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}
