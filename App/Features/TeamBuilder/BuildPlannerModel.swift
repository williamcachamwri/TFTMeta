import Foundation
import SwiftUI

/// Manages build plans and calculates round-by-round progression.
/// The planner tracks what items we want, what we have, and how much gold we need
/// to complete the build by a target round.
@MainActor
final class BuildPlannerModel: ObservableObject {
    @Published var plans: [BuildPlan] = []
    @Published var selectedPlanID: UUID?
    @Published var currentRound: Int = 1
    @Published var currentGold: Int = 0
    @Published var currentLevel: Int = 1

    private let storeKey = "BuildPlanner.plans"

    init() {
        load()
    }

    var selectedPlan: BuildPlan? {
        get { plans.first { $0.id == selectedPlanID } }
    }

    /// Create a new build plan for a champion.
    func createPlan(name: String, championKey: String) -> BuildPlan {
        let plan = BuildPlan(name: name, championKey: championKey)
        plans.append(plan)
        selectedPlanID = plan.id
        save()
        return plan
    }

    /// Delete a plan by ID.
    func deletePlan(_ id: UUID) {
        plans.removeAll { $0.id == id }
        if selectedPlanID == id {
            selectedPlanID = plans.first?.id
        }
        save()
    }

    /// Update target items for the selected plan.
    func setTargetItems(_ items: [String]) {
        guard let index = plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        plans[index].targetItems = items
        save()
    }

    /// Add an item to the target list.
    func addTargetItem(_ itemKey: String, dataset: TFTDataset) {
        guard let index = plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        guard plans[index].targetItems.count < 3 else { return }
        guard !plans[index].targetItems.contains(itemKey) else { return }
        plans[index].targetItems.append(itemKey)
        save()
    }

    /// Remove an item from the target list.
    func removeTargetItem(_ itemKey: String) {
        guard let index = plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        plans[index].targetItems.removeAll { $0 == itemKey }
        save()
    }

    /// Mark a component as owned.
    func addOwnedComponent(_ componentKey: String, dataset: TFTDataset) {
        guard let index = plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        plans[index].ownedComponents.insert(componentKey)
        save()
    }

    /// Mark a component as not owned.
    func removeOwnedComponent(_ componentKey: String) {
        guard let index = plans.firstIndex(where: { $0.id == selectedPlanID }) else { return }
        plans[index].ownedComponents.remove(componentKey)
        save()
    }

    /// Calculate gold needed per round to complete the build by a target round.
    func goldPerRound(targetRound: Int, dataset: TFTDataset) -> [RoundGoldRequirement] {
        guard let plan = selectedPlan else { return [] }

        let totalCost = plan.missingCost(dataset: dataset)

        var requirements: [RoundGoldRequirement] = []
        var goldNeeded = totalCost
        var accumulatedGold = currentGold

        for round in currentRound...targetRound {
            let progression = RoundProgress.progression(for: round)
            let income = progression.goldIncome
            let interest = min(accumulatedGold / 10, 5)
            let totalIncome = income + interest

            let canSpend = min(goldNeeded, totalIncome)
            accumulatedGold += (totalIncome - canSpend)

            requirements.append(RoundGoldRequirement(
                round: round,
                level: progression.level,
                income: totalIncome,
                goldToSpend: canSpend,
                remainingGold: goldNeeded - canSpend
            ))

            goldNeeded -= canSpend
        }

        return requirements
    }

    /// Validate the current plan.
    func validate(dataset: TFTDataset) -> ValidationResult {
        guard let plan = selectedPlan else {
            return .failure("No plan selected")
        }
        return BuildValidator.validate(plan: plan, dataset: dataset)
    }

    /// Check if the build is complete (all target items can be built).
    func isBuildComplete(dataset: TFTDataset) -> Bool {
        guard let plan = selectedPlan else { return false }
        return plan.missingComponents(dataset: dataset).isEmpty
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([BuildPlan].self, from: data) else { return }
        plans = decoded
        selectedPlanID = plans.first?.id
    }
}

struct RoundGoldRequirement: Identifiable {
    let id = UUID()
    let round: Int
    let level: Int
    let income: Int
    let goldToSpend: Int
    let remainingGold: Int
}
