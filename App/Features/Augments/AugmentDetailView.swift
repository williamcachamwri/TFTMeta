import SwiftUI

struct AugmentDetailView: View {
    @EnvironmentObject private var repository: Repository
    let augmentKey: String

    private static let gradeOrder = ["OP", "S", "A", "B", "C", "D"]

    var body: some View {
        let dataset = repository.dataset
        if let ref = dataset.augment(augmentKey), let stat = dataset.augments.first(where: { $0.k == augmentKey }) {
            let traitKeys = ref.associatedTraits ?? []
            let related = traitKeys.isEmpty ? [] : traitKeys.flatMap { dataset.comps(forTrait: $0) }
                .reduce(into: [String: Comp]()) { map, comp in map[comp.id] = comp }
                .values.sorted { $0.stats.avg < $1.stats.avg }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    AugmentHero(ref: ref, stat: stat)
                        .padding(.horizontal, Theme.gutter)

                    if let tags = ref.tags, !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: L("App.augment.tags"))
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Chip(text: tag, color: Theme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }

                    traitBlock(title: L("App.augment.relatedTraits"), keys: traitKeys, color: Color(hex: 0x39B57A))
                    traitBlock(title: L("App.augment.incompatible"), keys: ref.incompatibleTraits ?? [], color: Color(hex: 0xE85D75))

                    if !related.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: L("App.augment.compsWith"), detail: L("App.augment.compCount", related.count))
                            ForEach(related.prefix(8), id: \.id) { comp in
                                NavigationLink {
                                    CompDetailView(compID: comp.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        if let tier = comp.opTier { Chip(text: tier, color: Theme.opTier(tier), filled: true) }
                                        Text(comp.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                        Spacer()
                                        Text(Fmt.decimal(comp.stats.avg) + " \(L("App.augment.avg"))").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(12)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }

                    siblingsSection
                    synergySection
                }
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .pageReveal()
            .navigationTitle(ref.n)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(L("App.augment.noData"), systemImage: "sparkles")
                .background(Theme.background)
        }
    }

    /// Every augment screen needs somewhere to go next; co-occurrence isn't in the
    /// source data, so the fallback is the same-rank pool ordered by OP grade.
    private var siblingsSection: some View {
        let dataset = repository.dataset
        let tier = dataset.augment(augmentKey)?.tier?.lowercased()
        let order = Self.gradeOrder
        let siblings = dataset.augments
            .filter { $0.k != augmentKey && dataset.augment($0.k)?.tier?.lowercased() == tier }
            .sorted { lhs, rhs in
                let l = order.firstIndex(of: lhs.opTier) ?? 99
                let r = order.firstIndex(of: rhs.opTier) ?? 99
                if l != r { return l < r }
                return (dataset.augment(lhs.k)?.n ?? "") < (dataset.augment(rhs.k)?.n ?? "")
            }
            .prefix(6)

        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.augment.sameTier"), detail: "\(Theme.augmentTier(tier).label)")
            ForEach(siblings, id: \.k) { stat in
                NavigationLink {
                    AugmentDetailView(augmentKey: stat.k)
                } label: {
                    AugmentSiblingRow(stat: stat)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var synergySection: some View {
        let dataset = repository.dataset
        let currentTraits = Set(dataset.augment(augmentKey)?.associatedTraits ?? [])
        guard !currentTraits.isEmpty else { return AnyView(EmptyView()) }

        let synergies = dataset.augments
            .filter { stat in
                stat.k != augmentKey &&
                !(dataset.augment(stat.k)?.incompatibleTraits ?? []).contains { currentTraits.contains($0) }
            }
            .compactMap { stat -> (stat: AugmentStat, overlap: Int)? in
                let otherTraits = Set(dataset.augment(stat.k)?.associatedTraits ?? [])
                let overlap = currentTraits.intersection(otherTraits).count
                return overlap > 0 ? (stat, overlap) : nil
            }
            .sorted { $0.overlap > $1.overlap }
            .prefix(4)

        if synergies.isEmpty {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: L("App.augment.synergy"), detail: L("App.augment.synergyHint"))
                ForEach(synergies.map(\.stat), id: \.k) { stat in
                    NavigationLink {
                        AugmentDetailView(augmentKey: stat.k)
                    } label: {
                        AugmentSiblingRow(stat: stat)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
        )
    }

    @ViewBuilder
    private func traitBlock(title: String, keys: [String], color: Color) -> some View {
        if !keys.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: title, detail: "\(keys.count)")
                Card {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(keys, id: \.self) { key in
                            NavigationLink {
                                TraitDetailView(traitKey: key)
                            } label: {
                                HStack(spacing: 6) {
                                    RemoteImage(url: repository.dataset.trait(key)?.icon, contentMode: .fit)
                                        .frame(width: 18, height: 18)
                                    Text(repository.dataset.trait(key)?.n ?? key)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(color)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

/// Reference card: oversized art on the left, wordmark pinned to the corner,
/// and the full effect text running underneath rather than truncated.
private struct AugmentHero: View {
    let ref: AugmentRef
    let stat: AugmentStat

    var body: some View {
        let tierMeta = Theme.augmentTier(ref.tier)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(tierMeta.color.opacity(0.16))
                    RemoteImage(url: ref.icon, contentMode: .fit)
                        .padding(9)
                }
                .frame(width: 84, height: 84)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tierMeta.color.opacity(0.85), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 7) {
                    Text(tierMeta.label)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(tierMeta.color)
                    Text(ref.n)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 5) {
                        Chip(text: L("App.comp.opFormat", stat.opTier), color: Theme.opTier(stat.opTier), filled: true)
                        if ref.unique == true { Chip(text: L("App.augment.unique"), color: Theme.gold) }
                        if let version = stat.version {
                            Text(version).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("OP.")
                    Text("GG")
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.gold.opacity(0.75))
            }

            Rectangle().fill(Theme.separator.opacity(0.7)).frame(height: 1).padding(.vertical, 14)

            Text(descText)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    private var descText: String {
        guard let desc = ref.desc, !desc.isEmpty else { return L("App.augment.noDesc") }
        return desc
    }
}

private struct AugmentSiblingRow: View {
    @EnvironmentObject private var repository: Repository
    let stat: AugmentStat

    var body: some View {
        let ref = repository.dataset.augment(stat.k)
        let tierMeta = Theme.augmentTier(ref?.tier)
        HStack(spacing: 11) {
            RemoteImage(url: ref?.icon, contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tierMeta.color.opacity(0.7), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(ref?.n ?? stat.k)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(ref?.desc ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(stat.opTier)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.opTier(stat.opTier))
                .frame(width: 26, alignment: .trailing)
        }
        .padding(11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .contentShape(Rectangle())
    }
}
