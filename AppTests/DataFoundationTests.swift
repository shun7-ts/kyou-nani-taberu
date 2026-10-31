import XCTest
import SwiftData
import UIKit
@testable import KyouNaniTaberu

@MainActor
final class DataFoundationTests: XCTestCase {
    func testRecipeImagesAreBundledWithUniqueRecipeKeysAndSourceCredits() throws {
        let entries = RecipeImageLibrary.entries
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.map(\.recipeKey)).count, entries.count)
        XCTAssertEqual(Set(entries.map(\.file)).count, entries.count)
        let seedURL = try XCTUnwrap(Bundle.main.url(forResource: "recipe-seed-v1", withExtension: "json"))
        let baseRecipes = try RecipeCatalog.decode([Data(contentsOf: seedURL)])
        for recipe in baseRecipes {
            XCTAssertNotNil(RecipeImageLibrary.entry(for: recipe.key), "基本レシピの画像: " + recipe.key)
        }
        let recipes = Set(try RecipeCatalog.load().map(\.key))
        XCTAssertEqual(Set(entries.map(\.recipeKey)), recipes, "全ての有効なレシピに固有画像を同梱する")
        for entry in entries {
            XCTAssertTrue(recipes.contains(entry.recipeKey), entry.recipeKey)
            XCTAssertFalse(entry.file.contains("/")); XCTAssertFalse(entry.file.contains(".."))
            let image = try XCTUnwrap(RecipeImageLibrary.image(for: entry.recipeKey), entry.file)
            XCTAssertGreaterThan(image.size.width, 300); XCTAssertGreaterThan(image.size.height, 300)
            XCTAssertFalse(entry.creator.isEmpty); XCTAssertFalse(entry.license.isEmpty)
            if entry.kind == "free" {
                XCTAssertEqual(URL(string: entry.source)?.scheme, "https")
                if entry.license != "Public domain" { XCTAssertEqual(URL(string: entry.licenseURL)?.scheme, "https") }
            } else {
                XCTAssertEqual(entry.kind, "generated"); XCTAssertTrue(entry.source.isEmpty)
                XCTAssertFalse(entry.license.contains("CC0"))
            }
        }
        XCTAssertEqual(RecipeImageLibrary.entry(for: "tuna_mayo_bowl")?.kind, "generated")
        for key in ["chicken_soboro_bowl", "egg_fried_rice", "tomato_egg_stir_fry"] {
            XCTAssertEqual(RecipeImageLibrary.entry(for: key)?.kind, "generated")
        }
        XCTAssertEqual(RecipeImageLibrary.entry(for: "oyakodon")?.kind, "free")
        XCTAssertNotEqual(RecipeImageLibrary.entry(for: "oyakodon")?.file, RecipeImageLibrary.entry(for: "tuna_mayo_bowl")?.file)
        XCTAssertNil(RecipeImageLibrary.image(for: "unknown-recipe"))
        XCTAssertNil(RecipeImageLibrary.image(for: nil))
    }
    func testCategoryVectorIconsAreBundledAndReadable() throws {
        for category in [IngredientCategory.mushroom, .soyProduct, .staple, .processed] {
            let name = try XCTUnwrap(category.iconAsset)
            let image = try XCTUnwrap(UIImage(named: name), name)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    func testBundledCatalogLoadsWithoutDuplicatesAndPreservesStock() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        XCTAssertEqual(try IngredientMasterImporter.load(into: store), 244)
        let context = ModelContext(store)
        let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
        let egg = try XCTUnwrap(masters.first { $0.key == "egg" })
        let lot = try InventoryItem(ingredient: .master(egg.id), amount: .exact(3, .piece),
                                    storage: .refrigerated, purchasedAt: .now)
        let custom = try CustomIngredient(name: "自家製ソース")
        context.insert(lot)
        context.insert(custom)
        try context.save()
        try IngredientMasterImporter.load(into: store)
        let fresh = ModelContext(store)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<IngredientMaster>()), 244)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 3)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<CustomIngredient>()), 1)
        let water = try XCTUnwrap(masters.first { $0.key == "water" })
        XCTAssertFalse(water.trackInventory)
        XCTAssertFalse(water.shoppingEligible)
        XCTAssertEqual(water.catalogVersion, "1.8.0")
    }

    func testCatalogUpdateKeepsIdentityAndDoesNotDeleteOmittedIngredients() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let data = try IngredientMasterImporter.bundledData()
        try IngredientMasterImporter.load(into: store, data: data)
        var catalog = try IngredientCatalog.decode(data)
        let identity = catalog.ingredients[0].id
        catalog.catalogVersion = "1.3.1"
        catalog.ingredients[0].canonicalName = "水（表示更新）"
        catalog.ingredients = [catalog.ingredients[0]]
        try IngredientMasterImporter.load(into: store, data: JSONEncoder().encode(catalog))
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        XCTAssertEqual(masters.count, 244)
        let water = try XCTUnwrap(masters.first { $0.id == identity })
        XCTAssertEqual(water.key, "water")
        XCTAssertEqual(water.canonicalName, "水（表示更新）")
        XCTAssertEqual(water.catalogVersion, "1.3.1")
    }

    func testInvalidCatalogDoesNotPartiallyUpdateStore() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let data = try IngredientMasterImporter.bundledData()
        try IngredientMasterImporter.load(into: store, data: data)
        var catalog = try IngredientCatalog.decode(data)
        catalog.ingredients[0].canonicalName = "保存してはいけない変更"
        catalog.ingredients[1].key = "changed_fixed_key"
        XCTAssertThrowsError(try IngredientMasterImporter.load(
            into: store, data: JSONEncoder().encode(catalog)))
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        XCTAssertEqual(masters.first { $0.key == "water" }?.canonicalName, "水")
        catalog = try IngredientCatalog.decode(data)
        catalog.ingredients.append(catalog.ingredients[0])
        XCTAssertThrowsError(try IngredientCatalog.decode(JSONEncoder().encode(catalog)))
        catalog = try IngredientCatalog.decode(data)
        catalog.schemaVersion = 2
        XCTAssertThrowsError(try IngredientCatalog.decode(JSONEncoder().encode(catalog)))
    }

    func testExactAndRoughLotsPersistSeparatelyAndCanSwitchModes() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let context = ModelContext(store)
        let custom = try CustomIngredient(name: "  自家製ソース  ")
        context.insert(custom)
        let exact = try InventoryItem(ingredient: .custom(custom.id), amount: .exact(0.5, .block),
                                      storage: .refrigerated, purchasedAt: .now,
                                      expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                                      expiryKind: .useBy)
        let rough = try InventoryItem(ingredient: .custom(custom.id), amount: .rough(.available),
                                      storage: .frozen, purchasedAt: .now)
        context.insert(exact)
        context.insert(rough)
        try context.save()
        let fresh = ModelContext(store)
        let lots = try fresh.fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(lots.count, 2)
        let saved = try XCTUnwrap(lots.first { $0.id == exact.id })
        XCTAssertEqual(saved.quantity, 0.5)
        XCTAssertNil(saved.ingredientMasterID)
        XCTAssertEqual(saved.customIngredientID, custom.id)
        XCTAssertEqual(saved.expiryKind, .useBy)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CustomIngredient>()).first?.name, "自家製ソース")
        try saved.setAmount(.rough(.low))
        try fresh.save()
        XCTAssertNil(saved.quantity)
        XCTAssertNil(saved.unit)
        XCTAssertEqual(saved.roughState, .low)
        try saved.setAmount(.exact(0, .gram))
        XCTAssertNil(saved.roughState)
        XCTAssertEqual(saved.stockMode, .exact)
        XCTAssertThrowsError(try saved.setAmount(.exact(-1, .gram)))
        XCTAssertEqual(saved.quantity, 0)
        XCTAssertThrowsError(try InventoryItem(ingredient: .custom(custom.id),
            amount: .exact(.nan, .gram), storage: .roomTemperature, purchasedAt: .now))
        XCTAssertThrowsError(try CustomIngredient(name: "  "))
    }

    func testDiskStoreReopensWithSameMasterAndInventoryIDs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let lotID = UUID()
        let masterID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        func open() throws -> ModelContainer {
            let config = ModelConfiguration(schema: AppPersistence.schema, url: url)
            return try ModelContainer(for: AppPersistence.schema, configurations: [config])
        }
        do {
            let store = try open()
            try IngredientMasterImporter.load(into: store)
            let context = ModelContext(store)
            context.insert(try InventoryItem(id: lotID, ingredient: .master(masterID),
                amount: .rough(.available), storage: .roomTemperature, purchasedAt: .now))
            try context.save()
        }
        let reopened = try open()
        try IngredientMasterImporter.load(into: reopened)
        let context = ModelContext(reopened)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<IngredientMaster>()), 244)
        let lot = try XCTUnwrap(context.fetch(FetchDescriptor<InventoryItem>()).first)
        XCTAssertEqual(lot.id, lotID)
        XCTAssertEqual(lot.ingredientMasterID, masterID)
        XCTAssertEqual(lot.roughState, .available)
    }
    func testSupplementKeepsBaseIDsAndExistingLotsWhenUpgrading64To244() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let baseURL = try XCTUnwrap(Bundle.main.url(forResource: "ingredient-master-v1", withExtension: "json"))
        let base = try Data(contentsOf: baseURL)
        XCTAssertEqual(try IngredientMasterImporter.load(into: store, data: base), 64)
        let before = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let ids = Dictionary(uniqueKeysWithValues: before.map { ($0.key, $0.id) })
        let egg = try XCTUnwrap(before.first { $0.key == "egg" })
        let itemID = try InventoryService(container: store).save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece)))
        XCTAssertEqual(try IngredientMasterImporter.load(into: store), 244)
        XCTAssertEqual(try IngredientMasterImporter.load(into: store), 244)
        let context = ModelContext(store), after = try context.fetch(FetchDescriptor<IngredientMaster>())
        XCTAssertEqual(after.count, 244)
        for master in after where ids[master.key] != nil { XCTAssertEqual(master.id, ids[master.key]) }
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryItem>()).first { $0.id == itemID }?.quantity, 6)
        XCTAssertTrue(after.contains { $0.key == "spinach" })
    }
    func testRiceKanjiVariantsMatchOnlyCookedRice() throws {
        let catalog = try IngredientCatalog.decode(IngredientMasterImporter.bundledData())
        for query in ["ご飯", "ごはん", "ゴハン", "御飯", "炊いたご飯"] {
            let keys = catalog.ingredients.filter { IngredientSearch.matches(query, names: [$0.canonicalName] + $0.aliases) }.map(\.key)
            XCTAssertEqual(keys, ["cooked_rice"], query)
        }
    }
    func testFrenchItalianMastersUpgrade240WithoutChangingInventoryOrIdentities() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let newKeys: Set<String> = ["mozzarella", "black_olives", "puff_pastry"]
        var previous = try IngredientCatalog.decode(IngredientMasterImporter.bundledData())
        previous.catalogVersion = "1.6.1"
        previous.ingredients.removeAll { newKeys.contains($0.key) || $0.key == "pork_thigh" }
        XCTAssertEqual(try IngredientMasterImporter.load(into: store, data: JSONEncoder().encode(previous)), 240)
        let before = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let identities = Dictionary(uniqueKeysWithValues: before.map { ($0.key, $0.id) })
        let egg = try XCTUnwrap(before.first { $0.key == "egg" })
        let lotID = try InventoryService(container: store).save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece)))
        for _ in 0..<2 { XCTAssertEqual(try IngredientMasterImporter.load(into: store), 244) }
        let context = ModelContext(store)
        let after = try context.fetch(FetchDescriptor<IngredientMaster>())
        XCTAssertEqual(after.count, 244)
        for master in after where identities[master.key] != nil { XCTAssertEqual(master.id, identities[master.key]) }
        let lot = try XCTUnwrap(context.fetch(FetchDescriptor<InventoryItem>()).first { $0.id == lotID })
        XCTAssertEqual(lot.quantity, 6); XCTAssertEqual(lot.unit, .piece); XCTAssertEqual(lot.ingredientMasterID, egg.id)
        for (key, query) in [("mozzarella", "もっつぁれら"), ("black_olives", "黒オリーブ"), ("puff_pastry", "ぱいしーと")] {
            let master = try XCTUnwrap(after.first { $0.key == key })
            XCTAssertTrue(IngredientSearch.matches(query, names: [master.canonicalName] + master.aliases), query)
        }
    }
    func testIngredientSearchSupportsReadingsKanaWidthAndPartialQueries() throws {
        let catalog = try IngredientCatalog.decode(IngredientMasterImporter.bundledData())
        func keys(_ query: String) -> Set<String> {
            Set(catalog.ingredients.filter { IngredientSearch.matches(query, names: [$0.canonicalName] + $0.aliases) }.map(\.key))
        }
        for query in ["とりもも", "トリモモ", "ﾄﾘﾓﾓ", "鶏もも", " とり もも "] { XCTAssertTrue(keys(query).contains("chicken_thigh"), query) }
        for query in ["ぎゅうにゅう", "ギュウニュウ", "牛乳"] { XCTAssertTrue(keys(query).contains("milk"), query) }
        for query in ["ほうれん", "ホウレン", "ほうれん草"] { XCTAssertTrue(keys(query).contains("spinach"), query) }
        XCTAssertFalse(keys("ぶたもも").contains("chicken_thigh"))
        XCTAssertEqual(keys(""), Set(catalog.ingredients.map(\.key)))
    }

    func testBundledSharedMealImageIsDecodable() throws {
        let image = try XCTUnwrap(RecipeMealImage.image)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testRecipeKindPartitionsCatalogAndCanRecommendSidesForTwoPeople() throws {
        let recipes = try RecipeCatalog.load()
        XCTAssertEqual(recipes.filter { RecipeKind.main.includes($0) }.count, 117)
        XCTAssertEqual(recipes.filter { RecipeKind.side.includes($0) }.count, 55)
        XCTAssertEqual(recipes.filter { RecipeKind.soup.includes($0) }.count, 20)
        XCTAssertEqual(recipes.filter { RecipeKind.all.includes($0) }.count, 192)
        let sides = RecipeSuggestions.candidates(recipes.filter { RecipeKind.side.includes($0) }, foods: [], stock: [],
            servings: 2, allowedRoles: ["main", "side"])
        XCTAssertEqual(sides.count, 55); XCTAssertTrue(sides.allSatisfy { $0.servings == 2 })
        let recipe = try XCTUnwrap(sides.first)
        for ingredient in recipe.ingredients {
            XCTAssertEqual(ingredient.availability.required, ingredient.ingredient.amount(servings: 2, base: recipe.recipe.baseServings))
        }
    }
    func testRecipeAdditionsPreserveOriginalsAndUseValidMasterIngredients() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "recipe-seed-v1", withExtension: "json"))
        let original = try RecipeCatalog.decode([Data(contentsOf: url)])
        let merged = try RecipeCatalog.load()
        XCTAssertEqual(original.count, 40); XCTAssertEqual(merged.count, 192)
        XCTAssertEqual(Array(merged.prefix(40)).map(\.id), original.map(\.id))
        XCTAssertEqual(Array(merged.prefix(40)).map(\.key), original.map(\.key))
        let masters = try IngredientCatalog.decode(IngredientMasterImporter.bundledData()).ingredients
        let byKey = Dictionary(uniqueKeysWithValues: masters.map { ($0.key, $0) })
        for recipe in merged.dropFirst(40) {
            XCTAssertNotNil(recipe.kind)
            XCTAssertEqual(recipe.steps.map(\.order), Array(1...recipe.steps.count))
            XCTAssertEqual(Set(recipe.ingredients.map(\.ingredientKey)).count, recipe.ingredients.count)
            var allergens = Set<String>()
            for ingredient in recipe.ingredients {
                let master = try XCTUnwrap(byKey[ingredient.ingredientKey], recipe.key)
                XCTAssertTrue(master.allowedUnits.contains(ingredient.unit), recipe.key)
                XCTAssertGreaterThan(ingredient.quantity, 0)
                XCTAssertTrue(ingredient.quantity.isFinite)
                XCTAssertEqual(ingredient.inventoryMode, !master.trackInventory ? "ignored" : master.stockMode == .rough ? "presence" : "exact", recipe.key)
                allergens.formUnion(master.allergens)
            }
            XCTAssertEqual(Set(recipe.allergens), allergens, recipe.key)
            for step in recipe.steps {
                XCTAssertFalse(step.text.isEmpty)
                if let timer = step.timerMinutes { XCTAssertGreaterThan(timer, 0) }
            }
        }
        for food in ["spinach", "broccoli", "tomato", "eggplant", "lettuce", "lotus_root", "burdock", "sweet_potato"] {
            XCTAssertFalse(RecipeSuggestions.candidates(merged, foods: [], stock: [], requiredIngredientKey: food, allowedRoles: ["main", "side"]).isEmpty, food)
        }
    }
    func testMajorRecipeExpansionConnectsPreviouslyUnusedFoodsAndScalesAmounts() throws {
        let recipes = try RecipeCatalog.load()
        let old = Array(recipes.prefix(60)), added = Array(recipes.dropFirst(60).prefix(25))
        XCTAssertEqual(added.count, 25)
        XCTAssertEqual(Set(added.map(\.key)).count, 25)
        let previouslyUnused = ["chicken_breast", "ground_mixed", "shrimp", "pumpkin", "hijiki", "kiriboshi_daikon", "enoki", "bread", "macaroni", "nameko", "asari_clams", "taro", "tarako"]
        for key in previouslyUnused {
            XCTAssertFalse(old.contains { $0.ingredients.contains { $0.ingredientKey == key && $0.requirement == "required" } }, key)
            let matches = RecipeSuggestions.candidates(recipes, foods: [], stock: [], requiredIngredientKey: key, allowedRoles: ["main", "side"])
            XCTAssertFalse(matches.isEmpty, key)
            XCTAssertTrue(matches.allSatisfy { $0.recipe.ingredients.contains { $0.ingredientKey == key && $0.requirement == "required" } }, key)
        }
        for (key, ingredientKey, expected, unit) in [("chicken_banbanji", "chicken_breast", 300.0, IngredientUnit.gram), ("shrimp_chili", "shrimp", 240.0, .gram), ("french_toast", "milk", 160.0, .milliliter)] {
            let recipe = try XCTUnwrap(added.first { $0.key == key })
            let ingredient = try XCTUnwrap(recipe.ingredients.first { $0.ingredientKey == ingredientKey })
            XCTAssertEqual(ingredient.unit, unit)
            XCTAssertEqual(ingredient.amount(servings: 2), expected)
            let step = try XCTUnwrap(recipe.steps.first { ($0.ingredients ?? []).contains { $0.ingredientKey == ingredientKey } })
            XCTAssertEqual(recipe.instructionIngredients(for: step, servings: 2).first { $0.ingredient.ingredientKey == ingredientKey }?.quantity, expected)
        }
        let fried = try XCTUnwrap(added.first { $0.key == "chicken_karaage" })
        let oil = try XCTUnwrap(fried.ingredients.first { $0.ingredientKey == "neutral_oil" })
        XCTAssertEqual(oil.inventoryMode, "presence")
        XCTAssertEqual(oil.amount(servings: 4), oil.quantity)
        let hijiki = try XCTUnwrap(added.first { $0.key == "simmered_hijiki" })
        XCTAssertGreaterThanOrEqual(hijiki.prepMinutes, 30)
        XCTAssertTrue(hijiki.steps[0].text.contains("戻し水を捨て"))
        let clam = try XCTUnwrap(added.first { $0.key == "asari_sake_steam" })
        XCTAssertTrue(clam.ingredients.first { $0.ingredientKey == "asari_clams" }?.note?.contains("砂抜き済み") == true)
    }


    func testUnusedFoodExpansionProvidesRequiredCandidatesAcrossKinds() throws {
        let recipes = Array(try RecipeCatalog.load().prefix(135)), previous = Array(recipes.prefix(85))
        // この追加分のカバレッジは当時の240食材・135レシピで固定して検証する。
        let foods = try IngredientCatalog.decode(IngredientMasterImporter.bundledData()).ingredients.prefix(240).filter { $0.trackInventory }
        let oldKeys = Set(previous.flatMap { $0.ingredients.map(\.ingredientKey) })
        let previouslyUnused = foods.filter { !oldKeys.contains($0.key) }
        XCTAssertEqual(previouslyUnused.count, 143)
        let newlyCovered = previouslyUnused.filter { food in
            recipes.dropFirst(85).contains { $0.ingredients.contains { $0.ingredientKey == food.key && $0.requirement == "required" } }
        }
        XCTAssertEqual(newlyCovered.count, 97)
        for food in newlyCovered {
            let matches = RecipeSuggestions.candidates(recipes, foods: [], stock: [], requiredIngredientKey: food.key, allowedRoles: ["main", "side"])
            XCTAssertFalse(matches.isEmpty, food.key)
            XCTAssertTrue(matches.allSatisfy { $0.recipe.ingredients.contains { $0.ingredientKey == food.key && $0.requirement == "required" } }, food.key)
        }
        let allUsed = Set(recipes.flatMap { $0.ingredients.map(\.ingredientKey) })
        XCTAssertEqual(foods.filter { !allUsed.contains($0.key) }.count, 46)
        let zucchini = RecipeSuggestions.candidates(recipes.filter { RecipeKind.side.includes($0) }, foods: [], stock: [], requiredIngredientKey: "zucchini", allowedRoles: ["main", "side"])
        XCTAssertEqual(zucchini.map { $0.recipe.key }, ["ratatouille"])
        let grain = try XCTUnwrap(recipes.first { $0.key == "corn_edamame_rice" })
        XCTAssertEqual(grain.ingredients.first { $0.ingredientKey == "raw_rice" }?.amount(servings: 2), 150)
        XCTAssertFalse(grain.ingredients.contains { $0.ingredientKey == "cooked_rice" })
        let dry = try XCTUnwrap(recipes.first { $0.key == "koya_shiitake_simmer" })
        XCTAssertTrue(dry.summary.contains("別途"))
        XCTAssertTrue(dry.steps.first?.timeNote?.contains("合計に含まない") == true)
        XCTAssertTrue(dry.steps.allSatisfy { ($0.timerMinutes ?? 0) <= 120 })
        let tuna = try XCTUnwrap(recipes.first { $0.key == "tuna_avocado_rice" })
        XCTAssertTrue(tuna.steps.first?.text.contains("生食用") == true)
        let liver = try XCTUnwrap(recipes.first { $0.key == "pork_liver_chives" })
        XCTAssertTrue(liver.steps.contains { $0.tip?.contains("75℃") == true })
    }

    func testOctoberRecipesScaleSplitIngredientsAndKeepWaterOutOfShopping() throws {
        let recipes = try RecipeCatalog.load()
        let new = recipes.filter { AppNoticeFeed.newRecipeKeys.contains($0.key) }
        XCTAssertEqual(new.count, 6)
        XCTAssertTrue(new.allSatisfy { $0.steps.allSatisfy { !($0.timeNote ?? "").isEmpty } })
        let chicken = try XCTUnwrap(new.first { $0.key == "chicken_nanban" })
        XCTAssertTrue(chicken.allergens.contains("egg")); XCTAssertTrue(chicken.allergens.contains("wheat"))
        let tartar = chicken.steps[2], coating = chicken.steps[3]
        for servings in 1...4 {
            let tartarEgg = try XCTUnwrap(chicken.instructionIngredients(for: tartar, servings: servings).first { $0.ingredient.ingredientKey == "egg" })
            let coatingEgg = try XCTUnwrap(chicken.instructionIngredients(for: coating, servings: servings).first { $0.ingredient.ingredientKey == "egg" })
            XCTAssertEqual(tartarEgg.quantity + coatingEgg.quantity, 2 * Double(servings))
            let vinegar = [chicken.steps[1], tartar].flatMap { chicken.instructionIngredients(for: $0, servings: servings) }
                .filter { $0.ingredient.ingredientKey == "vinegar" }.reduce(0) { $0 + $1.quantity }
            XCTAssertEqual(vinegar, 1.5 * Double(servings), accuracy: 0.00001)
        }
        let salmon = try XCTUnwrap(new.first { $0.key == "salmon_chanchan" })
        XCTAssertTrue(salmon.allergens.contains("salmon")); XCTAssertTrue(salmon.allergens.contains("milk"))
        let butter = [salmon.steps[2], salmon.steps[4]].flatMap { salmon.instructionIngredients(for: $0, servings: 2) }
            .filter { $0.ingredient.ingredientKey == "butter" }.reduce(0) { $0 + $1.quantity }
        XCTAssertEqual(butter, 10)
        for recipe in new {
            XCTAssertTrue(recipe.steps.allSatisfy { ($0.timerMinutes ?? 0) > 0 })
            XCTAssertTrue(recipe.ingredients.filter { $0.ingredientKey == "water" }.allSatisfy { $0.inventoryMode == "ignored" })
        }
    }

    func testRecipeCatalogRejectsDuplicatesAndInvalidKindsOrSchema() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "recipe-additions-v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        XCTAssertThrowsError(try RecipeCatalog.decode([data, data]))
        var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        catalog["schemaVersion"] = 2
        XCTAssertThrowsError(try RecipeCatalog.decode([JSONSerialization.data(withJSONObject: catalog)]))
        catalog["schemaVersion"] = 1
        var recipes = try XCTUnwrap(catalog["recipes"] as? [[String: Any]])
        recipes[0]["kind"] = "all"; catalog["recipes"] = recipes
        XCTAssertThrowsError(try RecipeCatalog.decode([JSONSerialization.data(withJSONObject: catalog)]))
        recipes[0]["kind"] = "soup"; catalog["recipes"] = recipes
        XCTAssertThrowsError(try RecipeCatalog.decode([JSONSerialization.data(withJSONObject: catalog)]))
    }
    func testDefaultServingsBoundsAndReset() throws {
        let suite = "serving-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppPreferences.validatedServings(defaults.integer(forKey: AppPreferences.defaultServings)), 1)
        defaults.set(2, forKey: AppPreferences.defaultServings)
        XCTAssertEqual(AppPreferences.validatedServings(UserDefaults(suiteName: suite)!.integer(forKey: AppPreferences.defaultServings)), 2)
        XCTAssertEqual(AppPreferences.validatedServings(0), 1); XCTAssertEqual(AppPreferences.validatedServings(5), 1)
        AppPreferences.reset(defaults); XCTAssertNil(defaults.object(forKey: AppPreferences.defaultServings))
    }

    func testDetailedInstructionsCoverEveryRecipeWithoutChangingRequirements() throws {
        let base = try ["recipe-seed-v1", "recipe-additions-v1"].map { name in
            try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json")))
        }
        let originals = try RecipeCatalog.decode(base), revised = try RecipeCatalog.load()
        XCTAssertEqual(revised.count, 192)
        XCTAssertEqual(revised.reduce(0) { $0 + $1.steps.count }, 755)
        for (before, after) in zip(originals, revised) {
            XCTAssertEqual(before.id, after.id); XCTAssertEqual(before.key, after.key)
            XCTAssertEqual(before.title, after.title); XCTAssertEqual(before.summary, after.summary)
            XCTAssertEqual(before.role, after.role); XCTAssertEqual(before.kind, after.kind)
            XCTAssertEqual(before.baseServings, after.baseServings)
            XCTAssertEqual(before.allergens, after.allergens); XCTAssertEqual(before.status, after.status)
            XCTAssertEqual(before.ingredients.count, after.ingredients.count)
            for (a, b) in zip(before.ingredients, after.ingredients) {
                XCTAssertEqual(a.ingredientKey, b.ingredientKey); XCTAssertEqual(a.quantity, b.quantity)
                XCTAssertEqual(a.unit, b.unit); XCTAssertEqual(a.requirement, b.requirement)
                XCTAssertEqual(a.inventoryMode, b.inventoryMode); XCTAssertEqual(a.scaling, b.scaling)
                XCTAssertEqual(a.thawing, b.thawing); XCTAssertEqual(a.note, b.note)
            }
            XCTAssertEqual(after.steps.map(\.order), Array(1...after.steps.count))
            XCTAssertEqual(after.steps.compactMap(\.timerMinutes).reduce(0, +), after.minutes, after.key)
            XCTAssertTrue(after.steps.allSatisfy { !($0.title ?? "").isEmpty && !$0.text.isEmpty })
            let referenced = Set(after.steps.flatMap { ($0.ingredients ?? []).map(\.ingredientKey) })
            XCTAssertEqual(referenced, Set(after.ingredients.map(\.ingredientKey)), after.key)
        }
    }
    func testInstructionPortionsScaleWithServingsAndSplitButterOnlyOnce() throws {
        let recipes = try RecipeCatalog.load()
        let recipe = try XCTUnwrap(recipes.first { $0.key == "omurice" })
        let butterSteps = recipe.steps.filter { ($0.ingredients ?? []).contains { $0.ingredientKey == "butter" } }
        XCTAssertEqual(butterSteps.count, 2)
        for servings in 1...4 {
            let amounts = butterSteps.flatMap { recipe.instructionIngredients(for: $0, servings: servings) }
                .filter { $0.ingredient.ingredientKey == "butter" }.map(\.quantity)
            XCTAssertEqual(amounts, [5 * Double(servings), 5 * Double(servings)])
            let rice = try XCTUnwrap(recipe.instructionIngredients(for: recipe.steps[2], servings: servings)
                .first { $0.ingredient.ingredientKey == "cooked_rice" })
            XCTAssertEqual(rice.quantity, 200 * Double(servings))
        }
        let tuna = try XCTUnwrap(recipes.first { $0.key == "tuna_mayo_bowl" })
        let sauce = try XCTUnwrap(tuna.instructionIngredients(for: tuna.steps[0], servings: 2)
            .first { $0.ingredient.ingredientKey == "mayonnaise" })
        XCTAssertEqual(sauce.quantity, 2)
    }
    func testInstructionsRejectPartialUnknownDuplicateAndInvalidRevisions() throws {
        let sources = try ["recipe-seed-v1", "recipe-additions-v1"].map { name in
            try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json")))
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "recipe-instructions-v1", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func reject(_ change: (inout [String: Any]) -> Void) throws {
            var copy = object; change(&copy)
            XCTAssertThrowsError(try RecipeCatalog.decode(sources, instructionsData: JSONSerialization.data(withJSONObject: copy)))
        }
        try reject { $0["schemaVersion"] = 2 }
        try reject { root in var recipes = root["recipes"] as! [[String: Any]]; recipes.removeLast(); root["recipes"] = recipes }
        try reject { root in var recipes = root["recipes"] as! [[String: Any]]; recipes[0] = recipes[1]; root["recipes"] = recipes }
        for (field, value) in [("title", "" as Any), ("order", 9 as Any), ("timerMinutes", 0 as Any)] {
            try reject { root in
                var recipes = root["recipes"] as! [[String: Any]], steps = recipes[0]["steps"] as! [[String: Any]]
                steps[0][field] = value; recipes[0]["steps"] = steps; root["recipes"] = recipes
            }
        }
        for (field, value) in [("ingredientKey", "not_in_recipe" as Any), ("fraction", 0 as Any), ("fraction", 1.5 as Any)] {
            try reject { root in
                var recipes = root["recipes"] as! [[String: Any]], steps = recipes[0]["steps"] as! [[String: Any]]
                var uses = steps[0]["ingredients"] as! [[String: Any]]
                uses[0][field] = value; steps[0]["ingredients"] = uses; recipes[0]["steps"] = steps; root["recipes"] = recipes
            }
        }
        try reject { root in var recipes = root["recipes"] as! [[String: Any]]; recipes[0]["cookMinutes"] = 999; root["recipes"] = recipes }
    }

    func testIngredientUpgradePreserves72And160IdentitiesAndUserRecords() throws {
        let full = try IngredientCatalog.decode(IngredientMasterImporter.bundledData())
        for (previousCount, version) in [(72, "1.4.0"), (160, "1.5.0"), (243, "1.7.0")] {
        var previous = full
        previous.catalogVersion = version
        previous.ingredients = Array(full.ingredients.prefix(previousCount))
        let store = try AppPersistence.makeContainer(inMemory: true)
        XCTAssertEqual(try IngredientMasterImporter.load(into: store, data: JSONEncoder().encode(previous)), previousCount)
        let context = ModelContext(store)
        let spinach = try XCTUnwrap(previous.ingredients.first { $0.key == "spinach" })
        let service = InventoryService(container: store)
        let stockID = try service.save(InventoryDraft(masterID: spinach.id, amount: .exact(0.5, .bunch),
            storage: .frozen, purchasedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let customID = try service.save(InventoryDraft(customName: "自家製ジャム", amount: .rough(.low)))
        let originalEvents = try context.fetch(FetchDescriptor<InventoryEvent>()).map(\.id)
        for _ in 0..<2 { XCTAssertEqual(try IngredientMasterImporter.load(into: store), 244) }
        let fresh = ModelContext(store)
        let masters = try fresh.fetch(FetchDescriptor<IngredientMaster>())
        let byKey = Dictionary(uniqueKeysWithValues: masters.map { ($0.key, $0) })
        for seed in previous.ingredients {
            XCTAssertEqual(byKey[seed.key]?.id, seed.id, seed.key)
            XCTAssertEqual(byKey[seed.key]?.allowedUnits, seed.allowedUnits, seed.key)
        }
        let lots = try fresh.fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(lots.count, 2)
        let stock = try XCTUnwrap(lots.first { $0.id == stockID })
        XCTAssertEqual(stock.quantity, 0.5); XCTAssertEqual(stock.unit, .bunch)
        XCTAssertEqual(stock.storage, .frozen); XCTAssertEqual(stock.ingredientMasterID, spinach.id)
        XCTAssertEqual(stock.purchasedAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(lots.first { $0.id == customID }?.roughState, .low)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CustomIngredient>()).first?.name, "自家製ジャム")
        XCTAssertEqual(Set(try fresh.fetch(FetchDescriptor<InventoryEvent>()).map(\.id)), Set(originalEvents))
        }
    }

    func testCommonFoodReadingsAndProcessingStatesRemainDistinct() throws {
        let catalog = try IngredientCatalog.decode(IngredientMasterImporter.bundledData())
        func keys(_ query: String) -> Set<String> {
            Set(catalog.ingredients.filter { IngredientSearch.matches(query, names: [$0.canonicalName] + $0.aliases) }.map(\.key))
        }
        for (query, key) in [("とりむね", "chicken_breast"), ("ﾄﾘｻｻﾐ", "chicken_tenderloin"),
            ("椎茸", "shiitake"), ("とうみょう", "pea_shoots"), ("あぶらあげ", "aburaage"),
            ("ちゅうかめん", "ramen_noodles"), ("しょくぱん", "bread"), ("ぽんず", "ponzu"),
            ("みっくす べじ", "frozen_mixed_vegetables"), ("あいびき", "ground_mixed"),
            ("さといも", "taro"), ("こむぎこ", "wheat_flour")] {
            XCTAssertTrue(keys(query).contains(key), query)
        }
        XCTAssertTrue(keys("さば").isSuperset(of: ["mackerel_fillet", "canned_mackerel"]))
        XCTAssertEqual(keys("生さば"), ["mackerel_fillet"])
        XCTAssertFalse(keys("とりむね").contains("chicken_thigh"))
        XCTAssertFalse(keys("とうにゅう").contains("milk"))
        let foods = Dictionary(uniqueKeysWithValues: catalog.ingredients.map { ($0.key, $0) })
        XCTAssertEqual(foods["enoki"]?.category, .mushroom)
        XCTAssertEqual(foods["aburaage"]?.category, .soyProduct)
        XCTAssertEqual(foods["bread"]?.category, .staple)
        XCTAssertEqual(foods["ponzu"]?.stockMode, .rough)
        XCTAssertEqual(foods["frozen_mixed_vegetables"]?.defaultStorage, .frozen)
        XCTAssertEqual(foods["raw_rice"]?.defaultStorage, .roomTemperature)
    }

    func testExpandedBulkRegistrationIsIdempotentAndSeasoningsSupportThreeStates() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let service = InventoryService(container: store)
        let keys: Set<String> = ["enoki", "chicken_breast", "ponzu", "frozen_mixed_vegetables"]
        XCTAssertEqual(try service.bulkRegister(keys: keys), 4)
        XCTAssertEqual(try service.bulkRegister(keys: keys), 0)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let byKey = Dictionary(uniqueKeysWithValues: masters.map { ($0.key, $0) })
        let lots = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(lots.count, 4)
        for key in keys {
            let master = try XCTUnwrap(byKey[key])
            let lot = try XCTUnwrap(lots.first { $0.ingredientMasterID == master.id })
            XCTAssertEqual(lot.storage, master.defaultStorage)
            XCTAssertEqual(lot.roughState, .available); XCTAssertNil(lot.quantity)
        }
        let ponzu = try XCTUnwrap(byKey["ponzu"])
        let id = try XCTUnwrap(lots.first { $0.ingredientMasterID == ponzu.id }?.id)
        for state in [RoughStockState.available, .low, .unavailable] {
            try service.save(InventoryDraft(masterID: ponzu.id, amount: .rough(state), storage: .refrigerated), editingID: id)
            let saved = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id })
            XCTAssertEqual(saved.roughState, state); XCTAssertNil(saved.quantity); XCTAssertNil(saved.unit)
        }
        let breast = try XCTUnwrap(byKey["chicken_breast"])
        XCTAssertThrowsError(try service.save(InventoryDraft(masterID: breast.id, amount: .exact(1, .liter))))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 4)
    }

    func testAdditionalFoodsDistinguishDriedCannedAndFreshIngredients() throws {
        let catalog = try IngredientCatalog.decode(IngredientMasterImporter.bundledData())
        let foods = Dictionary(uniqueKeysWithValues: catalog.ingredients.map { ($0.key, $0) })
        for (query, key) in [("きりぼし", "kiriboshi_daikon"), ("ホシシイタケ", "dried_shiitake"),
            ("ﾏｶﾛﾆ", "macaroni"), ("かまあげ", "shirasu"), ("きょうりきこ", "bread_flour"),
            ("かんそう ひよこ", "dried_chickpeas"), ("ぎょにく", "fish_sausage"), ("ほたて", "scallops")] {
            let food = try XCTUnwrap(foods[key])
            XCTAssertTrue(IngredientSearch.matches(query, names: [food.canonicalName] + food.aliases), query)
        }
        for (fresh, processed) in [("shiitake", "dried_shiitake"), ("corn", "canned_corn"),
            ("fresh_tuna", "canned_tuna"), ("dried_soybeans", "boiled_soybeans"), ("dried_udon", "chilled_udon")] {
            XCTAssertNotEqual(foods[fresh]?.id, foods[processed]?.id)
            XCTAssertNotEqual(foods[fresh]?.defaultStorage, foods[processed]?.defaultStorage)
        }
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let service = InventoryService(container: store)
        let keys: Set<String> = ["nameko", "kiriboshi_daikon", "baking_powder", "frozen_french_fries"]
        XCTAssertEqual(try service.bulkRegister(keys: keys), 4)
        XCTAssertEqual(try service.bulkRegister(keys: keys), 0)
        let stock = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        for key in keys {
            let seed = try XCTUnwrap(foods[key])
            let saved = try XCTUnwrap(stock.first { $0.ingredientMasterID == seed.id })
            XCTAssertEqual(saved.storage, seed.defaultStorage)
            XCTAssertEqual(saved.roughState, .available)
        }
    }

}
