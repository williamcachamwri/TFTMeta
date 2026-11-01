import SwiftUI
import UIKit

// MARK: - Image loading

/// Small in-memory + URLCache-backed loader so list scrolling never re-downloads art.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private var pending: [NSString: [(UIImage?) -> Void]] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 24_000_000, diskCapacity: 120_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": "TFTMeta/1.0"]
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url.absoluteString as NSString) }

    func request(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { completion(hit); return }
        if pending[key] != nil { pending[key]?.append(completion); return }
        pending[key] = [completion]

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        Task { [weak self] in
            guard let self else { return }
            let data = try? await self.session.data(for: request).0
            let loaded = data.flatMap(UIImage.init)
            if let loaded { self.memory.setObject(loaded, forKey: key, cost: loaded.size.cost) }
            let callbacks = self.pending[key] ?? []
            self.pending[key] = nil
            callbacks.forEach { $0(loaded) }
        }
    }

    /// Preload an image without a callback — used when a row is about to appear so the art
    /// is already in memory by the time RemoteImage asks for it.
    func prefetch(_ url: URL) {
        let key = url.absoluteString as NSString
        if memory.object(forKey: key) != nil || pending[key] != nil { return }
        pending[key] = []
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        Task { [weak self] in
            guard let self else { return }
            let data = try? await self.session.data(for: request).0
            if let loaded = data.flatMap(UIImage.init) {
                self.memory.setObject(loaded, forKey: key, cost: loaded.size.cost)
            }
            self.pending[key] = nil
        }
    }
}

private extension CGSize {
    var cost: Int { max(1, Int(width * height * 4)) }
}

struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fit
    var tintFallback: Color = Theme.surfaceRaised

    @State private var image: UIImage?

    var body: some View {
        // A .fill image reports a layout size larger than the proposal it was given, which
        // widens whole columns. GeometryReader pins us to the proposed size and the clip
        // happens at that exact boundary.
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                } else {
                    Rectangle().fill(tintFallback.opacity(0.5))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
        // Art arriving over a network should fade in rather than pop into an otherwise
        // settled page. Scoped to this cell, so scrolling itself stays untouched.
        .animation(.easeOut(duration: 0.22), value: image == nil)
        .onAppear(perform: load)
        .onChange(of: url) { _, _ in image = nil; load() }
    }

    private func load() {
        guard image == nil, let string = url, let parsed = URL(string: string) else { return }
        if let hit = ImageStore.shared.cached(parsed) { image = hit; return }
        ImageStore.shared.request(parsed) { loaded in
            if let loaded { image = loaded }
        }
    }
}

/// View modifier that prefetches an image URL when the view is about to appear — call it
/// on a row that's one or two positions ahead of the visible area so the art lands before
/// the user scrolls to it.
struct PrefetchImage: ViewModifier {
    let url: String?

    func body(content: Content) -> some View {
        content.onAppear {
            guard let string = url, let parsed = URL(string: string) else { return }
            ImageStore.shared.prefetch(parsed)
        }
    }
}

extension View {
    func prefetchImage(_ url: String?) -> some View {
        modifier(PrefetchImage(url: url))
    }
}


/// Vertical scroll column whose width is pinned to the viewport. A single row that asks
/// for more than the screen would otherwise widen the column and slide the whole page
/// sideways, which is how the detail screens looked clipped on both edges.
struct ColumnScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                content()
                    .frame(width: proxy.size.width)
            }
        }
    }
}


// MARK: - Building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.textSecondary
    var filled = false
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .foregroundStyle(filled ? Color.black.opacity(0.85) : color)
        .background(filled ? color : color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// "#1" style rank marker used throughout the reference list rows.
struct RankLabel: View {
    let rank: Int
    var emphasized = false

    var body: some View {
        Text("#\(rank)")
            .font(.system(size: emphasized ? 15 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(rank <= 3 ? medal : Theme.textSecondary)
    }

    private var medal: Color {
        switch rank { case 1: return Theme.gold; case 2: return Theme.silver; default: return Theme.bronze }
    }
}

/// Big value + small unit, exactly the "3.418 LP" lockup from the reference.
struct MetricValue: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded))
            Text(unit).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Theme.textPrimary)
    }
}

/// Label above value — the "Vị trí trung bình / Top 1 / Tỉ lệ top 4" column style.
struct StatColumn: View {
    let title: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Underline segmented control mirroring "Bậc / Tướng / Cấp độ".
struct UnderlineTabs<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T
    var onPick: ((T) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(options, id: \.value) { option in
                        Button {
                            selection = option.value
                            onPick?(option.value)
                            withAnimation(.snappy) { proxy.scrollTo(option.value, anchor: .center) }
                        } label: {
                            VStack(spacing: 10) {
                                Text(option.title)
                                    .font(.system(size: 14, weight: selection == option.value ? .bold : .semibold))
                                    .foregroundStyle(selection == option.value ? Theme.textPrimary : Theme.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 12)
                                Rectangle()
                                    .fill(selection == option.value ? Theme.textPrimary : .clear)
                                    .frame(height: 3)
                                    .padding(.horizontal, 14)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .id(option.value)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .onAppear {
                withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .animation(.snappy(duration: 0.28), value: selection)
    }
}

/// Which filter pill currently owns the screen. The dropdown hangs out of the pill as an
/// overlay, and inside a ScrollView the only thing that reorders drawing is sibling `zIndex`,
/// so the rows underneath have to be told to step aside — hence shared state rather than a
/// private `@State` per pill.
final class DropdownGate: ObservableObject {
    static let shared = DropdownGate()
    @Published var openID: AnyHashable?

    private init() {}

    var isOpen: Bool { openID != nil }

    func toggle(_ id: AnyHashable) {
        withAnimation(.snappy) { openID = openID == id ? nil : id }
    }

    func close() {
        guard isOpen else { return }
        withAnimation(.snappy) { openID = nil }
    }
}

/// Row of filter controls, lifted while one of its pills is open.
struct FilterBar<Content: View>: View {
    @ObservedObject private var gate = DropdownGate.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10, content: content)
            .zIndex(gate.isOpen ? 100 : 0)
    }
}

/// Pill filter selector with an inline dropdown. A `.popover` here renders an
/// empty chrome panel on iOS, and a nested `Menu` cannot be styled, so the list
/// is drawn as an overlay hanging under the pill.
struct FilterPill<T: Hashable>: View {
    let title: String
    let options: [(value: T, title: String)]
    @Binding var selection: T
    var menuID: AnyHashable?
    @ObservedObject private var gate = DropdownGate.shared

    var body: some View {
        let identity = menuID ?? AnyHashable(title)
        let open = gate.openID == identity
        Button { gate.toggle(identity) } label: {
            HStack(spacing: 8) {
                Text(current).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    // Long names must truncate, never push the rest of the filter row off screen.
                    .frame(maxWidth: 132)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 12)
            // Fixed height so a pill always sits level with the icon button beside it,
            // whatever the option label measures.
            .frame(height: 36)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .background {
            // Catcher sized to swallow the whole screen: a background view is allowed to be
            // larger than the view it sits behind, and `ignoresSafeArea` alone would only
            // stretch it a few points past the pill.
            if open {
                Color.black.opacity(0.001)
                    .frame(width: UIScreen.main.bounds.width * 3, height: UIScreen.main.bounds.height * 3)
                    .contentShape(Rectangle())
                    .onTapGesture { gate.close() }
            }
        }
        .overlay(alignment: .topLeading) {
            if open {
                list
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.top) { $0[.bottom] + 6 }
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading)))
            }
        }
        .zIndex(open ? 20 : 0)
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection = option.value
                        gate.close()
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title)
                                .font(.system(size: 13, weight: option.value == selection ? .bold : .medium))
                                .foregroundStyle(option.value == selection ? Theme.accentBright : Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if option.value == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(option.value == selection ? Theme.accent.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(5)
        }
        .frame(width: 224)
        .frame(maxHeight: 262)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.separator.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    private var current: String {
        options.first(where: { $0.value == selection })?.title ?? title
    }
}

/// Horizontally scrolling chip row used for sort + secondary filters.
struct ChipRow<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T
    var leading: AnyView?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                leading
                ForEach(options, id: \.value) { option in
                    Button {
                        selection = option.value
                    } label: {
                        Text(option.title)
                            .font(.system(size: 13, weight: selection == option.value ? .bold : .semibold))
                            .foregroundStyle(selection == option.value ? .white : Theme.textSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background {
                                if selection == option.value {
                                    Capsule().fill(Theme.accent)
                                } else {
                                    Capsule().fill(Theme.surface)
                                }
                            }
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

struct SectionTitle: View {
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Thin proportional bar for win/top4/pick rates.
struct MeterBar: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSunken)
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        // Scoped here, not on the enclosing list: switching a season filter re-values every bar
        // and the growth reads as the data landing rather than the page reloading.
        .animation(.easeOut(duration: 0.32), value: fraction)
    }
}

/// Inline error banner with a retry affordance — network, missing page, bad query.
struct FailureCard: View {
    let text: String
    var systemImage = "wifi.exclamationmark"
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.gold)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("ErrorPage.retry"), action: retry)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentBright)
        }
        .padding(12)
        .background(Theme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

/// Every tappable card answers a press. `.plain` strips iOS's own highlight, which leaves a
/// dark-on-dark list with no feedback at all; a short dip in scale and brightness is the
/// lightest thing that still reads as "the app felt that".
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.light() }
            }
    }
}

/// A pushed page lifts into place once instead of arriving at full opacity mid-slide. Same curve
/// as the boot dissolve, so the navigation stack and the first screen read as one motion.
struct PageReveal: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)) { shown = true }
            }
    }
}

extension View {
    /// Reads better at the call sites than `modifier(PageReveal())`.
    func pageReveal() -> some View { modifier(PageReveal()) }
}

/// System share sheet, used by the team builder's image export.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Chips that wrap onto new lines. The reference never scrolls a game's synergy list — it
/// flows it across two rows — and a `LazyVGrid` would stretch every pill to the widest one.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { total, row in total + row.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let limit = proposal.width ?? .infinity
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            // A second chip on an empty row is allowed to overflow; one alone never wraps.
            if !row.indices.isEmpty, row.width + spacing + size.width > limit {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
