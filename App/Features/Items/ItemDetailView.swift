import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var repository: Repository
    let keys: [String]

    var body: some View {
        let dataset = repository.dataset
        let refs = keys.compactMap { dataset.item($0) }
        let combos = dataset.items.filter { combo in combo.keys.first == keys.first }
            .sorted { $0.winRate > $1.winRate }

        ColumnScroll {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                    ItemCard(item: ref)
                }

                if refs.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: L("App.item.comboPerf"), detail: Fmt.integer(combos.first(where: { $0.keys == keys })?.total) + " \(L("MetaTrendsChampion.games"))")
                        if let exact = combos.first(where: { $0.keys == keys }) {
                            Card {
                                HStack(spacing: 0) {
                                    StatColumn(title: L("HomeSummary.winRate"), value: Fmt.percent(exact.winRate, digits: 1), color: Color(hex: 0x39B57A))
                                    StatColumn(title: L("App.stat.top4"), value: Fmt.percent(exact.top4Rate, digits: 1))
                                    StatColumn(title: L("App.champion.sort.avg"), value: Fmt.decimal(exact.avg))
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: L("App.item.bestChamps"), detail: L("App.item.byWinRate"))
                    let usage = (combos.first(where: { $0.keys == keys })?.champs ?? []).prefix(10)
                    if usage.isEmpty {
                        Card { Text(L("App.item.noData")).font(.system(size: 12)).foregroundStyle(Theme.textTertiary) }
                    } else {
                        Card(padding: 6) {
                            VStack(spacing: 0) {
                                ForEach(Array(usage.enumerated()), id: \.offset) { index, row in
                                    NavigationLink {
                                        ChampionDetailView(championKey: row.k)
                                    } label: {
                                        HStack(spacing: 10) {
                                            RankLabel(rank: index + 1, emphasized: false)
                                            RemoteImage(url: dataset.champion(row.k)?.tile, contentMode: .fill)
                                                .frame(width: 30, height: 30)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            Text(dataset.champion(row.k)?.n ?? row.k)
                                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(Fmt.integer(row.total) + " \(L("MetaTrendsChampion.games"))")
                                                .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                                            Text(Fmt.percent(row.winRate, digits: 1))
                                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x39B57A))
                                                .frame(width: 52, alignment: .trailing)
                                        }
                                        .padding(9)
                                    }
                                    .buttonStyle(PressStyle())
                                    if index < min(usage.count, 10) - 1 { Divider().overlay(Theme.separator.opacity(0.6)) }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: L("App.item.otherCombos"), detail: L("App.item.comboCount", max(combos.count - 1, 0)))
                    ForEach(combos.filter { $0.keys != keys }.prefix(8), id: \.label) { combo in
                        NavigationLink {
                            ItemDetailView(keys: combo.keys)
                        } label: {
                            HStack(spacing: 10) {
                                HStack(spacing: -5) {
                                    ForEach(Array(combo.keys.enumerated()), id: \.offset) { _, key in
                                        RemoteImage(url: dataset.item(key)?.icon, contentMode: .fit).frame(width: 26, height: 26)
                                    }
                                }
                                .frame(width: CGFloat(combo.keys.count) * 21 + 5)
                                Text(combo.label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                Spacer()
                                Text(Fmt.percent(combo.winRate, digits: 1))
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            }
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                    }
                }

                Color.clear.frame(height: 40)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.gutter)
        }
        .background(Theme.background)
        .pageReveal()
        .navigationTitle(refs.map(\.n).joined(separator: " + "))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ItemCard: View {
    @EnvironmentObject private var repository: Repository
    let item: ItemRef

    var body: some View {
        let meta = Theme.itemCategory(item.category)
        let dataset = repository.dataset
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: item.icon, contentMode: .fit)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.n).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 5) {
                        Chip(text: meta.label, color: meta.color, filled: meta.color == Theme.itemCategory("radiant").color)
                        if item.unique == true { Chip(text: L("App.augment.unique"), color: Theme.gold) }
                    }
                }
                Spacer()
            }

            if let statDesc = item.statDesc, !statDesc.isEmpty {
                Text(statDesc)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x7FD08A))
                    .lineSpacing(2)
            }

            Text(item.desc ?? "—")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)

            if let composition = item.composition, !composition.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("App.item.buildFormula")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 6) {
                        ForEach(Array(composition.enumerated()), id: \.offset) { index, key in
                            let component = dataset.item(key)
                            HStack(spacing: 6) {
                                RemoteImage(url: component?.icon, contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(component?.n ?? key).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            if index < composition.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }

            if let traits = item.associatedTraits, !traits.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("App.item.associatedTraits")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 8) {
                        ForEach(traits, id: \.self) { key in
                            NavigationLink {
                                TraitDetailView(traitKey: key)
                            } label: {
                                HStack(spacing: 5) {
                                    RemoteImage(url: dataset.trait(key)?.icon, contentMode: .fit).frame(width: 18, height: 18)
                                    Text(dataset.trait(key)?.n ?? key).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                                }
                                .padding(5)
                                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}
