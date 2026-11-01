import SwiftUI

/// Player lookup. Typing answers like the site's header box does — one `getAutoSuggest` call
/// per pause, listing real accounts with their icon and league — and picking a row opens the
/// full profile screen the reference renders.
struct SummonerSearchView: View {
    @EnvironmentObject private var store: SummonerStore
    @ObservedObject private var dropdown = DropdownGate.shared
    @State private var wantDetail = false

    /// The reference debounces at 300 ms; anything livelier retraces the same prefix over and over.
    private static let pause: Duration = .milliseconds(300)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                searchCard
                results
                Color.clear.frame(height: 40)
            }
            .padding(.top, 6)
        }
        .background(Theme.background)
        .pageReveal()
        .navigationTitle(L("App.tool.summoner"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task(id: LiveQuery(text: store.text, region: store.region)) {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            await store.suggest()
        }
        .navigationDestination(isPresented: detailRoute) {
            if let profile = store.profile {
                SummonerProfileView(route: profile)
            }
        }
    }

    /// Opens only once the profile asked for has actually landed — otherwise a second search
    /// would push the previous player's screen while the new one is still in flight. Loading is
    /// deliberately not part of this: the detail screen's "Cập nhật" re-enters the loader for
    /// the same player, and a gate that went false there would pop the user back out.
    private var detailRoute: Binding<Bool> {
        Binding(get: {
            wantDetail && store.profile.map { isSameName($0.displayName) } == true
        }, set: { if !$0 { wantDetail = false } })
    }

    private func isSameName(_ displayName: String) -> Bool {
        func key(_ value: String) -> String {
            value.lowercased().replacingOccurrences(of: " ", with: "")
        }
        return key(displayName) == key(store.text)
    }

    // MARK: - Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterBar {
                FilterPill(title: L("App.summoner.server"),
                           options: SummonerRegion.ordered.map { ($0, $0.title) },
                           selection: $store.region)
                TextField(L("App.summoner.nameTag"), text: $store.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(store.search)
            }

            if !store.suggestions.isEmpty {
                SuggestionList(items: store.suggestions) { pick in
                    store.open(pick)
                    wantDetail = true
                } onSearchAll: {
                    store.search()
                    wantDetail = true
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity))
            }

            Button(action: store.search) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .bold))
                    Text(L("BuffAndNerf.search")).font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(PressStyle())
            .disabled(store.isLoading)

            Text(L("App.summoner.searchHint"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
        .zIndex(dropdown.isOpen ? 100 : 0)
        .animation(.easeOut(duration: 0.2), value: store.suggestions.isEmpty)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if store.isLoading {
            SearchSkeleton(name: store.text)
                .padding(.horizontal, Theme.gutter)
        }

        if let failure = store.failure {
            FailureCard(text: failure.displayText,
                        systemImage: "person.crop.circle.badge.questionmark",
                        retry: store.search)
                .padding(.horizontal, Theme.gutter)
        }

        if let profile = store.profile, !store.isLoading {
            Button {
                wantDetail = true
            } label: {
                FoundRow(profile: profile)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, Theme.gutter)
            .transition(.opacity)
        }

        if store.profile == nil, store.failure == nil, !store.isLoading, store.suggestions.isEmpty {
            ContentUnavailableView(L("App.summoner.noLookup"),
                                   systemImage: "magnifyingglass.circle",
                                   description: Text(L("App.summoner.noLookupDesc")))
                .padding(.top, 24)
        }
    }
}

/// The live dropdown: one row per account, then the "search this text" row the reference keeps
/// at the bottom so an exact Name#TAG still wins over a near match.
private struct SuggestionList: View {
    let items: [SummonerSuggestion]
    var onPick: (SummonerSuggestion) -> Void
    var onSearchAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    SuggestionRow(suggestion: suggestion)
                }
                .buttonStyle(PressStyle())
                .overlay(alignment: .top) {
                    if index > 0 { Divider().overlay(Theme.separator.opacity(0.6)) }
                }
            }
            Divider().overlay(Theme.separator.opacity(0.6))
            Button(action: onSearchAll) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                    Text(L("App.summoner.searchPlayer"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .background(Theme.accent.opacity(0.08))
        }
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct SuggestionRow: View {
    let suggestion: SummonerSuggestion

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: suggestion.icon, contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(suggestion.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("#\(suggestion.tag)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                if let ranked = suggestion.ranked, !ranked.isEmpty {
                    Text(ranked)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Self.tint(ranked))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// op.gg sends the league line as text (`MASTER I - 28LP`); only the tier word carries colour.
    static func tint(_ ranked: String) -> Color {
        TierLocal.color(ranked.split(separator: " ").first.map(String.init))
    }
}

/// The row a finished lookup leaves behind, one tap from the full profile.
private struct FoundRow: View {
    let profile: SummonerProfile

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: profile.icon, contentMode: .fill)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TierLocal.color(profile.standing?.tier).opacity(0.7), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(TierLocal.name(profile.standing?.tier)) \(TierLocal.division(profile.standing?.division))"
                     + (profile.level.map { " · \(L("App.summoner.level")) \($0)" } ?? ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TierLocal.color(profile.standing?.tier))
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(profile.region.code)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
        )
    }
}

/// Destination-shaped loading line: the same row the answer will become.
private struct SearchSkeleton: View {
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceRaised.opacity(0.7))
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surfaceRaised.opacity(0.7))
                    .frame(width: 132, height: 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surfaceRaised.opacity(0.5))
                    .frame(width: 88, height: 11)
            }
            Spacer(minLength: 6)
            ProgressView().tint(Theme.accent)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(alignment: .leading) {
            Text(L("App.summoner.searching", name))
                .font(.system(size: 10))
                .foregroundStyle(.clear)
        }
        .accessibilityLabel(L("App.summoner.searching", name))
    }
}

/// Identity for `.task(id:)`: a new keystroke or a new server restarts the debounce window.
private struct LiveQuery: Hashable {
    let text: String
    let region: SummonerRegion
}
