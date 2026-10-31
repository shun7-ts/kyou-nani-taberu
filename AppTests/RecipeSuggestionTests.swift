import XCTest
import SwiftData
@testable import KyouNaniTaberu

final class RecipeSuggestionTests: XCTestCase {
    @MainActor func testWesternRecipesReachFoodFilterAndScaleForOneToFourPeople() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let recipes = try RecipeCatalog.load()
        let expected = [
            ("hamburg_mushroom_stew", "ground_mixed", 150.0), ("pork_chap", "pork_loin", 150.0),
            ("chicken_cheese_piccata", "chicken_breast", 150.0), ("salmon_spinach_cream_pasta", "salmon_fillet", 100.0),
            ("shrimp_broccoli_gratin", "shrimp", 80.0), ("beef_mushroom_hayashi", "beef_slices", 100.0),
            ("cod_lemon_meuniere", "cod_fillet", 120.0), ("german_potato", "potato", 150.0),
            ("mushroom_marinade", "shimeji", 70.0), ("corn_potage", "canned_corn", 100.0)]
        for (key, food, grams) in expected {
            for servings in 1...4 {
                let rows = RecipeSuggestions.candidates(recipes, foods: foods, stock: [], requiredIngredientKey: food,
                    servings: servings, allowedRoles: ["main", "side"])
                let row = try XCTUnwrap(rows.first { $0.recipe.key == key }, key)
                let ingredient = try XCTUnwrap(row.ingredients.first { $0.ingredient.ingredientKey == food })
                XCTAssertEqual(ingredient.ingredient.unit, .gram, key)
                XCTAssertEqual(ingredient.availability.shortage, grams * Double(servings), key)
                XCTAssertEqual(ingredient.availability.required, grams * Double(servings), key)
            }
        }
        let poultry = try XCTUnwrap(recipes.first { $0.key == "chicken_cheese_piccata" })
        XCTAssertTrue(poultry.steps.contains { ($0.tip ?? "").contains("75℃") })
        let soup = try XCTUnwrap(recipes.first { $0.key == "corn_potage" })
        XCTAssertEqual(soup.kind, .soup)
        XCTAssertTrue(soup.steps.contains { ($0.tip ?? "").contains("熱い液体は入れず") })
    }

    @MainActor func testPorkChapPurchasesOnlyShortageAndCookingUsesCombinedStock() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let loin = try XCTUnwrap(masters.first { $0.key == "pork_loin" })
        let initialID = try InventoryService(container: store).save(InventoryDraft(masterID: loin.id,
            amount: .exact(200, .gram), storage: .refrigerated))
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "pork_chap" })
        let service = MealService(container: store)
        try service.select(recipe: recipe, servings: 2)
        let shopping = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first { $0.ingredientMasterID == loin.id })
        XCTAssertEqual(shopping.quantity, 100); XCTAssertEqual(shopping.unit, .gram)
        try service.setChecked(id: shopping.id, checked: true)
        try service.purchase([PurchaseDraft(id: shopping.id, quantity: 150, unit: .gram,
            storage: .refrigerated, purchasedAt: .now)])
        let before = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).filter { $0.ingredientMasterID == loin.id && !$0.isDeleted }
        XCTAssertEqual(before.count, 1); XCTAssertEqual(before.first?.id, initialID); XCTAssertEqual(before.first?.quantity, 350)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.state == "selected" })
        let drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "pork_loin" ? 300 : 0)
        }
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts)
        let after = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == initialID })
        XCTAssertEqual(after.quantity, 50); XCTAssertEqual(after.unit, .gram)
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts))
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == initialID }?.quantity, 50)
    }

    @MainActor func testPorkThighRecipesReachIngredientFilterScalingAndShopping() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let recipes = try RecipeCatalog.load()
        let rows = RecipeSuggestions.candidates(recipes, foods: foods, stock: [], requiredIngredientKey: "pork_thigh", servings: 2)
        XCTAssertEqual(Set(rows.map { $0.recipe.key }), Set([
            "pork_thigh_ginger", "pork_thigh_cabbage_miso", "pork_thigh_pepper_stir", "pork_thigh_napa_simmer",
            "pork_thigh_sprout_steam", "pork_thigh_mushroom_ponzu", "pork_thigh_bowl", "pork_thigh_daikon_simmer"]))
        for row in rows {
            let meat = try XCTUnwrap(row.ingredients.first { $0.ingredient.ingredientKey == "pork_thigh" })
            XCTAssertEqual(meat.availability.shortage, 240)
            XCTAssertEqual(row.recipe.steps.compactMap(\.timerMinutes).reduce(0, +), row.recipe.minutes)
            XCTAssertTrue(row.recipe.steps.contains { ($0.tip ?? $0.text).contains("75℃") })
        }
        let dish = try XCTUnwrap(recipes.first { $0.key == "pork_thigh_ginger" })
        let service = MealService(container: store)
        try service.select(recipe: dish, servings: 2)
        let context = ModelContext(store)
        let thigh = try XCTUnwrap(masters.first { $0.key == "pork_thigh" })
        let meat = try XCTUnwrap(context.fetch(FetchDescriptor<ShoppingListItem>()).first { $0.ingredientMasterID == thigh.id })
        XCTAssertEqual(meat.name, "豚もも肉"); XCTAssertEqual(meat.quantity, 240); XCTAssertEqual(meat.unit, .gram)
        try service.setChecked(id: meat.id, checked: true)
        try service.purchase([PurchaseDraft(id: meat.id, quantity: 300, unit: .gram, storage: .refrigerated, purchasedAt: .now)])
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.state == "selected" })
        let drafts = dish.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "pork_thigh" ? 240 : 0)
        }
        try service.cook(mealID: meal.id, recipe: dish, drafts: drafts)
        let stock = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.ingredientMasterID == thigh.id })
        XCTAssertEqual(stock.quantity, 60); XCTAssertEqual(stock.unit, .gram)
    }
    private let egg = RecipeFood(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, key: "egg", name: "卵")
    private let milk = RecipeFood(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, key: "milk", name: "牛乳")
    private var now: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))! }
    private func ingredient(_ key: String = "egg", quantity: Double = 2, unit: IngredientUnit = .piece,
                            requirement: String = "required", mode: String = "exact", thawing: String = "none") -> RecipeIngredient {
        RecipeIngredient(ingredientKey: key, quantity: quantity, unit: unit, requirement: requirement,
            inventoryMode: mode, scaling: "linear", thawing: thawing, note: nil)
    }
    private func recipe(_ key: String = "test", ingredients: [RecipeIngredient]? = nil, minutes: Int = 10,
                        role: String = "main", status: String = "active", base: Int = 1) -> Recipe {
        Recipe(id: UUID(), key: key, title: key, summary: "", role: role, baseServings: base,
            prepMinutes: 0, cookMinutes: minutes, ingredients: ingredients ?? [ingredient()], steps: [], allergens: [], status: status)
    }
    private func evaluate(_ recipe: Recipe, stock: [StockLot], servings: Int = 1) -> RecipeSuggestion {
        RecipeSuggestions.evaluate(recipe, foods: [egg, milk], stock: stock, servings: servings, on: now)
    }
    @MainActor func testAddedThighRecipesReachFilteringScalingAndCombinedShortages() throws {
        let c = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: c)
        let masters = try ModelContext(c).fetch(FetchDescriptor<IngredientMaster>())
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let catalog = try RecipeCatalog.load()
        let keys: Set<String> = ["chicken_yurinchi", "chicken_daikon", "chikuzenni", "chicken_napa_cream", "garlic_chicken_saute", "chicken_cabbage_miso"]
        let rows = RecipeSuggestions.candidates(catalog, foods: foods, stock: [], requiredIngredientKey: "chicken_thigh", servings: 2)
        XCTAssertEqual(rows.count, 14)
        XCTAssertTrue(keys.isSubset(of: Set(rows.map { $0.recipe.key })))
        for row in rows where keys.contains(row.recipe.key) {
            let chicken = try XCTUnwrap(row.ingredients.first { $0.ingredient.ingredientKey == "chicken_thigh" })
            XCTAssertEqual(chicken.availability.shortage, chicken.ingredient.quantity * 2)
            XCTAssertTrue(row.recipe.steps.contains { $0.text.contains("75℃") && $0.text.contains("1分") })
            XCTAssertEqual(row.recipe.steps.compactMap(\.timerMinutes).reduce(0,+), row.recipe.minutes)
        }
        let dish = try XCTUnwrap(catalog.first { $0.key == "chicken_yurinchi" })
        let service = MealService(container: c)
        try service.select(recipe: dish, servings: 2)
        let chicken = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first { $0.name == "鶏もも肉" })
        XCTAssertEqual(chicken.quantity, 360); XCTAssertEqual(chicken.unit, .gram)
    }
    func testCookingTagsDoNotClaimRoughOrExpiredStockIsReady() {
        let meal = recipe(ingredients: [ingredient(), ingredient("milk", quantity: 100, unit: .milliliter)])
        let exact = [StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece),
                     StockLot(id: UUID(), masterID: milk.id, quantity: 100, unit: .milliliter)]
        XCTAssertEqual(evaluate(meal, stock: exact).cookingTags, [.ready])
        XCTAssertEqual(evaluate(meal, stock: exact, servings: 2).cookingTags, [.shopping])
        let mixed = [StockLot(id: UUID(), masterID: egg.id, roughState: .available)]
        XCTAssertEqual(evaluate(meal, stock: mixed).cookingTags, [.shopping, .quantity])
        XCTAssertEqual(evaluate(recipe(), stock: mixed).cookingTags, [.quantity])
        let expired = [StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece,
                               expiresAt: now.addingTimeInterval(-86400))]
        XCTAssertEqual(evaluate(recipe(), stock: expired).cookingTags, [.shopping])
        XCTAssertEqual(evaluate(recipe(ingredients: []), stock: exact).cookingTags, [.review])
    }
    func testMealPickerKeepsRiceFirstThenRanksByActualAvailability() {
        let salt = RecipeFood(id: UUID(), key: "salt", name: "塩")
        let stock = [StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece),
                     StockLot(id: UUID(), masterID: milk.id, roughState: .available)]
        let recipes = [
            recipe("buy_two", ingredients: [ingredient("salt", quantity: 1), ingredient("egg", quantity: 4)], minutes: 5),
            recipe("check", ingredients: [ingredient("milk", quantity: 100, unit: .milliliter)]),
            recipe("buy_one", ingredients: [ingredient("salt", quantity: 1)]),
            recipe("ready", ingredients: [ingredient()], minutes: 20),
            recipe("plain_rice", ingredients: [ingredient("salt", quantity: 1)], minutes: 30)
        ]
        let rows = RecipeSuggestions.mealPickerCandidates(recipes, foods: [egg, milk, salt], stock: stock,
            servings: 1, on: now)
        XCTAssertEqual(rows.map(\.recipe.key), ["plain_rice", "ready", "check", "buy_one", "buy_two"])
        XCTAssertTrue(rows[1].ready)
        XCTAssertEqual(rows[2].confirmation.count, 1)
        XCTAssertEqual(rows[3].shortages.count, 1)
        XCTAssertEqual(rows[4].shortages.count, 2)

        let twoServings = RecipeSuggestions.mealPickerCandidates(recipes, foods: [egg, milk, salt], stock: stock,
            servings: 2, on: now)
        XCTAssertEqual(twoServings.first?.recipe.key, "plain_rice")
        XCTAssertEqual(twoServings.dropFirst().first?.recipe.key, "check")
    }
    @MainActor func testFrenchItalianRecipesScaleAndReachShoppingWithNewMasters() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let keys: Set<String> = ["sausage_pot_au_feu", "onion_gratin_soup", "spinach_bacon_quiche", "nicoise_salad",
            "carottes_rapees", "potato_dauphinois", "caprese_salad", "vegetable_minestrone", "cod_acqua_pazza",
            "penne_arrabbiata", "potato_frittata", "mushroom_risotto"]
        let recipes = try RecipeCatalog.load().filter { keys.contains($0.key) }
        XCTAssertEqual(recipes.count, 12)
        XCTAssertEqual(recipes.filter { RecipeKind.main.includes($0) }.count, 5)
        XCTAssertEqual(recipes.filter { RecipeKind.side.includes($0) }.count, 4)
        XCTAssertEqual(recipes.filter { RecipeKind.soup.includes($0) }.count, 3)
        for servings in 1...4 {
            let rows = RecipeSuggestions.candidates(recipes, foods: foods, stock: [], servings: servings, allowedRoles: ["main", "side"])
            XCTAssertEqual(rows.count, 12)
            for row in rows {
                XCTAssertFalse(row.ready)
                XCTAssertEqual(row.recipe.steps.compactMap(\.timerMinutes).reduce(0,+), row.recipe.minutes)
                for ingredient in row.ingredients {
                    XCTAssertEqual(ingredient.availability.required, ingredient.ingredient.quantity * Double(servings), row.recipe.key)
                }
                XCTAssertTrue(row.recipe.steps.allSatisfy { !($0.timeNote ?? "").isEmpty })
            }
        }
        let caprese = try XCTUnwrap(recipes.first { $0.key == "caprese_salad" })
        let quiche = try XCTUnwrap(recipes.first { $0.key == "spinach_bacon_quiche" })
        let service = MealService(container: store)
        try service.select(recipe: caprese, servings: 2)
        try service.select(recipe: quiche, servings: 2)
        let shopping = try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>())
        let mozzarella = try XCTUnwrap(shopping.first { $0.name == "モッツァレラチーズ" })
        XCTAssertEqual(mozzarella.quantity, 120); XCTAssertEqual(mozzarella.unit, .gram)
        let pastry = try XCTUnwrap(shopping.first { $0.name == "冷凍パイシート" })
        XCTAssertEqual(pastry.quantity, 150); XCTAssertEqual(pastry.unit, .gram)
        XCTAssertFalse(shopping.contains { $0.name == "水" })
        XCTAssertTrue(caprese.allergens.contains("milk")); XCTAssertTrue(quiche.allergens.contains("wheat"))
        let risotto = try XCTUnwrap(recipes.first { $0.key == "mushroom_risotto" })
        XCTAssertEqual(risotto.ingredients.first { $0.ingredientKey == "raw_rice" }?.amount(servings: 2), 140)
        XCTAssertFalse(risotto.ingredients.contains { $0.ingredientKey == "cooked_rice" })
        let cheese = try XCTUnwrap(masters.first { $0.key == "mozzarella" })
        let rough = RecipeSuggestions.evaluate(caprese, foods: foods,
            stock: [StockLot(id: UUID(), masterID: cheese.id, roughState: .available)], servings: 2)
        XCTAssertFalse(rough.ready)
        XCTAssertTrue(rough.confirmation.contains { $0.ingredient.ingredientKey == "mozzarella" })
    }
    func testRoughAvailableMatchesWithoutClaimingQuantitySufficiency() {
        let result = evaluate(recipe(), stock: [StockLot(id: UUID(), masterID: egg.id, roughState: .available)])
        XCTAssertEqual(result.coverage, 1); XCTAssertEqual(result.matchedCount, 1)
        XCTAssertEqual(result.confirmation.count, 1); XCTAssertTrue(result.shortages.isEmpty)
        XCTAssertFalse(result.ready); XCTAssertTrue(result.reason.contains("確認"))
        XCTAssertEqual(result.confirmationLabel, "量を要確認：卵")
    }
    func testStoreQuantityParsingAndValidation() {
        XCTAssertEqual(StorePurchasePlan.parseQuantity("３００"), 300)
        XCTAssertEqual(StorePurchasePlan.parseQuantity("1,000.5"), 1000.5)
        XCTAssertEqual(StorePurchasePlan.parseQuantity(".5"), 0.5)
        for value in ["", "0", "-1", "NaN", "inf", "3,00", "300g", "1e3", "1.2.3"] {
            XCTAssertNil(StorePurchasePlan.parseQuantity(value), value)
        }
        for value in [0.0, -1, .infinity, .nan] {
            XCTAssertFalse(StorePurchasePlan(ingredientKey: "egg", quantity: value, unit: .piece).isValid)
        }
        XCTAssertFalse(StorePurchasePlan(ingredientKey: "milk", quantity: .greatestFiniteMagnitude, unit: .liter).isValid)
    }
    func testStoreAmountAddsOnlyUsableStockAndScalesWithServings() {
        let meal = recipe(ingredients: [ingredient("milk", quantity: 300, unit: .milliliter)])
        let plan = StorePurchasePlan(ingredientKey: milk.key, quantity: 0.2, unit: .liter)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let lots = [StockLot(id: UUID(), masterID: milk.id, quantity: 100, unit: .milliliter),
            StockLot(id: UUID(), masterID: milk.id, quantity: 1000, unit: .milliliter, expiresAt: yesterday),
            StockLot(id: UUID(), masterID: milk.id, quantity: 1000, unit: .milliliter, isDeleted: true)]
        let one = RecipeSuggestions.evaluate(meal, foods: [milk], stock: lots,
            shoppingIngredientKey: milk.key, storePlan: plan, on: now)
        XCTAssertEqual(one.plannedAvailability?.status, .available)
        XCTAssertEqual(one.plannedIngredient?.availability.shortage, 200)
        XCTAssertFalse(one.ready)
        let two = RecipeSuggestions.evaluate(meal, foods: [milk], stock: lots, servings: 2,
            shoppingIngredientKey: milk.key, storePlan: plan, on: now)
        XCTAssertEqual(two.plannedAvailability?.status, .shortage)
        XCTAssertEqual(two.plannedAvailability?.shortage, 300)
    }
    func testStoreAmountKeepsUnknownUnitsAndRoughStockUncertainUnlessKnownAmountSuffices() {
        let meal = recipe(), rough = [StockLot(id: UUID(), masterID: egg.id, roughState: .available)]
        let small = StorePurchasePlan(ingredientKey: egg.key, quantity: 1, unit: .piece)
        let uncertain = RecipeSuggestions.evaluate(meal, foods: [egg], stock: rough,
            shoppingIngredientKey: egg.key, storePlan: small, on: now)
        XCTAssertEqual(uncertain.plannedAvailability?.status, .confirmation)
        let enough = RecipeSuggestions.evaluate(meal, foods: [egg], stock: rough,
            shoppingIngredientKey: egg.key, storePlan: StorePurchasePlan(ingredientKey: egg.key, quantity: 2, unit: .piece), on: now)
        XCTAssertEqual(enough.plannedAvailability?.status, .available)
        let pack = RecipeSuggestions.evaluate(meal, foods: [egg], stock: [],
            shoppingIngredientKey: egg.key, storePlan: StorePurchasePlan(ingredientKey: egg.key, quantity: 1, unit: .pack), on: now)
        XCTAssertEqual(pack.plannedAvailability?.status, .confirmation)
        let presence = RecipeSuggestions.evaluate(recipe(ingredients: [ingredient(mode: "presence")]), foods: [egg], stock: [],
            shoppingIngredientKey: egg.key, storePlan: small, on: now)
        XCTAssertEqual(presence.plannedAvailability?.status, .shortage)
    }
    func testStoreAmountRanksEnoughFirstAndCanFilterToEnoughOnly() {
        let recipes = [recipe("large", ingredients: [ingredient(quantity: 3)], minutes: 1),
            recipe("small", ingredients: [ingredient(quantity: 1)], minutes: 30)]
        let plan = StorePurchasePlan(ingredientKey: egg.key, quantity: 2, unit: .piece)
        let all = RecipeSuggestions.candidates(recipes, foods: [egg], stock: [], requiredIngredientKey: egg.key,
            shoppingIngredientKey: egg.key, storePlan: plan, on: now)
        XCTAssertEqual(all.map { $0.recipe.key }, ["small", "large"])
        let only = RecipeSuggestions.candidates(recipes, foods: [egg], stock: [], requiredIngredientKey: egg.key,
            shoppingIngredientKey: egg.key, storePlan: plan, onlyEnoughForPlannedIngredient: true, on: now)
        XCTAssertEqual(only.map { $0.recipe.key }, ["small"])
        XCTAssertTrue(RecipeSuggestions.candidates(recipes, foods: [egg], stock: [], requiredIngredientKey: egg.key,
            shoppingIngredientKey: egg.key, onlyEnoughForPlannedIngredient: true, on: now).isEmpty)
        let mismatch = RecipeSuggestions.evaluate(recipes[0], foods: [egg], stock: [], shoppingIngredientKey: egg.key,
            storePlan: StorePurchasePlan(ingredientKey: milk.key, quantity: 500, unit: .milliliter), on: now)
        XCTAssertNil(mismatch.plannedAvailability)
    }
    @MainActor func testStorePurchaseKeepsWhole300GramsAndCookingLeaves150Grams() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let meal = recipe("chicken", ingredients: [ingredient("chicken_thigh", quantity: 150, unit: .gram)])
        let plan = StorePurchasePlan(ingredientKey: "chicken_thigh", quantity: 300, unit: .gram)
        let service = MealService(container: store)
        XCTAssertEqual(try service.select(recipe: meal, servings: 1, storePlan: plan), 1)
        var context = ModelContext(store)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertEqual(row.quantity, 300); XCTAssertEqual(row.requiredQuantity, 150)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
        try service.setChecked(id: row.id, checked: true)
        try service.purchase([PurchaseDraft(id: row.id, quantity: row.quantity, unit: row.unit,
            storage: .refrigerated, purchasedAt: .now)])
        context = ModelContext(store)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 300)
        let selected = try XCTUnwrap(context.fetch(FetchDescriptor<MealSelection>()).first)
        try service.cook(mealID: selected.id, recipe: meal, drafts: [CookingDraft(ingredientKey: "chicken_thigh", quantity: 150)])
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 150)
    }
    @MainActor func testInsufficientAndInvalidStorePlanDoNotReplaceExistingMealOrShopping() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let service = MealService(container: store)
        let meal = recipe(ingredients: [ingredient()])
        try service.select(recipe: meal, servings: 1)
        try service.saveManual(name: "スポンジ", quantity: 1, unit: .piece)
        let before = try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).map(\.id).sorted { $0.uuidString < $1.uuidString }
        for plan in [StorePurchasePlan(ingredientKey: "egg", quantity: 1, unit: .piece),
            StorePurchasePlan(ingredientKey: "egg", quantity: 0, unit: .piece),
            StorePurchasePlan(ingredientKey: "unknown", quantity: 300, unit: .gram),
            StorePurchasePlan(ingredientKey: "egg", quantity: 5, unit: .liter)] {
            XCTAssertThrowsError(try service.select(recipe: meal, servings: 1, storePlan: plan))
        }
        let context = ModelContext(store)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingListItem>()).map(\.id).sorted { $0.uuidString < $1.uuidString }, before)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealSelection>()).filter { $0.state == "selected" }.count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
    }
    @MainActor func testStorePlanQuantityIsPreservedEvenWhenFridgeAlreadyHasEnough() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let master = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "chicken_thigh" })
        try InventoryService(container: store).save(InventoryDraft(masterID: master.id, amount: .exact(150, .gram)))
        let service = MealService(container: store)
        try service.select(recipe: recipe(ingredients: [ingredient("chicken_thigh", quantity: 150, unit: .gram)]), servings: 1,
            storePlan: StorePurchasePlan(ingredientKey: "chicken_thigh", quantity: 0.3, unit: .kilogram))
        let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertEqual(row.quantity, 0.3); XCTAssertEqual(row.unit, .kilogram)
        XCTAssertEqual(row.requiredQuantity, 0.15)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 150)
    }
    func testShoppingComparisonUsesOtherIngredientsWithoutFakingStock() {
        let meal = recipe(ingredients: [ingredient(), ingredient("milk", quantity: 100, unit: .milliliter)])
        let lots = [StockLot(id: UUID(), masterID: milk.id, quantity: 100, unit: .milliliter)]
        let result = RecipeSuggestions.evaluate(meal, foods: [egg, milk], stock: lots,
            shoppingIngredientKey: egg.key, on: now)
        XCTAssertEqual(result.coverage, 1); XCTAssertEqual(result.comparisonIngredients.count, 1)
        XCTAssertEqual(result.plannedIngredient?.availability.status, .shortage)
        XCTAssertEqual(result.plannedIngredient?.availability.shortage, 2)
        XCTAssertFalse(result.ready); XCTAssertEqual(result.shortages.count, 1)
        XCTAssertNil(result.shortageLabel); XCTAssertTrue(result.reason.contains("必要量買えば"))
        XCTAssertTrue(result.matchLabel.contains("ほかの食材一致 100%"))
        let normal = evaluate(meal, stock: lots)
        XCTAssertEqual(normal.coverage, 0.5); XCTAssertNil(normal.plannedLabel)
    }
    func testShoppingComparisonRetainsAdditionalShortagesAndRoughConfirmation() {
        let meal = recipe(ingredients: [ingredient(), ingredient("milk", quantity: 100, unit: .milliliter)])
        let expired = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let result = RecipeSuggestions.evaluate(meal, foods: [egg, milk],
            stock: [StockLot(id: UUID(), masterID: milk.id, quantity: 500, unit: .milliliter, expiresAt: expired)],
            shoppingIngredientKey: egg.key, on: now)
        XCTAssertEqual(result.coverage, 0)
        XCTAssertEqual(result.shortageLabel, "追加の買い足し 1品：牛乳")
        let rough = RecipeSuggestions.evaluate(meal, foods: [egg, milk],
            stock: [StockLot(id: UUID(), masterID: milk.id, roughState: .available)],
            shoppingIngredientKey: egg.key, on: now)
        XCTAssertEqual(rough.coverage, 1); XCTAssertEqual(rough.additionalConfirmation.count, 1)
        XCTAssertTrue(rough.reason.contains("量の確認")); XCTAssertFalse(rough.ready)
        XCTAssertNil(rough.shortageLabel)
    }
    func testShoppingComparisonRequiredAmountScalesAndEmptyRemainderIsExplicit() {
        let result = RecipeSuggestions.evaluate(recipe(), foods: [egg], stock: [],
            servings: 2, shoppingIngredientKey: egg.key, on: now)
        XCTAssertEqual(result.plannedIngredient?.availability.required, 4)
        XCTAssertEqual(result.coverage, 1); XCTAssertFalse(result.ready)
        XCTAssertEqual(result.matchLabel, "ほかに必要な材料はありません")
        XCTAssertTrue(result.plannedLabel?.contains("2人分") == true)
        for ingredient in [ingredient(requirement: "optional"), ingredient(mode: "ignored"), ingredient(quantity: 0)] {
            let row = RecipeSuggestions.evaluate(recipe(ingredients: [ingredient]), foods: [egg], stock: [],
                shoppingIngredientKey: egg.key, on: now)
            XCTAssertNil(row.plannedIngredient)
        }
    }
    func testShoppingCandidatesKeepFilterAndPreferFewerExtraPurchasesOnTie() {
        let small = recipe("small", ingredients: [ingredient(), ingredient("milk", unit: .milliliter)], minutes: 30)
        let large = recipe("large", ingredients: [ingredient(), ingredient("milk", unit: .milliliter), ingredient("other")], minutes: 1)
        let values = [large, small, recipe("unrelated", ingredients: [ingredient("milk", unit: .milliliter)])]
        let rows = RecipeSuggestions.candidates(values, foods: [egg, milk], stock: [],
            requiredIngredientKey: egg.key, shoppingIngredientKey: egg.key, on: now)
        XCTAssertEqual(rows.map { $0.recipe.key }, ["small", "large"])
        let mismatch = RecipeSuggestions.candidates(values, foods: [egg, milk], stock: [],
            requiredIngredientKey: egg.key, shoppingIngredientKey: milk.key, on: now)
        XCTAssertTrue(mismatch.allSatisfy { $0.plannedIngredient == nil })
    }
    @MainActor func testShoppingComparisonDoesNotPurchaseOrRemovePlannedFoodFromShopping() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let context = ModelContext(store)
        let foods = try context.fetch(FetchDescriptor<IngredientMaster>()).map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let recipe = try XCTUnwrap(try RecipeCatalog.load().first { $0.key == "tuna_mayo_bowl" })
        let result = RecipeSuggestions.evaluate(recipe, foods: foods, stock: [], shoppingIngredientKey: "canned_tuna")
        XCTAssertEqual(result.additionalShortages.count, 3); XCTAssertEqual(result.shortages.count, 4)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
        XCTAssertEqual(try MealService(container: store).select(recipe: recipe, servings: 1), 4)
        let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.first { $0.name == "ツナ缶" }?.quantity, 1)
        XCTAssertTrue(rows.allSatisfy { !$0.isChecked && !$0.isAddedToInventory })
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }
    func testLowNoneAndIncompatibleUnitsRemainDistinct() {
        let low = evaluate(recipe(), stock: [StockLot(id: UUID(), masterID: egg.id, roughState: .low)])
        XCTAssertEqual(low.coverage, 0); XCTAssertEqual(low.confirmation.count, 1); XCTAssertTrue(low.shortages.isEmpty)
        let none = evaluate(recipe(), stock: [StockLot(id: UUID(), masterID: egg.id, roughState: .unavailable)])
        XCTAssertEqual(none.shortages.count, 1); XCTAssertTrue(none.confirmation.isEmpty)
        let incompatible = evaluate(recipe(), stock: [StockLot(id: UUID(), masterID: egg.id, quantity: 5, unit: .pack)])
        XCTAssertEqual(incompatible.coverage, 0); XCTAssertEqual(incompatible.confirmation.count, 1)
        XCTAssertNil(incompatible.shortageLabel)
    }
    func testCompatibleConversionAndBaseServingsAgreeWithDetail() {
        let meal = recipe(ingredients: [ingredient("milk", quantity: 1, unit: .liter)], base: 2)
        let lots = [StockLot(id: UUID(), masterID: milk.id, quantity: 500, unit: .milliliter)]
        let one = evaluate(meal, stock: lots)
        XCTAssertTrue(one.ready); XCTAssertEqual(one.required.first?.availability.required, 0.5)
        XCTAssertTrue(RecipeAvailability.matches(meal.ingredients[0], lots: lots, servings: 1, base: 2, on: now))
        let four = evaluate(meal, stock: lots, servings: 4)
        XCTAssertFalse(four.ready); XCTAssertEqual(four.coverage, 0)
        XCTAssertEqual(four.shortages.first?.availability.shortage, 1.5)
    }
    func testOptionalAndIgnoredIngredientsDoNotChangeMatchingOrPurchaseSummary() {
        let meal = recipe(ingredients: [ingredient(), ingredient("milk", requirement: "optional"), ingredient("water", mode: "ignored")])
        let result = evaluate(meal, stock: [StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece)])
        XCTAssertEqual(result.required.count, 1); XCTAssertEqual(result.coverage, 1); XCTAssertTrue(result.ready)
        XCTAssertNil(result.shortageLabel); XCTAssertNil(result.confirmationLabel)
        XCTAssertEqual(result.ingredients.count, 3)
    }
    func testExpiredDeletedZeroAndUnmappedCustomStockCannotIncreaseMatch() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let result = evaluate(recipe(), stock: [
            StockLot(id: UUID(), masterID: egg.id, quantity: 5, unit: .piece, expiresAt: yesterday),
            StockLot(id: UUID(), masterID: egg.id, quantity: 5, unit: .piece, isDeleted: true),
            StockLot(id: UUID(), masterID: egg.id, quantity: 0, unit: .piece),
            StockLot(id: UUID(), quantity: 5, unit: .piece)])
        XCTAssertEqual(result.coverage, 0); XCTAssertEqual(result.shortages.first?.availability.shortage, 2)
        let today = evaluate(recipe(), stock: [StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece, expiresAt: now)])
        XCTAssertTrue(today.ready)
    }
    func testHigherMatchWinsBeforeCertaintyOrSpeed() {
        let mostly = recipe("mostly", ingredients: [ingredient(), ingredient("milk", unit: .milliliter)], minutes: 60)
        let empty = recipe("empty", ingredients: [ingredient("milk", unit: .milliliter)], minutes: 1)
        let rows = RecipeSuggestions.candidates([empty, mostly], foods: [egg, milk],
            stock: [StockLot(id: UUID(), masterID: egg.id, roughState: .available)], on: now)
        XCTAssertEqual(rows.map { $0.recipe.key }, ["mostly", "empty"])
    }
    func testEqualMatchPrefersKnownAmountsBeforeSpeed() {
        let certain = recipe("certain", minutes: 60)
        let uncertain = recipe("uncertain", ingredients: [ingredient("milk", unit: .milliliter)], minutes: 1)
        let rows = RecipeSuggestions.candidates([uncertain, certain], foods: [egg, milk], stock: [
            StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece),
            StockLot(id: UUID(), masterID: milk.id, roughState: .available)], on: now)
        XCTAssertEqual(rows.map { $0.recipe.key }, ["certain", "uncertain"])
        XCTAssertTrue(rows[0].ready); XCTAssertFalse(rows[1].ready)
    }
    func testSideAndInactiveAreExcludedAndTiesAreStableAcrossInputOrder() {
        let alpha = recipe("alpha"), beta = recipe("beta"), slow = recipe("slow", minutes: 20)
        let values = [beta, recipe("side", minutes: 1, role: "side"), slow, recipe("inactive", status: "deprecated"), alpha]
        for input in [values, values.reversed().map { $0 }] {
            let rows = RecipeSuggestions.candidates(input, foods: [egg], stock: [], on: now)
            XCTAssertEqual(rows.map { $0.recipe.key }, ["alpha", "beta", "slow"])
        }
    }
    func testExpiryAndThawingDoNotPenalizeOtherwiseEqualCandidates() {
        let a = recipe("alpha"), b = recipe("beta", ingredients: [ingredient("milk", quantity: 2, unit: .milliliter)])
        let lots = [StockLot(id: UUID(), masterID: egg.id, quantity: 2, unit: .piece, storage: .frozen),
            StockLot(id: UUID(), masterID: milk.id, quantity: 2, unit: .milliliter, expiresAt: now)]
        let rows = RecipeSuggestions.candidates([b, a], foods: [egg, milk], stock: lots, on: now)
        XCTAssertEqual(rows.map { $0.recipe.key }, ["alpha", "beta"])
        XCTAssertEqual(rows[0].thawingLabel, "解凍が必要：卵")
        let frozen = evaluate(recipe(ingredients: [ingredient(thawing: "cook_from_frozen")]), stock: [lots[0]])
        XCTAssertNil(frozen.thawingLabel); XCTAssertEqual(frozen.frozenCookingLabel, "凍ったまま調理：卵")
    }
    func testNearExpiryUsesCalendarDaysAndSeparatesExpiredAndEmptyLots() {
        let calendar = Calendar.current
        func at(_ days: Int, hour: Int = 23) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: now)!
            return calendar.date(bySettingHour: hour, minute: 59, second: 0, of: day)!
        }
        let past = StockLot(id: UUID(), roughState: .available, expiresAt: at(-1))
        let today = StockLot(id: UUID(), roughState: .low, expiresAt: at(0))
        let lastDay = StockLot(id: UUID(), quantity: 1, unit: .piece, expiresAt: at(2))
        let later = StockLot(id: UUID(), roughState: .available, expiresAt: at(3))
        let empty = StockLot(id: UUID(), quantity: 0, unit: .piece, expiresAt: at(0))
        let removed = StockLot(id: UUID(), roughState: .available, expiresAt: at(0), isDeleted: true)
        let none = StockLot(id: UUID(), roughState: .available)
        let stock = [past, today, lastDay, later, empty, removed, none]
        XCTAssertEqual(StockExpiry.near(stock, on: now), [today.id, lastDay.id])
        XCTAssertEqual(StockExpiry.expired(stock, on: now), [past.id])
        XCTAssertEqual(StockExpiry.near(stock, on: now, days: 0), [today.id])
    }
    func testEmptyRequiredSetAndZeroFrozenStockDoNotClaimReadinessOrThawing() {
        let empty = evaluate(recipe(ingredients: [ingredient(requirement: "optional")]), stock: [])
        XCTAssertEqual(empty.coverage, 0); XCTAssertFalse(empty.ready)
        let zero = evaluate(recipe(), stock: [StockLot(id: UUID(), masterID: egg.id, quantity: 0, unit: .piece, storage: .frozen)])
        XCTAssertNil(zero.thawingLabel)
    }
    @MainActor func testAllBundledRecipesHaveConsistentAssessmentAndMainCandidates() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let context = SwiftData.ModelContext(store)
        let foods = try context.fetch(SwiftData.FetchDescriptor<IngredientMaster>()).map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let recipes = try RecipeCatalog.load(), rows = RecipeSuggestions.candidates(recipes, foods: foods, stock: [], on: now)
        XCTAssertEqual(rows.count, 116); XCTAssertEqual(rows.first?.recipe.key, "tuna_mayo_bowl")
        for recipe in recipes {
            let result = RecipeSuggestions.evaluate(recipe, foods: foods, stock: [], on: now)
            XCTAssertFalse(result.ingredients.contains { $0.name == "未登録の食材" }, recipe.key)
            XCTAssertEqual(result.confirmation.count, 0)
            XCTAssertEqual(result.shortages.count, result.required.count)
            XCTAssertFalse(result.ready)
        }
    }
    func testIngredientFilterExcludesOptionalIgnoredAndSimilarKeys() {
        let required = recipe("required")
        let optional = recipe("optional", ingredients: [ingredient(requirement: "optional")])
        let ignored = recipe("ignored", ingredients: [ingredient(mode: "ignored")])
        let similar = recipe("egg", ingredients: [ingredient("egg_white")])
        let zero = recipe("zero", ingredients: [ingredient(quantity: 0)])
        let values = [required, optional, ignored, similar, zero]
        XCTAssertEqual(RecipeSuggestions.candidates(values, foods: [egg], stock: [],
            requiredIngredientKey: egg.key, on: now).map { $0.recipe.key }, ["required"])
    }
    func testIngredientFilterDoesNotRelaxForMissingExpiredOrRoughStock() {
        let selected = recipe(ingredients: [ingredient(), ingredient("milk", unit: .milliliter)])
        let unrelated = recipe("unrelated", ingredients: [ingredient("milk", unit: .milliliter)])
        let expired = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        for lots in [[], [StockLot(id: UUID(), masterID: egg.id, quantity: 6, unit: .piece, expiresAt: expired)]] {
            let rows = RecipeSuggestions.candidates([unrelated, selected], foods: [egg, milk], stock: lots,
                requiredIngredientKey: egg.key, on: now)
            XCTAssertEqual(rows.map { $0.recipe.key }, [selected.key])
            XCTAssertEqual(rows[0].shortages.count, 2)
        }
        let rough = RecipeSuggestions.candidates([selected], foods: [egg, milk],
            stock: [StockLot(id: UUID(), masterID: egg.id, roughState: .available)],
            requiredIngredientKey: egg.key, on: now)[0]
        XCTAssertEqual(rough.confirmation.map { $0.name }, ["卵"])
        XCTAssertEqual(rough.shortages.map { $0.name }, ["牛乳"])
    }
    func testIngredientFilterPreservesRankingAndClearingRestoresCandidates() {
        let values = [recipe("slow", minutes: 30), recipe("fast", minutes: 5),
            recipe("milk", ingredients: [ingredient("milk", unit: .milliliter)], minutes: 1)]
        let all = RecipeSuggestions.candidates(values, foods: [egg, milk], stock: [], on: now)
        let filtered = RecipeSuggestions.candidates(values, foods: [egg, milk], stock: [], requiredIngredientKey: egg.key, on: now)
        XCTAssertEqual(filtered.map { $0.recipe.key }, ["fast", "slow"])
        XCTAssertEqual(all.filter { RecipeSuggestions.includesRequiredIngredient($0.recipe, key: egg.key) }.map(\.id), filtered.map(\.id))
        XCTAssertEqual(RecipeSuggestions.candidates(values, foods: [egg, milk], stock: [], requiredIngredientKey: nil, on: now).map(\.id), all.map(\.id))
        XCTAssertTrue(RecipeSuggestions.candidates(values, foods: [egg], stock: [], requiredIngredientKey: "unknown", on: now).isEmpty)
    }
    @MainActor func testBundledIngredientFiltersUseRequiredMaterialsForEveryFood() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let context = ModelContext(store)
        let foods = try context.fetch(FetchDescriptor<IngredientMaster>()).map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let recipes = try RecipeCatalog.load()
        let all = RecipeSuggestions.candidates(recipes, foods: foods, stock: [], on: now)
        for food in foods {
            let rows = RecipeSuggestions.candidates(recipes, foods: foods, stock: [], requiredIngredientKey: food.key, on: now)
            let expected = all.filter { $0.recipe.ingredients.contains { $0.ingredientKey == food.key && $0.requirement == "required" && $0.inventoryMode != "ignored" && $0.quantity > 0 } }
            XCTAssertEqual(rows.map(\.id), expected.map(\.id), food.key)
        }
    }
    @MainActor func testHomeMemoReusesSameDayAndInvalidatesEveryAvailabilityInput() {
        let cache = HomeSuggestionCache(), dish = recipe()
        let lotID = UUID()
        func run(_ dishes: [Recipe] = [], foods: [RecipeFood]? = nil, quantity: Double = 2,
                 expires: Date? = nil, deleted: Bool = false, masterID: UUID? = nil,
                 servings: Int = 1, key: String? = nil, date: Date? = nil) -> [RecipeSuggestion] {
            cache.candidates(dishes.isEmpty ? [dish] : dishes, foods: foods ?? [egg],
                stock: [StockLot(id: lotID, masterID: masterID ?? egg.id, quantity: quantity, unit: .piece,
                    expiresAt: expires, purchasedAt: now, isDeleted: deleted)], requiredIngredientKey: key, servings: servings, on: date ?? now)
        }
        XCTAssertTrue(run()[0].ready)
        for _ in 0..<20 { XCTAssertTrue(run(date: now.addingTimeInterval(60))[0].ready) }
        XCTAssertEqual(cache.evaluationCount, 1, "Same-day navigation and minute ticks reuse the evaluation")
        XCTAssertFalse(run(quantity: 1)[0].ready)
        XCTAssertEqual(cache.evaluationCount, 2)
        XCTAssertFalse(run(deleted: true)[0].ready)
        XCTAssertEqual(cache.evaluationCount, 3)
        XCTAssertFalse(run(masterID: milk.id)[0].ready)
        XCTAssertEqual(cache.evaluationCount, 4)
        XCTAssertFalse(run(servings: 2)[0].ready)
        XCTAssertEqual(cache.evaluationCount, 5)
        XCTAssertTrue(run(key: "milk").isEmpty)
        XCTAssertEqual(cache.evaluationCount, 6)
        XCTAssertEqual(run(foods: [RecipeFood(id: egg.id, key: egg.key, name: "たまご")])[0].ingredients[0].name, "たまご")
        XCTAssertEqual(cache.evaluationCount, 7)
        var revised = dish; revised.steps = [Recipe.Step(order: 1, text: "新しい手順", timerMinutes: 3)]
        XCTAssertEqual(run([revised])[0].recipe.steps[0].text, "新しい手順")
        XCTAssertEqual(cache.evaluationCount, 8)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now)!
        XCTAssertTrue(run(expires: now, date: endOfDay)[0].ready)
        XCTAssertFalse(run(expires: now, date: endOfDay.addingTimeInterval(120))[0].ready)
        XCTAssertEqual(cache.evaluationCount, 10, "Expiry is reevaluated after midnight")
        XCTAssertTrue(run(expires: now, date: now)[0].ready)
        XCTAssertEqual(cache.evaluationCount, 11, "Returning across a calendar day also invalidates")
        func changedStock(_ lot: StockLot) -> RecipeSuggestion {
            cache.candidates([dish], foods: [egg], stock: [lot], requiredIngredientKey: nil, servings: 1, on: now)[0]
        }
        XCTAssertEqual(changedStock(StockLot(id: lotID, masterID: egg.id, roughState: .available, purchasedAt: now)).confirmation.count, 1)
        XCTAssertEqual(changedStock(StockLot(id: lotID, masterID: egg.id, roughState: .unavailable, purchasedAt: now)).shortages.count, 1)
        XCTAssertEqual(changedStock(StockLot(id: lotID, masterID: egg.id, quantity: 2, unit: .gram, purchasedAt: now)).confirmation.count, 1)
        XCTAssertEqual(cache.evaluationCount, 14)
    }
    @MainActor func testIndexedRecommendationsPreserveCatalogRankingAndMeasureReuse() throws {
        let container = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: container)
        let masters = try ModelContext(container).fetch(FetchDescriptor<IngredientMaster>())
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let recipes = try RecipeCatalog.load()
        let lots = masters.enumerated().map { offset, master in
            StockLot(id: UUID(), masterID: master.id,
                quantity: offset % 4 == 0 ? nil : Double(offset % 7 + 1),
                unit: offset % 4 == 0 ? nil : master.defaultUnit,
                roughState: offset % 4 == 0 ? .available : nil,
                expiresAt: offset % 6 == 0 ? now.addingTimeInterval(-86400) : nil,
                isDeleted: offset % 11 == 0)
        }
        // Original ranking and per-recipe index construction serve as an independent reference.
        func reference(key: String? = nil, servings: Int = 1, plan: StorePurchasePlan? = nil) -> [RecipeSuggestion] {
            recipes.filter { !$0.isPlainRice && ["main", "side"].contains($0.role) && $0.status == "active"
                && RecipeSuggestions.includesRequiredIngredient($0, key: key) }
                .map { RecipeSuggestions.evaluate($0, foods: foods, stock: lots, servings: servings,
                    shoppingIngredientKey: plan == nil ? nil : key, storePlan: plan, on: now) }
                .sorted {
                    if $0.plannedAmountRank != $1.plannedAmountRank { return $0.plannedAmountRank < $1.plannedAmountRank }
                    if $0.coverage != $1.coverage { return $0.coverage > $1.coverage }
                    if $0.plannedIngredient != nil && $1.plannedIngredient != nil && $0.additionalShortages.count != $1.additionalShortages.count {
                        return $0.additionalShortages.count < $1.additionalShortages.count
                    }
                    if $0.additionalConfirmation.count != $1.additionalConfirmation.count { return $0.additionalConfirmation.count < $1.additionalConfirmation.count }
                    if $0.recipe.minutes != $1.recipe.minutes { return $0.recipe.minutes < $1.recipe.minutes }
                    if $0.recipe.key != $1.recipe.key { return $0.recipe.key < $1.recipe.key }
                    return $0.id.uuidString < $1.id.uuidString
                }
        }
        for (key, servings, plan) in [(nil, 1, nil), (nil, 2, nil), ("egg", 2, nil),
            ("egg", 1, StorePurchasePlan(ingredientKey: "egg", quantity: 2, unit: .piece))] as [(String?, Int, StorePurchasePlan?)] {
            let old = reference(key: key, servings: servings, plan: plan)
            let new = RecipeSuggestions.candidates(recipes, foods: foods, stock: lots, requiredIngredientKey: key,
                shoppingIngredientKey: plan == nil ? nil : key, storePlan: plan, servings: servings, allowedRoles: ["main", "side"], on: now)
            XCTAssertEqual(new.map(\.id), old.map(\.id))
            for (left, right) in zip(new, old) {
                XCTAssertEqual(left.ingredients.map { $0.availability.status }, right.ingredients.map { $0.availability.status })
                XCTAssertEqual(left.ingredients.map { $0.availability.shortage }, right.ingredients.map { $0.availability.shortage })
            }
        }
        func median(_ work: () -> Void) -> Double {
            (0..<9).map { _ in let start = Date.timeIntervalSinceReferenceDate; work(); return (Date.timeIntervalSinceReferenceDate - start) * 1000 }.sorted()[4]
        }
        let oldMS = median { _ = reference() }
        let newMS = median { _ = RecipeSuggestions.candidates(recipes, foods: foods, stock: lots, allowedRoles: ["main", "side"], on: now) }
        let cache = HomeSuggestionCache()
        _ = cache.candidates(recipes, foods: foods, stock: lots, requiredIngredientKey: nil, servings: 1, on: now)
        // Home rebuilds value snapshots on each body, so measure equal values in fresh arrays.
        let reusedMS = median {
            let refreshedFoods = foods.map { RecipeFood(id: $0.id, key: $0.key, name: $0.name) }
            let refreshedStock = lots.map { StockLot(id: $0.id, masterID: $0.masterID, quantity: $0.quantity,
                unit: $0.unit, roughState: $0.roughState, storage: $0.storage, expiresAt: $0.expiresAt,
                purchasedAt: $0.purchasedAt, isDeleted: $0.isDeleted) }
            _ = cache.candidates(recipes.filter { ["main", "side"].contains($0.role) }, foods: refreshedFoods,
                stock: refreshedStock, requiredIngredientKey: nil, servings: 1, on: now)
        }
        XCTAssertEqual(cache.evaluationCount, 1)
        print("HOME_REVIEW_BENCH recipes=\(recipes.count) stock=\(lots.count) reference_ms=\(oldMS) indexed_ms=\(newMS) reused_ms=\(reusedMS)")
    }

}
