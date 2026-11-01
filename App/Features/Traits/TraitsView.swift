import SwiftUI

enum TraitSort: String, CaseIterable, Identifiable {
    case winRate, avg, top4Rate, total
    var id: String { rawValue }
    var title: String {
        switch self {
        case .winRate: return L("App.trait.sort.winRate")
        case .avg: return L("App.champion.sort.avg")
        case .top4Rate: return L("MetaTrendsChampion.top4Rate")
        case .total: return L("App.champion.sort.total")
        }
    }
}

private enum TraitKind: Hashable { case all, origin, `class` }

struct TraitsView: View {
    @EnvironmentObject private var repository: Repository
    @State private var sort: TraitSort = .winRate
    @State private var kind: TraitKind = .all

    /// One entry per trait, carrying every activation threshold op.gg measured.
    fileprivate struct Group: Identifiable {
        let key: String
        let name: String
        let icon: String?
        let type: String?
        let rows: [TraitStat]
        var headline: TraitStat { rows.max(by: { $0.total < $1.total })! }
        var id: String { key }
    }

    private var groups: [Group] {
        let dataset = repository.dataset
        let bucketed = Dictionary(grouping: dataset.traits, by: \.k)
        return bucketed.compactMap { key, rows in
            guard let ref = dataset.trait(key) else { return nil }
            let matchesKind: Bool
            switch kind {
            case .all: matchesKind = true
            case .origin: matchesKind = ref.type?.lowercased() == "origin"
            case .class: matchesKind = ref.type?.lowercased() == "class"
            }
            guard matchesKind else { return nil }
            return Group(key: key, name: ref.n, icon: ref.icon, type: ref.type,
                         rows: rows.sorted { $0.num < $1.num })
        }
        .sorted { lhs, rhs in
            switch sort {
            case .winRate: return lhs.headline.winRate > rhs.headline.winRate
            case .avg: return lhs.headline.avg < rhs.headline.avg
            case .top4Rate: return lhs.headline.top4Rate > rhs.headline.top4Rate
            case .total: return lhs.headline.total > rhs.headline.total
            }
        }
    }

    var body: some View {
        ScreenScaffold(title: L("App.trait.title"), subtitle: L("App.trait.subtitle", groups.count)) {
            UnderlineTabs(options: TraitSort.allCases.map { ($0, $0.title) }, selection: $sort)
                .padding(.horizontal, Theme.gutter)
        } filters: {
            ChipRow(options: [(.all, L("App.trait.filter.all")), (.origin, L("App.trait.filter.origin")), (.class, L("App.trait.filter.class"))], selection: $kind)
        } content: {
            LazyVStack(spacing: 8) {
                ForEach(groups) { group in
                    NavigationLink {
                        TraitDetailView(traitKey: group.key)
                    } label: {
                        TraitRow(group: group)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    fileprivate struct TraitRow: View {
        let group: TraitsView.Group

        var body: some View {
            HStack(spacing: 12) {
                RemoteImage(url: group.icon, contentMode: .fit)
                    .frame(width: 46, height: 46)
                    .background(Theme.surfaceSunken, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 4) {
                        Text(group.type == "origin" ? L("App.trait.filter.origin") : L("App.trait.filter.class"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        ForEach(group.rows, id: \.num) { row in
                            let palette = Theme.traitStyle(row.style)
                            Text("\(row.num)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(palette.text)
                                .frame(minWidth: 16)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(palette.color, in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    MetricValue(value: Fmt.percent(group.headline.winRate, digits: 1), unit: L("App.trait.winUnit"))
                    Text(Fmt.decimal(group.headline.avg) + " \(L("App.champion.sort.avg"))")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
    }
}
