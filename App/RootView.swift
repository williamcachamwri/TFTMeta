import Combine
import SwiftUI

@main
struct TFTMetaApp: App {
    @StateObject private var repository = Repository.shared
    @StateObject private var balance = BalanceStore.shared
    @StateObject private var summoners = SummonerStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(repository)
                .environmentObject(balance)
                .environmentObject(summoners)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Section: Int, CaseIterable, Identifiable {
    case comps, champions, items, traits, augments

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .comps: return L("MetaTrends.comps")
        case .champions: return L("MetaTrends.champion")
        case .items: return L("MetaTrends.item")
        case .traits: return L("MetaTrends.synergy")
        case .augments: return L("App.tab.augments")
        }
    }
    var icon: String {
        switch self {
        case .comps: return "square.stack.3d.up.fill"
        case .champions: return "person.fill"
        case .items: return "hammer.fill"
        case .traits: return "point.3.connected.trianglepath.dotted"
        case .augments: return "sparkles.rectangle.stack.fill"
        }
    }
    var tagline: String {
        switch self {
        case .comps: return L("App.tagline.comps")
        case .champions: return L("HomeContent.championTierList")
        case .items: return L("App.tagline.items")
        case .traits: return L("App.tagline.traits")
        case .augments: return L("App.tagline.augments")
        }
    }
}

/// The stack is what keeps every NavigationLink enabled — a link with no navigation
/// ancestor renders permanently greyed out and swallows its taps.
struct RootView: View {
    @EnvironmentObject private var repository: Repository
    @State private var section: Section = .comps
    @State private var booted = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()

                Group {
                    switch section {
                    case .comps: CompsView()
                    case .champions: ChampionsView()
                    case .items: ItemsView()
                    case .traits: TraitsView()
                    case .augments: AugmentsView()
                    }
                }
                .id(section)
                // A page swap dissolves the container only. Per-row fades over a lazily built
                // list are what left rows stranded mid-opacity before; the whole page shares
                // one value, so nothing can be caught halfway.
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: section)
                // Same container-scoped trick: a language swap retitles everything at once, and
                // the layout settling is the only motion it needs.
                .animation(.easeOut(duration: 0.22), value: repository.language)
                .opacity(booted ? 1 : 0)
                .offset(y: booted ? 0 : 8)
                // An invisible view still takes taps; the boot surface only covers part of it.
                .allowsHitTesting(booted)

                if !booted {
                    BootSurface(title: section.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Theme.background.ignoresSafeArea())
                        .transition(.opacity)
                }

                // Declared after the boot surface so the dock survives the hand-off: it is the
                // one piece of chrome that never changes, which is what makes the dissolve read
                // as the page filling in rather than a screen being replaced.
                FloatingTabBar(selection: $section)
            }
        }
        .task {
            // Unstructured so the fetch outlives the boot gate and still lands the update.
            let load = Task { await repository.refresh() }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await Task.sleep(for: .seconds(0.7)) }
                group.addTask { _ = await load.value }
                _ = await group.next()
                group.cancelAll()
            }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)) { booted = true }
        }
    }
}

/// The boot screen is the page it turns into — same brand row, same vertical rhythm, every
/// slot drawn as the block that will resolve into content. A splash logo that cuts to a
/// finished page reads as two different apps; a page filling itself in reads as one, and the
/// hand-off is a straight cross-dissolve between two identical layouts.
private struct BootSurface: View {
    let title: String
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(title: title)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 22) {
                    bar(78, 15)
                    bar(64, 15)
                    bar(52, 15)
                    bar(58, 15)
                }
                .frame(height: 31)
                .padding(.top, 4)

                bar(214, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in fill(35, Theme.radiusChip) }
                }
                .padding(.top, 12)

                HStack(spacing: 10) {
                    bar(96, 36, Theme.radiusChip)
                    bar(96, 36, Theme.radiusChip)
                    Spacer()
                    bar(38, 36, Theme.radiusChip)
                }
                .padding(.top, 12)

                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in fill(78, Theme.radiusCard, strong: true) }
                }
                .padding(.top, 12)
            }
            .opacity(dimmed ? 0.55 : 1)
            .padding(.horizontal, Theme.gutter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("App.boot.loading"))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dimmed = true }
        }
    }

    private func bar(_ width: CGFloat, _ height: CGFloat, _ corner: CGFloat = 5) -> some View {
        block(width: width, height: height, corner: corner, strong: false)
    }

    private func fill(_ height: CGFloat, _ corner: CGFloat, strong: Bool = false) -> some View {
        block(width: nil, height: height, corner: corner, strong: strong)
    }

    private func block(width: CGFloat?, height: CGFloat, corner: CGFloat, strong: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(strong ? Theme.surface : Theme.surfaceRaised.opacity(0.7))
        return Group {
            if let width {
                shape.frame(width: width, height: height)
            } else {
                shape.frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            }
        }
    }
}

/// Blurred capsule dock lifted from the reference's bottom navigation.
struct FloatingTabBar: View {
    @EnvironmentObject private var repository: Repository
    @Binding var selection: Section
    @Namespace private var pill

    var body: some View {
        // Touch repository.language so the tab labels re-render on a language switch.
        // The titles come from L(), which reads AppLanguage.current, but SwiftUI only
        // re-evaluates the body when an observed property it actually reads changes.
        let _ = repository.language
        HStack(spacing: 2) {
            ForEach(Section.allCases) { section in
                Button {
                    Haptics.selection()
                    selection = section
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(section.title)
                            .font(.system(size: 10, weight: selection == section ? .bold : .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == section ? Theme.accentBright : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selection == section {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(section.title)
            }
        }
        // The slide belongs to the dock alone; wrapping the tab change in a transaction
        // would animate the page content underneath it too.
        .animation(.snappy, value: selection)
        .fixedSize(horizontal: false, vertical: true)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

/// Shared page chrome: brand row, underline tabs slot, filter slot, list content.
struct ScreenScaffold<Tabs: View, Filters: View, Content: View>: View {
    @EnvironmentObject private var repository: Repository
    @ObservedObject private var dropdown = DropdownGate.shared
    let title: String
    var subtitle: String?
    var tabs: () -> Tabs
    var filters: () -> Filters
    var content: () -> Content

    init(title: String, subtitle: String? = nil,
         @ViewBuilder tabs: @escaping () -> Tabs,
         @ViewBuilder filters: @escaping () -> Filters,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tabs = tabs
        self.filters = filters
        self.content = content
    }

    var body: some View {
        CustomRefreshable {
            VStack(spacing: 0) {
                BrandHeader(title: title, subtitle: subtitle)

                tabs()
                    .padding(.top, 4)

                MetaLine()
                    .padding(.top, 14)

                ToolStrip()
                    .padding(.top, 12)

                filters()
                    .padding(.top, 12)
                    // An open dropdown is an overlay of its pill, so the whole filter block
                    // has to outrank the list below it or the rows paint straight over it.
                    .zIndex(dropdown.isOpen ? 100 : 0)

                content()
                    .padding(.top, 12)

                Color.clear.frame(height: 120)
            }
        } action: {
            await repository.refresh()
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { dropdown.close() }
    }
}

struct BrandHeader: View {
    @EnvironmentObject private var repository: Repository
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("OP.GG")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Rectangle().fill(Theme.separator).frame(width: 1, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                LanguageMenu()
                Text(L("App.season", repository.dataset.meta.set))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.gold.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }
}

/// The header's language switch, in the shape op.gg gives its own menu: endonyms only, the
/// saved language carrying the tick.
///
/// The whole data layer rides the choice — bundled dataset, live pages, server actions, number
/// and date grouping — so it is one mutation on `Repository` and everything else follows.
private struct LanguageMenu: View {
    @EnvironmentObject private var repository: Repository

    var body: some View {
        Menu {
            Picker(L("App.language.favorite"), selection: $repository.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text(repository.language.chip.uppercased())
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("App.language.change"))
        .accessibilityValue(repository.language.title)
    }
}

struct MetaLine: View {
    @EnvironmentObject private var repository: Repository

    var body: some View {
        let meta = repository.dataset.meta
        let games = Fmt.integer(meta.totalGames)
        let cohort = LSplit("MetaTrendsComps.lastHourWithGames",
                            ["games": games, "hour": String(meta.windowHours ?? 24)],
                            emphasising: games)
        HStack(spacing: 6) {
            Circle()
                .fill(repository.origin == .live ? Color(hex: 0x39B57A) : Theme.textTertiary)
                .frame(width: 6, height: 6)
            (
                Text(cohort.head)
                + Text(cohort.value).foregroundColor(Theme.textPrimary).fontWeight(.bold)
                + Text(cohort.tail + " · " + L("App.patch", meta.version))
            )
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 2)
    }
}

/// Entry points for the tools that live outside the five meta tabs.
struct ToolStrip: View {
    @EnvironmentObject private var repository: Repository

    var body: some View {
        // Force re-render on language switch so the tool button labels update.
        let _ = repository.language
        HStack(spacing: 8) {
            ToolButton(title: L("App.tool.teamBuilder"), systemImage: "square.grid.3x3.fill", tint: Theme.accentBright) {
                TeamBuilderView()
            }
            ToolButton(title: L("App.tool.buffNerf"), systemImage: "arrow.up.arrow.down", tint: Theme.gold) {
                BuffNerfView()
            }
            ToolButton(title: L("App.tool.summoner"), systemImage: "person.crop.circle.badge.magnifyingglass", tint: Color(hex: 0x57C7E3)) {
                SummonerSearchView()
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct ToolButton<Destination: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(PressStyle())
    }
}
