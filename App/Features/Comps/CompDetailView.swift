import SwiftUI

struct CompDetailView: View {
    @EnvironmentObject private var repository: Repository
    @Environment(\.dismiss) private var dismiss
    let compID: String

    @State private var stage: Stage = .final
    enum Stage: String, CaseIterable, Identifiable {
        case early, middle, final
        var id: String { rawValue }
        var title: String {
            switch self {
            case .early: return L("App.comp.stage.early")
            case .middle: return L("App.comp.stage.middle")
            case .final: return L("App.comp.stage.final")
            }
        }
    }

    private var comp: Comp? { repository.dataset.comps.first { $0.id == compID } }

    var body: some View {
        Group {
            if let comp { CompContent(comp: comp, stage: $stage) }
            else { ContentUnavailableView(L("App.comp.notFound"), systemImage: "tray") }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }
}

private struct CompContent: View {
    @EnvironmentObject private var repository: Repository
    let comp: Comp
    @Binding var stage: CompDetailView.Stage

    private var dataset: TFTDataset { repository.dataset }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.horizontal, Theme.gutter)

                unitStrip

                stagePicker
                    .padding(.horizontal, Theme.gutter)

                BoardSection(comp: comp, stage: stage)
                    .padding(.horizontal, Theme.gutter)
                    .animation(.snappy, value: stage)

                if stage == .final {
                    coreSection
                        .padding(.horizontal, Theme.gutter)
                }

                traitSection
                    .padding(.horizontal, Theme.gutter)

                if stage == .final {
                    similarSection
                        .padding(.horizontal, Theme.gutter)
                }

                statSection
                    .padding(.horizontal, Theme.gutter)

                if stage == .final {
                    NavigationLink {
                        TeamCodeView(teamCode: comp.teamCode, name: comp.name)
                    } label: {
                        Label(L("App.comp.teamCode"), systemImage: "shippingbox.and.arrow.backward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accentBright)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                    }
                    .padding(.horizontal, Theme.gutter)
                }

                Color.clear.frame(height: 40)
            }
            .padding(.top, 4)
        }
        .pageReveal()
        .navigationTitle(comp.name)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let tier = comp.opTier { Chip(text: tier, color: Theme.opTier(tier), filled: true) }
                    Chip(text: L("App.comp.level", comp.reroll ?? 0), color: Theme.textSecondary)
                    Chip(text: Theme.difficulty(comp.difficulty), color: Color(hex: 0xC07E43))
                    if comp.honey == true { Chip(text: L("App.comp.honey"), color: Theme.gold) }
                }
                Text(L("App.comp.recentPlays", comp.cost, Fmt.integer(comp.stats.count)))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.decimal(comp.stats.avg)).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(L("App.comp.avgRank")).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// Roster strip above the board: stars, priority tag and built items per unit.
    private var unitStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 9) {
                ForEach(comp.units.sorted { ($0.prio ?? 99) < ($1.prio ?? 99) }, id: \.k) { unit in
                    NavigationLink {
                        ChampionDetailView(championKey: unit.k)
                    } label: {
                        UnitChip(unit: unit)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 4)
        }
    }

    private func enabled(_ option: CompDetailView.Stage) -> Bool {        switch option {
        case .early: return comp.early != nil
        case .middle: return comp.middle != nil
        case .final: return true
        }
    }

    private func stageLevel(_ option: CompDetailView.Stage) -> String {
        let level: Int?
        switch option {
        case .early: level = comp.early?.level
        case .middle: level = comp.middle?.level
        case .final: level = comp.reroll
        }
        return level.map { L("App.comp.level", $0) } ?? L("App.comp.unknown")
    }

    private var stagePicker: some View {
        HStack(spacing: 6) {
            ForEach(CompDetailView.Stage.allCases) { option in
                let enabled = self.enabled(option)
                Button {
                    guard enabled else { return }
                    stage = option
                } label: {
                    VStack(spacing: 3) {
                        Text(option.title).font(.system(size: 12, weight: stage == option ? .bold : .semibold))
                        Text(stageLevel(option))
                            .font(.system(size: 10))
                            .opacity(0.75)
                    }
                    .foregroundStyle(stage == option ? .white : Theme.textSecondary)
                    .opacity(enabled ? 1 : 0.35)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(stage == option ? Theme.accent : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .disabled(!enabled)
            }
        }
        .animation(.snappy, value: stage)
    }

    @ViewBuilder private var coreSection: some View {
        let cores = comp.units.filter(\.core).sorted { ($0.prio ?? 9) < ($1.prio ?? 9) }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.comp.coreChampions"), detail: L("App.comp.coreCount", cores.count, comp.units.count))
            ForEach(Array(cores.enumerated()), id: \.element.k) { index, unit in
                CoreUnitRow(comp: comp, unit: unit, order: index + 1)
            }
        }
    }

    private var traitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.traits"), detail: L("App.comp.tapForDetail"))
            Card(padding: 4) {
                VStack(spacing: 0) {
                    let ranked = comp.traits.sorted { ($0.style ?? -1) > ($1.style ?? -1) }
                    ForEach(Array(ranked.enumerated()), id: \.element.k) { index, trait in
                        NavigationLink {
                            TraitDetailView(traitKey: trait.k)
                        } label: {
                            TraitLadderRow(key: trait.k, num: trait.num, style: trait.style)
                        }
                        .buttonStyle(PressStyle())
                        if index < ranked.count - 1 {
                            Divider().overlay(Theme.separator.opacity(0.6)).padding(.leading, 45)
                        }
                    }
                }
            }
        }
    }

    private var similarSection: some View {
        let picks = Array(dataset.similarComps(to: comp).prefix(4))
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.comp.similarComps"), detail: L("App.comp.mostSharedTraits"))
            VStack(spacing: 8) {
                ForEach(picks, id: \.comp.id) { match in
                    NavigationLink {
                        CompDetailView(compID: match.comp.id)
                    } label: {
                        SimilarCompRow(match: match)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private var statSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.champion.performance"), detail: L("App.comp.vsAll"))
            Card {
                VStack(spacing: 14) {
                    statRow(L("HomeSummary.winRate"), comp.stats.win, baseline: comp.labelStats?.win)
                    statRow(L("MetaTrendsChampion.top4Rate"), comp.stats.top4, baseline: comp.labelStats?.top4)
                    statRow(L("App.comp.sort.pick"), comp.stats.pick, baseline: comp.labelStats?.pick, scale: 0.06)
                    HStack {
                        Text(L("App.comp.sort.opScore")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Fmt.decimal(comp.opScore, digits: 2)).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accentBright)
                    }
                }
            }
        }
    }

    private func statRow(_ title: String, _ value: Double, baseline: Double?, scale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Fmt.percent(value, digits: 2)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let baseline, baseline > 0 {
                    Text(L("App.comp.baseline", Fmt.percent(baseline, digits: 2)))
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            MeterBar(fraction: value / max(scale, 0.001), color: Theme.accent)
        }
    }
}

// MARK: - Board

private struct BoardSection: View {
    @EnvironmentObject private var repository: Repository
    let comp: Comp
    let stage: CompDetailView.Stage

    private struct Piece: Identifiable {
        let id = UUID()
        let key: String
        let cell: Cell?
        let tier: Int?
        let items: [String]
        let core: Bool
        let prio: Int?
    }

    private var pieces: [Piece] {
        switch stage {
        case .final:
            return comp.units.map { Piece(key: $0.k, cell: $0.cell, tier: $0.tier, items: $0.items, core: $0.core, prio: $0.prio) }
        case .early:
            return comp.early?.units.map { Piece(key: $0.k, cell: $0.cell, tier: nil, items: $0.items, core: false, prio: nil) } ?? []
        case .middle:
            return comp.middle?.units.map { Piece(key: $0.k, cell: $0.cell, tier: nil, items: $0.items, core: false, prio: nil) } ?? []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                text: stage.title,
                detail: stage == .final ? nil : L("App.comp.stageWinRate", Fmt.percent(winRate, digits: 1), Fmt.integer(plays)))
            if hasPositions {
                board
            } else {
                Card(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("App.comp.noPositions"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        roster
                    }
                }
            }
        }
    }

    private var hasPositions: Bool { pieces.contains { $0.cell != nil } }

    private var board: some View {
        let dataset = repository.dataset
        return HexBoard(width: HexGeometry.cardWidth(), cap: 44) { geometry in
            ForEach(pieces) { piece in
                let champ = dataset.champion(piece.key)
                let cell = piece.cell ?? Cell(x: 1, y: 1)
                HexPlacement(x: cell.x, y: cell.y, geometry: geometry) {
                    NavigationLink {
                        ChampionDetailView(championKey: piece.key)
                    } label: {
                        HexUnit(geometry: geometry,
                                tile: champ?.tile,
                                border: piece.core ? Theme.gold : Theme.rarity(champ?.cost),
                                emphasized: piece.core,
                                tier: piece.tier ?? 0,
                                items: piece.items,
                                prio: piece.core ? piece.prio : nil)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(10)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    /// Deck rows without board coordinates, kept readable as a roster.
    private var roster: some View {
        let dataset = repository.dataset
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(pieces) { piece in
                let champ = dataset.champion(piece.key)
                NavigationLink {
                    ChampionDetailView(championKey: piece.key)
                } label: {
                    HStack(spacing: 6) {
                        RemoteImage(url: champ?.tile, contentMode: .fill)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(piece.core ? Theme.gold : Theme.rarity(champ?.cost), lineWidth: 1.5))
                        Text(champ?.n ?? piece.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !piece.items.isEmpty {
                            Text("\(piece.items.count)")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceRaised, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private var plays: Int? {
        switch stage { case .early: comp.early?.play; case .middle: comp.middle?.play; case .final: nil }
    }
    private var winRate: Double {
        switch stage {
        case .early: guard let b = comp.early, let p = b.play, p > 0 else { return 0 }; return Double(b.win ?? 0) / Double(p)
        case .middle: guard let b = comp.middle, let p = b.play, p > 0 else { return 0 }; return Double(b.win ?? 0) / Double(p)
        case .final: return comp.stats.win
        }
    }
}

private struct CoreUnitRow: View {
    @EnvironmentObject private var repository: Repository
    let comp: Comp
    let unit: CompUnit
    let order: Int

    var body: some View {
        let dataset = repository.dataset
        let champ = dataset.champion(unit.k)
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    ChampionDetailView(championKey: unit.k)
                } label: {
                    HStack(spacing: 10) {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(url: champ?.tile, contentMode: .fill)
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.rarity(champ?.cost), lineWidth: 2))
                            Text("\(order)")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Theme.gold, in: Circle())
                                .offset(x: -4, y: 4)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(champ?.n ?? unit.k).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                if let tier = unit.tier {
                                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Theme.gold)
                                    Text("\(tier)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gold)
                                }
                            }
                            HStack(spacing: 4) {
                                Text(L("App.champion.filter.costFormat", "\(champ?.cost ?? 0)")).font(.system(size: 10)).foregroundStyle(Theme.rarity(champ?.cost))
                                if let role = champ?.role { Text("· \(role)").font(.system(size: 10)).foregroundStyle(Theme.textTertiary) }
                            }
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())

                if !unit.items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("App.comp.items")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                        ForEach(unit.items, id: \.self) { itemKey in
                            ItemBuildRow(itemKey: itemKey)
                        }
                    }
                }
            }
        }
    }
}

private struct UnitChip: View {
    @EnvironmentObject private var repository: Repository
    let unit: CompUnit

    /// op.gg marks the carry order as 1st/2nd/3rd badges in these three colors.
    private var priorityMeta: (text: String, color: Color)? {
        guard let prio = unit.prio, prio > 0 else { return nil }
        switch prio {
        case 1: return (L("App.comp.ordinal.1"), Color(hex: 0xE85D75))
        case 2: return (L("App.comp.ordinal.2"), Color(hex: 0xE0A32E))
        case 3: return (L("App.comp.ordinal.3"), Color(hex: 0x3E82E0))
        case 4: return (L("App.comp.ordinal.4"), Color(hex: 0x3E82E0))
        default: return (L("App.comp.ordinalNth", "\(prio)"), Color(hex: 0x8A94A0))
        }
    }

    var body: some View {
        let champ = repository.dataset.champion(unit.k)
        VStack(spacing: 4) {
            HStack(spacing: 1.5) {
                ForEach(0..<(unit.tier ?? 1), id: \.self) { _ in
                    Image(systemName: "star.fill").font(.system(size: 7))
                }
            }
            // Reference colours the star row green for carries, grey for the rest.
            .foregroundStyle(unit.core ? Color(hex: 0x39B57A) : Color(hex: 0x6C757D))
            .frame(height: 8)

            ZStack(alignment: .topLeading) {
                RemoteImage(url: champ?.tile, contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(unit.core ? Color(hex: 0x39B57A) : Theme.rarity(champ?.cost),
                                      lineWidth: unit.core ? 2.2 : 1.6))
                if let meta = priorityMeta {
                    Text(meta.text)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(meta.color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .offset(x: -2, y: -3)
                }
            }
            // Built items sit inside the bottom edge of the artwork, like the reference.
            .overlay(alignment: .bottom) {
                if !unit.items.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(Array(unit.items.prefix(3)), id: \.self) { key in
                            RemoteImage(url: repository.dataset.item(key)?.icon, contentMode: .fit)
                                .frame(width: 15, height: 15)
                        }
                    }
                    .padding(1.5)
                    .background(Theme.surfaceSunken.opacity(0.85), in: Capsule())
                }
            }

            Text(champ?.n ?? unit.k)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 58)
    }
}

/// One trait row with its full activation ladder; op.gg lights only the tiers this deck actually reaches.
private struct TraitLadderRow: View {
    @EnvironmentObject private var repository: Repository
    let key: String
    let num: Int
    let style: Int?

    private var tiers: [TraitTier] { repository.dataset.trait(key)?.tiers ?? [] }

    var body: some View {
        let ref = repository.dataset.trait(key)
        let current = Theme.traitStyle(style)
        HStack(alignment: .center, spacing: 9) {
            RemoteImage(url: ref?.icon, contentMode: .fit)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(ref?.n ?? key)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let type = ref?.type {
                        Text(type).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    }
                }
                if tiers.isEmpty {
                    Text(L("App.comp.championCount", "\(num)")).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                } else {
                    HStack(spacing: 3) {
                        ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                            let reached = num >= tier.min
                            let palette = Theme.traitStyle(tier.style)
                            Text("\(tier.min)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(reached ? palette.text : Theme.textTertiary)
                                .frame(minWidth: 17)
                                .padding(.vertical, 2)
                                .background(reached ? palette.color : Theme.surfaceSunken,
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            if index < tiers.count - 1 {
                                Image(systemName: "chevron.right").font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            Text("\(num)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(current.text)
                .frame(minWidth: 26, minHeight: 26)
                .background(current.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// A built item with the component pieces op.gg lists beside it.
private struct ItemBuildRow: View {
    @EnvironmentObject private var repository: Repository
    let itemKey: String

    var body: some View {
        let item = repository.dataset.item(itemKey)
        let partKeys = item?.composition ?? []
        HStack(spacing: 8) {
            NavigationLink {
                ItemDetailView(keys: [itemKey])
            } label: {
                HStack(spacing: 8) {
                    RemoteImage(url: item?.icon, contentMode: .fit).frame(width: 26, height: 26)
                    Text(item?.n ?? itemKey)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            Spacer(minLength: 6)
            if partKeys.isEmpty {
                Text(L("App.comp.itemCount", "1")).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(partKeys.enumerated()), id: \.offset) { index, key in
                        if index > 0 {
                            Image(systemName: "plus").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        NavigationLink {
                            ItemDetailView(keys: [key])
                        } label: {
                            RemoteImage(url: repository.dataset.item(key)?.icon, contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(6)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SimilarCompRow: View {
    @EnvironmentObject private var repository: Repository
    let match: CompMatch

    var body: some View {
        let comp = match.comp
        let lead = repository.dataset.champion(comp.units.first(where: \.core)?.k ?? comp.units.first?.k)
        HStack(spacing: 10) {
            RemoteImage(url: lead?.tile, contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.rarity(lead?.cost), lineWidth: 1.8))
            VStack(alignment: .leading, spacing: 3) {
                Text(comp.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L("App.comp.sharedTraits", match.shared, comp.cost))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.decimal(comp.stats.avg, digits: 2))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(L("App.comp.avgRankShort")).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

struct TeamCodeView: View {
    let teamCode: String?
    let name: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("App.comp.teamCodeTitle")).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Text(teamCode ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button {
                    UIPasteboard.general.string = teamCode
                } label: {
                    Label(L("App.comp.copyCode"), systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                }
                Text(L("App.comp.pasteInstruction"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.gutter)
        }
        .background(Theme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
