import SwiftUI

/// One finished game: the reference's collapsed row, then the eight boards it expands into.
///
/// The row itself needs no extra call — `getSummonerMatches` already ships the roster and the
/// player's own board. Only the opponents' boards come from `getMatchDetail`, and those load
/// the first time a row opens and stay cached.
struct SummonerMatchRow: View {
    @EnvironmentObject private var repository: Repository
    let match: SummonerMatch
    let rivals: [MatchRival]?
    var isLoadingRivals = false
    let loadRivals: () -> Void

    @State private var expanded = false

    private var dataset: TFTDataset { repository.dataset }
    private var mine: String? { match.opponents.first(where: \.isSelf)?.puuid }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                summary
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())

            if expanded {
                Divider()
                    .overlay(Theme.separator.opacity(0.7))
                    .padding(.top, 10)
                detail
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(alignment: .leading) {
            // The medal colour runs down the left edge instead of tinting the whole card, which
            // keeps a page of rows readable.
            RoundedRectangle(cornerRadius: 3)
                .fill(rankColor)
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(match.isTop4 ? Theme.gold.opacity(0.35) : Theme.separator.opacity(0.6), lineWidth: 1)
        )
    }

    /// The unit strips scroll, so the whole card cannot be the tap target — the summary block
    /// above them is, and it carries the chevron that says so.
    private func toggle() {
        withAnimation(.easeOut(duration: 0.22)) { expanded.toggle() }
        if expanded, rivals == nil { loadRivals() }
    }

    // MARK: - Collapsed

    private var summary: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ordinal(match.placement))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(rankColor)
                Text(SummonerFilters.title(forQueueType: match.queueType))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(When.ago(match.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Text(L("App.summoner.round", match.roundLabel))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Text(When.duration(match.seconds))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 68, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                pills
                unitStrip
                roster
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var pills: some View {
        let active = match.traits.filter(\.isActive)
        if !active.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(active.enumerated()), id: \.offset) { _, trait in
                    MatchTraitPill(trait: trait, ref: dataset.trait(trait.key))
                }
            }
        }
    }

    private var unitStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(match.units.enumerated()), id: \.offset) { _, unit in
                    MatchUnitView(unit: unit, ref: dataset.champion(unit.key), size: 42)
                }
            }
            .padding(.bottom, 2)
        }
        .frame(height: 76)
    }

    /// The eight accounts of the game, this player ringed — the reference prints their names
    /// beside the row; here they arrive with the expanded table one tap away.
    private var roster: some View {
        HStack(spacing: 5) {
            ForEach(match.opponents, id: \.puuid) { rival in
                RemoteImage(url: rival.icon, contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(rival.isSelf ? Theme.accent : Theme.separator,
                                      lineWidth: rival.isSelf ? 2 : 1))
            }
            Spacer(minLength: 4)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Expanded

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            boardFacts
            rivalsSection
        }
        .padding(.top, 10)
    }

    private var boardFacts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                StatColumn(title: L("App.summoner.level"), value: Fmt.integer(match.level))
                StatColumn(title: L("App.summoner.goldLeft"), value: Fmt.integer(match.goldLeft))
                StatColumn(title: L("App.summoner.eliminated"), value: Fmt.integer(match.eliminated))
                StatColumn(title: L("App.champion.stat.damage"), value: Fmt.integer(match.damageToPlayers))
            }
            if !match.augments.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(match.augments.enumerated()), id: \.offset) { _, key in
                        let augment = dataset.augment(key)
                        HStack(spacing: 5) {
                            if let icon = augment?.icon {
                                RemoteImage(url: icon, contentMode: .fit).frame(width: 16, height: 16)
                            }
                            Text(augment?.n ?? key)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.augmentTier(augment?.tier).color)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rivalsSection: some View {
        if let rivals, !rivals.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rivals.enumerated()), id: \.element.id) { index, rival in
                    MatchRivalRow(rival: rival, isSelf: rival.id == mine)
                        .overlay(alignment: .top) {
                            if index > 0 { Divider().overlay(Theme.separator.opacity(0.6)) }
                        }
                }
            }
        } else if isLoadingRivals {
            HStack(spacing: 8) {
                ProgressView().tint(Theme.accent).controlSize(.small)
                Text(L("App.summoner.loadingBoard"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 10)
        } else if rivals != nil {
            Text(L("App.summoner.noBoard"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.vertical, 6)
        }
    }

    private var rankColor: Color { PlacementDonut.color(index: match.placement - 1) }

    /// The reference keeps English ordinals even in Vietnamese ("1st", "6th").
    private func ordinal(_ place: Int) -> String {
        switch place {
        case 1: return L("App.comp.ordinal.1")
        case 2: return L("App.comp.ordinal.2")
        case 3: return L("App.comp.ordinal.3")
        default: return L("App.comp.ordinalNth", "\(place)")
        }
    }
}

/// Synergy chip: icon, name, unit count — coloured by the tier the game actually reached.
struct MatchTraitPill: View {
    let trait: MatchTrait
    let ref: TraitRef?

    var body: some View {
        let style = Theme.traitStyle(trait.style)
        HStack(spacing: 5) {
            icon(size: 15, tint: style.color)
            Text(ref?.n ?? trait.key)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(trait.isActive ? style.text : Theme.textTertiary)
            Text("\(trait.units)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(trait.isActive ? style.color : Theme.textTertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(style.color.opacity(trait.isActive ? 0.24 : 0.1),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func icon(size: CGFloat, tint: Color) -> some View {
        if let url = ref?.icon {
            RemoteImage(url: url, contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.8), lineWidth: 1))
        } else {
            Circle().fill(tint.opacity(0.5)).frame(width: size, height: size)
        }
    }
}

/// A unit as the reference draws it: stars above, portrait ringed in its cost colour, items below.
struct MatchUnitView: View {
    let unit: MatchUnit
    let ref: ChampionRef?
    var size: CGFloat = 42

    private var tint: Color { Theme.rarity(ref?.cost) }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 1) {
                ForEach(0..<max(unit.star, 1), id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: max(5, size * 0.16), weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(height: size * 0.24)

            RemoteImage(url: ref?.tile, contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.6))

            HStack(spacing: 1) {
                ForEach(Array(unit.items.prefix(3).enumerated()), id: \.offset) { _, key in
                    ItemGlyph(key: key, size: size * 0.3)
                }
            }
            .frame(height: size * 0.3)
        }
        .frame(width: size + 4)
    }
}

/// A finished item icon, falling back to a neutral chip when the set does not carry it.
struct ItemGlyph: View {
    @EnvironmentObject private var repository: Repository
    let key: String
    var size: CGFloat = 16

    var body: some View {
        let ref = repository.dataset.item(key)
        return Group {
            if let icon = ref?.icon {
                RemoteImage(url: icon, contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Theme.surfaceRaised)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// One row of the expanded eight-player table.
struct MatchRivalRow: View {
    @EnvironmentObject private var repository: Repository
    let rival: MatchRival
    var isSelf = false

    private var dataset: TFTDataset { repository.dataset }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(rival.placement)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(PlacementDonut.color(index: rival.placement - 1))
                    .frame(width: 16, alignment: .leading)

                RemoteImage(url: rival.icon, contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelf ? Theme.accent : Theme.separator, lineWidth: isSelf ? 2 : 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(rival.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(TierLocal.name(rival.standing?.tier)) \(TierLocal.division(rival.standing?.division))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TierLocal.color(rival.standing?.tier))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("App.summoner.round", "\(round(rival.lastRound))"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        Metric(symbol: "circle.fill", value: rival.goldLeft, tint: Theme.gold)
                        Metric(symbol: "person.fill.checkmark", value: rival.eliminated, tint: Theme.textTertiary)
                        Metric(symbol: "bolt.fill", value: rival.damage, tint: Theme.textTertiary)
                    }
                }
            }

            let active = rival.traits.filter(\.isActive)
            if !active.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(active.enumerated()), id: \.offset) { _, trait in
                            MatchTraitPill(trait: trait, ref: dataset.trait(trait.key))
                        }
                    }
                }
                .frame(height: 25)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(rival.units.enumerated()), id: \.offset) { _, unit in
                        MatchUnitView(unit: unit, ref: dataset.champion(unit.key), size: 32)
                    }
                }
            }
            .frame(height: 58)
        }
        .padding(.vertical, 8)
    }

    private func round(_ value: Int) -> String {
        value >= 10 ? "\(value / 10)-\(value % 10)" : "\(value)"
    }

    private struct Metric: View {
        let symbol: String
        let value: Int
        let tint: Color

        var body: some View {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 8)).foregroundStyle(tint)
                Text("\(value)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
