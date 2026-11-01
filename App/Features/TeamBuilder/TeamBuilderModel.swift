import Foundation
import SwiftUI

enum BuilderOverlay: String, CaseIterable, Identifiable {
    case none, winRate, frequency

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return L("App.builder.board")
        case .winRate: return L("TeamBuilder.positionWinRate")
        case .frequency: return L("TeamBuilder.positionFrequency")
        }
    }
}

struct TraitTally {
    let key: String
    let count: Int
    let tiers: [TraitTier]

    var active: TraitTier? { tiers.last { $0.min <= count } }
    var next: TraitTier? { tiers.first { $0.min > count } }
}

struct PlacedUnit: Identifiable, Hashable {
    let cell: Cell
    let key: String
    var id: String { key }
}

/// The scratch deck: who stands where, what they hold, which cores were taken.
@MainActor
final class TeamBuilderModel: ObservableObject {
    @Published private(set) var units: [Cell: String] = [:] { didSet { persist() } }
    @Published var items: [String: [String]] = [:] { didSet { persist() } }
    @Published var cores: [String?] = [nil, nil, nil] { didSet { persist() } }
    /// Every placed piece wears its number by default — the board reads as a set of odds the
    /// moment something lands, and the segmented control above switches which odds.
    @Published var overlay: BuilderOverlay = .winRate
    @Published var focus: String?
    /// The key currently in the air. `.onDrag`'s action closure is the one place that learns
    /// which tray cell started the drag, and the board needs it to print that champion's odds
    /// on every hex before it is ever placed.
    @Published private(set) var dragKey: String?
    /// The hex a drag is hovering, and whether the board as a whole claims the drag. Either
    /// signal alone can miss, depending on which drop target UIKit decides to aim.
    @Published private(set) var hoveredCell: Cell?
    @Published private(set) var boardClaimed = false

    static let maxUnits = 10
    private static let storeKey = "team.builder.v1"

    private struct Snapshot: Codable {
        var cells: [String: String]
        var items: [String: [String]]
        var cores: [String?]
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let saved = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        var restored: [Cell: String] = [:]
        for (raw, key) in saved.cells where raw.contains("-") {
            let parts = raw.split(separator: "-")
            guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { continue }
            restored[Cell(x: x, y: y)] = key
        }
        units = restored
        items = saved.items
        cores = saved.cores.count == 3 ? saved.cores : [nil, nil, nil]
    }

    private func persist() {
        var cells: [String: String] = [:]
        for (cell, key) in units { cells["\(cell.x)-\(cell.y)"] = key }
        let snapshot = Snapshot(cells: cells, items: items, cores: cores)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    // MARK: - Board

    /// Front row to back, left to right — the reading order of every roster list.
    var placed: [PlacedUnit] {
        units.sorted { $0.key.y != $1.key.y ? $0.key.y > $1.key.y : $0.key.x < $1.key.x }
            .map { PlacedUnit(cell: $0.key, key: $0.value) }
    }

    func place(_ key: String, at cell: Cell, dataset: TFTDataset) {
        guard dataset.champion(key) != nil, units[cell] != key else { return }
        var next = units
        let source = next.first { $0.value == key }?.key
        let occupant = next[cell]
        if source == nil, occupant == nil, next.count >= Self.maxUnits { return }

        if let source {
            next[source] = occupant
        } else if let occupant {
            items[occupant] = nil
        }
        next[cell] = key
        units = next
        focus = key
        Haptics.medium()
    }

    func remove(_ key: String) {
        units = units.filter { $0.value != key }
        items[key] = nil
        if focus == key { focus = nil }
        Haptics.light()
    }

    func clear() {
        units = [:]
        items = [:]
        cores = [nil, nil, nil]
        focus = nil
    }

    /// Melee take the frontline, carries tuck behind — the same fill order op.gg uses.
    func autoPlace(_ key: String, dataset: TFTDataset) {
        let role = dataset.champion(key)?.role ?? ""
        let frontline = ["Tank", "Fighter", "Bruiser", "Warden", "Vanguard"].contains { role.contains($0) }
        let order = frontline ? Self.frontOrder : Self.backOrder
        guard let cell = order.first(where: { units[$0] == nil }) else { return }
        place(key, at: cell, dataset: dataset)
    }

    private static let frontOrder = [Cell(x: 4, y: 4), Cell(x: 3, y: 4), Cell(x: 5, y: 4),
                                     Cell(x: 4, y: 3), Cell(x: 3, y: 3), Cell(x: 5, y: 3),
                                     Cell(x: 2, y: 4), Cell(x: 6, y: 4), Cell(x: 2, y: 3),
                                     Cell(x: 6, y: 3), Cell(x: 1, y: 4), Cell(x: 7, y: 4)]

    private static let backOrder = [Cell(x: 4, y: 1), Cell(x: 3, y: 1), Cell(x: 5, y: 1),
                                    Cell(x: 4, y: 2), Cell(x: 3, y: 2), Cell(x: 5, y: 2),
                                    Cell(x: 2, y: 1), Cell(x: 6, y: 1), Cell(x: 2, y: 2),
                                    Cell(x: 6, y: 2), Cell(x: 1, y: 1), Cell(x: 7, y: 1), Cell(x: 7, y: 2)]

    /// One drop target, two jobs: champion keys fill the board, item keys load the unit.
    @discardableResult
    func drop(_ payload: [String], at cell: Cell, dataset: TFTDataset) -> Bool {
        guard let key = payload.first else { return false }
        if dataset.champion(key) != nil {
            place(key, at: cell, dataset: dataset)
            return true
        }
        if dataset.item(key) != nil, let resident = units[cell] {
            assign(key, to: resident)
            return true
        }
        return false
    }

    // MARK: - Drag

    /// `.onDrag`'s action closure is the only place that knows which tray cell lifted off, so
    /// the board learns the piece before it lands and can print its odds on every hex.
    func beginDrag(_ key: String) {
        if dragKey != key { dragKey = key }
    }

    func endDrag() {
        dragKey = nil
        hoveredCell = nil
        boardClaimed = false
    }

    /// A drop target reporting itself is worth one publish per crossing, not one per frame:
    /// writing the same cell again would redraw all twenty-eight hexes at drag speed.
    func hover(_ cell: Cell) {
        if hoveredCell != cell { hoveredCell = cell }
        if !boardClaimed { boardClaimed = true }
    }

    func leave(_ cell: Cell) {
        if hoveredCell == cell { hoveredCell = nil }
    }

    func claimBoard(_ claimed: Bool) {
        if boardClaimed != claimed { boardClaimed = claimed }
    }

    /// While this is true the board is a preview: the hexes are showing what a drop would do.
    var boardArmed: Bool { dragKey != nil && (boardClaimed || hoveredCell != nil) }

    /// What an unplaced piece would wear at this hex — the same reading as a placed badge, so
    /// a drag turns the whole board into a grid of odds rather than one hint under the finger.
    func ghost(at cell: Cell, dataset: TFTDataset) -> (text: String, color: Color)? {
        guard let key = dragKey, dataset.champion(key) != nil else { return nil }
        return overlay(for: key, at: cell, dataset: dataset)
    }

    // MARK: - Items and cores

    func assign(_ item: String, to champion: String) {
        var list = items[champion] ?? []
        if list.contains(item) {
            list.removeAll { $0 == item }
        } else {
            guard list.count < 3 else { return }
            list.append(item)
        }
        items[champion] = list.isEmpty ? nil : list
        focus = champion
        Haptics.light()
    }

    func toggleCore(_ key: String) {
        if let index = cores.firstIndex(where: { $0 == key }) {
            cores[index] = nil
        } else if let slot = cores.firstIndex(of: nil) {
            cores[slot] = key
        }
        Haptics.medium()
    }

    // MARK: - Derived

    func traitTallies(dataset: TFTDataset) -> [TraitTally] {
        var counts: [String: Int] = [:]
        for key in units.values {
            for trait in dataset.champion(key)?.traits ?? [] { counts[trait, default: 0] += 1 }
        }
        return counts
            .map { TraitTally(key: $0.key, count: $0.value,
                              tiers: (dataset.trait($0.key)?.tiers ?? []).sorted { $0.min < $1.min }) }
            .sorted { lhs, rhs in
                if (lhs.active != nil) != (rhs.active != nil) { return lhs.active != nil }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return (dataset.trait(lhs.key)?.n ?? "") < (dataset.trait(rhs.key)?.n ?? "")
            }
    }

    func costSummary(dataset: TFTDataset) -> (count: Int, average: Double, spent: Int) {
        let costs = units.values.compactMap { dataset.champion($0)?.cost }
        let total = costs.reduce(0, +)
        return (costs.count, costs.isEmpty ? 0 : Double(total) / Double(costs.count), total)
    }

    /// Per-hex badge. op.gg measures a champion one cell at a time, so the same unit carries a
    /// different number at the tip of the front row than in the back corner; cells with no
    /// sample fall back to the champion's overall rate rather than showing nothing.
    ///
    /// One decimal: the hex itself is 37pt across and "48,04%" needs 34.6pt before the capsule's
    /// padding, so two ellipsised inside their own badge.
    func overlay(for key: String, at cell: Cell, dataset: TFTDataset) -> (text: String, color: Color)? {
        switch overlay {
        case .none: return nil
        case .winRate:
            let rate = Repository.shared.positions.stat(champion: key, at: cell)?.winRate
                ?? dataset.stat(forChampion: key)?.winRate
            guard let rate else { return nil }
            let color = rate >= 0.5 ? Color(hex: 0x39B57A) : rate >= 0.42 ? Theme.gold : Color(hex: 0xE85D75)
            return (Fmt.percent(rate, digits: 1), color)
        case .frequency:
            if let share = Repository.shared.positions.stat(champion: key, at: cell)?.frequency {
                return (Fmt.percent(share, digits: 1), Theme.accent)
            }
            guard let stat = dataset.stat(forChampion: key),
                  let games = dataset.meta.totalGames, games > 0 else { return nil }
            return (Fmt.percent(Double(stat.total) / Double(games), digits: 1), Theme.accent)
        }
    }

    func shareText(dataset: TFTDataset) -> String {
        let roster = placed.map { dataset.champion($0.key)?.n ?? $0.key }.joined(separator: ", ")
        let taken = cores.compactMap { dataset.augment($0)?.n }
        var lines = [L("App.builder.shareFormat", dataset.meta.set, dataset.meta.version), roster]
        if !taken.isEmpty { lines.append(L("App.builder.coresLabel") + taken.joined(separator: " · ")) }
        return lines.joined(separator: "\n")
    }
}
