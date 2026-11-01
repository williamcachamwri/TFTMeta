import SwiftUI
import UniformTypeIdentifiers

private enum BuilderTab: String, CaseIterable, Identifiable {
    case champions, items, augments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .champions: return L("TeamBuilder.champion")
        case .items: return L("TeamBuilder.item")
        case .augments: return L("TeamBuilder.augment")
        }
    }
}

struct TeamBuilderView: View {
    @EnvironmentObject private var repository: Repository
    @StateObject private var model = TeamBuilderModel()
    @State private var tab: BuilderTab = .champions
    @State private var itemCategory = "radiant"

    private var dataset: TFTDataset { repository.dataset }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    BuilderBoardCard(model: model, dataset: dataset)
                    BuilderTraitPanel(tallies: model.traitTallies(dataset: dataset), dataset: dataset)
                    BuilderRosterPanel(model: model, dataset: dataset)
                    BuilderCoreSlots(model: model, dataset: dataset)
                    BuilderActions(model: model, dataset: dataset, poster: renderPoster)
                }
                .padding(.top, 10)
                .padding(.bottom, 18)
            }

            BuilderTray(tab: $tab, itemCategory: $itemCategory, model: model, dataset: dataset)
        }
        .background(Theme.background)
        .pageReveal()
        .navigationTitle(L("App.tool.teamBuilder"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func renderPoster() -> UIImage? {
        let renderer = ImageRenderer(
            content: BuilderPoster(model: model, dataset: dataset)
                .environmentObject(repository)
                .frame(width: 420)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Board

private struct BuilderBoardCard: View {
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        let summary = model.costSummary(dataset: dataset)
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(BuilderOverlay.allCases) { option in
                    Button {
                        model.overlay = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: model.overlay == option ? .bold : .medium))
                            .foregroundStyle(model.overlay == option ? .white : Theme.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(model.overlay == option ? Theme.accent : Theme.surfaceRaised,
                                        in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer()
                Text("\(summary.count)/\(TeamBuilderModel.maxUnits)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .animation(.snappy(duration: 0.22), value: model.overlay)

            HexBoard(geometry: .builderBoard()) { geometry in
                // A catcher spanning the whole board, underneath the pieces: a drag released in
                // the seams between hexes resolves to the nearest cell instead of evaporating.
                Color.clear
                    .frame(width: geometry.boardWidth, height: geometry.totalHeight)
                    .contentShape(Rectangle())
                    .onDrop(of: [.utf8PlainText], isTargeted: Binding(
                        get: { model.boardClaimed },
                        set: { model.claimBoard($0) }
                    )) { providers, point in
                        BuilderDrop.read(providers) { key in
                            model.drop([key], at: geometry.cell(near: point), dataset: dataset)
                        }
                        model.endDrag()
                        return true
                    }

                ForEach(HexGeometry.allCells, id: \.self) { cell in
                    HexPlacement(x: cell.x, y: cell.y, geometry: geometry) {
                        BuilderHex(cell: cell, geometry: geometry, model: model, dataset: dataset)
                    }
                }
            }

            HStack(spacing: 10) {
                Label(L("App.builder.avgCost", Fmt.decimal(summary.average, digits: 2)), systemImage: "circle.hexagongrid.fill")
                Text("\(summary.spent) \(L("TeamBuilder.gold"))")
                Spacer()
                Text(hint(dataset: dataset, armed: model.boardArmed))
                    .foregroundStyle(model.boardArmed ? Theme.accentBright : Theme.textTertiary)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
    }

    /// While a piece is in the air the board is showing that piece's odds on every hex, so the
    /// line under it names the piece instead of repeating how to drag.
    private func hint(dataset: TFTDataset, armed: Bool) -> String {
        if armed, let key = model.dragKey {
            return L("App.builder.dropHint", dataset.champion(key)?.n ?? L("App.builder.dropCancel"))
        }
        if let focused = model.focus { return dataset.champion(focused)?.n ?? "" }
        return L("App.builder.dragHint")
    }
}

/// `.onDrag` hands the drop a provider, not a value, and the read is asynchronous — so the cell
/// resolved at drop time travels into the callback with it rather than being re-derived later.
private enum BuilderDrop {
    static func read(_ providers: [NSItemProvider], _ body: @escaping (String) -> Void) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let key = object as? String else { return }
            DispatchQueue.main.async { body(key) }
        }
    }
}

private struct BuilderHex: View {
    let cell: Cell
    let geometry: HexGeometry
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        let key = model.units[cell]
        let armed = model.boardArmed
        let targeted = model.hoveredCell == cell
        // What the piece in the air would carry at this hex, printed exactly where its badge
        // lands: the board turns into a grid of odds before anything is committed.
        let ghost = key == nil && armed ? model.ghost(at: cell, dataset: dataset) : nil
        ZStack {
            Hexagon().fill(targeted ? Theme.accent.opacity(0.26)
                                    : (armed && key == nil ? Theme.accent.opacity(0.06) : Color.clear))
            if targeted, key == nil {
                Hexagon().stroke(Theme.accent.opacity(0.85),
                                 style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            }
            if let key {
                // One badge lookup per hex: the number is formatted, not just read.
                let badge = model.overlay(for: key, at: cell, dataset: dataset)
                HexUnit(geometry: geometry,
                        tile: dataset.champion(key)?.tile,
                        border: badge?.color ?? Theme.rarity(dataset.champion(key)?.cost),
                        emphasized: model.focus == key,
                        items: model.items[key] ?? [],
                        overlayLabel: badge?.text)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else if let ghost {
                Text(ghost.text)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(ghost.color)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 0.5)
                    .fixedSize()
                    .offset(y: (geometry.height - 5) / 2 - 10)
            }
        }
        .animation(.easeOut(duration: 0.16), value: targeted)
        .animation(.easeOut(duration: 0.16), value: armed)
        // A piece landing is the one moment the board should move; the hover states stay instant.
        .animation(.spring(duration: 0.32, bounce: 0.24), value: key)
        .frame(width: geometry.width - 4, height: geometry.height - 4)
        .contentShape(Hexagon())
        .onTapGesture { model.focus = key }
        .onLongPressGesture(minimumDuration: 0.35) {
            if let key { model.remove(key) }
        }
        .onDrag {
            if let key {
                model.beginDrag(key)
                return NSItemProvider(object: key as NSString)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.utf8PlainText], isTargeted: Binding(
            get: { targeted },
            set: { on in if on { model.hover(cell) } else { model.leave(cell) } }
        )) { providers, _ in
            BuilderDrop.read(providers) { model.drop([$0], at: cell, dataset: dataset) }
            model.endDrag()
            return true
        }
    }
}

// MARK: - Traits

private struct BuilderTraitPanel: View {
    let tallies: [TraitTally]
    let dataset: TFTDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("TeamBuilder.synergy"), detail: tallies.isEmpty ? nil : L("App.builder.activeCount", tallies.filter { $0.active != nil }.count))
            if tallies.isEmpty {
                Text(L("App.builder.emptyTrait"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(tallies, id: \.key) { tally in
                        BuilderTraitCell(tally: tally, dataset: dataset)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct BuilderTraitCell: View {
    let tally: TraitTally
    let dataset: TFTDataset

    var body: some View {
        let ref = dataset.trait(tally.key)
        HStack(spacing: 7) {
            RemoteImage(url: ref?.icon, contentMode: .fit)
                .frame(width: 20, height: 20)
            Text(ref?.n ?? tally.key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tally.active != nil ? Theme.textPrimary : Theme.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(tally.tiers.prefix(3), id: \.min) { tier in
                    Text("\(tier.min)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(tally.count >= tier.min ? .white : Theme.textTertiary)
                        .frame(width: 15, height: 15)
                        .background(tally.count >= tier.min ? Theme.accent : Theme.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text("\(tally.count)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 12)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
    }
}

// MARK: - Roster and cores

private struct BuilderRosterPanel: View {
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("TeamBuilder.coreChampionAndItem"),
                         detail: model.placed.isEmpty ? nil : "\(model.placed.count) \(L("App.builder.onBoard"))")
            if model.placed.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 8) {
                    ForEach(model.placed) { slot in
                        BuilderRosterRow(cell: slot.cell, key: slot.key, model: model, dataset: dataset)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var emptyHint: some View {
        Text(L("App.builder.rosterHint"))
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

private struct BuilderRosterRow: View {
    let cell: Cell
    let key: String
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        let ref = dataset.champion(key)
        let held = model.items[key] ?? []
        HStack(spacing: 9) {
            RemoteImage(url: ref?.tile, contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.rarity(ref?.cost), lineWidth: 1.4))

            VStack(alignment: .leading, spacing: 2) {
                Text(ref?.n ?? key)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(L("App.builder.cellCost", cell.x, cell.y, ref?.cost ?? 0))
                    .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    BuilderItemSlot(item: index < held.count ? held[index] : nil,
                                    dataset: dataset,
                                    model: model,
                                    champion: key)
                }
            }

            Button {
                model.remove(key)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(PressStyle())
        }
        .padding(9)
        .background(model.focus == key ? Theme.surfaceRaised : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.focus = key }
        .animation(.easeOut(duration: 0.16), value: model.focus == key)
    }
}

private struct BuilderItemSlot: View {
    let item: String?
    let dataset: TFTDataset
    @ObservedObject var model: TeamBuilderModel
    let champion: String
    @State private var targeted = false

    var body: some View {
        ZStack {
            if let item {
                RemoteImage(url: dataset.item(item)?.icon, contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(targeted ? Theme.accent : Theme.separator,
                                  style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    .transition(.opacity)
            }
        }
        .frame(width: 28, height: 28)
        .background(targeted ? Theme.accent.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: targeted)
        .animation(.spring(duration: 0.26, bounce: 0.3), value: item)
        .contentShape(Rectangle())
        .onTapGesture { if let item { model.assign(item, to: champion) } }
        .onDrop(of: [.utf8PlainText], isTargeted: $targeted) { providers, _ in
            BuilderDrop.read(providers) { key in
                if dataset.item(key) != nil { model.assign(key, to: champion) }
            }
            model.endDrag()
            return true
        }
    }
}

private struct BuilderCoreSlots: View {
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("TeamBuilder.augment"), detail: "\(model.cores.compactMap { $0 }.count)/3")
            HStack(spacing: 8) {
                ForEach(Array(model.cores.enumerated()), id: \.offset) { _, core in
                    BuilderCoreSlot(key: core, dataset: dataset) {
                        if let key = core { model.toggleCore(key) }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

private struct BuilderCoreSlot: View {
    let key: String?
    let dataset: TFTDataset
    var onClear: () -> Void

    var body: some View {
        let ref = dataset.augment(key)
        let tier = Theme.augmentTier(ref?.tier)
        VStack(spacing: 5) {
            if let ref {
                RemoteImage(url: ref.icon, contentMode: .fit).frame(width: 34, height: 34)
                Text(ref.n)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: 34)
                Text(L("App.builder.selectCore")).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.26), value: key)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
            .strokeBorder(key == nil ? Theme.separator : tier.color.opacity(0.8), lineWidth: 1.4))
        .onTapGesture(perform: onClear)
    }
}

// MARK: - Actions

private struct BuilderActions: View {
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset
    var poster: () -> UIImage?
    @State private var share: ShareItems?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.clear()
            } label: {
                Label(L("TeamBuilder.clearBoard"), systemImage: "trash")
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(Color(hex: 0xE85D75))

            Button {
                guard let image = poster() else { return }
                share = ShareItems(items: [image,
                                           model.shareText(dataset: dataset),
                                           URL(string: OpGG.base + "/tft/tools/team-builder") as Any])
            } label: {
                Label(L("TeamBuilder.saveImage"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(Theme.accentBright)
        }
        .font(.system(size: 12.5, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .padding(.horizontal, Theme.gutter)
        .sheet(item: $share) { payload in
            ActivityView(items: payload.items).ignoresSafeArea()
        }
    }
}

// MARK: - Tray

private struct BuilderTray: View {
    @Binding var tab: BuilderTab
    @Binding var itemCategory: String
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.separator)
            UnderlineTabs(options: BuilderTab.allCases.map { ($0, $0.title) }, selection: $tab)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 6)

            if tab == .items {
                ChipRow(options: BuilderTray.itemCategories.map { ($0, Theme.itemCategory($0).label) },
                        selection: $itemCategory)
                    .padding(.top, 4)
            }

            content
                .frame(height: 196)
        }
        .background(Theme.surface)
        // One value on the container: the grids are lazy, and animating the swap per cell is
        // how stranded half-faded tiles used to appear.
        .animation(.easeOut(duration: 0.2), value: tab)
    }

    static let itemCategories = ["radiant", "artifact", "core", "emblem", "component"]

    @ViewBuilder private var content: some View {
        switch tab {
        case .champions: championGrid
        case .items: itemGrid
        case .augments: augmentGrid
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 68), spacing: 8)]
    }

    private var championGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(dataset.ref.champions.keys.sorted(), id: \.self) { key in
                    let ref = dataset.champion(key)
                    BuilderTrayCell(title: ref?.n ?? key,
                                    image: ref?.tile,
                                    fill: true,
                                    badge: ref?.cost.map(String.init),
                                    badgeColor: Theme.rarity(ref?.cost),
                                    border: Theme.rarity(ref?.cost),
                                    selected: model.units.values.contains(key))
                        .onTapGesture { model.autoPlace(key, dataset: dataset) }
                        // `.onDrag`'s closure runs the instant the piece lifts, which is the only
                        // moment the board can learn what is in the air and preview its odds there.
                        .onDrag {
                            model.beginDrag(key)
                            return NSItemProvider(object: key as NSString)
                        }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
        }
    }

    private var itemGrid: some View {
        let keys = dataset.ref.items.filter { $0.value.category == itemCategory }
            .keys.sorted { (dataset.item($0)?.n ?? $0) < (dataset.item($1)?.n ?? $1) }
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    BuilderTrayCell(title: dataset.item(key)?.n ?? key,
                                    image: dataset.item(key)?.icon,
                                    fill: false,
                                    badge: nil,
                                    badgeColor: Theme.surfaceSunken,
                                    border: Theme.itemCategory(itemCategory).color,
                                    selected: model.focus.map { (model.items[$0] ?? []).contains(key) } ?? false)
                        .onTapGesture { assign(key) }
                        .onDrag {
                            model.beginDrag(key)
                            return NSItemProvider(object: key as NSString)
                        }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
        }
    }

    /// Tapping an item loads the focused unit, falling back to the first champion on the board.
    private func assign(_ key: String) {
        guard dataset.item(key) != nil else { return }
        if let target = model.focus ?? model.placed.first?.key { model.assign(key, to: target) }
    }

    private var augmentGrid: some View {
        let order = ["prism", "gold", "silver"]
        let keys = dataset.ref.augments.keys
            .sorted {
                let l = order.firstIndex(of: dataset.augment($0)?.tier?.lowercased() ?? "") ?? 9
                let r = order.firstIndex(of: dataset.augment($1)?.tier?.lowercased() ?? "") ?? 9
                return l != r ? l < r : $0 < $1
            }
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    BuilderTrayCell(title: dataset.augment(key)?.n ?? key,
                                    image: dataset.augment(key)?.icon,
                                    fill: false,
                                    badge: nil,
                                    badgeColor: Theme.surfaceSunken,
                                    border: Theme.augmentTier(dataset.augment(key)?.tier).color,
                                    selected: model.cores.contains(key))
                        .onTapGesture { model.toggleCore(key) }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
        }
    }
}

private struct BuilderTrayCell: View {
    let title: String
    let image: String?
    let fill: Bool
    let badge: String?
    let badgeColor: Color
    let border: Color
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: image, contentMode: fill ? .fill : .fit)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selected ? Theme.accentBright : border, lineWidth: selected ? 2.2 : 1.3))
                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(badgeColor, in: Circle())
                        .offset(x: 4, y: 4)
                }
            }
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(selected ? Theme.accentBright : Theme.textSecondary)
                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

// MARK: - Shareable snapshot

private struct BuilderPoster: View {
    @ObservedObject var model: TeamBuilderModel
    let dataset: TFTDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OP.GG").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                Text(L("App.builder.shareFormat", dataset.meta.set, dataset.meta.version))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
            }

            HexBoard(width: 372, cap: 42) { geometry in
                ForEach(model.placed) { slot in
                    HexPlacement(x: slot.cell.x, y: slot.cell.y, geometry: geometry) {
                        HexUnit(geometry: geometry,
                                tile: dataset.champion(slot.key)?.tile,
                                border: Theme.rarity(dataset.champion(slot.key)?.cost),
                                items: model.items[slot.key] ?? [])
                    }
                }
            }

            let tallies = model.traitTallies(dataset: dataset).filter { $0.active != nil }
            Text(tallies.map { "\($0.count) \(dataset.trait($0.key)?.n ?? $0.key)" }.joined(separator: " · "))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            let taken = model.cores.compactMap { dataset.augment($0) }
            if !taken.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(taken.enumerated()), id: \.offset) { _, core in
                        HStack(spacing: 5) {
                            RemoteImage(url: core.icon, contentMode: .fit).frame(width: 22, height: 22)
                            Text(core.n).font(.system(size: 10)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                        }
                        .padding(6)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.background)
    }
}
