import SwiftUI

/// TFT arranges units on a 7×4 grid of pointy-top hexes. Even rows nest half a hex
/// to the right, and y=4 is the frontline nearest the midline — so it draws at the top.
struct HexGeometry {
    static let columns = 7
    static let rows = 4

    /// Every playable hex, frontline first.
    static let allCells: [Cell] = (1...rows).flatMap { y in (1...columns).map { Cell(x: $0, y: y) } }

    let width: CGFloat
    let boardWidth: CGFloat

    init(boardWidth: CGFloat, cap: CGFloat = 48) {
        self.boardWidth = boardWidth
        self.width = min(boardWidth / (CGFloat(Self.columns) + 0.5), cap)
    }

    var height: CGFloat { width * 2 / CGFloat(sqrt(3.0)) }
    var rowStep: CGFloat { height * 0.75 }
    var totalWidth: CGFloat { (CGFloat(Self.columns) + 0.5) * width }
    var totalHeight: CGFloat { rowStep * CGFloat(Self.rows - 1) + height }

    /// Centre of the hex at op.gg board coordinates (x 1…7, y 1…4).
    func center(x: Int, y: Int) -> CGPoint {
        let pad = max((boardWidth - totalWidth) / 2, 0)
        let shift = (y % 2 == 0) ? width / 2 : 0
        let row = CGFloat(Self.rows - max(min(y, Self.rows), 1))
        return CGPoint(x: pad + shift + CGFloat(max(min(x, Self.columns), 1) - 1) * width + width / 2,
                       y: row * rowStep + height / 2)
    }

    func center(_ cell: Cell) -> CGPoint { center(x: cell.x, y: cell.y) }

    /// The hex whose centre sits nearest a drop point. A drag released between two cells
    /// still has to land somewhere, and the nearest centre is what a reader would call it.
    func cell(near point: CGPoint) -> Cell {
        Self.allCells.min { a, b in
            squaredDistance(from: center(a), to: point) < squaredDistance(from: center(b), to: point)
        } ?? Cell(x: 4, y: 4)
    }

    /// The hex under a point measured in this board's own space, or nil once the point has
    /// left the board — a piece dragged back toward the tray must not highlight anything.
    func cell(covering point: CGPoint) -> Cell? {
        guard point.x >= 0, point.x <= boardWidth, point.y >= 0, point.y <= totalHeight else { return nil }
        return cell(near: point)
    }

    private func squaredDistance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    /// The builder board. Its card pads itself by 12, not the 10 `cardWidth()` assumes, so the
    /// board is measured here once and the hexes cannot spill past the card's own edges.
    static func builderBoard() -> HexGeometry {
        HexGeometry(boardWidth: cardWidth(padding: 12), cap: 42)
    }
}

/// Hexagon standing on its point, top and bottom.
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height / 4))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height / 4))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY + rect.height / 4))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY - rect.height / 4))
        p.closeSubpath()
        return p
    }
}

/// The empty grid the pieces sit on, front half of the board slightly brighter.
struct HexBoardGrid: View {
    let geometry: HexGeometry

    var body: some View {
        ForEach(1...HexGeometry.rows, id: \.self) { y in
            ForEach(1...HexGeometry.columns, id: \.self) { x in
                Hexagon()
                    .fill(y >= 3 ? Theme.surfaceRaised.opacity(0.5) : Theme.surfaceRaised.opacity(0.18))
                    .overlay(Hexagon().stroke(Theme.separator.opacity(0.5), lineWidth: 1))
                    .frame(width: geometry.width - 3, height: geometry.height - 3)
                    .position(geometry.center(x: x, y: y))
            }
        }
    }
}

/// A unit rendered inside its board hex: art, cost border, stars, items, priority.
struct HexUnit: View {
    let geometry: HexGeometry
    let tile: String?
    var border: Color = Theme.separator
    var emphasized = false
    var tier = 0
    var items: [String] = []
    var prio: Int?
    var overlayLabel: String?

    @EnvironmentObject private var repository: Repository

    var body: some View {
        let cellWidth = geometry.width - 5
        let cellHeight = geometry.height - 5
        ZStack {
            RemoteImage(url: tile, contentMode: .fill)
                .frame(width: cellWidth, height: cellHeight)
                .clipShape(Hexagon())
                .overlay(Hexagon()
                    .stroke(border, lineWidth: emphasized ? 2.4 : 1.6))

            if let overlayLabel {
                Text(overlayLabel)
                    // The playable hex is 37pt wide once the cap bites, and "48,04%" measures
                    // 34.6pt before any padding — it ellipsised inside its own capsule. One
                    // decimal is the most this cell can print without clipping.
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .fixedSize()
                    .background(border.opacity(0.95), in: Capsule())
                    .offset(y: cellHeight / 2 - 10)
            }

            VStack(alignment: .leading, spacing: 1) {
                if tier > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<min(tier, 3), id: \.self) { _ in
                            Image(systemName: "star.fill").font(.system(size: 5.5))
                        }
                    }
                    .foregroundStyle(Theme.gold)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                }
                if let prio {
                    Text("\(prio)")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 13, height: 13)
                        .background(Theme.gold, in: Circle())
                        .offset(x: 1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: cellWidth * 0.6, height: cellHeight, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            if !items.isEmpty {
                HStack(spacing: 1) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, key in
                        RemoteImage(url: repository.dataset.item(key)?.icon, contentMode: .fit)
                            .frame(width: 13, height: 13)
                    }
                }
                .padding(.horizontal, 3).padding(.vertical, 1.5)
                .background(Theme.surfaceSunken.opacity(0.92), in: Capsule())
                .offset(y: 3)
                .zIndex(100) // Items must float above every hex — rows below would otherwise clip them.
            }
        }
        .frame(width: cellWidth, height: cellHeight)
    }
}

/// Places content at the centre of one board hex.
struct HexPlacement<Content: View>: View {
    let x: Int
    let y: Int
    let geometry: HexGeometry
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().position(geometry.center(x: x, y: y))
    }
}

/// Whole board: grid + pieces. Width is explicit because a GeometryReader here
/// would stretch to whatever height the enclosing ScrollView offers.
struct HexBoard<Content: View>: View {
    let geometry: HexGeometry
    var content: (HexGeometry) -> Content

    init(width: CGFloat, cap: CGFloat = 48, @ViewBuilder content: @escaping (HexGeometry) -> Content) {
        self.init(geometry: HexGeometry(boardWidth: width, cap: cap), content: content)
    }

    init(geometry: HexGeometry, @ViewBuilder content: @escaping (HexGeometry) -> Content) {
        self.geometry = geometry
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HexBoardGrid(geometry: geometry)
            content(geometry)
        }
        .frame(width: geometry.boardWidth, height: geometry.totalHeight)
    }
}

extension HexGeometry {
    /// Board width inside a card that itself sits at `Theme.gutter` with 10pt of padding.
    static func cardWidth(padding: CGFloat = 10) -> CGFloat {
        min(UIScreen.main.bounds.width, 430) - Theme.gutter * 2 - padding * 2
    }
}
