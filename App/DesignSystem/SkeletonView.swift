import SwiftUI

/// Shimmering placeholder that matches the layout of content about to load.
/// The gradient sweeps left-to-right in a loop, giving the eye something to track
/// while the data arrives — a blank card feels broken, a shimmering one feels alive.
struct SkeletonView: View {
    enum Style {
        case text(width: CGFloat? = nil, height: CGFloat = 12)
        case circle(size: CGFloat)
        case rectangle(width: CGFloat? = nil, height: CGFloat)
        case rounded(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8)
    }

    let style: Style
    @State private var phase: CGFloat = -1

    private var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Theme.surfaceRaised, location: 0),
                .init(color: Theme.surfaceRaised.opacity(0.5), location: 0.35),
                .init(color: Theme.surfaceRaised, location: 0.5),
                .init(color: Theme.surfaceRaised.opacity(0.5), location: 0.65),
                .init(color: Theme.surfaceRaised, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        Group {
            switch style {
            case .text(let width, let height):
                let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                skeletonShape(shape, width: width, height: height)
            case .circle(let size):
                let shape = Circle()
                skeletonShape(shape, width: size, height: size)
            case .rectangle(let width, let height):
                let shape = Rectangle()
                skeletonShape(shape, width: width, height: height)
            case .rounded(let width, let height, let radius):
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                skeletonShape(shape, width: width, height: height)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }

    private func skeletonShape<S: Shape>(_ shape: S, width: CGFloat?, height: CGFloat?) -> some View {
        shape
            .fill(gradient)
            .mask(shape.fill(LinearGradient(
                stops: [
                    .init(color: .clear, location: max(phase - 0.3, 0)),
                    .init(color: .black, location: phase),
                    .init(color: .clear, location: min(phase + 0.3, 1)),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )))
            .background(shape.fill(Theme.surfaceRaised))
            .frame(width: width, height: height)
    }
}

/// A single row in a list skeleton: icon + two lines of text.
struct SkeletonListRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView(style: .circle(size: 44))
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView(style: .text(width: 140, height: 14))
                SkeletonView(style: .text(width: 90, height: 10))
            }
            Spacer()
            SkeletonView(style: .text(width: 50, height: 16))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
    }
}

/// Card-shaped skeleton for grid layouts.
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView(style: .rounded(height: 100, cornerRadius: 12))
            SkeletonView(style: .text(width: 120, height: 12))
            SkeletonView(style: .text(width: 80, height: 10))
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

/// Full-screen skeleton for list-based views (Comps, Champions, Items, etc.).
struct SkeletonListView: View {
    var rows: Int = 8

    var body: some View {
        VStack(spacing: 0) {
            // Header area
            HStack(spacing: 12) {
                SkeletonView(style: .text(width: 100, height: 20))
                Spacer()
                SkeletonView(style: .rounded(width: 60, height: 28, cornerRadius: 14))
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonView(style: .rounded(width: 70, height: 28, cornerRadius: 14))
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 8)

            // List rows
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { index in
                    SkeletonListRow()
                    if index < rows - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
        }
    }
}

/// Grid-based skeleton for card layouts.
struct SkeletonGridView: View {
    var columns: Int = 2
    var rows: Int = 4

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SkeletonView(style: .text(width: 140, height: 20))
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)

            LazyVGrid(columns: gridItems, spacing: 12) {
                ForEach(0..<(columns * rows), id: \.self) { _ in
                    SkeletonCard()
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}
