import SwiftUI

/// Grid of every champion in the set, tappable to mark as owned. The selected set drives the
/// "playable with my champs" filter on the comps tab — a quick way to answer "what can I run
/// right now" without rebuilding the collection every session.
struct ChampionSelectorView: View {
    @EnvironmentObject private var repository: Repository
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(repository.dataset.champions.sorted(by: { ($0.winRate) > ($1.winRate) }), id: \.k) { stat in
                        if let champ = repository.dataset.champion(stat.k) {
                            ChampionTile(champ: champ, owned: repository.owns(stat.k)) {
                                repository.toggleOwnership(stat.k)
                            }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.background)
            .navigationTitle(L("App.championSelector.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("App.championSelector.clear")) {
                        repository.ownedChampions.removeAll()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("App.championSelector.done")) { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                }
            }
            .overlay(alignment: .bottom) {
                if !repository.ownedChampions.isEmpty {
                    Text(L("App.championSelector.count", Fmt.integer(repository.ownedChampions.count)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct ChampionTile: View {
    let champ: ChampionRef
    let owned: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    RemoteImage(url: champ.tile, contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.rarity(champ.cost), lineWidth: owned ? 2.5 : 1.5)
                        )
                        .opacity(owned ? 1 : 0.55)
                    if owned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.accentBright)
                            .background(Circle().fill(Theme.background))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(champ.n)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(owned ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(PressStyle())
    }
}
