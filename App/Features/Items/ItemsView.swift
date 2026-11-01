import SwiftUI

enum ItemSort: String, CaseIterable, Identifiable {
    case winRate, avg, total, top4Rate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .winRate: return L("HomeSummary.winRate")
        case .avg: return L("App.champion.sort.avg")
        case .top4Rate: return L("MetaTrendsChampion.top4Rate")
        case .total: return L("App.champion.sort.total")
        }
    }
}

private enum ItemScope: Hashable { case all, combo, single, byCategory(String) }

struct ItemsView: View {
    @EnvironmentObject private var repository: Repository
    @State private var sort: ItemSort = .winRate
    @State private var scope: ItemScope = .all

    private var categories: [String] {
        Set(repository.dataset.items.flatMap { $0.keys.compactMap { repository.dataset.item($0)?.category } })
            .sorted()
    }

    private var rows: [ItemComboStat] {
        repository.dataset.items
            .filter { combo in
                switch scope {
                case .all: return true
                case .combo: return combo.keys.count > 1
                case .single: return combo.keys.count == 1
                case .byCategory(let category): return combo.keys.contains { repository.dataset.item($0)?.category == category }
                }
            }
            .sorted { lhs, rhs in
                switch sort {
                case .winRate: return lhs.winRate > rhs.winRate
                case .avg: return lhs.avg < rhs.avg
                case .top4Rate: return lhs.top4Rate > rhs.top4Rate
                case .total: return lhs.total > rhs.total
                }
            }
    }

    var body: some View {
        ScreenScaffold(title: L("App.item.title"), subtitle: L("App.item.subtitle", rows.count, sort.title.lowercased())) {
            UnderlineTabs(options: ItemSort.allCases.map { ($0, $0.title) }, selection: $sort)
                .padding(.horizontal, Theme.gutter)
        } filters: {
            HStack {
                FilterPill(
                    title: L("App.item.filter.type"),
                    options: [(.all, L("App.item.filter.all")), (.single, L("App.item.filter.single")), (.combo, L("App.item.filter.combo"))]
                        + categories.map { (ItemScope.byCategory($0), Theme.itemCategory($0).label) },
                    selection: $scope
                )
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
        } content: {
            VStack(spacing: 0) {
                ItemTableHeader()
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.label) { index, combo in
                        NavigationLink {
                            ItemDetailView(keys: combo.keys)
                        } label: {
                            ItemRow(combo: combo, rank: index + 1, shaded: index.isMultiple(of: 2))
                        }
                        .buttonStyle(PressStyle())
                        if index < rows.count - 1 {
                            Divider().overlay(Theme.separator.opacity(0.55)).padding(.leading, 64)
                        }
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .padding(.horizontal, Theme.gutter)
        }
    }
}

/// Shared column metrics: the header and the rows have to agree, and every number is sized
/// against the widest value the column can print — "100,00%" measures 50.7pt at 11.5pt type,
/// so the old 44pt top-4 column ellipsised "69,06%" into "69,06…".
private enum ItemColumns {
    static let rank: CGFloat = 16
    static let art: CGFloat = 30
    static let overlap: CGFloat = -10
    static let avg: CGFloat = 35
    static let percent: CGFloat = 50
    static let gap: CGFloat = 6
}

private struct ItemTableHeader: View {
    var body: some View {
        HStack(spacing: ItemColumns.gap) {
            Text("#").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
                .frame(width: ItemColumns.rank, alignment: .leading)
            Color.clear.frame(width: ItemColumns.art, height: 1)
            Text(L("App.item.header")).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 6)
            column(L("App.item.col.avg"), ItemColumns.avg)
            column(L("App.item.col.win"), ItemColumns.percent)
            column(L("App.stat.top4Header"), ItemColumns.percent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surfaceRaised.opacity(0.55))
    }

    private func column(_ title: String, _ width: CGFloat) -> some View {
        Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
            .fixedSize()
            .frame(width: width, alignment: .trailing)
    }
}

/// Table row: rank · art · name with its users · placement · win rate · top 4.
struct ItemRow: View {
    @EnvironmentObject private var repository: Repository
    let combo: ItemComboStat
    let rank: Int
    let shaded: Bool

    var body: some View {
        let refs = combo.keys.compactMap { repository.dataset.item($0) }
        let category = refs.first.flatMap { Theme.itemCategory($0.category) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ItemColumns.gap) {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(rank <= 3 ? Theme.gold : Theme.textTertiary)
                    .frame(width: ItemColumns.rank, alignment: .leading)
                HStack(spacing: ItemColumns.overlap) {
                    ForEach(Array(refs.prefix(3).enumerated()), id: \.offset) { _, item in
                        RemoteImage(url: item.icon, contentMode: .fit)
                            .frame(width: ItemColumns.art, height: ItemColumns.art)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(category?.color ?? Theme.separator, lineWidth: 1.4))
                    }
                }
                // No minimumScaleFactor here: it lifts the text's *minimum* width, and the row
                // then has nowhere to compress but the numbers.
                Text(refs.map(\.n).joined(separator: " + "))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Text("#" + Fmt.decimal(combo.avg, digits: 2))
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .fixedSize()
                    .frame(width: ItemColumns.avg, alignment: .trailing)
                VStack(spacing: 3) {
                    Text(Fmt.percent(combo.winRate, digits: 2))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize()
                    MeterBar(fraction: min(max((combo.winRate - 0.4) / 0.25, 0.04), 1), color: Theme.accent, height: 3)
                        .frame(width: ItemColumns.percent)
                }
                .frame(width: ItemColumns.percent, alignment: .trailing)
                Text(Fmt.percent(combo.top4Rate, digits: 2))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                    .frame(width: ItemColumns.percent, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)

            HStack(spacing: 6) {
                Text(L("App.item.gameCount", Fmt.integer(combo.total)))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                if let category {
                    Text(category.label).font(.system(size: 10)).foregroundStyle(category.color)
                }
                Spacer(minLength: 4)
                HStack(spacing: -5) {
                    ForEach(Array(combo.champs.prefix(5).enumerated()), id: \.offset) { _, usage in
                        let champ = repository.dataset.champion(usage.k)
                        RemoteImage(url: champ?.tile, contentMode: .fill)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.rarity(champ?.cost), lineWidth: 1.2))
                    }
                }
                if combo.champs.count > 5 {
                    Text("+\(combo.champs.count - 5)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .background(shaded ? Theme.surfaceRaised.opacity(0.32) : Color.clear)
        .contentShape(Rectangle())
    }
}
