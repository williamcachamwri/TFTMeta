import SwiftUI

struct BuffNerfView: View {
    @EnvironmentObject private var store: BalanceStore
    @State private var kind: KindFilter = .all

    private enum KindFilter: Hashable {
        case all
        case kind(BalanceKind)

        var title: String {
            switch self {
            case .all: return L("BuffAndNerf.all")
            case .kind(let value): return value.title
            }
        }
    }

    private struct LoadKey: Hashable {
        let route: BalanceRoute
        let version: String
        let language: AppLanguage
    }

    private var routeBinding: Binding<BalanceRoute> {
        Binding(get: { store.route }, set: { store.route = $0 })
    }

    private var versionBinding: Binding<String> {
        Binding(get: { store.version }, set: { store.version = $0 })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.horizontal, Theme.gutter)

                if !store.versions.isEmpty {
                    ChipRow(options: store.versions.map { ($0, L("App.balance.patchFormat", $0)) }, selection: versionBinding)
                }

                UnderlineTabs(options: BalanceRoute.allCases.map { ($0, $0.title) }, selection: routeBinding)
                    .padding(.horizontal, Theme.gutter)

                if let snapshot = store.current {
                    SummaryStrip(snapshot: snapshot)
                        .padding(.horizontal, Theme.gutter)
                }

                ChipRow(options: ([KindFilter.all] + BalanceKind.allCases.map { KindFilter.kind($0) })
                            .map { ($0, $0.title) },
                        selection: $kind)
                    .padding(.top, 2)

                content

                Color.clear.frame(height: 40)
            }
            .padding(.top, 4)
        }
        .background(Theme.background)
        .pageReveal()
        .navigationTitle(L("App.tool.buffNerf"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .refreshable { await store.reload() }
        .task(id: LoadKey(route: store.route, version: store.version, language: store.language)) { await store.load() }
        .onChange(of: store.route) { _, _ in kind = .all }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("App.balance.title"))
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            let snapshot = store.current
            Text(L("App.balance.versionCompare", store.version, snapshot?.prevVersion ?? L("App.balance.prevPatch"), snapshot?.entries.count ?? 0))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let notice = store.notice {
            FailureCard(text: notice) { Task { await store.reload() } }
                .padding(.horizontal, Theme.gutter)
        }

        if store.isLoading && store.current == nil {
            VStack(spacing: 10) {
                ProgressView().tint(Theme.accent)
                Text(L("App.balance.loadingChanges", store.route.title, store.version))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 52)
        } else if let snapshot = store.current {
            let entries = visible(snapshot)
            if entries.isEmpty {
                ContentUnavailableView(L("App.balance.noChanges"), systemImage: "equal.circle",
                                       description: Text(L("App.balance.noChangesDesc", store.route.title, store.version)))
                    .padding(.top, 30)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(entries) { entry in
                        BalanceCard(entry: entry)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .animation(.snappy(duration: 0.25), value: kind)
            }
        }
    }

    private func visible(_ snapshot: BalanceSnapshot) -> [BalanceEntry] {
        switch kind {
        case .all: return snapshot.entries
        case .kind(let wanted): return snapshot.entries.filter { $0.kind == wanted }
        }
    }
}

// MARK: - Summary

private struct SummaryStrip: View {
    let snapshot: BalanceSnapshot

    private func count(_ kind: BalanceKind) -> Int { snapshot.entries.filter { $0.kind == kind }.count }

    var body: some View {
        HStack(spacing: 0) {
            StatColumn(title: L("App.balance.changeCount"), value: Fmt.integer(snapshot.entries.count))
            StatColumn(title: L("BuffAndNerf.buff"), value: Fmt.integer(count(.buff)), color: BalanceText.up)
            StatColumn(title: L("BuffAndNerf.nerf"), value: Fmt.integer(count(.nerf)), color: BalanceText.down)
            StatColumn(title: L("BuffAndNerf.adjust"), value: Fmt.integer(count(.adjust)), color: Theme.accentBright)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

// MARK: - Card

private struct BalanceCard: View {
    @EnvironmentObject private var repository: Repository
    let entry: BalanceEntry

    private var accent: Color {
        if let cost = entry.cost { return Theme.rarity(cost) }
        if let tier = entry.tier { return Theme.augmentTier(tier).color }
        if let category = entry.category { return Theme.itemCategory(category).color }
        return Theme.separator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: entry.icon(in: repository.dataset), contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(accent, lineWidth: 1.8))

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: 6) {
                        if let detail = entry.detail {
                            Chip(text: detail, color: accent)
                        }
                        Chip(text: entry.kind.short, color: entry.kind.color, filled: true)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: entry.kind.icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(entry.kind.color)
                    .frame(width: 28, height: 28)
                    .background(entry.kind.color.opacity(0.14), in: Circle())
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(entry.changes) { change in
                    BalanceChangeRow(change: change)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(entry.kind.color.opacity(0.6))
                .frame(width: 3)
                .padding(.vertical, 16)
        }
    }
}

private struct BalanceChangeRow: View {
    let change: BalanceChange

    var body: some View {
        if let pair = change.numeric {
            numeric(pair)
        } else {
            prose
        }
    }

    private func numeric(_ pair: (old: Double, new: Double)) -> some View {
        let tint = pair.new > pair.old ? BalanceText.up : BalanceText.down
        return HStack(spacing: 7) {
            Text(change.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(Self.value(pair.old))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .strikethrough(true, color: Theme.textTertiary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(Self.value(pair.new))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            if let delta = change.delta, delta != 0 {
                Text((delta > 0 ? "+" : "") + Self.value(delta))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
    }

    private var prose: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(change.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(BalanceText.marked(before: change.before, after: change.after))
                .font(.system(size: 12))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private static func value(_ number: Double) -> String {
        number == number.rounded() ? Fmt.integer(Int(number)) : Fmt.decimal(number, digits: 2)
    }
}
