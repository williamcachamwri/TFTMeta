import SwiftUI

struct TraitDetailView: View {
    @EnvironmentObject private var repository: Repository
    let traitKey: String

    var body: some View {
        let dataset = repository.dataset
        if let ref = dataset.trait(traitKey) {
            let rows = dataset.traits.filter { $0.k == traitKey }.sorted { $0.num < $1.num }
            let comps = dataset.comps(forTrait: traitKey)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            RemoteImage(url: ref.icon, contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .background(Theme.surfaceSunken, in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ref.n).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                                HStack(spacing: 5) {
                                    Chip(text: ref.type == "origin" ? L("App.trait.filter.origin") : L("App.trait.filter.class"), color: Theme.textSecondary)
                                    Chip(text: "\(ref.champions?.count ?? 0) \(L("TeamBuilder.champion"))", color: Theme.accent)
                                }
                            }
                            Spacer()
                        }
                        Text(ref.desc ?? "—")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: L("App.trait.activationTiers"), detail: L("App.trait.statsByTier"))
                        Card(padding: 6) {
                            VStack(spacing: 0) {
                                ForEach(Array((ref.tiers ?? []).enumerated()), id: \.offset) { _, tier in
                                    let stat = rows.first { $0.num == tier.min }
                                    TierRow(tier: tier, stat: stat)
                                    if tier.min != (ref.tiers?.last?.min ?? -1) {
                                        Divider().overlay(Theme.separator.opacity(0.6))
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: L("App.trait.champions"), detail: "\(ref.champions?.count ?? 0)")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                            ForEach(ref.champions ?? [], id: \.self) { key in
                                NavigationLink {
                                    ChampionDetailView(championKey: key)
                                } label: {
                                    let champ = dataset.champion(key)
                                    VStack(spacing: 4) {
                                        RemoteImage(url: champ?.tile, contentMode: .fill)
                                            .frame(width: 54, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(Theme.rarity(champ?.cost), lineWidth: 2))
                                        Text(champ?.n ?? key)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: L("App.trait.compsUsing"), detail: L("App.champion.compCount", comps.count))
                        ForEach(comps.prefix(8), id: \.id) { comp in
                            NavigationLink {
                                CompDetailView(compID: comp.id)
                            } label: {
                                HStack(spacing: 10) {
                                    if let tier = comp.opTier { Chip(text: tier, color: Theme.opTier(tier), filled: true) }
                                    Text(comp.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    Spacer()
                                    Text(Fmt.percent(comp.stats.top4, digits: 1) + L("App.stat.top4Suffix"))
                                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                                }
                                .padding(12)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
            }
            .background(Theme.background)
            .pageReveal()
            .navigationTitle(ref.n)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(L("App.trait.noData"), systemImage: "questionmark.circle")
                .background(Theme.background)
        }
    }
}

private struct TierRow: View {
    let tier: TraitTier
    let stat: TraitStat?

    var body: some View {
        let palette = Theme.traitStyle(tier.style)
        HStack(spacing: 11) {
            Text("\(tier.min)+")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.text)
                .frame(width: 34, height: 34)
                .background(palette.color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(tier.desc ?? "—")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let stat {
                    Text(L("App.trait.statFormat", Fmt.integer(stat.total), Fmt.decimal(stat.avg)))
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 6)
            if let stat {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.percent(stat.winRate, digits: 1)).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x39B57A))
                    Text(Fmt.percent(stat.top4Rate, digits: 1)).font(.system(size: 11)).foregroundStyle(Theme.accentBright)
                }
            } else {
                Text("—").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(10)
    }
}
