import Foundation

/// Four places on today's tray; original catalog identities and saved meals stay intact.
enum MealCourse: String, CaseIterable, Identifiable {
    case main, side, staple, soup
    var id: String { rawValue }
    var label: String {
        switch self { case .main: "主菜"; case .side: "副菜"; case .staple: "主食"; case .soup: "汁物" }
    }
    static func of(_ recipe: Recipe) -> Self {
        if RecipeKind.soup.includes(recipe) { return .soup }
        if RecipeKind.side.includes(recipe) { return .side }
        // Rice, noodles, bread and similar complete dishes occupy the staple place once,
        // including bowls/curry sets, rather than counting one recipe in two places.
        let staples: Set<String> = ["cooked_rice", "raw_rice", "spaghetti", "frozen_udon",
            "yakisoba_noodles", "bread", "soba", "somen", "ramen_noodles", "penne",
            "oatmeal", "rice_cake", "rice_vermicelli"]
        return recipe.ingredients.contains { $0.requirement == "required" && staples.contains($0.ingredientKey) }
            ? .staple : .main
    }
}

/// Requirements are frozen at selection time. Calculations never mutate refrigerator lots.
struct PlannedMeal {
    let id: UUID
    let day: Date
    let createdAt: Date
    let ingredients: [RecipeIngredient]
    let hasKnownIngredients: Bool
}
struct PlannedMaterial: Identifiable {
    let id: String
    let key: String
    let name: String
    let unit: IngredientUnit
    let optional: Bool
    let mode: String
    var required: Double = 0
    var shortage: Double = 0
    var unconfirmed: Double = 0
    var hasConfirmation: Bool { unconfirmed > 0.0000001 }
    var hasShortage: Bool { shortage > 0.0000001 }
    var amountLabel: String { required.formatted() + unit.label }
}
struct MealMaterialSummary {
    let materials: [PlannedMaterial]
    let incomplete: Bool
    var shortages: [PlannedMaterial] { materials.filter(\.hasShortage) }
    var confirmation: [PlannedMaterial] { materials.filter(\.hasConfirmation) }
    var displayMaterials: [PlannedMaterial] {
        materials.sorted {
            let left = $0.hasShortage ? 0 : $0.hasConfirmation ? 1 : $0.optional ? 3 : $0.mode == "ignored" ? 4 : 2
            let right = $1.hasShortage ? 0 : $1.hasConfirmation ? 1 : $1.optional ? 3 : $1.mode == "ignored" ? 4 : 2
            if left != right { return left < right }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }
}

/// Explicit material additions keep their selected meals and requirement, including across relaunches.
struct MaterialPurchaseScope: Codable, Equatable {
    let mealIDs: [UUID]
    let materialID: String
}
struct MaterialPurchase {
    let id: UUID
    let masterID: UUID?
    let quantity: Double
    let unit: IngredientUnit
    var sourceMealID: UUID? = nil
    var isAddedToInventory = false
    var scope: MaterialPurchaseScope? = nil
}
/// One purchase quantity can cover only one share of the displayed requirements.
/// Both the material screen and its save transaction use this allocation.
struct MaterialShoppingCoverage {
    let remaining: [String: Double]
    let credited: [String: Double]
    var addedIDs: Set<String> {
        Set(remaining.keys.filter { (remaining[$0] ?? 0) <= 0.0000001 && (credited[$0] ?? 0) > 0.0000001 })
    }
    static func assess(_ materials: [PlannedMaterial], foods: [RecipeFood], purchases: [MaterialPurchase],
                       visibleMealIDs: Set<UUID>) -> Self {
        allocate([(ids: visibleMealIDs, materials: materials)], foods: foods, purchases: purchases, visibleMealIDs: visibleMealIDs, includeAll: true)
    }
    /// Allocate purchases once across every active reservation, then project the selected day/week.
    static func assess(plans: [PlannedMeal], foods: [RecipeFood], stock: [StockLot],
                       purchases: [MaterialPurchase], visibleMealIDs: Set<UUID>) -> Self {
        let requirements = MealPlanning.requirements(plans, foods: foods, stock: stock)
        return allocate(requirements.map { (ids: Set([$0.plan.id]), materials: $0.materials) },
            foods: foods, purchases: purchases, visibleMealIDs: visibleMealIDs)
    }
    private static func allocate(_ requirements: [(ids: Set<UUID>, materials: [PlannedMaterial])], foods: [RecipeFood],
                                 purchases: [MaterialPurchase], visibleMealIDs: Set<UUID>, includeAll: Bool = false) -> Self {
        let masters = Dictionary(uniqueKeysWithValues: foods.map { ($0.key, $0.id) })
        let activeIDs = requirements.reduce(into: Set<UUID>()) { $0.formUnion($1.ids) }
        let eligible = purchases.filter { !$0.isAddedToInventory && $0.quantity.isFinite && $0.quantity > 0 }
            .sorted {
                // Narrow reservations first: a day-specific purchase must not be displaced by a weekly one.
                let left = $0.sourceMealID != nil ? 0 : $0.scope?.mealIDs.count ?? Int.max
                let right = $1.sourceMealID != nil ? 0 : $1.scope?.mealIDs.count ?? Int.max
                if left != right { return left < right }
                return $0.id.uuidString < $1.id.uuidString
            }
        let byMaster = Dictionary(grouping: eligible.filter { $0.masterID != nil }, by: { $0.masterID! })
        var available = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0.quantity) })
        var entries = requirements.flatMap { requirement in
            requirement.materials.compactMap { material -> (ids: Set<UUID>, material: PlannedMaterial, masterID: UUID, needed: Double, remaining: Double)? in
                let needed = material.shortage + material.unconfirmed
                guard !material.optional, material.mode != "ignored", needed.isFinite,
                      needed > 0.0000001, let masterID = masters[material.key] else { return nil }
                return (requirement.ids, material, masterID, needed, needed)
            }
        }
        // First satisfy earmarked meals; then allocate manual purchases and any explicit surplus.
        for reserved in [true, false] {
            for i in entries.indices {
                for purchase in byMaster[entries[i].masterID] ?? [] {
                    if let source = purchase.sourceMealID {
                        guard reserved && entries[i].ids.contains(source) else { continue }
                    } else if let scope = purchase.scope {
                        guard !scope.mealIDs.isEmpty else { continue }
                        if reserved {
                            guard scope.materialID == entries[i].material.id,
                                  !Set(scope.mealIDs).intersection(activeIDs).isDisjoint(with: entries[i].ids) else { continue }
                        }
                    } else if reserved { continue }
                    guard entries[i].remaining > 0.0000001,
                          let quantity = Units.convert(available[purchase.id] ?? 0, from: purchase.unit, to: entries[i].material.unit),
                          quantity.isFinite, quantity > 0,
                          let used = Units.convert(min(quantity, entries[i].remaining), from: entries[i].material.unit, to: purchase.unit) else { continue }
                    entries[i].remaining = max(0, entries[i].remaining - min(quantity, entries[i].remaining))
                    available[purchase.id] = max(0, (available[purchase.id] ?? 0) - used)
                }
            }
        }
        var remaining: [String: Double] = [:], credited: [String: Double] = [:]
        for entry in entries where includeAll || !entry.ids.isDisjoint(with: visibleMealIDs) {
            remaining[entry.material.id, default: 0] += entry.remaining
            credited[entry.material.id, default: 0] += entry.needed - entry.remaining
        }
        return Self(remaining: remaining, credited: credited)
    }
}
enum MealPlanning {
    static func selectedDay(_ selection: Date?, now: Date, calendar: Calendar = .current) -> Date {
        day(selection ?? now, calendar: calendar)
    }
    static func title(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let selected = day(date, calendar: calendar), today = day(now, calendar: calendar)
        if selected == today { return "今日の献立" }
        if selected == calendar.date(byAdding: .day, value: 1, to: today) { return "明日の献立" }
        return label(selected) + "の献立"
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> Date { calendar.startOfDay(for: date) }
    static func days(from date: Date, calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: day(date, calendar: calendar)) }
    }
    static func label(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).month().day().weekday(.abbreviated))
    }
    static func normalized(_ unit: IngredientUnit) -> IngredientUnit {
        switch unit { case .kilogram: .gram; case .liter: .milliliter; default: unit }
    }
    /// Process each lot once in chronological order, independently of the displayed period.
    static func requirements(_ plans: [PlannedMeal], foods: [RecipeFood], stock: [StockLot],
                             assessAvailability: Bool = true) -> [(plan: PlannedMeal, materials: [PlannedMaterial])] {
        let foodsByKey = Dictionary(uniqueKeysWithValues: foods.map { ($0.key, $0) })
        var remaining = stock
        return plans.sorted(by: {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }).map { plan in
            var rows: [String: PlannedMaterial] = [:]
            for ingredient in plan.ingredients {
                let food = foodsByKey[ingredient.ingredientKey]
                let result = RecipeAvailability.evaluate(ingredient, servings: 1,
                    lots: remaining.filter { $0.masterID == food?.id && food != nil }, on: plan.day)
                let unit = normalized(ingredient.unit), optional = ingredient.requirement == "optional"
                let id = ingredient.ingredientKey + "-" + unit.rawValue + "-" + ingredient.inventoryMode + "-" + (optional ? "optional" : "required")
                var row = rows[id] ?? PlannedMaterial(id: id, key: ingredient.ingredientKey,
                    name: food?.name ?? ingredient.ingredientKey, unit: unit, optional: optional, mode: ingredient.inventoryMode)
                row.required += Units.convert(result.required, from: ingredient.unit, to: unit) ?? result.required
                if assessAvailability && !optional && ingredient.inventoryMode != "ignored" {
                    if result.status == .shortage { row.shortage += Units.convert(result.shortage, from: ingredient.unit, to: unit) ?? result.shortage }
                    else if result.status == .confirmation { row.unconfirmed += Units.convert(result.shortage, from: ingredient.unit, to: unit) ?? result.shortage }
                }
                rows[id] = row
                if assessAvailability && ingredient.requirement == "required" && ingredient.inventoryMode == "exact" {
                    remaining = reserve(result, ingredient: ingredient, in: remaining)
                }
            }
            return (plan, rows.values.sorted { $0.id < $1.id })
        }
    }
    static func summarize(_ plans: [PlannedMeal], visibleIDs: Set<UUID>, foods: [RecipeFood], stock: [StockLot], assessAvailability: Bool = true) -> MealMaterialSummary {
        var rows: [String: PlannedMaterial] = [:]
        let lastVisibleDay = plans.filter { visibleIDs.contains($0.id) }.map(\.day).max()
        let knownKeys = Set(foods.map(\.key))
        let incomplete = plans.contains { plan in
            (!plan.hasKnownIngredients && (visibleIDs.contains(plan.id) || lastVisibleDay.map { plan.day <= $0 } == true)) ||
            (visibleIDs.contains(plan.id) && plan.ingredients.contains { $0.requirement != "optional" && $0.inventoryMode != "ignored" && !knownKeys.contains($0.ingredientKey) })
        }
        for requirement in requirements(plans, foods: foods, stock: stock, assessAvailability: assessAvailability)
            where visibleIDs.contains(requirement.plan.id) {
            for material in requirement.materials {
                if var row = rows[material.id] {
                    row.required += material.required; row.shortage += material.shortage; row.unconfirmed += material.unconfirmed
                    rows[material.id] = row
                } else { rows[material.id] = material }
            }
        }
        return MealMaterialSummary(materials: rows.values.sorted {
            if $0.optional != $1.optional { return !$0.optional }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }, incomplete: incomplete)
    }
    static func reserve(_ result: Availability, ingredient: RecipeIngredient, in stock: [StockLot]) -> [StockLot] {
        let consumed = Dictionary(uniqueKeysWithValues: result.consumption.map { ($0.id, $0.quantity) })
        return stock.map { lot in
            guard let used = consumed[lot.id], let quantity = lot.quantity, let unit = lot.unit,
                  let amount = Units.convert(used, from: ingredient.unit, to: unit) else { return lot }
            return StockLot(id: lot.id, masterID: lot.masterID, quantity: max(0, quantity - amount), unit: unit,
                roughState: lot.roughState, storage: lot.storage, expiresAt: lot.expiresAt,
                purchasedAt: lot.purchasedAt, isDeleted: lot.isDeleted)
        }
    }
}
