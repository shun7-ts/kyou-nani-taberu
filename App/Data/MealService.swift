import Foundation
import SwiftData

enum MealError: LocalizedError {
    case invalidQuantity, missingItem, confirmationRequired, alreadyCompleted, plannedPurchaseInsufficient, plannedPurchaseUncertain, ambiguousIngredient
    var errorDescription: String? {
        switch self {
        case .ambiguousIngredient: "同じ名前の食材があります。候補から選んでください。"
        case .invalidQuantity: "数量・単位を確認してください。購入量は0より大きい数で入力します。"
        case .missingItem: "対象の食材・献立が見つかりません。"
        case .confirmationRequired: "在庫量・単位を確認してください。使わなかった場合は使用量を0にします。"
        case .alreadyCompleted: "この献立は調理中、または終了しています。"
        case .plannedPurchaseInsufficient: "買う予定の量と冷蔵庫の在庫では足りません。買う量か人数を変更してください。"
        case .plannedPurchaseUncertain: "買う予定の量で足りるか確認できません。冷蔵庫の量や単位を確認してください。"
        }
    }
}
struct PurchaseDraft: Identifiable {
    let id: UUID
    var quantity: Double
    var unit: IngredientUnit
    var storage: StorageMethod
    var purchasedAt: Date
    var expiresAt: Date?
    var expiryKind: ExpiryKind = .unspecified
    var seasoningState: RoughStockState = .available
    var addToInventory = true
}
enum CookingAmountMode: String, CaseIterable { case used, remaining }
struct RemainingStockAmount {
    var quantity: Double
    var unit: IngredientUnit
}
struct CookingDraft {
    let ingredientKey: String
    var quantity: Double
    var roughStates: [UUID: RoughStockState] = [:]
    var inputMode: CookingAmountMode = .used
    // Explicit choices made on the seasoning form may convert an exact lot to rough.
    var seasoningStates: [UUID: RoughStockState] = [:]
    // A measured remainder is an observation, never inferred consumption.
    var remainingAmounts: [UUID: RemainingStockAmount] = [:]
}

enum CookingAmounts {
    static func available(lots: [StockLot], unit: IngredientUnit) -> Double? {
        var sum = 0.0
        for lot in lots where StockExpiry.hasStock(lot) {
            guard lot.roughState == nil, let amount = lot.quantity, let from = lot.unit,
                  let converted = Units.convert(amount, from: from, to: unit) else { return nil }
            sum += converted
            guard sum.isFinite else { return nil }
        }
        return sum
    }
    static func usage(for draft: CookingDraft, lots: [StockLot], unit: IngredientUnit) throws -> Double {
        guard draft.quantity.isFinite, draft.quantity >= 0 else { throw MealError.invalidQuantity }
        if draft.inputMode == .used { return draft.quantity }
        guard let current = available(lots: lots, unit: unit), draft.quantity <= current else {
            throw MealError.confirmationRequired
        }
        return current - draft.quantity
    }
}

@MainActor
struct MealService {
    let container: ModelContainer
    var mergeDuplicates = true
    @discardableResult
    func select(recipe: Recipe, servings: Int, storePlan: StorePurchasePlan? = nil, includeUncertain: Bool = false, scheduledDate: Date? = nil, includeMaterials: Bool = true, addShortagesToShopping: Bool? = nil) throws -> Int {
        guard (1...4).contains(servings), includeMaterials || storePlan == nil else { throw MealError.invalidQuantity }
        return try transaction { context in
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
            let stock = IngredientIdentity.snapshots(try context.fetch(FetchDescriptor<InventoryItem>()), customs: customs, masters: masters)
            let active = try context.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive)
            let targetDay = MealPlanning.day(scheduledDate ?? .now)
            let same = active.first { $0.recipeID == recipe.id && $0.plannedDay() == targetDay }
            guard same?.state != "cooking" else { throw MealError.alreadyCompleted }
            let meal = same ?? MealSelection(recipe: recipe, servings: servings)
            if same == nil { context.insert(meal) }
            // Re-selecting this recipe changes only its own meal and unpurchased rows.
            let shopping = try context.fetch(FetchDescriptor<ShoppingListItem>())
            let purchases = shopping.filter { $0.sourceMealID == meal.id && $0.isChecked && !$0.isAddedToInventory }
            if !includeMaterials {
                // Legacy prepared-dish edits keep purchased goods as independent shopping records.
                for row in purchases { row.sourceMealID = nil; row.sourceRecipeTitle = nil }
            }
            for row in shopping where row.sourceMealID == meal.id && !row.isAddedToInventory && !row.isChecked {
                context.delete(row)
            }
            meal.servings = servings; meal.updatedAt = .now
            meal.scheduledDate = targetDay
            meal.addsShortagesToShopping = addShortagesToShopping ?? meal.addsShortagesToShopping ?? true
            let plan = (includeMaterials ? recipe.ingredients : []).map {
                RecipeIngredient(ingredientKey: $0.ingredientKey,
                    quantity: $0.amount(servings: servings, base: recipe.baseServings), unit: $0.unit,
                    requirement: $0.requirement, inventoryMode: $0.inventoryMode, scaling: "fixed",
                    thawing: $0.thawing, note: $0.note)
            }
            meal.ingredientPlanData = try JSONEncoder().encode(plan)
            if !includeMaterials || !meal.shouldAddShortagesToShopping {
                try reconcileLaterShopping(after: meal, context: context, masters: masters, stock: stock)
                return 0
            }
            var remainingStock = stock
            for other in active.filter({
                let otherDay = $0.plannedDay()
                return otherDay < targetDay || (otherDay == targetDay &&
                    ($0.date < meal.date || ($0.date == meal.date && $0.id.uuidString < meal.id.uuidString)))
            }).sorted(by: {
                if $0.plannedDay() != $1.plannedDay() { return $0.plannedDay() < $1.plannedDay() }
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }) {
                let ingredients: [RecipeIngredient]
                if let data = other.ingredientPlanData {
                    ingredients = try JSONDecoder().decode([RecipeIngredient].self, from: data)
                } else if let previous = try RecipeCatalog.load().first(where: { $0.id == other.recipeID }) {
                    ingredients = previous.ingredients.map {
                        RecipeIngredient(ingredientKey: $0.ingredientKey,
                            quantity: $0.amount(servings: other.servings, base: previous.baseServings), unit: $0.unit,
                            requirement: $0.requirement, inventoryMode: $0.inventoryMode, scaling: "fixed",
                            thawing: $0.thawing, note: $0.note)
                    }
                } else { throw MealError.missingItem }
                for ingredient in ingredients where ingredient.requirement == "required" && ingredient.inventoryMode == "exact" {
                    guard let master = masters.first(where: { $0.key == ingredient.ingredientKey }) else { throw MealError.missingItem }
                    let allocation = RecipeAvailability.evaluate(ingredient, servings: 1,
                        lots: remainingStock.filter { $0.masterID == master.id }, on: other.plannedDay())
                    remainingStock = remainingStock.map { lot in
                        guard let consumed = allocation.consumption.first(where: { $0.id == lot.id }),
                              let unit = lot.unit, let quantity = lot.quantity,
                              let amount = Units.convert(consumed.quantity, from: ingredient.unit, to: unit) else { return lot }
                        return StockLot(id: lot.id, masterID: lot.masterID, quantity: max(0, quantity - amount),
                            unit: unit, roughState: lot.roughState, storage: lot.storage,
                            expiresAt: lot.expiresAt, purchasedAt: lot.purchasedAt, isDeleted: lot.isDeleted)
                    }
                }
            }
            if let plan = storePlan {
                guard plan.isValid else { throw MealError.invalidQuantity }
                guard let ingredient = recipe.ingredients.first(where: { $0.ingredientKey == plan.ingredientKey }),
                      let master = masters.first(where: { $0.key == plan.ingredientKey }),
                      master.status == .active, master.shoppingEligible,
                      master.allowedUnits.contains(plan.unit),
                      let assessment = StorePurchasePlan.availability(ingredient, plan: plan, masterID: master.id,
                        stock: remainingStock, servings: servings, base: recipe.baseServings, on: targetDay) else { throw MealError.missingItem }
                if assessment.status == .shortage { throw MealError.plannedPurchaseInsufficient }
                guard assessment.status == .available else { throw MealError.plannedPurchaseUncertain }
            }
            let catalog = try RecipeCatalog.load()
            let plans = try context.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).map { selected in
                let ingredients = selected.plannedIngredients(recipes: catalog)
                return PlannedMeal(id: selected.id, day: selected.plannedDay(), createdAt: selected.date,
                    ingredients: ingredients ?? [], hasKnownIngredients: ingredients != nil)
            }
            let coverage = MaterialShoppingCoverage.assess(plans: plans,
                foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }, stock: stock,
                purchases: try context.fetch(FetchDescriptor<ShoppingListItem>()).map(MaterialPurchase.init), visibleMealIDs: [meal.id])
            var count = 0
            for ingredient in recipe.ingredients where ingredient.requirement == "required" {
                guard let master = masters.first(where: { $0.key == ingredient.ingredientKey }) else {
                    throw MealError.missingItem
                }
                guard master.shoppingEligible else { continue }
                if let plan = storePlan, plan.ingredientKey == ingredient.ingredientKey {
                    context.insert(ShoppingListItem(masterID: master.id, name: master.canonicalName,
                        quantity: plan.quantity, unit: plan.unit,
                        required: Units.convert(ingredient.amount(servings: servings, base: recipe.baseServings), from: ingredient.unit, to: plan.unit),
                        meal: meal))
                    count += 1
                    continue
                }
                let availability = RecipeAvailability.evaluate(ingredient, servings: servings, base: recipe.baseServings,
                    lots: remainingStock.filter { $0.masterID == master.id }, on: targetDay)
                guard availability.status == .shortage || (includeUncertain && availability.status == .confirmation) else { continue }
                let materialID = ingredient.ingredientKey + "-" + MealPlanning.normalized(ingredient.unit).rawValue + "-" + ingredient.inventoryMode + "-required"
                let shortage = Units.convert(coverage.remaining[materialID] ?? 0,
                    from: MealPlanning.normalized(ingredient.unit), to: ingredient.unit) ?? 0
                guard shortage > 0.0000001 else { continue }
                context.insert(ShoppingListItem(masterID: master.id, name: master.canonicalName,
                    quantity: shortage, unit: ingredient.unit,
                    required: availability.required, meal: meal,
                    needsConfirmation: availability.status == .confirmation))
                count += 1
            }
            try reconcileLaterShopping(after: meal, context: context, masters: masters, stock: stock)
            return count
        }
    }

    /// Adding an earlier reservation can change a later day's shortage. Respect that meal's
    /// saved shopping choice and preserve purchased, manual, edited and legacy shopping rows.
    private func reconcileLaterShopping(after selected: MealSelection, context: ModelContext,
                                        masters: [IngredientMaster], stock: [StockLot]) throws {
        let meals = try context.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive)
        let catalog = try RecipeCatalog.load()
        let plans = meals.map { meal in
            let ingredients = meal.plannedIngredients(recipes: catalog)
            return PlannedMeal(id: meal.id, day: meal.plannedDay(), createdAt: meal.date,
                ingredients: ingredients ?? [], hasKnownIngredients: ingredients != nil)
        }
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        for meal in meals.sorted(by: {
            if $0.plannedDay() != $1.plannedDay() { return $0.plannedDay() < $1.plannedDay() }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }) where meal.id != selected.id && meal.shouldAddShortagesToShopping {
            let later = meal.plannedDay() > selected.plannedDay() || (meal.plannedDay() == selected.plannedDay() &&
                (meal.date > selected.date || (meal.date == selected.date && meal.id.uuidString > selected.id.uuidString)))
            guard later else { continue }
            let summary = MealPlanning.summarize(plans, visibleIDs: [meal.id], foods: foods, stock: stock)
            guard !summary.incomplete else { continue }
            let shopping = try context.fetch(FetchDescriptor<ShoppingListItem>())
            let own = shopping.filter { $0.sourceMealID == meal.id && !$0.isAddedToInventory }
            for material in summary.materials where !material.optional && material.mode != "ignored" {
                guard let master = masters.first(where: { $0.key == material.key }), master.shoppingEligible else { continue }
                let existing = own.filter { $0.ingredientMasterID == master.id && Units.convert(1, from: $0.unit, to: material.unit) != nil }
                // Explicit shopping edits, old rows and uncertainty choices are not overwritten.
                guard !material.hasConfirmation,
                      !existing.contains(where: { !$0.isChecked && ($0.automaticallyManaged != true || $0.needsConfirmation) }) else { continue }
                let generated = existing.filter { !$0.isChecked && $0.automaticallyManaged == true }
                let generatedIDs = Set(generated.map(\.id))
                let coverage = MaterialShoppingCoverage.assess(plans: plans, foods: foods, stock: stock,
                    purchases: shopping.filter { !generatedIDs.contains($0.id) }.map(MaterialPurchase.init), visibleMealIDs: [meal.id])
                let shortage = coverage.remaining[material.id] ?? 0
                if shortage <= 0.0000001 {
                    for row in generated { context.delete(row) }
                } else if let row = generated.first {
                    row.quantity = Units.convert(shortage, from: material.unit, to: row.unit) ?? shortage
                    row.requiredQuantity = Units.convert(material.required, from: material.unit, to: row.unit)
                    for duplicate in generated.dropFirst() { context.delete(duplicate) }
                } else {
                    context.insert(ShoppingListItem(masterID: master.id, name: master.canonicalName,
                        quantity: shortage, unit: material.unit, required: material.required, meal: meal))
                }
            }
        }
    }

    func startCooking(mealID: UUID) throws {
        try transaction { context in
            guard let meal = try context.fetch(FetchDescriptor<MealSelection>()).first(where: { $0.id == mealID }) else { throw MealError.missingItem }
            guard meal.isActive else { throw MealError.alreadyCompleted }
            if meal.state != "cooking" { meal.state = "cooking"; meal.updatedAt = .now }
        }
    }
    func cancel(mealID: UUID) throws {
        try transaction { context in
            guard let meal = try context.fetch(FetchDescriptor<MealSelection>()).first(where: { $0.id == mealID }) else { throw MealError.missingItem }
            guard meal.isActive else { throw MealError.alreadyCompleted }
            meal.state = "cancelled"; meal.updatedAt = .now
            for row in try context.fetch(FetchDescriptor<ShoppingListItem>())
                where row.sourceMealID == mealID && !row.isAddedToInventory {
                // A checked purchase must remain available for fridge registration.
                if row.isChecked { row.sourceMealID = nil; row.sourceRecipeTitle = nil }
                else { context.delete(row) }
            }
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
            let stock = IngredientIdentity.snapshots(try context.fetch(FetchDescriptor<InventoryItem>()), customs: customs, masters: masters)
            try reconcileLaterShopping(after: meal, context: context, masters: masters, stock: stock)
        }
    }

    func saveManual(name: String, quantity: Double, unit: IngredientUnit, masterID: UUID? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, quantity.isFinite, quantity > 0 else { throw MealError.invalidQuantity }
        try transaction(changesInventory: false) { context in
            let candidates = IngredientNameResolver.candidates(trimmed, masters: try context.fetch(FetchDescriptor<IngredientMaster>()))
            let master: IngredientMaster?
            if let masterID {
                guard let selected = candidates.first(where: { $0.id == masterID }) else { throw InventoryError.missingIngredient }
                master = selected
            } else {
                guard candidates.count <= 1 else { throw MealError.ambiguousIngredient }
                master = candidates.first
            }
            if let master, !master.allowedUnits.contains(unit) { throw InventoryError.invalidUnit }
            context.insert(ShoppingListItem(masterID: master?.id, name: trimmed, quantity: quantity, unit: unit))
        }
    }
    /// An explicit material-screen purchase is independent of automatic recipe shopping.
    /// Recompute inside the save transaction, and credit existing pending/checked purchases.
    @discardableResult
    func addMaterialShortages(from startDate: Date, days: Int, materialIDs: Set<String>, now: Date = .now) throws -> Int {
        guard [1, 7].contains(days), MealPlanning.day(startDate) >= MealPlanning.day(now) else { throw MealError.invalidQuantity }
        return try transaction(changesInventory: false) { context in
            let start = MealPlanning.day(startDate)
            let dates = Set(MealPlanning.days(from: start).prefix(days))
            let meals = try context.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive)
            let visibleIDs = Set(meals.filter { dates.contains($0.plannedDay(on: now)) }.map(\.id))
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
            let catalog = try RecipeCatalog.load()
            let plans = meals.map { meal in
                let ingredients = meal.plannedIngredients(recipes: catalog)
                return PlannedMeal(id: meal.id, day: meal.plannedDay(on: now), createdAt: meal.date,
                    ingredients: ingredients ?? [], hasKnownIngredients: ingredients != nil)
            }
            let stock = IngredientIdentity.snapshots(try context.fetch(FetchDescriptor<InventoryItem>()), customs: customs, masters: masters)
            let summary = MealPlanning.summarize(plans, visibleIDs: visibleIDs,
                foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }, stock: stock)
            guard !summary.incomplete else { throw MealError.missingItem }
            let shopping = try context.fetch(FetchDescriptor<ShoppingListItem>())
            let mastersByKey = Dictionary(uniqueKeysWithValues: masters.filter(\.shoppingEligible).map { ($0.key, $0) })
            let coverage = MaterialShoppingCoverage.assess(plans: plans,
                foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }, stock: stock,
                purchases: shopping.map(MaterialPurchase.init), visibleMealIDs: visibleIDs)
            var count = 0
            for material in summary.displayMaterials where materialIDs.contains(material.id) && !material.optional && material.mode != "ignored" {
                guard let master = mastersByKey[material.key], let amount = coverage.remaining[material.id], amount > 0.0000001 else { continue }
                let row = ShoppingListItem(masterID: master.id, name: master.canonicalName,
                    quantity: amount, unit: material.unit, required: material.required,
                    needsConfirmation: material.hasConfirmation)
                row.materialScopeData = try JSONEncoder().encode(MaterialPurchaseScope(
                    mealIDs: visibleIDs.sorted { $0.uuidString < $1.uuidString }, materialID: material.id))
                context.insert(row)
                count += 1
            }
            return count
        }
    }
    func updateShopping(id: UUID, quantity: Double, unit: IngredientUnit) throws {
        guard quantity.isFinite, quantity > 0 else { throw MealError.invalidQuantity }
        try transaction(changesInventory: false) { context in
            var request = FetchDescriptor<ShoppingListItem>(predicate: #Predicate { $0.id == id && !$0.isAddedToInventory })
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else { throw MealError.missingItem }
            if let id = row.ingredientMasterID {
                var request = FetchDescriptor<IngredientMaster>(predicate: #Predicate { $0.id == id })
                request.fetchLimit = 1
                guard let master = try context.fetch(request).first,
                      master.allowedUnits.contains(unit) else { throw InventoryError.invalidUnit }
            }
            row.quantity = quantity; row.unit = unit; row.needsConfirmation = false
            row.automaticallyManaged = false
        }
    }
    func setChecked(id: UUID, checked: Bool) throws {
        try InventoryUndoCenter.transaction(container: container, changesInventory: false) { context in
            try ShoppingCheckPersistence.update(context, id: id, checked: checked)
        }
    }
    func removeShopping(id: UUID) throws {
        try transaction(changesInventory: false) { context in
            var request = FetchDescriptor<ShoppingListItem>(predicate: #Predicate { $0.id == id && !$0.isAddedToInventory })
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else { throw MealError.missingItem }
            context.delete(row)
        }
    }
    func removeCheckedShopping(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { throw MealError.missingItem }
        try transaction(changesInventory: false) { context in
            let rows = try context.fetch(FetchDescriptor<ShoppingListItem>()).filter { ids.contains($0.id) }
            guard rows.count == ids.count, rows.allSatisfy({ $0.isChecked && !$0.isAddedToInventory }) else {
                throw MealError.missingItem
            }
            rows.forEach { context.delete($0) }
        }
    }
    func purchase(_ drafts: [PurchaseDraft]) throws {
        guard !drafts.isEmpty, Set(drafts.map(\.id)).count == drafts.count else { throw MealError.missingItem }
        try transaction(title: "購入品の在庫登録") { context in
            let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            var stock = try context.fetch(FetchDescriptor<InventoryItem>())
            for draft in drafts {
                guard let row = rows.first(where: { $0.id == draft.id && $0.isChecked && !$0.isAddedToInventory }) else {
                    throw MealError.missingItem
                }
                let master = masters.first { $0.id == row.ingredientMasterID }
                let seasoning = master?.category == .seasoning
                guard seasoning || (draft.quantity.isFinite && draft.quantity > 0) else { throw MealError.invalidQuantity }
                if !draft.addToInventory { row.isAddedToInventory = true; continue }
                let reference: IngredientReference
                if let id = row.ingredientMasterID {
                    guard let master, seasoning || master.allowedUnits.contains(draft.unit) else {
                        throw InventoryError.invalidUnit
                    }
                    reference = .master(id)
                } else {
                    let custom = try CustomIngredient(name: row.name)
                    context.insert(custom); reference = .custom(custom.id)
                }
                // Automatically combine compatible lots while keeping expiry/storage information.
                let compatible = stock.filter {
                    mergeDuplicates && InventoryAddition.sameConditions(reference: reference,
                        storage: draft.storage, expiresAt: draft.expiresAt, expiryKind: draft.expiryKind, item: $0)
                }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
                if seasoning {
                    if let target = compatible.first {
                        let before = InventoryService.rawAmount(target)
                        try target.setAmount(.rough(draft.seasoningState))
                        context.insert(InventoryEvent(item: target, kind: "added", beforeAmount: before, note: "購入後の調味料の状態"))
                        for duplicate in compatible.dropFirst() {
                            let old = InventoryService.rawAmount(duplicate)
                            duplicate.isDeleted = true; duplicate.updatedAt = .now; duplicate.syncVersion += 1
                            context.insert(InventoryEvent(item: duplicate, kind: "merged", beforeAmount: old, note: "調味料の状態をまとめる"))
                        }
                    } else {
                        let item = try InventoryItem(ingredient: reference, amount: .rough(draft.seasoningState),
                            storage: draft.storage, purchasedAt: draft.purchasedAt, expiresAt: draft.expiresAt, expiryKind: draft.expiryKind)
                        context.insert(item); stock.append(item)
                        context.insert(InventoryEvent(item: item, kind: "added", note: "購入した調味料を登録"))
                    }
                    row.isAddedToInventory = true
                    continue
                }
                try InventoryAddition.add(reference: reference, amount: .exact(draft.quantity, draft.unit),
                    storage: draft.storage, purchasedAt: draft.purchasedAt, expiresAt: draft.expiresAt,
                    expiryKind: draft.expiryKind, merge: mergeDuplicates, inventory: &stock,
                    context: context, note: "購入品を登録")
                row.isAddedToInventory = true
            }
        }
    }

    func cook(mealID: UUID, recipe: Recipe, drafts: [CookingDraft], updateInventory: Bool = true) throws {
        try transaction(title: "調理完了") { context in
            guard let meal = try context.fetch(FetchDescriptor<MealSelection>()).first(where: { $0.id == mealID }) else {
                throw MealError.missingItem
            }
            guard meal.isActive else { throw MealError.alreadyCompleted }
            guard meal.recipeID == recipe.id else { throw MealError.missingItem }
            if meal.isPrepared || !updateInventory { if meal.scheduledDate == nil { meal.scheduledDate = MealPlanning.day(.now) }; meal.state = "cooked"; meal.updatedAt = .now; return }
            guard Set(drafts.map(\.ingredientKey)).count == drafts.count,
                  Set(drafts.map(\.ingredientKey)) == Set(recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map(\.ingredientKey)) else {
                throw MealError.missingItem
            }
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            let stock = try context.fetch(FetchDescriptor<InventoryItem>())
            // Validate every draft before any stock changes to avoid partial consumption.
            var exactChanges: [(InventoryItem, Double)] = []
            let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
            var roughChanges: [(InventoryItem, RoughStockState)] = []
            var remainingChanges: [(InventoryItem, RemainingStockAmount)] = []
            for draft in drafts {
                guard draft.quantity.isFinite, draft.quantity >= 0,
                      let ingredient = recipe.ingredients.first(where: { $0.ingredientKey == draft.ingredientKey }),
                      let master = masters.first(where: { $0.key == draft.ingredientKey }) else {
                    throw MealError.invalidQuantity
                }
                if ingredient.inventoryMode == "ignored" { continue }
                let lots = stock.filter { IngredientIdentity.masterID(for: $0, customs: customs, masters: masters) == master.id && InventoryService.usable($0, on: .now) }
                if !draft.seasoningStates.isEmpty {
                    guard (master.category == .seasoning || ingredient.inventoryMode == "presence"),
                          draft.quantity == 0, draft.inputMode == .used, draft.roughStates.isEmpty, draft.remainingAmounts.isEmpty else {
                        throw MealError.invalidQuantity
                    }
                    for (id, state) in draft.seasoningStates {
                        guard let lot = lots.first(where: { $0.id == id }) else { throw MealError.missingItem }
                        roughChanges.append((lot, state))
                    }
                    continue
                }
                guard Set(draft.roughStates.keys).isDisjoint(with: Set(draft.remainingAmounts.keys)) else { throw MealError.invalidQuantity }
                for (id, amount) in draft.remainingAmounts {
                    guard master.category != .seasoning && ingredient.inventoryMode != "presence",
                          amount.quantity.isFinite && amount.quantity >= 0,
                          master.allowedUnits.contains(amount.unit),
                          let lot = lots.first(where: { $0.id == id && $0.stockMode == .rough }) else {
                        throw MealError.invalidQuantity
                    }
                    remainingChanges.append((lot, amount))
                }
                for (id, state) in draft.roughStates {
                    guard let lot = lots.first(where: { $0.id == id && $0.stockMode == .rough }) else {
                        throw MealError.missingItem
                    }
                    roughChanges.append((lot, state))
                }
                let usedQuantity = try CookingAmounts.usage(for: draft, lots: lots.map(StockLot.init), unit: ingredient.unit)
                if usedQuantity == 0 { continue }
                let requirement = RecipeIngredient(ingredientKey: ingredient.ingredientKey, quantity: usedQuantity,
                    unit: ingredient.unit, requirement: "required", inventoryMode: "exact", scaling: "linear",
                    thawing: ingredient.thawing, note: nil)
                let result = RecipeAvailability.evaluate(requirement, servings: 1, lots: lots.map(StockLot.init))
                guard result.status == .available else { throw MealError.confirmationRequired }
                for change in result.consumption {
                    guard let lot = lots.first(where: { $0.id == change.id }), let unit = lot.unit,
                          let used = Units.convert(change.quantity, from: ingredient.unit, to: unit) else {
                        throw MealError.confirmationRequired
                    }
                    exactChanges.append((lot, used))
                }
            }
            for (lot, used) in exactChanges {
                let before = InventoryService.rawAmount(lot)
                try lot.setAmount(.exact(max(0, (lot.quantity ?? 0) - used), lot.unit!))
                context.insert(InventoryEvent(item: lot, kind: "cooked", beforeAmount: before, note: recipe.title))
            }
            for (lot, state) in roughChanges {
                let before = InventoryService.rawAmount(lot)
                try lot.setAmount(.rough(state))
                context.insert(InventoryEvent(item: lot, kind: "cooked", beforeAmount: before, note: recipe.title))
            }
            for (lot, amount) in remainingChanges {
                let before = InventoryService.rawAmount(lot)
                try lot.setAmount(.exact(amount.quantity, amount.unit))
                context.insert(InventoryEvent(item: lot, kind: "edited", beforeAmount: before,
                    note: recipe.title + "・調理後の残量を記録（使用量は不明）"))
            }
            if meal.scheduledDate == nil { meal.scheduledDate = MealPlanning.day(.now) }
            meal.state = "cooked"; meal.updatedAt = .now
        }
    }
    private func transaction<T>(title: String? = nil, changesInventory: Bool = true, _ body: (ModelContext) throws -> T) throws -> T {
        try InventoryUndoCenter.transaction(container: container, title: title, changesInventory: changesInventory, body)
    }
}
