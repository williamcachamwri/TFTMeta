import Foundation

/// A planned item build: which items we want, what we have, and how much gold we need.
/// The planner validates recipes and tracks component ownership so the player can see
/// exactly which rounds to farm for which pieces.
struct BuildPlan: Codable, Identifiable {
    let id: UUID
    var name: String
    var championKey: String
    var targetItems: [String]
    var ownedComponents: Set<String>
    var createdAt: Date

    init(id: UUID = UUID(), name: String, championKey: String, targetItems: [String] = [], ownedComponents: Set<String> = []) {
        self.id = id
        self.name = name
        self.championKey = championKey
        self.targetItems = targetItems
        self.ownedComponents = ownedComponents
        self.createdAt = Date()
    }

    /// All components needed for the target items, with duplicates counted.
    func requiredComponents(dataset: TFTDataset) -> [String: Int] {
        var counts: [String: Int] = [:]
        for itemKey in targetItems {
            guard let item = dataset.item(itemKey) else { continue }
            if let components = item.composition {
                for component in components {
                    counts[component, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// Components we still need to buy, after subtracting what we already own.
    func missingComponents(dataset: TFTDataset) -> [String: Int] {
        let required = requiredComponents(dataset: dataset)
        var missing: [String: Int] = [:]
        for (component, count) in required {
            let owned = ownedComponents.filter { $0 == component }.count
            let needed = count - owned
            if needed > 0 {
                missing[component] = needed
            }
        }
        return missing
    }

    /// Total gold cost of all missing components (base components cost 2 gold each).
    func missingCost(dataset: TFTDataset) -> Int {
        let baseComponentCost = 2
        return missingComponents(dataset: dataset).reduce(0) { total, pair in
            return total + baseComponentCost * pair.value
        }
    }

    /// Gold needed to complete the build, accounting for components already owned.
    func totalCost(dataset: TFTDataset) -> Int {
        let baseComponentCost = 2
        return targetItems.reduce(0) { total, itemKey in
            guard let item = dataset.item(itemKey) else { return total }
            if let components = item.composition {
                return total + baseComponentCost * components.count
            }
            return total
        }
    }
}

/// Round-by-round progression: what level we are, how much gold we have, and what we can buy.
struct RoundProgress: Codable {
    var round: Int
    var level: Int
    var gold: Int
    var income: Int
    var shopOdds: [Int: Double]

    /// TFT round progression: round 1-1 to 4-7, with level caps at each stage.
    static func progression(for round: Int) -> (level: Int, goldIncome: Int) {
        switch round {
        case 1...3: return (2, 5)
        case 4...9: return (3, 6)
        case 10...15: return (4, 7)
        case 16...21: return (5, 8)
        case 22...27: return (6, 9)
        case 28...35: return (7, 10)
        case 36...45: return (8, 12)
        default: return (9, 15)
        }
    }

    /// Shop odds by level: chance to see champions of each cost tier (1-5 gold).
    static func shopOdds(for level: Int) -> [Int: Double] {
        switch level {
        case 1: return [1: 1.0]
        case 2: return [1: 1.0]
        case 3: return [1: 0.75, 2: 0.25]
        case 4: return [1: 0.55, 2: 0.30, 3: 0.15]
        case 5: return [1: 0.40, 2: 0.35, 3: 0.20, 4: 0.05]
        case 6: return [1: 0.25, 2: 0.40, 3: 0.25, 4: 0.10]
        case 7: return [1: 0.15, 2: 0.30, 3: 0.35, 4: 0.15, 5: 0.05]
        case 8: return [1: 0.10, 2: 0.20, 3: 0.35, 4: 0.25, 5: 0.10]
        default: return [1: 0.05, 2: 0.10, 3: 0.25, 4: 0.35, 5: 0.25]
        }
    }
}

/// Validation: check if a build plan is legal given TFT rules.
enum BuildValidator {
    /// A champion can hold at most 3 items.
    static func validateItemCount(_ count: Int) -> ValidationResult {
        if count > 3 {
            return .failure("Champion can only hold 3 items")
        }
        return .success
    }

    /// Check if all target items exist in the dataset.
    static func validateItems(_ items: [String], dataset: TFTDataset) -> ValidationResult {
        for itemKey in items {
            if dataset.item(itemKey) == nil {
                return .failure("Unknown item: \(itemKey)")
            }
        }
        return .success
    }

    /// Check if component items are valid (not combined items).
    static func validateComponents(_ components: Set<String>, dataset: TFTDataset) -> ValidationResult {
        for componentKey in components {
            guard let item = dataset.item(componentKey) else {
                return .failure("Unknown component: \(componentKey)")
            }
            if item.composition != nil {
                return .failure("\(componentKey) is not a base component")
            }
        }
        return .success
    }

    /// Full validation of a build plan.
    static func validate(plan: BuildPlan, dataset: TFTDataset) -> ValidationResult {
        if let failure = validateItemCount(plan.targetItems.count).failure {
            return .failure(failure)
        }
        if let failure = validateItems(plan.targetItems, dataset: dataset).failure {
            return .failure(failure)
        }
        if let failure = validateComponents(plan.ownedComponents, dataset: dataset).failure {
            return .failure(failure)
        }
        return .success
    }
}

enum ValidationResult {
    case success
    case failure(String)

    var isValid: Bool {
        if case .success = self { return true }
        return false
    }

    var failure: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}
