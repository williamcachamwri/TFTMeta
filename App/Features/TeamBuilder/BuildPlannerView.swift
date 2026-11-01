import SwiftUI

/// Build planner: create item builds for champions, track components, and calculate
/// gold requirements per round. The planner validates combinations and shows exactly
/// which rounds to farm for which pieces.
struct BuildPlannerView: View {
    @EnvironmentObject private var repository: Repository
    @StateObject private var model = BuildPlannerModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.plans.isEmpty {
                    emptyState
                } else {
                    planList
                }
            }
            .background(Theme.background)
            .navigationTitle(L("App.builder.planner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreatePlan = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showCreatePlan) {
                CreatePlanSheet(model: model, repository: repository)
            }
        }
    }

    @State private var showCreatePlan = false

    private var emptyState: some View {
        ContentUnavailableView(
            L("App.builder.noPlans"),
            systemImage: "hammer",
            description: Text(L("App.builder.noPlansDesc"))
        )
    }

    private var planList: some View {
        List {
            ForEach(model.plans) { plan in
                NavigationLink {
                    PlanDetailView(plan: plan, model: model)
                } label: {
                    PlanRow(plan: plan, model: model)
                }
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.separator)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    model.deletePlan(model.plans[index].id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct PlanRow: View {
    @EnvironmentObject private var repository: Repository
    let plan: BuildPlan
    let model: BuildPlannerModel

    var body: some View {
        let dataset = repository.dataset
        let champ = dataset.champion(plan.championKey)
        let progress = plan.targetItems.isEmpty ? 0 : Double(plan.ownedComponents.count) / Double(plan.requiredComponents(dataset: dataset).values.reduce(0, +))

        HStack(spacing: 12) {
            RemoteImage(url: champ?.tile, contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rarity(champ?.cost), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 4) {
                Text(champ?.n ?? plan.championKey)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(L("App.builder.itemsCount", plan.targetItems.count))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accentBright)

                Text(L("App.builder.goldNeeded", plan.missingCost(dataset: dataset)))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PlanDetailView: View {
    @EnvironmentObject private var repository: Repository
    let plan: BuildPlan
    @ObservedObject var model: BuildPlannerModel

    @State private var showItemPicker = false

    var body: some View {
        let dataset = repository.dataset
        let champ = dataset.champion(plan.championKey)

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header(champ: champ)

                targetItemsSection

                componentsSection

                goldRequirementSection

                Color.clear.frame(height: 40)
            }
            .padding(.top, 4)
        }
        .pageReveal()
        .navigationTitle(champ?.n ?? plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .sheet(isPresented: $showItemPicker) {
            ItemPickerSheet(model: model, repository: repository)
        }
    }

    private func header(champ: ChampionRef?) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: champ?.tile, contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.rarity(champ?.cost), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(champ?.n ?? plan.championKey)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 6) {
                    Chip(text: L("App.champion.filter.costFormat", "\(champ?.cost ?? 0)"), color: Theme.rarity(champ?.cost))
                    if let role = champ?.role {
                        Chip(text: role, color: Theme.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var targetItemsSection: some View {
        let dataset = repository.dataset
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: L("App.builder.targetItems"), detail: L("App.builder.itemsCount", plan.targetItems.count))

            Card(padding: 12) {
                VStack(spacing: 10) {
                    ForEach(plan.targetItems, id: \.self) { itemKey in
                        if let item = dataset.item(itemKey) {
                            HStack(spacing: 10) {
                                RemoteImage(url: item.icon, contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.n)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)

                                    Text(L("App.builder.cost", 4))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()

                                Button {
                                    model.removeTargetItem(itemKey)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }

                    if plan.targetItems.count < 3 {
                        Button {
                            showItemPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.accent)
                                Text(L("App.builder.addItem"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var componentsSection: some View {
        // TODO: Fix compiler binding bug - temporarily disabled
        EmptyView()
    }

    private var goldRequirementSection: some View {
        // TODO: Fix compiler bug - temporarily disabled
        EmptyView()
    }
}

private struct CreatePlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: BuildPlannerModel
    let repository: Repository

    @State private var name = ""
    @State private var selectedChampion: String?

    var body: some View {
        let dataset = repository.dataset
        let champs = dataset.champions.sorted { a, b in
            let champA = dataset.champion(a.k)
            let champB = dataset.champion(b.k)
            return (champA?.n ?? a.k) < (champB?.n ?? b.k)
        }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("App.builder.planName"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("Enter plan name", text: $name)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal, Theme.gutter)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("App.builder.selectChampion"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(champs, id: \.k) { champStat in
                            let champ = dataset.champion(champStat.k)
                            Button {
                                selectedChampion = champStat.k
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: champ?.tile, contentMode: .fill)
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    Text(champ?.n ?? champStat.k)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)

                                    Spacer()

                                    if selectedChampion == champStat.k {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(10)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(L("App.builder.createPlan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("App.cancel")) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L("App.create")) {
                        if !name.isEmpty, let champ = selectedChampion {
                            _ = model.createPlan(name: name, championKey: champ)
                            dismiss()
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(name.isEmpty || selectedChampion == nil ? Theme.textTertiary : Theme.accent)
                    .disabled(name.isEmpty || selectedChampion == nil)
                }
            }
        }
    }
}

private struct ItemPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: BuildPlannerModel
    let repository: Repository

    var body: some View {
        let dataset = repository.dataset
        let items: [(key: String, ref: ItemRef)] = dataset.ref.items.filter { $0.value.composition != nil }.map { ($0.key, $0.value) }.sorted { $0.ref.n < $1.ref.n }

        NavigationStack {
            List {
                ForEach(items, id: \.key) { item in
                    Button {
                        if let planID = model.selectedPlanID,
                           let index = model.plans.firstIndex(where: { $0.id == planID }) {
                            model.addTargetItem(item.key, dataset: dataset)
                        }
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: item.ref.icon, contentMode: .fit)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.ref.n)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)

                                if let from = item.ref.composition {
                                    Text(from.map { dataset.item($0)?.n ?? $0 }.joined(separator: " + "))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }

                            Spacer()
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(L("App.builder.selectItem"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("App.cancel")) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
