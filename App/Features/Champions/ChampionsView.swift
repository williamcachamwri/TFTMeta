import SwiftUI

enum ChampionSort: String, CaseIterable, Identifiable {
    case avg, winRate, top4Rate, total
    var id: String { rawValue }
    var title: String {
        switch self {
        case .avg: return L("App.champion.sort.avg")
        case .winRate: return L("HomeSummary.winRate")
        case .top4Rate: return L("MetaTrendsChampion.top4Rate")
        case .total: return L("App.champion.sort.total")
        }
    }
}

struct ChampionsView: View {
    @EnvironmentObject private var repository: Repository
    @State private var sort: ChampionSort = .avg
    @State private var cost = 0
    @State private var traitKey: String?
    @State private var query = ""
    @State private var searching = false

    private var rows: [(stat: ChampionStat, rank: Int)] {
        let dataset = repository.dataset
        let sorted = dataset.champions
            .filter { cost == 0 || dataset.champion($0.k)?.cost == cost }
            .filter { traitKey == nil || dataset.champion($0.k)?.traits?.contains(traitKey!) == true }
            .filter { row in
                guard !query.isEmpty else { return true }
                let name = dataset.champion(row.k)?.n ?? ""
                return name.folding(options: .diacriticInsensitive, locale: AppLanguage.current.format)
                    .localizedCaseInsensitiveContains(query.folding(options: .diacriticInsensitive, locale: AppLanguage.current.format))
            }
            .sorted { lhs, rhs in
                switch sort {
                case .avg: return lhs.avg < rhs.avg
                case .winRate: return lhs.winRate > rhs.winRate
                case .top4Rate: return lhs.top4Rate > rhs.top4Rate
                case .total: return lhs.total > rhs.total
                }
            }
        return sorted.enumerated().map { ($0.element, $0.offset + 1) }
    }

    private var traitOptions: [(String, String)] {
        repository.dataset.traits
            .reduce(into: [String: Int]()) { counts, stat in counts[stat.k, default: 0] += 1 }
            .compactMap { key, _ in repository.dataset.trait(key).map { (key, $0.n) } }
            .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        ScreenScaffold(title: L("App.champion.title"), subtitle: L("App.champion.subtitle", repository.dataset.meta.set)) {
            UnderlineTabs(options: ChampionSort.allCases.map { ($0, $0.title) }, selection: $sort)
                .padding(.horizontal, Theme.gutter)
        } filters: {
            VStack(spacing: 10) {
                FilterBar {
                    FilterPill(title: L("App.champion.filter.cost"), options: [(0, L("App.champion.filter.allCosts")), (1, L("App.champion.filter.costFormat", 1)), (2, L("App.champion.filter.costFormat", 2)), (3, L("App.champion.filter.costFormat", 3)), (4, L("App.champion.filter.costFormat", 4)), (5, L("App.champion.filter.costFormat", 5))],
                               selection: $cost)
                    FilterPill(title: L("App.champion.filter.trait"), options: [(nil as String?, L("App.champion.filter.allTraits"))] + traitOptions.map { (Optional($0.0), $0.1) },
                               selection: $traitKey)
                    Spacer()
                    Button {
                        if searching { query = "" }
                        searching.toggle()
                    } label: {
                        Image(systemName: searching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 38, height: 36)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
                if searching {
                    TextField(L("App.champion.searchPlaceholder"), text: $query)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .animation(.snappy, value: searching)
        } content: {
            LazyVStack(spacing: 8) {
                ForEach(rows, id: \.stat.k) { row in
                    NavigationLink {
                        ChampionDetailView(championKey: row.stat.k)
                    } label: {
                        ChampionRow(stat: row.stat, rank: row.rank)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

struct ChampionRow: View {
    @EnvironmentObject private var repository: Repository
    let stat: ChampionStat
    let rank: Int

    var body: some View {
        let ref = repository.dataset.champion(stat.k)
        HStack(spacing: 12) {
            RemoteImage(url: ref?.tile, contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.rarity(ref?.cost), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RankLabel(rank: rank)
                    if let cost = ref?.cost {
                        Text(L("App.champion.filter.costFormat", cost)).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.rarity(cost))
                    }
                }
                Text(ref?.n ?? stat.k)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach((ref?.traits ?? []).prefix(3), id: \.self) { key in
                        let trait = repository.dataset.trait(key)
                        RemoteImage(url: trait?.icon, contentMode: .fit)
                            .frame(width: 15, height: 15)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                    }
                    Text(Fmt.integer(stat.total) + " \(L("MetaTrendsChampion.games"))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 2)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 5) {
                MetricValue(value: Fmt.decimal(stat.avg), unit: L("App.champion.avg"))
                HStack(spacing: 6) {
                    Text(Fmt.percent(stat.winRate, digits: 1) + " \(L("App.champion.winSuffix"))")
                        .contentTransition(.numericText())
                    Text(Fmt.percent(stat.top4Rate, digits: 1) + L("App.stat.top4Suffix"))
                        .contentTransition(.numericText())
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}
