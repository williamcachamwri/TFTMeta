import SwiftUI

enum AugmentSort: String, CaseIterable, Identifiable {
    case opTier, name, tier
    var id: String { rawValue }
    var title: String {
        switch self {
        case .opTier: return L("App.augment.sort.opTier")
        case .name: return L("TeamBuilder.name")
        case .tier: return L("App.augment.sort.tier")
        }
    }
}

struct AugmentsView: View {
    @EnvironmentObject private var repository: Repository
    @State private var sort: AugmentSort = .opTier
    @State private var grade: String?
    @State private var tier: String?
    @State private var query = ""
    @State private var searching = false

    private static let gradeOrder = ["OP", "S", "A", "B", "C", "D"]
    private static let tierOrder = ["prism", "gold", "silver", "bronze"]

    private var rows: [AugmentStat] {
        let dataset = repository.dataset
        return dataset.augments
            .filter { grade == nil || $0.opTier == grade }
            .filter { tier == nil || dataset.augment($0.k)?.tier?.lowercased() == tier }
            .filter {
                guard !query.isEmpty else { return true }
                let name = dataset.augment($0.k)?.n ?? ""
                return name.folding(options: .diacriticInsensitive, locale: AppLanguage.current.format)
                    .localizedCaseInsensitiveContains(query.folding(options: .diacriticInsensitive, locale: AppLanguage.current.format))
            }
            .sorted { lhs, rhs in
                switch sort {
                case .opTier:
                    let l = Self.gradeOrder.firstIndex(of: lhs.opTier) ?? 99
                    let r = Self.gradeOrder.firstIndex(of: rhs.opTier) ?? 99
                    return l != r ? l < r : lhs.k < rhs.k
                case .name:
                    return (dataset.augment(lhs.k)?.n ?? "") < (dataset.augment(rhs.k)?.n ?? "")
                case .tier:
                    let l = Self.tierOrder.firstIndex(of: dataset.augment(lhs.k)?.tier?.lowercased() ?? "") ?? 99
                    let r = Self.tierOrder.firstIndex(of: dataset.augment(rhs.k)?.tier?.lowercased() ?? "") ?? 99
                    return l != r ? l < r : lhs.k < rhs.k
                }
            }
    }

    var body: some View {
        ScreenScaffold(title: L("App.tagline.augments"), subtitle: L("App.augment.subtitle", rows.count, repository.dataset.meta.version)) {
            UnderlineTabs(options: AugmentSort.allCases.map { ($0, $0.title) }, selection: $sort)
                .padding(.horizontal, Theme.gutter)
        } filters: {
            VStack(spacing: 10) {
                FilterBar {
                    FilterPill(title: L("App.augment.filter.grade"),
                               options: [(nil as String?, L("App.augment.filter.allGrades"))] + Self.gradeOrder.map { (Optional($0), L("App.augment.filter.gradeFormat", $0)) },
                               selection: $grade)
                    FilterPill(title: L("App.augment.filter.rank"),
                               options: [(nil as String?, L("App.augment.filter.allRanks"))] + Self.tierOrder.map { (Optional($0), Theme.augmentTier($0).label) },
                               selection: $tier)
                    Spacer()
                    Button {
                        if searching { query = "" }
                        searching.toggle()
                    } label: {
                        Image(systemName: searching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 38, height: 36)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
                if searching {
                    TextField(L("App.augment.searchPlaceholder"), text: $query)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .animation(.snappy, value: searching)
        } content: {
            LazyVStack(spacing: 8) {
                ForEach(rows, id: \.k) { row in
                    NavigationLink {
                        AugmentDetailView(augmentKey: row.k)
                    } label: {
                        AugmentRow(stat: row)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

struct AugmentRow: View {
    @EnvironmentObject private var repository: Repository
    let stat: AugmentStat

    var body: some View {
        let ref = repository.dataset.augment(stat.k)
        let tierMeta = Theme.augmentTier(ref?.tier)
        HStack(spacing: 12) {
            RemoteImage(url: ref?.icon, contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tierMeta.color.opacity(0.7), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 5) {
                Text(ref?.n ?? stat.k)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(ref?.desc ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                Chip(text: stat.opTier, color: Theme.opTier(stat.opTier), filled: true)
                Text(tierMeta.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(tierMeta.color)
            }
        }
        .padding(12)
        .frame(height: 84, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}
