import XCTest
import SwiftData
import UIKit
import CoreText
import Combine
@testable import KyouNaniTaberu

@MainActor
final class InventoryMergeTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store); return store
    }
    private func food(_ store: ModelContainer) throws -> IngredientMaster {
        try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "pork_thigh" })
    }
    private func stock(_ store: ModelContainer) throws -> [InventoryItem] {
        try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).filter { !$0.isDeleted }
    }
    private func receiptFood(_ master: IngredientMaster) -> ReceiptIngredient {
        ReceiptIngredient(id: master.id, name: master.canonicalName, aliases: master.aliases,
            unit: master.defaultUnit, allowedUnits: master.allowedUnits, storage: master.defaultStorage, category: master.category)
    }
    func testAdditionCombinesConvertibleAmountsOnSameExpiryDayAndKeepsOldestPurchase() throws {
        let store = try store(), food = try food(store), service = InventoryService(container: store)
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000))
        let purchased = day.addingTimeInterval(-86400)
        let first = try service.save(InventoryDraft(masterID: food.id, amount: .exact(200, .gram),
            purchasedAt: purchased, expiresAt: day.addingTimeInterval(3600), expiryKind: .useBy))
        let second = try service.save(InventoryDraft(masterID: food.id, amount: .exact(0.3, .kilogram),
            purchasedAt: day, expiresAt: day.addingTimeInterval(7200), expiryKind: .useBy))
        XCTAssertEqual(first, second)
        let lot = try XCTUnwrap(stock(store).first)
        XCTAssertEqual(try stock(store).count, 1); XCTAssertEqual(lot.quantity, 500); XCTAssertEqual(lot.unit, .gram)
        XCTAssertEqual(lot.purchasedAt, purchased); XCTAssertEqual(lot.expiresAt, day.addingTimeInterval(3600))
    }
    func testStorageExpiryKindDifferentDatesAndUnconvertibleUnitsKeepSeparateLots() throws {
        let store = try store(), food = try food(store), service = InventoryService(container: store)
        let day = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400 * 7)
        let original = InventoryDraft(masterID: food.id, amount: .exact(200, .gram), expiresAt: day, expiryKind: .useBy)
        try service.save(original)
        var changed = original; changed.storage = .frozen; try service.save(changed)
        changed = original; changed.expiresAt = day.addingTimeInterval(86400); try service.save(changed)
        changed = original; changed.expiryKind = .bestBefore; try service.save(changed)
        changed = original; changed.expiresAt = nil; try service.save(changed)
        changed = original; changed.amount = .exact(1, .pack); try service.save(changed)
        XCTAssertEqual(try stock(store).count, 6)
        XCTAssertEqual(try stock(store).filter { $0.quantity == 200 && $0.unit == .gram }.count, 5)
    }
    func testRoughPresenceConsolidatesButNeverSwallowsMeasuredOrUnknownStock() throws {
        let store = try store(), food = try food(store), service = InventoryService(container: store)
        let measured = try service.save(InventoryDraft(masterID: food.id, amount: .exact(200, .gram)))
        let rough = try service.save(InventoryDraft(masterID: food.id, amount: .rough(.available)))
        XCTAssertEqual(rough, try service.save(InventoryDraft(masterID: food.id, amount: .rough(.available))))
        XCTAssertEqual(rough, try service.save(InventoryDraft(masterID: food.id, amount: .rough(.low))))
        XCTAssertEqual(try stock(store).count, 2)
        XCTAssertEqual(try stock(store).first { $0.id == measured }?.quantity, 200)
        XCTAssertEqual(try stock(store).first { $0.id == rough }?.roughState, .available)
        try service.save(InventoryDraft(masterID: food.id, amount: .exact(50, .gram)))
        XCTAssertEqual(try stock(store).count, 2)
        XCTAssertEqual(try stock(store).first { $0.id == measured }?.quantity, 250)
    }
    func testManualReceiptVoiceAndPurchaseShareDefaultMergingAndRespectDisabledSetting() throws {
        for enabled in [true, false] {
            let store = try store(), food = try food(store)
            let manual = InventoryService(container: store, mergeDuplicates: enabled)
            try manual.save(InventoryDraft(masterID: food.id, amount: .exact(100, .gram)))
            try manual.save(InventoryDraft(masterID: food.id, amount: .exact(200, .gram)))
            var receipt = try ReceiptParser.parse(["豚もも切り落とし 300g ¥498"], ingredients: [receiptFood(food)])
            receipt[0].confirmed = true
            let receiptService = ReceiptImportService(container: store, mergeDuplicates: enabled), session = UUID()
            try receiptService.save(rows: receipt, sessionID: session)
            XCTAssertThrowsError(try receiptService.save(rows: receipt, sessionID: session))
            var voice = try VoiceParser.parse("豚もも肉を400g買った", ingredients: [receiptFood(food)])
            voice[0].draft.confirmed = true
            let voiceService = VoiceImportService(container: store, mergeDuplicates: enabled), voiceSession = UUID()
            try voiceService.save(rows: voice, sessionID: voiceSession)
            XCTAssertThrowsError(try voiceService.save(rows: voice, sessionID: voiceSession))
            let purchases = MealService(container: store, mergeDuplicates: enabled)
            try purchases.saveManual(name: food.canonicalName, quantity: 500, unit: .gram, masterID: food.id)
            let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
            try purchases.setChecked(id: row.id, checked: true)
            try purchases.purchase([PurchaseDraft(id: row.id, quantity: 500, unit: .gram,
                storage: .refrigerated, purchasedAt: .now)])
            XCTAssertThrowsError(try purchases.purchase([PurchaseDraft(id: row.id, quantity: 500, unit: .gram,
                storage: .refrigerated, purchasedAt: .now)]))
            let lots = try stock(store)
            XCTAssertEqual(lots.count, enabled ? 1 : 5)
            XCTAssertEqual(lots.compactMap(\.quantity).reduce(0, +), 1500)
        }
    }
    func testBatchReceiptCombinesItsOwnRowsAndFailureRollsBackMergedAmounts() throws {
        let store = try store(), food = try food(store)
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: food.id, amount: .exact(100, .gram)))
        var rows = try ReceiptParser.parse(["豚もも 200g ¥298", "豚モモ 300g ¥398"], ingredients: [receiptFood(food)])
        for i in rows.indices { rows[i].confirmed = true }
        try ReceiptImportService(container: store).save(rows: rows, sessionID: UUID())
        XCTAssertEqual(try stock(store).count, 1)
        XCTAssertEqual(try stock(store).first?.id, id); XCTAssertEqual(try stock(store).first?.quantity, 600)
        rows[1].quantity = "-1"
        let events = try ModelContext(store).fetchCount(FetchDescriptor<InventoryEvent>())
        XCTAssertThrowsError(try ReceiptImportService(container: store).save(rows: rows, sessionID: UUID()))
        XCTAssertEqual(try stock(store).first?.quantity, 600)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryEvent>()), events)
    }
    func testEditingReplacesAmountAndDeletedStockIsNotReused() throws {
        let store = try store(), food = try food(store), service = InventoryService(container: store)
        let id = try service.save(InventoryDraft(masterID: food.id, amount: .exact(200, .gram)))
        try service.save(InventoryDraft(masterID: food.id, amount: .exact(50, .gram)), editingID: id)
        XCTAssertEqual(try stock(store).first?.quantity, 50)
        try service.discard(id: id)
        let next = try service.save(InventoryDraft(masterID: food.id, amount: .exact(300, .gram)))
        XCTAssertNotEqual(id, next); XCTAssertEqual(try stock(store).count, 1)
        XCTAssertEqual(try stock(store).first?.quantity, 300)
    }
    func testOverflowAndUndoLeaveTheOriginalLotIntact() throws {
        let store = try store(), food = try food(store), service = InventoryService(container: store)
        let center = InventoryUndoCenter(container: store)
        let id = try service.save(InventoryDraft(masterID: food.id, amount: .exact(200, .gram)))
        try service.save(InventoryDraft(masterID: food.id, amount: .exact(300, .gram)))
        XCTAssertEqual(try stock(store).first?.quantity, 500)
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertEqual(try stock(store).count, 1); XCTAssertEqual(try stock(store).first?.id, id)
        XCTAssertEqual(try stock(store).first?.quantity, 200)
        try service.save(InventoryDraft(masterID: food.id, amount: .exact(Double.greatestFiniteMagnitude, .gram)), editingID: id)
        XCTAssertThrowsError(try service.save(InventoryDraft(masterID: food.id, amount: .exact(Double.greatestFiniteMagnitude, .gram))))
        XCTAssertEqual(try stock(store).count, 1)
        XCTAssertEqual(try stock(store).first?.quantity, Double.greatestFiniteMagnitude)
    }
    func testMergePreferenceIsOwnedByDataReset() throws {
        let suite = "merge-preference-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(defaults.object(forKey: AppPreferences.mergeInventory))
        defaults.set(false, forKey: AppPreferences.mergeInventory)
        defaults.set("keep", forKey: "unrelated-key")
        AppPreferences.reset(defaults)
        XCTAssertNil(defaults.object(forKey: AppPreferences.mergeInventory))
        XCTAssertEqual(defaults.string(forKey: "unrelated-key"), "keep")
    }
    func testEmptyStockIsReusedForNewPurchasesAndBulkRegistration() throws {
        let store = try store(), food = try food(store), service = InventoryService(container: store)
        let oldPurchase = Date(timeIntervalSince1970: 1_700_000_000), newPurchase = oldPurchase.addingTimeInterval(86400)
        let id = try service.save(InventoryDraft(masterID: food.id, amount: .exact(0, .gram), purchasedAt: oldPurchase))
        XCTAssertEqual(id, try service.save(InventoryDraft(masterID: food.id, amount: .exact(1, .pack), purchasedAt: newPurchase)))
        XCTAssertEqual(try stock(store).count, 1); XCTAssertEqual(try stock(store).first?.unit, .pack)
        XCTAssertEqual(try stock(store).first?.quantity, 1); XCTAssertEqual(try stock(store).first?.purchasedAt, newPurchase)
        try service.save(InventoryDraft(amount: .rough(.unavailable)), editingID: id)
        XCTAssertEqual(try service.bulkRegister(keys: [food.key], now: newPurchase), 1)
        XCTAssertEqual(try service.bulkRegister(keys: [food.key], now: newPurchase), 0)
        XCTAssertEqual(try stock(store).count, 1); XCTAssertEqual(try stock(store).first?.id, id)
        XCTAssertEqual(try stock(store).first?.roughState, .available)
    }
    func testActiveCompatibleStockWinsOverAnOlderEmptyLotWithoutDeletingHistory() throws {
        let store = try store(), food = try food(store)
        let separate = InventoryService(container: store, mergeDuplicates: false)
        let empty = try separate.save(InventoryDraft(masterID: food.id, amount: .exact(0, .gram)))
        let full = try separate.save(InventoryDraft(masterID: food.id, amount: .exact(200, .gram)))
        let target = try InventoryService(container: store).save(InventoryDraft(masterID: food.id, amount: .exact(300, .gram)))
        XCTAssertEqual(target, full); XCTAssertEqual(try stock(store).count, 2)
        XCTAssertEqual(try stock(store).first { $0.id == empty }?.quantity, 0)
        XCTAssertEqual(try stock(store).first { $0.id == full }?.quantity, 500)
    }
}

@MainActor
final class InventoryFlowTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        return store
    }
    func testFoundRecipeIngredientAddsOnlyEnteredStockAndPreservesExistingLotsAndShopping() throws {
        let store = try store(), service = InventoryService(container: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let lettuce = try XCTUnwrap(masters.first { $0.key == "lettuce" })
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "caesar_salad" })
        let existingExpiry = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        let expiredDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let existing = try service.save(InventoryDraft(masterID: lettuce.id, amount: .exact(20, .gram), expiresAt: existingExpiry, expiryKind: .useBy))
        let expired = try service.save(InventoryDraft(masterID: lettuce.id, amount: .exact(80, .gram), expiresAt: expiredDate, expiryKind: .useBy))
        let meals = MealService(container: store)
        try meals.saveManual(name: "台所スポンジ", quantity: 1, unit: .piece)
        try meals.select(recipe: recipe, servings: 1)
        let before = try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>())
        let shoppingIDs = Set(before.map(\.id)), quantities = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.quantity) })
        func availability() throws -> Availability {
            let context = ModelContext(store), stock = try context.fetch(FetchDescriptor<InventoryItem>())
            let result = RecipeSuggestions.evaluate(recipe, foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
                stock: IngredientIdentity.snapshots(stock, customs: [], masters: masters), servings: 1)
            return try XCTUnwrap(result.ingredients.first { $0.id == "lettuce" }).availability
        }
        XCTAssertEqual(try availability().shortage, 60)
        let added = try service.save(InventoryDraft(masterID: lettuce.id, amount: .exact(60, .gram)))
        XCTAssertEqual(try availability().status, .available)
        let fresh = ModelContext(store), lots = try fresh.fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(lots.count, 3)
        XCTAssertEqual(lots.first { $0.id == existing }?.quantity, 20)
        XCTAssertEqual(lots.first { $0.id == existing }?.expiresAt, existingExpiry)
        XCTAssertEqual(lots.first { $0.id == expired }?.expiresAt, expiredDate)
        XCTAssertEqual(lots.first { $0.id == added }?.quantity, 60)
        let shopping = try fresh.fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(Set(shopping.map(\.id)), shoppingIDs)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: shopping.map { ($0.id, $0.quantity) }), quantities)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<MealSelection>()), 1)
    }
    func testFoundRoughStockKeepsQuantityUncertainAndSeasoningUsesPresence() throws {
        let store = try store(), service = InventoryService(container: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let lettuce = try XCTUnwrap(masters.first { $0.key == "lettuce" })
        let mayonnaise = try XCTUnwrap(masters.first { $0.key == "mayonnaise" })
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "caesar_salad" })
        try service.save(InventoryDraft(masterID: lettuce.id, amount: .rough(.available)))
        let mayoID = try service.save(InventoryDraft(masterID: mayonnaise.id, amount: .rough(.low)))
        func result() throws -> RecipeSuggestion {
            RecipeSuggestions.evaluate(recipe, foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
                stock: IngredientIdentity.snapshots(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()), customs: [], masters: masters), servings: 1)
        }
        XCTAssertTrue(try result().confirmation.contains { $0.id == "lettuce" })
        XCTAssertTrue(try result().confirmation.contains { $0.id == "mayonnaise" })
        XCTAssertFalse(try result().ready)
        try service.save(InventoryDraft(masterID: mayonnaise.id, amount: .rough(.available)), editingID: mayoID)
        let saved = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == mayoID })
        XCTAssertNil(saved.quantity); XCTAssertNil(saved.unit)
        XCTAssertEqual(try result().ingredients.first { $0.id == "mayonnaise" }?.availability.status, .available)
        XCTAssertTrue(try result().confirmation.contains { $0.id == "lettuce" })
    }
    func testPresetMappingAndRepeatedBulkRegistrationKeepsExactStock() throws {
        let store = try store()
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let presets = try InventoryPresets.load()
        let keys = Set(presets.sections.flatMap(\.items).map(\.ingredientKey))
        XCTAssertEqual(keys.count, 32)
        XCTAssertTrue(keys.isSubset(of: Set(masters.map(\.key))))
        let egg = try XCTUnwrap(masters.first { $0.key == "egg" })
        let service = InventoryService(container: store)
        let id = try service.save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece), storage: .refrigerated))
        XCTAssertEqual(try service.bulkRegister(keys: ["egg", "soy_sauce"]), 1)
        XCTAssertEqual(try service.bulkRegister(keys: ["egg", "soy_sauce"]), 0)
        let context = ModelContext(store)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryItem>()), 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id }?.quantity, 6)
        XCTAssertThrowsError(try service.bulkRegister(keys: ["salt", "unknown"]))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 2)
    }
    func testEditMoveDiscardHistoryAndValidationAreAtomic() throws {
        let store = try store()
        let master = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let service = InventoryService(container: store)
        let id = try service.save(InventoryDraft(masterID: master.id, amount: .exact(4, .piece)))
        XCTAssertThrowsError(try service.save(InventoryDraft(masterID: master.id, amount: .exact(3, .liter)), editingID: id))
        var item = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first)
        XCTAssertEqual(item.quantity, 4)
        try service.save(InventoryDraft(masterID: master.id, amount: .rough(.low), storage: .frozen), editingID: id)
        item = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.roughState, .low)
        XCTAssertEqual(item.storage, .frozen)
        try service.discard(id: id)
        item = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first)
        XCTAssertTrue(item.isDeleted)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryEvent>()), 3)
        try service.restore(id: id)
        XCTAssertFalse(try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first).isDeleted)
        XCTAssertThrowsError(try service.save(InventoryDraft(customName: "ソース", amount: .exact(-1, .gram))))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<CustomIngredient>()), 0)
    }
    func testMultipleMealsPreserveManualShoppingAndOwnShortages() throws {
        let store = try store()
        let recipes = try RecipeCatalog.load()
        XCTAssertEqual(recipes.count, 192)
        XCTAssertEqual(recipes.filter { $0.role == "main" }.count, 117)
        let service = MealService(container: store)
        try service.saveManual(name: "台所スポンジ", quantity: 1, unit: .piece)
        try service.select(recipe: recipes[0], servings: 1)
        try service.select(recipe: recipes[1], servings: 2)
        let context = ModelContext(store)
        let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.filter { $0.sourceMealID == nil }.count, 1)
        XCTAssertEqual(Set(rows.filter { $0.sourceMealID != nil }.compactMap(\.sourceRecipeTitle)), Set([recipes[0].title, recipes[1].title]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealSelection>()).filter { $0.state == "selected" }.count, 2)
    }
    func testNewShrimpRecipeSelectionPurchaseAndCookingUseStableMasterIdentity() throws {
        let store = try store(), service = MealService(container: store)
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "shrimp_chili" })
        try service.select(recipe: recipe, servings: 2)
        let context = ModelContext(store)
        let master = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "shrimp" })
        let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        let shrimp = try XCTUnwrap(rows.first { $0.ingredientMasterID == master.id })
        XCTAssertEqual(shrimp.quantity, 240); XCTAssertEqual(shrimp.unit, .gram)
        let optional = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "doubanjiang" })
        let water = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "water" })
        XCTAssertFalse(rows.contains { $0.ingredientMasterID == optional.id || $0.ingredientMasterID == water.id })
        try service.setChecked(id: shrimp.id, checked: true)
        try service.purchase([PurchaseDraft(id: shrimp.id, quantity: 0.3, unit: .kilogram, storage: .refrigerated, purchasedAt: .now)])
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.state == "selected" })
        // Record the measured shrimp actually used; other materials were not used in this flow.
        let drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "shrimp" ? 240 : 0)
        }
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts)
        let after = ModelContext(store)
        let stock = try XCTUnwrap(after.fetch(FetchDescriptor<InventoryItem>()).first { $0.ingredientMasterID == master.id })
        XCTAssertEqual(stock.quantity ?? -1, 0.06, accuracy: 0.000001)
        XCTAssertEqual(stock.unit, .kilogram)
        XCTAssertEqual(try after.fetch(FetchDescriptor<MealSelection>()).first { $0.id == meal.id }?.state, "cooked")
        XCTAssertTrue(try after.fetch(FetchDescriptor<InventoryEvent>()).contains { $0.kind == "cooked" && $0.note == recipe.title })
    }


    func testRawRiceRecipePurchasesAndConsumesRawGrainWithoutCreatingCookedRiceStock() throws {
        let store = try store(), service = MealService(container: store)
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "corn_edamame_rice" })
        try service.select(recipe: recipe, servings: 2)
        let context = ModelContext(store)
        let master = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "raw_rice" })
        let cookedMaster = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "cooked_rice" })
        let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        let rice = try XCTUnwrap(rows.first { $0.ingredientMasterID == master.id })
        XCTAssertEqual(rice.quantity, 150); XCTAssertEqual(rice.unit, .gram)
        XCTAssertFalse(rows.contains { $0.ingredientMasterID == cookedMaster.id || $0.name == "水" })
        try service.setChecked(id: rice.id, checked: true)
        try service.purchase([PurchaseDraft(id: rice.id, quantity: 1, unit: .kilogram, storage: .roomTemperature, purchasedAt: .now)])
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.state == "selected" })
        let drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "raw_rice" ? 150 : 0)
        }
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts)
        let after = ModelContext(store), stocks = try after.fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(try XCTUnwrap(stocks.first { $0.ingredientMasterID == master.id }).quantity ?? -1, 0.85, accuracy: 0.000001)
        XCTAssertFalse(stocks.contains { $0.ingredientMasterID == cookedMaster.id })
        XCTAssertEqual(try after.fetch(FetchDescriptor<MealSelection>()).first { $0.id == meal.id }?.state, "cooked")
    }

    func testPurchaseRejectsPartialBatchAndRetainsUncheckedRows() throws {
        let store = try store()
        let service = MealService(container: store)
        try service.saveManual(name: "卵", quantity: 3, unit: .piece)
        try service.saveManual(name: "玉ねぎ", quantity: 2, unit: .piece)
        let rows = try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>())
        let egg = try XCTUnwrap(rows.first { $0.name == "卵" })
        let onion = try XCTUnwrap(rows.first { $0.name == "玉ねぎ" })
        try service.setChecked(id: egg.id, checked: true)
        let valid = PurchaseDraft(id: egg.id, quantity: 3, unit: .piece, storage: .refrigerated, purchasedAt: .now)
        let invalid = PurchaseDraft(id: onion.id, quantity: 0, unit: .piece, storage: .roomTemperature, purchasedAt: .now)
        XCTAssertThrowsError(try service.purchase([valid, invalid]))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 0)
        try service.purchase([valid])
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 1)
        let saved = try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertTrue(saved.first { $0.id == egg.id }!.isAddedToInventory)
        XCTAssertFalse(saved.first { $0.id == onion.id }!.isAddedToInventory)
        XCTAssertThrowsError(try service.purchase([valid]))
    }
    func testPurchaseMergesCompatibleUnitsButSeparatesExpiryLots() throws {
        let store = try store()
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let pork = try XCTUnwrap(masters.first { $0.key == "pork_slices" })
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: pork.id, amount: .exact(100, .gram)))
        let service = MealService(container: store)
        try service.saveManual(name: pork.canonicalName, quantity: 0.2, unit: .kilogram)
        let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.setChecked(id: row.id, checked: true)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 0.2, unit: .kilogram, storage: .refrigerated,
            purchasedAt: .now)])
        let items = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first { $0.id == id }?.quantity, 300)
        try service.saveManual(name: pork.canonicalName, quantity: 50, unit: .gram)
        let new = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first { !$0.isAddedToInventory })
        try service.setChecked(id: new.id, checked: true)
        try service.purchase([PurchaseDraft(id: new.id, quantity: 50, unit: .gram, storage: .refrigerated,
            purchasedAt: .now, expiresAt: Date.now.addingTimeInterval(86400))])
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 2)
    }
    func testCookingUsesFEFOAndPreventsDoubleConsumptionOrOverdraft() throws {
        let store = try store()
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "teriyaki_chicken" })
        let chicken = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "chicken_thigh" })
        let inventory = InventoryService(container: store)
        let early = try inventory.save(InventoryDraft(masterID: chicken.id, amount: .exact(100, .gram),
            expiresAt: .now.addingTimeInterval(86400)))
        let late = try inventory.save(InventoryDraft(masterID: chicken.id, amount: .exact(100, .gram),
            expiresAt: .now.addingTimeInterval(5 * 86400)))
        let service = MealService(container: store)
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        var drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "chicken_thigh" ? 201 : 0)
        }
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts))
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == early }?.quantity, 100)
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: []))
        drafts[0].quantity = 180
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts)
        let items = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(items.first { $0.id == early }?.quantity, 0)
        XCTAssertEqual(items.first { $0.id == late }?.quantity, 20)
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts))
    }
    func testNonFoodPurchaseCanCompleteWithoutCreatingInventory() throws {
        let store = try store()
        let service = MealService(container: store)
        try service.saveManual(name: "台所スポンジ", quantity: 1, unit: .piece)
        let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.setChecked(id: row.id, checked: true)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 1, unit: .piece,
            storage: .roomTemperature, purchasedAt: .now, addToInventory: false)])
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 0)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<CustomIngredient>()), 0)
        XCTAssertTrue(try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first).isAddedToInventory)
    }

    private func refreshRecipe(_ ingredients: [RecipeIngredient]) -> Recipe {
        Recipe(id: UUID(), key: "refresh_test", title: "確認用料理", summary: "", role: "main", baseServings: 1,
            prepMinutes: 1, cookMinutes: 1, ingredients: ingredients, steps: [], allergens: [], status: "active")
    }
    private func refreshIngredient(_ key: String, unit: IngredientUnit = .gram, mode: String = "exact") -> RecipeIngredient {
        RecipeIngredient(ingredientKey: key, quantity: 150, unit: unit, requirement: "required", inventoryMode: mode,
            scaling: "linear", thawing: "none", note: nil)
    }
    func testRemainingQuantityUsesConvertibleLotsInExpiryOrderAndCanUndo() throws {
        let store = try store(), center = InventoryUndoCenter(container: store)
        let chicken = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "chicken_thigh" })
        let service = InventoryService(container: store)
        let early = try service.save(InventoryDraft(masterID: chicken.id, amount: .exact(100, .gram), expiresAt: .now.addingTimeInterval(86400)))
        let later = try service.save(InventoryDraft(masterID: chicken.id, amount: .exact(0.2, .kilogram), expiresAt: .now.addingTimeInterval(864000)))
        let recipe = refreshRecipe([refreshIngredient("chicken_thigh")]), meals = MealService(container: store)
        try meals.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        try meals.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "chicken_thigh", quantity: 50, inputMode: .remaining)])
        let items = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(items.first { $0.id == early }?.quantity, 0)
        XCTAssertEqual(try XCTUnwrap(items.first { $0.id == later }?.quantity), 0.05, accuracy: 0.000001)
        try center.undo(id: XCTUnwrap(center.offer).id)
        let restored = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(restored.first { $0.id == early }?.quantity, 100)
        XCTAssertEqual(restored.first { $0.id == later }?.quantity, 0.2)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "selected")
    }
    func testInvalidRemainingAmountRejectsWholeCookingBatch() throws {
        let store = try store(), context = ModelContext(store)
        let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
        let chicken = try XCTUnwrap(masters.first { $0.key == "chicken_thigh" }), salt = try XCTUnwrap(masters.first { $0.key == "salt" })
        let stock = InventoryService(container: store)
        let chickenID = try stock.save(InventoryDraft(masterID: chicken.id, amount: .exact(200, .gram)))
        let saltID = try stock.save(InventoryDraft(masterID: salt.id, amount: .exact(30, .gram)))
        let recipe = refreshRecipe([refreshIngredient("salt", mode: "presence"), refreshIngredient("chicken_thigh")])
        let service = MealService(container: store); try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(context.fetch(FetchDescriptor<MealSelection>()).first)
        for amount in [201.0, -1, Double.nan] {
            XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: [
                CookingDraft(ingredientKey: "salt", quantity: 0, seasoningStates: [saltID: .unavailable]),
                CookingDraft(ingredientKey: "chicken_thigh", quantity: amount, inputMode: .remaining)]))
        }
        let saved = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(saved.first { $0.id == saltID }?.quantity, 30)
        XCTAssertEqual(saved.first { $0.id == chickenID }?.quantity, 200)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "selected")
    }
    func testRemainingRejectsUncertainUnitsAndRoughStock() throws {
        let exact = StockLot(id: UUID(), quantity: 200, unit: .gram)
        for other in [StockLot(id: UUID(), quantity: 1, unit: .pack), StockLot(id: UUID(), roughState: .low)] {
            XCTAssertThrowsError(try CookingAmounts.usage(for: CookingDraft(ingredientKey: "chicken_thigh", quantity: 0, inputMode: .remaining), lots: [exact, other], unit: .gram))
        }
        XCTAssertEqual(try CookingAmounts.usage(for: CookingDraft(ingredientKey: "chicken_thigh", quantity: 0, inputMode: .remaining), lots: [exact], unit: .gram), 200)
    }
    func testSeasoningExactLotSavesAsThreeStatesAndUndoRestoresQuantity() throws {
        for state in [RoughStockState.available, .low, .unavailable] {
            let store = try store(), center = InventoryUndoCenter(container: store), context = ModelContext(store)
            let salt = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "salt" })
            let id = try InventoryService(container: store).save(InventoryDraft(masterID: salt.id, amount: .exact(30, .gram)))
            let recipe = refreshRecipe([refreshIngredient("salt", mode: "presence")]), service = MealService(container: store)
            try service.select(recipe: recipe, servings: 1)
            let meal = try XCTUnwrap(context.fetch(FetchDescriptor<MealSelection>()).first)
            try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "salt", quantity: 0, seasoningStates: [id: state])])
            let saved = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id })
            XCTAssertEqual(saved.roughState, state); XCTAssertNil(saved.quantity)
            try center.undo(id: XCTUnwrap(center.offer).id)
            XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id }?.quantity, 30)
        }
    }
    func testSeasoningCannotChangeExpiredUnrelatedOrNonSeasoningLots() throws {
        let store = try store(), context = ModelContext(store)
        let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
        let salt = try XCTUnwrap(masters.first { $0.key == "salt" }), chicken = try XCTUnwrap(masters.first { $0.key == "chicken_thigh" })
        let stock = InventoryService(container: store)
        let expired = try stock.save(InventoryDraft(masterID: salt.id, amount: .exact(30, .gram), expiresAt: .now.addingTimeInterval(-86400)))
        let unrelated = try stock.save(InventoryDraft(masterID: chicken.id, amount: .exact(200, .gram)))
        let recipe = refreshRecipe([refreshIngredient("salt", mode: "presence")]), service = MealService(container: store)
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(context.fetch(FetchDescriptor<MealSelection>()).first)
        for id in [expired, unrelated] {
            XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "salt", quantity: 0, seasoningStates: [id: .low])]))
        }
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == expired }?.quantity, 30)
        let chickenRecipe = refreshRecipe([refreshIngredient("chicken_thigh")])
        try service.select(recipe: chickenRecipe, servings: 1)
        let next = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == chickenRecipe.id })
        XCTAssertThrowsError(try service.cook(mealID: next.id, recipe: chickenRecipe, drafts: [CookingDraft(ingredientKey: "chicken_thigh", quantity: 0, seasoningStates: [unrelated: .low])]))
    }

    func testAmbiguousShoppingRequiresExplicitChoiceAndRejectsStaleChoice() throws {
        let store = try store(), service = MealService(container: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let candidates = IngredientNameResolver.candidates("サバ", masters: masters)
        XCTAssertEqual(Set(candidates.map(\.key)), ["canned_mackerel", "mackerel_fillet"])
        XCTAssertThrowsError(try service.saveManual(name: "さば", quantity: 200, unit: .gram))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<ShoppingListItem>()), 0)
        let fresh = try XCTUnwrap(candidates.first { $0.key == "mackerel_fillet" })
        try service.saveManual(name: "さば", quantity: 200, unit: .gram, masterID: fresh.id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first?.ingredientMasterID, fresh.id)
        XCTAssertThrowsError(try service.saveManual(name: "玉ねぎ", quantity: 1, unit: .piece, masterID: fresh.id))
        XCTAssertThrowsError(try service.saveManual(name: "さば", quantity: 1, unit: .can, masterID: fresh.id))
        try service.saveManual(name: "たまねぎ", quantity: 1, unit: .piece)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<ShoppingListItem>()), 2)
    }
    func testUncertainStockOnlyAddedToShoppingByOptInWithoutInventingQuantity() throws {
        let store = try store(), service = MealService(container: store)
        let onion = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "onion" })
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: onion.id, amount: .rough(.available)))
        let recipe = refreshRecipe([refreshIngredient("onion", unit: .piece)])
        XCTAssertEqual(try service.select(recipe: recipe, servings: 1), 0)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<ShoppingListItem>()), 0)
        XCTAssertEqual(try service.select(recipe: recipe, servings: 2, includeUncertain: true), 1)
        let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertTrue(row.needsConfirmation); XCTAssertEqual(row.quantity, 300)
        let lot = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id })
        XCTAssertNil(lot.quantity); XCTAssertEqual(lot.roughState, .available)
    }
    func testCustomMappingFeedsAvailabilityShortagesCookingAndUndoWithoutDuplicateStock() throws {
        let store = try store(), center = InventoryUndoCenter(container: store)
        let inventory = InventoryService(container: store), service = MealService(container: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let chicken = try XCTUnwrap(masters.first { $0.key == "chicken_thigh" })
        let early = try inventory.save(InventoryDraft(customName: "お店の鶏もも", mappedMasterID: chicken.id,
            amount: .exact(0.1, .kilogram), storage: .frozen, expiresAt: .now.addingTimeInterval(86400)))
        let late = try inventory.save(InventoryDraft(masterID: chicken.id, amount: .exact(100, .gram), expiresAt: .now.addingTimeInterval(864000)))
        let context = ModelContext(store), lots = try context.fetch(FetchDescriptor<InventoryItem>())
        let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
        let mapped = IngredientIdentity.snapshots(lots, customs: customs, masters: masters)
        let recipe = refreshRecipe([refreshIngredient("chicken_thigh")])
        XCTAssertEqual(mapped.filter { $0.masterID == chicken.id }.count, 2)
        XCTAssertTrue(RecipeSuggestions.includesRequiredIngredient(recipe, key: chicken.key))
        let suggestion = RecipeSuggestions.evaluate(recipe, foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }, stock: mapped)
        XCTAssertTrue(suggestion.ready)
        XCTAssertEqual(try service.select(recipe: recipe, servings: 2), 1)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 100)
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.state == "selected" })
        try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "chicken_thigh", quantity: 150)])
        let cooked = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(cooked.first { $0.id == early }?.quantity, 0)
        XCTAssertEqual(cooked.first { $0.id == late }?.quantity, 50)
        XCTAssertNil(cooked.first { $0.id == early }?.ingredientMasterID)
        XCTAssertEqual(cooked.count, 2)
        try center.undo(id: XCTUnwrap(center.offer).id)
        let restored = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(restored.first { $0.id == early }?.quantity, 0.1)
        XCTAssertEqual(restored.first { $0.id == late }?.quantity, 100)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.name, "お店の鶏もも")
    }
    func testMappingChangeAndClearUndoAndIncompatibleUnitAreAtomic() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), inventory = InventoryService(container: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let chicken = try XCTUnwrap(masters.first { $0.key == "chicken_thigh" }), onion = try XCTUnwrap(masters.first { $0.key == "onion" })
        let id = try inventory.save(InventoryDraft(customName: "ブランド鶏", amount: .exact(100, .gram)))
        let customID = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id }?.customIngredientID)
        try inventory.mapCustom(id: customID, masterID: chicken.id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.category, .meat)
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.mappedIngredientMasterID)
        try inventory.mapCustom(id: customID, masterID: chicken.id)
        try inventory.mapCustom(id: customID, masterID: nil)
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.mappedIngredientMasterID, chicken.id)
        let incompatible = try inventory.save(InventoryDraft(customName: "パック野菜", amount: .exact(1, .liter)))
        let wrongID = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == incompatible }?.customIngredientID)
        XCTAssertThrowsError(try inventory.mapCustom(id: wrongID, masterID: onion.id))
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first { $0.id == wrongID }?.mappedIngredientMasterID)
        XCTAssertThrowsError(try inventory.save(InventoryDraft(customName: "不正", mappedMasterID: onion.id, amount: .exact(1, .liter))))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<CustomIngredient>()), 2)
    }
    func testMappedExpiredDeletedAndIncompatibleLotsDoNotGuaranteeRecipe() throws {
        let store = try store(), inventory = InventoryService(container: store)
        let masters = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>())
        let chicken = try XCTUnwrap(masters.first { $0.key == "chicken_thigh" })
        try inventory.save(InventoryDraft(customName: "期限切れ", mappedMasterID: chicken.id, amount: .exact(200, .gram), expiresAt: .now.addingTimeInterval(-86400)))
        let deleted = try inventory.save(InventoryDraft(customName: "取り除いた", mappedMasterID: chicken.id, amount: .exact(200, .gram)))
        try inventory.discard(id: deleted)
        try inventory.save(InventoryDraft(customName: "パック", mappedMasterID: chicken.id, amount: .exact(1, .pack)))
        let context = ModelContext(store)
        let snapshots = IngredientIdentity.snapshots(try context.fetch(FetchDescriptor<InventoryItem>()), customs: try context.fetch(FetchDescriptor<CustomIngredient>()), masters: masters)
        let result = RecipeAvailability.evaluate(refreshIngredient("chicken_thigh"), servings: 1, lots: snapshots)
        XCTAssertEqual(result.status, .confirmation); XCTAssertTrue(result.consumption.isEmpty)
    }
    func testRoughResidualObservationRecordsHalfPieceAndUndoRestoresUnknownAmount() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), inventory = InventoryService(container: store)
        let onion = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "onion" })
        let id = try inventory.save(InventoryDraft(masterID: onion.id, amount: .rough(.available)))
        let recipe = refreshRecipe([refreshIngredient("onion", unit: .piece)]), service = MealService(container: store)
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "onion", quantity: 0,
            remainingAmounts: [id: RemainingStockAmount(quantity: 0.5, unit: .piece)])])
        let saved = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first)
        XCTAssertEqual(saved.quantity, 0.5); XCTAssertNil(saved.roughState); XCTAssertEqual(saved.unit, .piece)
        let event = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryEvent>()).first { $0.note.contains("使用量は不明") })
        XCTAssertEqual(event.kind, "edited"); XCTAssertEqual(event.beforeAmount, "available")
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.roughState, .available)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "selected")
    }
    func testResidualObservationsValidateWholeBatchAndRejectConflictingStates() throws {
        let store = try store(), inventory = InventoryService(container: store)
        let onion = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "onion" })
        let id = try inventory.save(InventoryDraft(masterID: onion.id, amount: .rough(.available)))
        let recipe = refreshRecipe([refreshIngredient("onion", unit: .piece)]), service = MealService(container: store)
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        for amount in [RemainingStockAmount(quantity: .nan, unit: .piece), RemainingStockAmount(quantity: -1, unit: .piece), RemainingStockAmount(quantity: 1, unit: .liter)] {
            XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "onion", quantity: 0, remainingAmounts: [id: amount])]))
        }
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "onion", quantity: 0, roughStates: [id: .low], remainingAmounts: [id: RemainingStockAmount(quantity: 1, unit: .piece)])]))
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: [CookingDraft(ingredientKey: "onion", quantity: 0, remainingAmounts: [UUID(): RemainingStockAmount(quantity: 1, unit: .piece)])]))
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "selected")
    }
    func testCompleteWithoutUpdatingStockLeavesAllAmountsAndEventsAndCanUndo() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), inventory = InventoryService(container: store)
        let onion = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "onion" })
        try inventory.save(InventoryDraft(masterID: onion.id, amount: .rough(.low)))
        let recipe = refreshRecipe([refreshIngredient("onion", unit: .piece)]), service = MealService(container: store)
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        let count = try ModelContext(store).fetchCount(FetchDescriptor<InventoryEvent>())
        try service.cook(mealID: meal.id, recipe: recipe, drafts: [], updateInventory: false)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryEvent>()), count)
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.roughState, .low)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "cooked")
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: recipe, drafts: [], updateInventory: false))
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "selected")
    }

    func testMappedCustomEditKeepsMappingValidatesUnitsAndBulkDoesNotDuplicateIt() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = InventoryService(container: store)
        let onion = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "onion" })
        let id = try service.save(InventoryDraft(customName: "お店の玉ねぎ", mappedMasterID: onion.id, amount: .exact(0.5, .piece)))
        let customID = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.customIngredientID)
        try service.save(InventoryDraft(amount: .exact(1, .piece)), editingID: id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.mappedIngredientMasterID, onion.id)
        XCTAssertThrowsError(try service.save(InventoryDraft(amount: .exact(1, .liter)), editingID: id))
        XCTAssertEqual(try service.bulkRegister(keys: ["onion"]), 0)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 1)
        try service.save(InventoryDraft(updatesMapping: true, amount: .exact(1, .liter)), editingID: id)
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.mappedIngredientMasterID)
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first { $0.id == customID }?.mappedIngredientMasterID, onion.id)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.unit, .piece)
    }

}


@MainActor
final class MultipleMealTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let result = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: result); return result
    }
    private func recipe(_ key: String, quantity: Double = 2, unit: IngredientUnit = .piece,
                        ingredientKey: String = "egg", mode: String = "exact") -> Recipe {
        Recipe(id: UUID(), key: key, title: key, summary: "", role: "main", baseServings: 1,
            prepMinutes: 1, cookMinutes: 5,
            ingredients: [RecipeIngredient(ingredientKey: ingredientKey, quantity: quantity, unit: unit,
                requirement: "required", inventoryMode: mode, scaling: "linear", thawing: "none", note: nil)],
            steps: [], allergens: [], status: "active")
    }
    func testSharedStockIsReservedWithoutChangingActualInventory() throws {
        let c = try store(), context = ModelContext(c), service = MealService(container: c)
        let egg = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let id = try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(3, .piece)))
        let first = recipe("first"), second = recipe("second")
        XCTAssertEqual(try service.select(recipe: first, servings: 1), 0)
        XCTAssertEqual(try service.select(recipe: second, servings: 1), 1)
        let fresh = ModelContext(c)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 1)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id }?.quantity, 3)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).count, 2)
    }
    func testReservationConvertsUnitsAndDoesNotReservePresenceTwice() throws {
        let c = try store(), context = ModelContext(c), service = MealService(container: c)
        let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
        let chicken = try XCTUnwrap(masters.first { $0.key == "chicken_thigh" }), salt = try XCTUnwrap(masters.first { $0.key == "salt" })
        try InventoryService(container: c).save(InventoryDraft(masterID: chicken.id, amount: .exact(0.3, .kilogram)))
        try InventoryService(container: c).save(InventoryDraft(masterID: salt.id, amount: .rough(.available)))
        try service.select(recipe: recipe("chicken1", quantity: 200, unit: .gram, ingredientKey: chicken.key), servings: 1)
        try service.select(recipe: recipe("salt1", quantity: 1, unit: .teaspoon, ingredientKey: salt.key, mode: "presence"), servings: 1)
        XCTAssertEqual(try service.select(recipe: recipe("salt2", quantity: 1, unit: .teaspoon, ingredientKey: salt.key, mode: "presence"), servings: 1), 0)
        try service.select(recipe: recipe("chicken2", quantity: 200, unit: .gram, ingredientKey: chicken.key), servings: 1)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity ?? -1, 100, accuracy: 0.00001)
    }
    func testStartResumeCookAndUndoAffectOnlyOneMeal() throws {
        let c = try store(), center = InventoryUndoCenter(container: c), service = MealService(container: c)
        let first = recipe("first"), second = recipe("second")
        try service.select(recipe: first, servings: 1); try service.select(recipe: second, servings: 1)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == first.id })
        try service.startCooking(mealID: meal.id); try service.startCooking(mealID: meal.id)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.id == meal.id }?.state, "cooking")
        XCTAssertThrowsError(try service.select(recipe: first, servings: 2))
        try service.cook(mealID: meal.id, recipe: first, drafts: [], updateInventory: false)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).count, 1)
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.id == meal.id }?.state, "cooking")
    }
    func testCancelKeepsOtherMealsManualCheckedPurchasesAndActualStock() throws {
        let c = try store(), service = MealService(container: c)
        let first = recipe("first"), second = recipe("second")
        try service.saveManual(name: "袋", quantity: 1, unit: .bag)
        try service.select(recipe: first, servings: 1); try service.select(recipe: second, servings: 1)
        let context = ModelContext(c), rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        let checked = try XCTUnwrap(rows.first { $0.sourceRecipeTitle == first.title })
        try service.setChecked(id: checked.id, checked: true)
        let meal = try XCTUnwrap(context.fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == first.id })
        try service.startCooking(mealID: meal.id); try service.cancel(mealID: meal.id)
        let fresh = ModelContext(c), remaining = try fresh.fetch(FetchDescriptor<ShoppingListItem>())
        // The detached checked purchase now covers the other meal; its redundant auto row is removed.
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining.first { $0.id == checked.id }?.isChecked, true)
        XCTAssertNil(remaining.first { $0.id == checked.id }?.sourceMealID)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == second.id }?.state, "selected")
        XCTAssertThrowsError(try service.startCooking(mealID: meal.id))
        XCTAssertThrowsError(try service.cook(mealID: meal.id, recipe: first, drafts: [], updateInventory: false))
        // Checked purchases still enter the fridge after unselecting their meal.
        try service.purchase([PurchaseDraft(id: checked.id, quantity: 2, unit: .piece, storage: .refrigerated, purchasedAt: .now)])
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 2)
    }
    func testCancelRemovesOnlyOwnUnpurchasedRowsAndReleasesReservations() throws {
        let c = try store(), service = MealService(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(1, .piece)))
        let first = recipe("first"), second = recipe("second")
        try service.select(recipe: first, servings: 1); try service.select(recipe: second, servings: 1)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == first.id })
        try service.cancel(mealID: meal.id)
        XCTAssertFalse(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).contains { $0.sourceMealID == meal.id })
        try service.select(recipe: second, servings: 1)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 1)
    }
    func testReselectUpdatesOwnServingsAndKeepsOtherMealShoppingEdits() throws {
        let c = try store(), service = MealService(container: c)
        let first = recipe("first"), second = recipe("second")
        try service.select(recipe: first, servings: 1); try service.select(recipe: second, servings: 1)
        let row = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first { $0.sourceRecipeTitle == second.title })
        try service.updateShopping(id: row.id, quantity: 7, unit: .piece)
        try service.select(recipe: first, servings: 3)
        let context = ModelContext(c)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == first.id }?.servings, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoppingListItem>()).first { $0.id == row.id }?.quantity, 7)
    }
    func testOldMealWithoutIngredientPlanUsesCatalogAndDoesNotLoseSelection() throws {
        let c = try store(), context = ModelContext(c)
        let recipes = try RecipeCatalog.load(), old = MealSelection(recipe: recipes[0], servings: 2)
        context.insert(old); try context.save(); XCTAssertNil(old.ingredientPlanData)
        try MealService(container: c).select(recipe: recipes[1], servings: 1)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).count, 2)
    }
    func testPickerOrderPrefersStockThenMainIngredientsAndStableNames() throws {
        let c = try store(), all = try ModelContext(c).fetch(FetchDescriptor<IngredientMaster>())
        let salt = try XCTUnwrap(all.first { $0.key == "salt" })
        let sorted = all.sorted { IngredientPickerOrder.precedes($0, $1, stocked: [salt.id]) }
        XCTAssertEqual(sorted.first?.key, "salt")
        XCTAssertEqual(sorted.dropFirst().first?.category, .meat)
        XCTAssertEqual(sorted.last?.category, .seasoning)
        XCTAssertLessThan(IngredientPickerOrder.rank(.fish), IngredientPickerOrder.rank(.vegetable))
        XCTAssertLessThan(IngredientPickerOrder.rank(.vegetable), IngredientPickerOrder.rank(.seasoning))
    }
    func testExplicitCategoryAndNameSortDoNotPutStockAheadOfSelectedOrder() throws {
        let c = try store(), all = try ModelContext(c).fetch(FetchDescriptor<IngredientMaster>())
        let salt = try XCTUnwrap(all.first { $0.key == "salt" })
        let categories = all.sorted { IngredientPickerOrder.precedes($0, $1, stocked: [salt.id], sort: .category) }
        XCTAssertEqual(categories.first?.category, .meat)
        XCTAssertEqual(categories.last?.category, .seasoning)
        XCTAssertEqual(categories.map { IngredientPickerOrder.rank($0.category) }, categories.map { IngredientPickerOrder.rank($0.category) }.sorted())
        let names = all.sorted { IngredientPickerOrder.precedes($0, $1, stocked: [salt.id], sort: .name) }
        XCTAssertNotEqual(names.first?.key, "salt")
        for pair in zip(names, names.dropFirst()) {
            XCTAssertNotEqual(pair.0.canonicalName.localizedStandardCompare(pair.1.canonicalName), .orderedDescending)
        }
    }

}

@MainActor
final class ShoppingCheckTests: XCTestCase {
    private struct Failure: Error {}
    private func receipt() -> ShoppingCheckSaveResult { .init(milliseconds: 1, ranOnMainThread: false) }
    func testImmediatePresentationBeforeAnyWriteAndFinalRapidIntentWins() async throws {
        let id = UUID()
        var writes: [Bool] = []
        var resume: CheckedContinuation<Void, Never>?
        let checks = ShoppingChecks { _, value in
            writes.append(value)
            if writes.count == 1 { await withCheckedContinuation { resume = $0 } }
            return self.receipt()
        }
        checks.toggle(id: id, stored: false)
        XCTAssertTrue(checks.isChecked(id: id, stored: false)); XCTAssertTrue(writes.isEmpty)
        while resume == nil { await Task.yield() }
        checks.toggle(id: id, stored: false); XCTAssertFalse(checks.isChecked(id: id, stored: false))
        checks.toggle(id: id, stored: false); XCTAssertTrue(checks.isChecked(id: id, stored: false))
        checks.toggle(id: id, stored: false); XCTAssertFalse(checks.isChecked(id: id, stored: false))
        // An old query event must not overwrite a pending, newer tap.
        checks.synchronize([id: true]); XCTAssertFalse(checks.isChecked(id: id, stored: true))
        resume?.resume(); let saved = await checks.flush()
        XCTAssertTrue(saved); XCTAssertEqual(writes, [true, false]); XCTAssertTrue(checks.savingIDs.isEmpty)
        checks.synchronize([id: false]); XCTAssertNil(checks.overrides[id])
    }
    func testCoalescesRepeatedTapsAlreadyEqualToSavedValueAndSerializesItems() async {
        let a = UUID(), b = UUID(); var writes: [UUID] = []
        let checks = ShoppingChecks { id, _ in writes.append(id); await Task.yield(); return self.receipt() }
        checks.toggle(id: a, stored: false); checks.toggle(id: a, stored: false)
        checks.toggle(id: b, stored: false)
        let saved = await checks.flush()
        XCTAssertTrue(saved); XCTAssertEqual(writes, [b]); XCTAssertFalse(checks.isChecked(id: a, stored: false))
        XCTAssertTrue(checks.isChecked(id: b, stored: false))
    }
    func testFailedSaveRollsBackAndPurchaseFlushReportsFailure() async {
        let id = UUID(); let checks = ShoppingChecks { _, _ in throw Failure() }
        checks.toggle(id: id, stored: false); XCTAssertTrue(checks.isChecked(id: id, stored: false))
        let saved = await checks.flush(); XCTAssertFalse(saved)
        XCTAssertFalse(checks.isChecked(id: id, stored: false)); XCTAssertNotNil(checks.errorMessage)
        XCTAssertTrue(checks.savingIDs.isEmpty)
    }
    func testOlderFailureDoesNotRollBackLaterIntent() async {
        let id = UUID(); var resume: CheckedContinuation<Void, Never>?
        var calls = 0
        let checks = ShoppingChecks { _, _ in
            calls += 1
            if calls == 1 { await withCheckedContinuation { resume = $0 }; throw Failure() }
            return self.receipt()
        }
        checks.toggle(id: id, stored: false)
        while resume == nil { await Task.yield() }
        checks.toggle(id: id, stored: false); checks.toggle(id: id, stored: false)
        resume?.resume(); _ = await checks.flush()
        XCTAssertEqual(calls, 2); XCTAssertTrue(checks.isChecked(id: id, stored: false))
    }
    func testBackgroundSaveFailureMissingRowAndPurchaseUndoNotifications() async throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let center = InventoryUndoCenter(container: store), service = MealService(container: store)
        try service.saveManual(name: "卵", quantity: 2, unit: .piece)
        let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: ExpiryNotifications.inventoryChanged, object: nil, queue: .main) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        try service.setChecked(id: row.id, checked: true); XCTAssertEqual(notifications, 0)
        let actor = await ShoppingCheckWriter.background(container: store)
        let result = try await actor.save(id: row.id, checked: false)
        XCTAssertFalse(result.ranOnMainThread); XCTAssertEqual(notifications, 0)
        do { _ = try await actor.save(id: row.id, checked: true, failBeforeSave: true); XCTFail("expected save failure") } catch {}
        XCTAssertFalse(try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first).isChecked)
        do { _ = try await actor.save(id: UUID(), checked: true); XCTFail("expected missing item") } catch {}
        let checks = ShoppingChecks(); checks.configure(container: store)
        checks.toggle(id: row.id, stored: false)
        let success = await checks.flush(); XCTAssertTrue(success)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 2, unit: .piece, storage: .refrigerated, purchasedAt: .now)])
        XCTAssertEqual(notifications, 1)
        let stock = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(stock.first?.quantity, 2)
        do { _ = try await actor.save(id: row.id, checked: false); XCTFail("registered row must not be checked") } catch {}
        try center.undo(id: XCTUnwrap(center.offer).id)
        XCTAssertEqual(notifications, 2)
        let restored = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertTrue(restored.isChecked); XCTAssertFalse(restored.isAddedToInventory)
        XCTAssertTrue(try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first).isDeleted)
    }
    func testSuccessfulCheckClearsPreviousUndoAndFailurePreservesIt() async throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let center = InventoryUndoCenter(container: store)
        let context = ModelContext(store), row = ShoppingListItem(masterID: nil, name: "試験", quantity: 1, unit: .piece)
        context.insert(row); try context.save()
        try InventoryService(container: store).save(InventoryDraft(customName: "在庫"))
        let token = try XCTUnwrap(center.offer).id
        let actor = await ShoppingCheckWriter.background(container: store)
        do { _ = try await actor.save(id: row.id, checked: true, failBeforeSave: true); XCTFail("expected failure") } catch {}
        XCTAssertEqual(center.offer?.id, token)
        let checks = ShoppingChecks(); checks.configure(container: store); checks.toggle(id: row.id, stored: false)
        _ = await checks.flush(); XCTAssertNil(center.offer)
    }
    func testDiskPersistenceTimingAndPresentationTiming() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try ModelContainer(for: AppPersistence.schema, configurations: ModelConfiguration(schema: AppPersistence.schema, url: folder.appendingPathComponent("timing.store"), cloudKitDatabase: .none))
        let context = ModelContext(store)
        let rows = (0..<100).map { ShoppingListItem(masterID: nil, name: "商品\($0)", quantity: 1, unit: .piece) }
        rows.forEach(context.insert); try context.save()
        let actor = await ShoppingCheckWriter.background(container: store)
        var durations: [Double] = []
        for index in 0..<30 { durations.append(try await actor.save(id: rows[index].id, checked: true).milliseconds) }
        var old: [Double] = []
        for index in 30..<60 {
            let start = ContinuousClock.now
            // Previous implementation's context + full fetch + save, excluding notification work.
            let ctx = ModelContext(store); ctx.autosaveEnabled = false
            let row = try XCTUnwrap(ctx.fetch(FetchDescriptor<ShoppingListItem>()).first { $0.id == rows[index].id })
            row.isChecked = true; try ctx.save()
            let elapsed = start.duration(to: .now).components
            old.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        let checks = ShoppingChecks { _, _ in self.receipt() }
        let start = ContinuousClock.now; checks.toggle(id: rows[0].id, stored: false)
        XCTAssertTrue(checks.isChecked(id: rows[0].id, stored: false))
        let elapsed = start.duration(to: .now).components
        let presentation = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        _ = await checks.flush()
        print("SHOPPING_TIMING simulator disk 100 rows / 30 writes: previous-full-fetch median=\(old.sorted()[15])ms, new-single-row median=\(durations.sorted()[15])ms max=\(durations.max()!)ms; synchronous-presentation=\(presentation)ms (not rendered-frame or device latency)")
    }
}

@MainActor
final class ShoppingReviewTests: XCTestCase {
    func testPurchasedSeasoningUsesSelectedStateConsolidatesAndCanUndo() throws {
        for state in [RoughStockState.available, .low, .unavailable] {
            let store = try AppPersistence.makeContainer(inMemory: true)
            try IngredientMasterImporter.load(into: store)
            let ctx = ModelContext(store)
            let soy = try XCTUnwrap(ctx.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "soy_sauce" })
            let exact = try InventoryItem(ingredient: .master(soy.id), amount: .exact(100, .milliliter), storage: .roomTemperature, purchasedAt: .now)
            let duplicate = try InventoryItem(ingredient: .master(soy.id), amount: .rough(.available), storage: .roomTemperature, purchasedAt: .now)
            let separate = try InventoryItem(ingredient: .master(soy.id), amount: .rough(.low), storage: .refrigerated, purchasedAt: .now)
            [exact, duplicate, separate].forEach { ctx.insert($0) }
            let row = ShoppingListItem(masterID: soy.id, name: soy.canonicalName, quantity: 1, unit: .milliliter)
            row.isChecked = true; ctx.insert(row); try ctx.save()
            let undo = InventoryUndoCenter(container: store)
            try MealService(container: store).purchase([PurchaseDraft(id: row.id, quantity: 0, unit: .block,
                storage: .roomTemperature, purchasedAt: .now, seasoningState: state)])
            let active = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).filter { !$0.isDeleted }
            let target = try XCTUnwrap(active.first { $0.storage == .roomTemperature })
            XCTAssertEqual(active.count, 2); XCTAssertEqual(target.roughState, state)
            XCTAssertEqual(target.stockMode, .rough); XCTAssertNil(target.quantity); XCTAssertNil(target.unit)
            XCTAssertEqual(active.first { $0.id == separate.id }?.roughState, .low)
            XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first!.isAddedToInventory)
            try undo.undo(id: XCTUnwrap(undo.offer).id)
            let restored = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
            XCTAssertEqual(restored.filter { !$0.isDeleted }.count, 3)
            XCTAssertEqual(restored.first { $0.id == exact.id }?.quantity, 100)
            XCTAssertFalse(try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first!.isAddedToInventory)
        }
    }
    func testNewSeasoningAndPurchaseOnlyNeverRequireQuantity() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let ctx = ModelContext(store)
        let salt = try XCTUnwrap(ctx.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "salt" })
        let rows = (0..<2).map { _ in ShoppingListItem(masterID: salt.id, name: salt.canonicalName, quantity: 1, unit: .gram) }
        rows.forEach { $0.isChecked = true; ctx.insert($0) }; try ctx.save()
        try MealService(container: store).purchase([
            PurchaseDraft(id: rows[0].id, quantity: .nan, unit: .piece, storage: .roomTemperature, purchasedAt: .now, seasoningState: .low),
            PurchaseDraft(id: rows[1].id, quantity: 0, unit: .piece, storage: .roomTemperature, purchasedAt: .now, addToInventory: false)
        ])
        let stock = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(stock.count, 1); XCTAssertEqual(stock.first?.roughState, .low)
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).allSatisfy(\.isAddedToInventory))
    }
    func testSeasoningUpdateRollsBackWhenAnotherPurchaseIsInvalid() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let ctx = ModelContext(store), service = MealService(container: store)
        let masters = try ctx.fetch(FetchDescriptor<IngredientMaster>())
        let salt = try XCTUnwrap(masters.first { $0.key == "salt" }), egg = try XCTUnwrap(masters.first { $0.key == "egg" })
        let item = try InventoryItem(ingredient: .master(salt.id), amount: .rough(.available), storage: .roomTemperature, purchasedAt: .now)
        ctx.insert(item)
        let first = ShoppingListItem(masterID: salt.id, name: salt.canonicalName, quantity: 1, unit: .gram)
        let second = ShoppingListItem(masterID: egg.id, name: egg.canonicalName, quantity: 1, unit: .piece)
        [first, second].forEach { $0.isChecked = true; ctx.insert($0) }; try ctx.save()
        XCTAssertThrowsError(try service.purchase([
            PurchaseDraft(id: first.id, quantity: 0, unit: .gram, storage: .roomTemperature, purchasedAt: .now, seasoningState: .unavailable),
            PurchaseDraft(id: second.id, quantity: 0, unit: .piece, storage: .refrigerated, purchasedAt: .now)
        ]))
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.roughState, .available)
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).allSatisfy { !$0.isAddedToInventory })
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryEvent>()), 0)
    }
    func testRemoveCheckedBatchIsAtomicAndNeverChangesStockOrRegisteredPurchases() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let ctx = ModelContext(store), service = MealService(container: store)
        let food = try XCTUnwrap(ctx.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let stock = try InventoryItem(ingredient: .master(food.id), amount: .exact(6, .piece), storage: .refrigerated, purchasedAt: .now)
        let first = ShoppingListItem(masterID: food.id, name: "卵", quantity: 2, unit: .piece)
        let second = ShoppingListItem(masterID: nil, name: "日用品", quantity: 1, unit: .piece)
        let pending = ShoppingListItem(masterID: nil, name: "未購入", quantity: 1, unit: .piece)
        let registered = ShoppingListItem(masterID: food.id, name: "登録済み", quantity: 3, unit: .piece)
        first.isChecked = true; second.isChecked = true; registered.isChecked = true; registered.isAddedToInventory = true
        ctx.insert(stock); [first, second, pending, registered].forEach { ctx.insert($0) }; try ctx.save()
        XCTAssertThrowsError(try service.removeCheckedShopping(ids: [first.id, pending.id]))
        XCTAssertThrowsError(try service.removeCheckedShopping(ids: [first.id, registered.id]))
        XCTAssertThrowsError(try service.removeCheckedShopping(ids: [first.id, UUID()]))
        XCTAssertThrowsError(try service.removeCheckedShopping(ids: []))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<ShoppingListItem>()), 4)
        try service.removeCheckedShopping(ids: [first.id, second.id])
        let after = ModelContext(store)
        XCTAssertEqual(Set(try after.fetch(FetchDescriptor<ShoppingListItem>()).map(\.id)), [pending.id, registered.id])
        XCTAssertEqual(try after.fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 6)
        XCTAssertEqual(try after.fetchCount(FetchDescriptor<InventoryEvent>()), 0)
    }
    private func receipt() -> ShoppingCheckSaveResult { .init(milliseconds: 1, ranOnMainThread: false) }
    func testPendingPresentationKeepsCountsFiltersGroupingAndOnlyChangesTappedRow() async throws {
        let manual = ShoppingListItem(masterID: nil, name: "手入力", quantity: 1, unit: .piece)
        let meal = ShoppingListItem(masterID: nil, name: "献立分", quantity: 100, unit: .gram)
        meal.sourceMealID = UUID(); meal.sourceRecipeTitle = "料理"
        let purchased = ShoppingListItem(masterID: nil, name: "登録済み", quantity: 1, unit: .piece)
        purchased.isChecked = true; purchased.isAddedToInventory = true
        let rows = [manual, meal, purchased]
        let checks = ShoppingChecks { _, _ in self.receipt() }
        let initial = ShoppingPresentation(rows: rows, filter: "すべて", checks: checks)
        XCTAssertEqual(initial.checkedCount, 0)
        XCTAssertEqual(initial.mealRows.map(\.id), [meal.id]); XCTAssertEqual(initial.manualRows.map(\.id), [manual.id])
        checks.toggle(id: manual.id, stored: false)
        let pending = ShoppingPresentation(rows: rows, filter: "すべて", checks: checks)
        XCTAssertEqual(pending.checkedCount, 1)
        XCTAssertEqual(initial.mealRows, pending.mealRows)
        XCTAssertNotEqual(initial.manualRows, pending.manualRows)
        XCTAssertTrue(pending.manualRows[0].isSaving)
        let selected = ShoppingPresentation(rows: rows, filter: "購入済み", checks: checks)
        XCTAssertEqual(selected.checkedCount, 1); XCTAssertEqual(selected.manualRows.map(\.id), [manual.id]); XCTAssertTrue(selected.mealRows.isEmpty)
        let remaining = ShoppingPresentation(rows: rows, filter: "未購入", checks: checks)
        XCTAssertEqual(remaining.checkedCount, 1); XCTAssertTrue(remaining.manualRows.isEmpty); XCTAssertEqual(remaining.mealRows.map(\.id), [meal.id])
        _ = await checks.flush()
        meal.quantity = 200
        let changed = ShoppingPresentation(rows: rows, filter: "すべて", checks: checks)
        XCTAssertNotEqual(initial.mealRows, changed.mealRows); XCTAssertEqual(changed.mealRows[0].quantity, 200)
    }
    func testCheckWithNoUndoDoesNotInvalidateWholeAppAndNoOpPresentationUpdatesAreSuppressed() async throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let center = InventoryUndoCenter(container: store), ctx = ModelContext(store)
        let row = ShoppingListItem(masterID: nil, name: "テスト", quantity: 1, unit: .piece)
        ctx.insert(row); try ctx.save()
        var undoChanges = 0
        let undoObserver = center.objectWillChange.sink { undoChanges += 1 }
        defer { undoObserver.cancel() }
        let checks = ShoppingChecks(); checks.configure(container: store)
        var presentations: [[UUID: Bool]] = [], saving: [Set<UUID>] = []
        let checksObserver = checks.$overrides.dropFirst().sink { presentations.append($0) }
        let savingObserver = checks.$savingIDs.dropFirst().sink { saving.append($0) }
        defer { checksObserver.cancel(); savingObserver.cancel() }
        checks.synchronize([row.id: false]); checks.toggle(id: row.id, stored: false)
        let success = await checks.flush(); XCTAssertTrue(success)
        XCTAssertEqual(undoChanges, 0)
        XCTAssertEqual(presentations, [[row.id: true]]) // Save completion cannot publish the same override again.
        XCTAssertEqual(saving, [Set([row.id]), []])
        checks.synchronize([row.id: true]); checks.synchronize([row.id: true])
        XCTAssertEqual(presentations, [[row.id: true], [:]])
    }
    func testShoppingOnlyEditsDoNotRescheduleExpiryAndCannotModifyRegisteredRows() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let service = MealService(container: store)
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: ExpiryNotifications.inventoryChanged, object: nil, queue: .main) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        try service.saveManual(name: "卵", quantity: 2, unit: .piece)
        let ctx = ModelContext(store), row = try XCTUnwrap(ctx.fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.updateShopping(id: row.id, quantity: 3, unit: .piece)
        XCTAssertThrowsError(try service.updateShopping(id: row.id, quantity: 3, unit: .milliliter))
        XCTAssertEqual(notifications, 0)
        try service.setChecked(id: row.id, checked: true)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 3, unit: .piece, storage: .refrigerated, purchasedAt: .now)])
        XCTAssertEqual(notifications, 1)
        XCTAssertThrowsError(try service.updateShopping(id: row.id, quantity: 1, unit: .piece))
        XCTAssertThrowsError(try service.removeShopping(id: row.id))
        try service.saveManual(name: "メモ", quantity: 1, unit: .piece)
        let memo = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first { $0.name == "メモ" })
        try service.removeShopping(id: memo.id)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 3)
    }
    func testDiskHistoryQueryTimingAndCompletedRowsRemainAvailableToUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try ModelContainer(for: AppPersistence.schema, configurations: ModelConfiguration(schema: AppPersistence.schema, url: folder.appendingPathComponent("history.store"), cloudKitDatabase: .none))
        let ctx = ModelContext(store)
        for index in 0..<2050 {
            let row = ShoppingListItem(masterID: nil, name: "品\(index)", quantity: 1, unit: .piece)
            row.isAddedToInventory = index < 2000; ctx.insert(row)
        }
        try ctx.save()
        var fullTimes: [Double] = [], openTimes: [Double] = []
        func milliseconds(_ start: ContinuousClock.Instant) -> Double {
            let e = start.duration(to: .now).components
            return Double(e.seconds) * 1000 + Double(e.attoseconds) / 1e15
        }
        for _ in 0..<10 {
            let context = ModelContext(store), start = ContinuousClock.now
            let visible = try context.fetch(FetchDescriptor<ShoppingListItem>(sortBy: [SortDescriptor(\.createdAt)])).filter { !$0.isAddedToInventory }
            XCTAssertEqual(visible.count, 50); fullTimes.append(milliseconds(start))
            let fresh = ModelContext(store), filteredStart = ContinuousClock.now
            let current = try fresh.fetch(FetchDescriptor<ShoppingListItem>(predicate: #Predicate { !$0.isAddedToInventory }, sortBy: [SortDescriptor(\.createdAt)]))
            XCTAssertEqual(current.count, 50); openTimes.append(milliseconds(filteredStart))
            XCTAssertEqual(visible.map(\.id), current.map(\.id))
        }
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<ShoppingListItem>()), 2050)
        print("SHOPPING_REVIEW_TIMING simulator disk 2000 completed + 50 open / 10 fresh-context reads: all-fetch median=\(fullTimes.sorted()[5])ms open-query median=\(openTimes.sorted()[5])ms (query only, not device tap or rendered frames)")
    }
}

@MainActor
final class MealPlanningTests: XCTestCase {
    func testTrayCoursesSeparateStaplesFromMainAndKeepSoupAndSide() throws {
        let catalog = try RecipeCatalog.load()
        let expected: [(String, MealCourse)] = [("tuna_mayo_bowl", .staple), ("tonjiru_rice_set", .staple),
            ("rice_vermicelli_stir", .staple), ("french_toast", .staple), ("mentaiko_mochi_pizza", .staple),
            ("teriyaki_chicken", .main), ("pork_daikon_simmer", .main), ("chilled_tofu", .side),
            ("macaroni_salad", .side), ("tofu_wakame_miso_soup", .soup), ("pumpkin_potage", .soup)]
        for (key, course) in expected {
            let recipe = try XCTUnwrap(catalog.first { $0.key == key })
            XCTAssertEqual(MealCourse.of(recipe), course, key)
        }
        XCTAssertEqual(Set(catalog.map(MealCourse.of)), Set(MealCourse.allCases))
    }
    private var today: Date { MealPlanning.day(.now) }
    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }
    private func ingredient(_ key: String = "egg", _ amount: Double = 2, unit: IngredientUnit = .piece,
                            mode: String = "exact", requirement: String = "required") -> RecipeIngredient {
        RecipeIngredient(ingredientKey: key, quantity: amount, unit: unit, requirement: requirement,
            inventoryMode: mode, scaling: "fixed", thawing: "none", note: nil)
    }
    private func plan(_ offset: Int, _ ingredients: [RecipeIngredient]) -> PlannedMeal {
        PlannedMeal(id: UUID(), day: day(offset), createdAt: .now, ingredients: ingredients, hasKnownIngredients: true)
    }
    private func recipe(_ key: String, _ ingredients: [RecipeIngredient]) -> Recipe {
        Recipe(id: UUID(), key: key, title: key, summary: "", role: "main", baseServings: 1, prepMinutes: 1,
            cookMinutes: 5, ingredients: ingredients, steps: [], allergens: [], status: "active")
    }
    private func store() throws -> ModelContainer {
        let c = try AppPersistence.makeContainer(inMemory: true); try IngredientMasterImporter.load(into: c); return c
    }
    func testPreparedSideDoesNotReserveBuyOrConsumeRawStockAndUndoRestoresChoice() throws {
        let c = try store(), service = MealService(container: c), undo = InventoryUndoCenter(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(3, .piece)))
        let side = recipe("prepared-side", [ingredient("egg", 2)])
        XCTAssertEqual(try service.select(recipe: side, servings: 1, includeMaterials: false), 0)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertTrue(meal.isPrepared); XCTAssertEqual(meal.plannedIngredients(recipes: [side])?.count, 0)
        let main = recipe("fresh-main", [ingredient("egg", 3)])
        XCTAssertEqual(try service.select(recipe: main, servings: 1), 0, "Prepared sides must not reserve stock for the main")
        let meals = try ModelContext(c).fetch(FetchDescriptor<MealSelection>())
        let summary = MealPlanning.summarize(meals.map {
            PlannedMeal(id: $0.id, day: today, createdAt: $0.date, ingredients: $0.plannedIngredients(recipes: []) ?? [], hasKnownIngredients: true)
        }, visibleIDs: Set(meals.map(\.id)), foods: [RecipeFood(id: egg.id, key: "egg", name: "卵")],
            stock: [StockLot(id: UUID(), masterID: egg.id, quantity: 3, unit: .piece)])
        XCTAssertEqual(summary.materials.first?.required, 3); XCTAssertTrue(summary.shortages.isEmpty)
        // Even an old/raw editor draft cannot deduct ingredients for an explicitly prepared meal.
        try service.cook(mealID: meal.id, recipe: side, drafts: [CookingDraft(ingredientKey: "egg", quantity: 2)])
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 3)
        XCTAssertFalse(try ModelContext(c).fetch(FetchDescriptor<InventoryEvent>()).contains { $0.kind == "cooked" })
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.id == meal.id }?.state, "cooked")
        try undo.undo(id: XCTUnwrap(undo.offer).id)
        let restored = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.id == meal.id })
        XCTAssertTrue(restored.isActive); XCTAssertTrue(restored.isPrepared)
        try service.cancel(mealID: restored.id)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).map(\.recipeID), [main.id])
    }
    func testSwitchToPreparedPreservesPurchasedAndManualRowsAndFreshChoiceAddsMaterials() throws {
        let c = try store(), service = MealService(container: c)
        let side = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "chilled_tofu" })
        XCTAssertGreaterThan(try service.select(recipe: side, servings: 1), 0)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        let bought = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.setChecked(id: bought.id, checked: true)
        try service.saveManual(name: "台所スポンジ", quantity: 1, unit: .piece)
        XCTAssertEqual(try service.select(recipe: side, servings: 1, includeMaterials: false), 0)
        let rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.count, 2); XCTAssertTrue(rows.allSatisfy { $0.sourceMealID == nil })
        XCTAssertTrue(rows.contains { $0.id == bought.id && $0.isChecked })
        XCTAssertTrue(try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first).isPrepared)
        XCTAssertGreaterThan(try service.select(recipe: side, servings: 2, includeMaterials: true), 0)
        let restored = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertEqual(restored.id, meal.id); XCTAssertFalse(restored.isPrepared)
        XCTAssertEqual(restored.plannedIngredients(recipes: [])?.first?.quantity, side.ingredients.first?.amount(servings: 2, base: side.baseServings))
    }
    func testPreparedChoiceSurvivesDiskReopenWhileLegacyAndCorruptPlansAreNotPrepared() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = AppPersistence.schema
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        try IngredientMasterImporter.load(into: c)
        let side = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "chilled_tofu" })
        try MealService(container: c).select(recipe: side, servings: 2, includeMaterials: false)
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let prepared = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertTrue(prepared.isPrepared); XCTAssertEqual(prepared.servings, 2)
        XCTAssertEqual(prepared.plannedIngredients(recipes: [side])?.count, 0)
        let legacy = MealSelection(recipe: side, servings: 1)
        XCTAssertFalse(legacy.isPrepared); XCTAssertFalse(try XCTUnwrap(legacy.plannedIngredients(recipes: [side])).isEmpty)
        legacy.ingredientPlanData = Data("invalid".utf8)
        XCTAssertFalse(legacy.isPrepared); XCTAssertNil(legacy.plannedIngredients(recipes: [side]))
    }
    func testPlainRiceUsesCookedRiceIdentityWithoutConvertingRawGrainAndCancelsOnlyItsRows() throws {
        let c = try store(), service = MealService(container: c), recipes = try RecipeCatalog.load()
        let rice = try XCTUnwrap(recipes.first { $0.isPlainRice })
        XCTAssertEqual(MealCourse.of(rice), .staple)
        XCTAssertEqual(rice.ingredients.count, 1); XCTAssertEqual(rice.ingredients.first?.ingredientKey, "cooked_rice")
        XCTAssertEqual(rice.ingredients.first?.quantity, 200)
        let masters = try ModelContext(c).fetch(FetchDescriptor<IngredientMaster>())
        let raw = try XCTUnwrap(masters.first { $0.key == "raw_rice" })
        let cooked = try XCTUnwrap(masters.first { $0.key == "cooked_rice" })
        try InventoryService(container: c).save(InventoryDraft(masterID: raw.id, amount: .exact(1000, .gram)))
        XCTAssertEqual(try service.select(recipe: rice, servings: 2), 1)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        let row = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertEqual(row.ingredientMasterID, cooked.id); XCTAssertEqual(row.quantity, 400)
        XCTAssertEqual(meal.plannedIngredients(recipes: [])?.first?.quantity, 400)
        try service.cancel(mealID: meal.id)
        XCTAssertTrue(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 1000)
        XCTAssertFalse(RecipeSuggestions.candidates(recipes, foods: [], stock: []).contains { $0.recipe.isPlainRice })
    }
    func testSevenCalendarDaysAndLegacyUndatedMealDefaultsToToday() {
        let days = MealPlanning.days(from: today)
        XCTAssertEqual(days.count, 7); XCTAssertEqual(Set(days).count, 7); XCTAssertEqual(days.last, day(6))
        let old = MealSelection(recipe: recipe("legacy", [ingredient()]), servings: 2, date: day(-30))
        XCTAssertNil(old.scheduledDate); XCTAssertEqual(old.plannedDay(on: today), today)
        XCTAssertNil(old.plannedIngredients(recipes: [recipe("unrelated", [])]))
        old.state = "cooked"; old.updatedAt = day(-4)
        XCTAssertEqual(old.plannedDay(on: today), day(-4))
    }
    func testWeeklyAndDailyDoNotCountTheSameStockTwice() throws {
        let id = UUID(), first = plan(0, [ingredient()]), second = plan(1, [ingredient()])
        let foods = [RecipeFood(id: id, key: "egg", name: "卵")]
        let stock = [StockLot(id: UUID(), masterID: id, quantity: 3, unit: .piece)]
        let weekly = MealPlanning.summarize([second, first], visibleIDs: [first.id, second.id], foods: foods, stock: stock)
        XCTAssertEqual(weekly.materials.count, 1); XCTAssertEqual(weekly.materials.first?.required, 4)
        XCTAssertEqual(weekly.materials.first?.shortage, 1)
        let tomorrow = MealPlanning.summarize([first, second], visibleIDs: [second.id], foods: foods, stock: stock)
        XCTAssertEqual(tomorrow.materials.first?.required, 2); XCTAssertEqual(tomorrow.materials.first?.shortage, 1)
        let justToday = MealPlanning.summarize([second, first], visibleIDs: [first.id], foods: foods, stock: stock)
        XCTAssertEqual(justToday.materials.first?.shortage, 0); XCTAssertEqual(stock.first?.quantity, 3)
    }
    func testFutureExpiryFEFOAndConfirmedVersusUncertainShortages() throws {
        let id = UUID(), plans = [plan(0, [ingredient()]), plan(3, [ingredient()])]
        let foods = [RecipeFood(id: id, key: "egg", name: "卵")]
        let stock = [StockLot(id: UUID(), masterID: id, quantity: 5, unit: .piece, expiresAt: day(1)),
            StockLot(id: UUID(), masterID: id, quantity: 1, unit: .piece, expiresAt: day(5)),
            StockLot(id: UUID(), masterID: id, roughState: .available, expiresAt: day(5))]
        let value = MealPlanning.summarize(plans, visibleIDs: Set(plans.map(\.id)), foods: foods, stock: stock)
        XCTAssertEqual(value.materials.first?.shortage, 0); XCTAssertEqual(value.materials.first?.unconfirmed, 1)
        let exact = MealPlanning.summarize(plans, visibleIDs: Set(plans.map(\.id)), foods: foods, stock: Array(stock.prefix(2)))
        XCTAssertEqual(exact.materials.first?.shortage, 1); XCTAssertTrue(exact.confirmation.isEmpty)
    }
    func testConvertibleAndIncompatibleUnitsPresenceOptionalIgnoredAndMissingRecipe() {
        let meat = UUID(), salt = UUID()
        let foods = [RecipeFood(id: meat, key: "meat", name: "肉"), RecipeFood(id: salt, key: "salt", name: "塩")]
        let first = plan(0, [ingredient("meat", 0.2, unit: .kilogram), ingredient("salt", 1, unit: .teaspoon, mode: "presence"),
            ingredient("meat", 5, unit: .gram, requirement: "optional"), ingredient("water", 100, unit: .milliliter, mode: "ignored")])
        let second = plan(1, [ingredient("meat", 200, unit: .gram), ingredient("salt", 1, unit: .teaspoon, mode: "presence"), ingredient("meat", 1)])
        let value = MealPlanning.summarize([first, second], visibleIDs: [first.id, second.id], foods: foods,
            stock: [StockLot(id: UUID(), masterID: meat, quantity: 0.5, unit: .kilogram), StockLot(id: UUID(), masterID: salt, roughState: .available)])
        XCTAssertEqual(value.materials.first { $0.key == "meat" && $0.unit == .gram && !$0.optional }?.required, 400)
        XCTAssertEqual(value.materials.first { $0.key == "meat" && $0.unit == .piece }?.unconfirmed, 1)
        XCTAssertEqual(value.materials.first { $0.key == "meat" && $0.optional }?.required, 5)
        XCTAssertTrue(value.shortages.isEmpty); XCTAssertFalse(value.incomplete)
        let unknown = PlannedMeal(id: UUID(), day: today, createdAt: .now, ingredients: [], hasKnownIngredients: false)
        XCTAssertTrue(MealPlanning.summarize([unknown], visibleIDs: [unknown.id], foods: foods, stock: []).incomplete)
    }
    func testSameRecipeCanBeScheduledOnTwoDaysAndCancelPreservesTheOther() throws {
        let c = try store(), service = MealService(container: c), recipes = try RecipeCatalog.load()
        let recipe = try XCTUnwrap(recipes.first { $0.key == "tuna_mayo_bowl" })
        try service.select(recipe: recipe, servings: 1, scheduledDate: day(0))
        try service.select(recipe: recipe, servings: 2, scheduledDate: day(1))
        let context = ModelContext(c), meals = try context.fetch(FetchDescriptor<MealSelection>())
        XCTAssertEqual(meals.count, 2); XCTAssertEqual(Set(meals.map { $0.plannedDay() }).count, 2)
        let first = try XCTUnwrap(meals.first { $0.plannedDay() == day(0) })
        let next = try XCTUnwrap(meals.first { $0.plannedDay() == day(1) })
        XCTAssertEqual(next.plannedIngredients(recipes: [])?.first { $0.ingredientKey == "cooked_rice" }?.quantity, 400)
        try service.cancel(mealID: first.id)
        let after = ModelContext(c)
        XCTAssertEqual(try after.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive).map(\.id), [next.id])
        XCTAssertTrue(try after.fetch(FetchDescriptor<ShoppingListItem>()).contains { $0.sourceMealID == next.id })
    }
    func testSelectingEarlierDayDoesNotReserveFutureMealAndLaterExpiryCreatesShortage() throws {
        let c = try store(), service = MealService(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(4, .piece), expiresAt: day(1)))
        let recipe = recipe("egg", [ingredient()])
        XCTAssertEqual(try service.select(recipe: recipe, servings: 1, scheduledDate: day(3)), 1)
        XCTAssertEqual(try service.select(recipe: recipe, servings: 1, scheduledDate: today), 0)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 4)
    }
    func testScheduleSnapshotAndOwnDaySurviveCookingUndoAndDiskReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = AppPersistence.schema
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        try IngredientMasterImporter.load(into: c)
        let service = MealService(container: c), undo = InventoryUndoCenter(container: c)
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "tuna_mayo_bowl" })
        try service.select(recipe: recipe, servings: 2, scheduledDate: day(5))
        let selected = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        let data = selected.ingredientPlanData
        try service.cook(mealID: selected.id, recipe: recipe, drafts: [], updateInventory: false)
        try undo.undo(id: XCTUnwrap(undo.offer).id)
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let restored = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertTrue(restored.isActive); XCTAssertEqual(restored.scheduledDate, day(5)); XCTAssertEqual(restored.ingredientPlanData, data)
    }
    func testCopiedLegacyStoreLightweightMigration() throws {
        let fixture = URL(fileURLWithPath: "/tmp/meal-week-plan/legacy.store")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("旧バージョン保存データの専用コピーがある検証環境で実行します") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        try FileManager.default.copyItem(at: fixture, to: url)
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = AppPersistence.schema
        let migrated = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let ctx = ModelContext(migrated)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<InventoryItem>()), 19)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ShoppingListItem>()), 2)
        let meal = try XCTUnwrap(ctx.fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertNil(meal.scheduledDate); XCTAssertEqual(meal.plannedDay(on: today), today)
        XCTAssertNotNil(meal.plannedIngredients(recipes: try RecipeCatalog.load()))
        XCTAssertNil(meal.addsShortagesToShopping); XCTAssertTrue(meal.shouldAddShortagesToShopping)
    }
    func testCalendarTodayAnchorMonthYearDSTAndLocalTimeZone() throws {
        for zone in ["Asia/Tokyo", "America/Los_Angeles"] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            for parts in [(2026, 12, 31), (2026, 2, 28), (2026, 3, 8)] {
                let now = try XCTUnwrap(calendar.date(from: DateComponents(year: parts.0, month: parts.1, day: parts.2, hour: 23, minute: 59)))
                let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: MealPlanning.day(now, calendar: calendar)))
                let days = MealPlanning.days(from: now, calendar: calendar)
                XCTAssertEqual(days.count, 7); XCTAssertEqual(Set(days).count, 7)
                XCTAssertEqual(days.first, calendar.startOfDay(for: now)); XCTAssertEqual(days[1], tomorrow)
                XCTAssertEqual(MealPlanning.title(for: tomorrow, now: now, calendar: calendar), "明日の献立")
                XCTAssertEqual(MealPlanning.selectedDay(nil, now: tomorrow, calendar: calendar), tomorrow)
                XCTAssertEqual(MealPlanning.selectedDay(days[0], now: tomorrow, calendar: calendar), days[0])
                XCTAssertEqual(MealPlanning.title(for: tomorrow, now: tomorrow, calendar: calendar), "今日の献立")
                for (index, day) in days.enumerated() {
                    XCTAssertEqual(calendar.dateComponents([.day], from: days[0], to: day).day, index)
                }
            }
        }
    }
    func testShoppingOffKeepsMaterialsReservationsAndCookingConsumption() throws {
        let c = try store(), service = MealService(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(1, .piece)))
        let first = recipe("off", [ingredient()]), second = recipe("on", [ingredient()])
        XCTAssertEqual(try service.select(recipe: first, servings: 1, addShortagesToShopping: false), 0)
        XCTAssertEqual(try service.select(recipe: second, servings: 1), 1)
        let ctx = ModelContext(c), meal = try XCTUnwrap(ctx.fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == first.id })
        XCTAssertFalse(meal.shouldAddShortagesToShopping); XCTAssertFalse(meal.isPrepared)
        XCTAssertEqual(meal.plannedIngredients(recipes: [])?.first?.quantity, 2)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 2)
        try service.cook(mealID: meal.id, recipe: first, drafts: [CookingDraft(ingredientKey: "egg", quantity: 1)])
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 0)
    }
    func testShoppingOffSurvivesRecalculationDiskReopenAndUndo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = AppPersistence.schema
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        try IngredientMasterImporter.load(into: c)
        let service = MealService(container: c), undo = InventoryUndoCenter(container: c), dish = recipe("off", [ingredient()])
        try service.select(recipe: dish, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
        XCTAssertEqual(try service.select(recipe: dish, servings: 2, scheduledDate: day(1)), 0)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        try service.cook(mealID: meal.id, recipe: dish, drafts: [], updateInventory: false)
        try undo.undo(id: XCTUnwrap(undo.offer).id)
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let ctx = ModelContext(reopened), restored = try XCTUnwrap(ctx.fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertTrue(restored.isActive); XCTAssertFalse(restored.shouldAddShortagesToShopping)
        XCTAssertEqual(restored.scheduledDate, day(1)); XCTAssertEqual(restored.plannedIngredients(recipes: [])?.first?.quantity, 2)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)
    }
    func testShoppingReselectNoDuplicateCheckedAndKeepsManualItems() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("on", [ingredient()])
        try service.saveManual(name: "手入力", quantity: 1, unit: .piece)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 1)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 1)
        let row = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first { $0.sourceMealID != nil })
        try service.setChecked(id: row.id, checked: true)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 0)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1, addShortagesToShopping: false), 0)
        let rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(rows.first { $0.id == row.id }?.isChecked, true)
        XCTAssertEqual(rows.first { $0.name == "手入力" }?.quantity, 1)
    }
    func testReselectUsesSameReservationOrderAsMaterialsAndKeepsOffFutureDay() throws {
        let c = try store(), service = MealService(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(3, .piece)))
        let first = recipe("first", [ingredient()]), second = recipe("second", [ingredient()])
        XCTAssertEqual(try service.select(recipe: first, servings: 1), 0)
        XCTAssertEqual(try service.select(recipe: second, servings: 1), 1)
        XCTAssertEqual(try service.select(recipe: first, servings: 1), 0)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 1)
        try service.select(recipe: first, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
        XCTAssertEqual(try service.select(recipe: first, servings: 1, scheduledDate: day(1)), 0)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 3)
        let future = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.plannedDay() == day(1) })
        XCTAssertFalse(future.shouldAddShortagesToShopping)
    }
    func testArchiveSummaryFrozenMaterialsWithoutFabricatedAvailabilityOrWrites() throws {
        let c = try store(), service = MealService(container: c)
        let dish = recipe("past", [ingredient()])
        try service.select(recipe: dish, servings: 1, scheduledDate: day(-1), addShortagesToShopping: false)
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        try service.cook(mealID: meal.id, recipe: dish, drafts: [], updateInventory: false)
        let ctx = ModelContext(c), saved = try XCTUnwrap(ctx.fetch(FetchDescriptor<MealSelection>()).first)
        let data = saved.ingredientPlanData, updated = saved.updatedAt
        let summary = MealPlanning.summarize([PlannedMeal(id: saved.id, day: saved.plannedDay(), createdAt: saved.date,
            ingredients: try XCTUnwrap(saved.plannedIngredients(recipes: [])), hasKnownIngredients: true)], visibleIDs: [saved.id],
            foods: [RecipeFood(id: UUID(), key: "egg", name: "卵")], stock: [], assessAvailability: false)
        XCTAssertEqual(summary.materials.first?.required, 2); XCTAssertTrue(summary.shortages.isEmpty)
        XCTAssertTrue(summary.confirmation.isEmpty)
        let after = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        XCTAssertEqual(after.ingredientPlanData, data); XCTAssertEqual(after.updatedAt, updated); XCTAssertEqual(after.state, "cooked")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<InventoryItem>()).isEmpty)
    }
    func testEarlierReservationRecalculatesLaterShoppingButNeverOffOrEditedRows() throws {
        let c = try store(), service = MealService(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(3, .piece)))
        let later = recipe("later", [ingredient()]), earlier = recipe("earlier", [ingredient()])
        XCTAssertEqual(try service.select(recipe: later, servings: 1, scheduledDate: day(1)), 0)
        XCTAssertEqual(try service.select(recipe: earlier, servings: 1, scheduledDate: today, addShortagesToShopping: false), 0)
        let context = ModelContext(c), meals = try context.fetch(FetchDescriptor<MealSelection>())
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertEqual(row.quantity, 1)
        XCTAssertEqual(row.sourceMealID, meals.first { $0.recipeID == later.id }?.id)
        try service.updateShopping(id: row.id, quantity: 7, unit: .piece)
        let meal = try XCTUnwrap(meals.first { $0.recipeID == earlier.id })
        try service.cancel(mealID: meal.id)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 7)
        try service.select(recipe: later, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
        try service.select(recipe: earlier, servings: 1, scheduledDate: today)
        let rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertFalse(rows.contains { $0.sourceMealID == meals.first { $0.recipeID == later.id }?.id })
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 3)
    }
    func testMaterialDisplayOrdersShortageThenConfirmationThenStock() {
        var missing = PlannedMaterial(id: "a", key: "a", name: "不足", unit: .piece, optional: false, mode: "exact")
        missing.shortage = 1
        var uncertain = PlannedMaterial(id: "b", key: "b", name: "確認", unit: .piece, optional: false, mode: "exact")
        uncertain.unconfirmed = 1
        let ready = PlannedMaterial(id: "c", key: "c", name: "在庫", unit: .piece, optional: false, mode: "exact")
        XCTAssertEqual(MealMaterialSummary(materials: [ready, uncertain, missing], incomplete: false).displayMaterials.map(\.id), ["a", "b", "c"])
    }
    func testExplicitMaterialShoppingDayWeekDeduplicationAndOffIntent() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("batch", [ingredient()])
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .exact(1, .piece)))
        try service.select(recipe: dish, servings: 1, scheduledDate: today, addShortagesToShopping: false)
        try service.select(recipe: dish, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
        let ids: Set<String> = ["egg-piece-exact-required"]
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: ids), 1)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first?.quantity, 1)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 7, materialIDs: ids), 1)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 7, materialIDs: ids), 0)
        let ctx = ModelContext(c), rows = try ctx.fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.reduce(0) { $0 + $1.quantity }, 3)
        XCTAssertTrue(rows.allSatisfy { $0.sourceMealID == nil && $0.automaticallyManaged == false })
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<MealSelection>()).allSatisfy { !$0.shouldAddShortagesToShopping })
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 1)
    }
    func testExplicitMaterialShoppingKeepsAutoAndCheckedRowsAndSkipsUnselected() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("batch", [ingredient()])
        try service.select(recipe: dish, servings: 1)
        let existing = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.setChecked(id: existing.id, checked: true)
        let ids: Set<String> = ["egg-piece-exact-required"]
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 7, materialIDs: ids), 0)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: []), 0)
        let after = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertEqual(after.id, existing.id); XCTAssertEqual(after.quantity, 2); XCTAssertTrue(after.isChecked)
        XCTAssertThrowsError(try service.addMaterialShortages(from: day(-1), days: 1, materialIDs: ids))
    }
    func testExplicitMaterialShoppingUncertainSelectedOnlyAndRegisteredPurchasesNotDoubleCredited() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("uncertain", [ingredient()])
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        try InventoryService(container: c).save(InventoryDraft(masterID: egg.id, amount: .rough(.available)))
        try service.select(recipe: dish, servings: 1, addShortagesToShopping: false)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: []), 0)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: ["egg-piece-exact-required"]), 1)
        let row = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertTrue(row.needsConfirmation); XCTAssertEqual(row.quantity, 2)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: ["egg-piece-exact-required"]), 0)
        let second = try store(), secondService = MealService(container: second)
        try secondService.saveManual(name: "卵", quantity: 2, unit: .piece)
        let bought = try XCTUnwrap(ModelContext(second).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try secondService.setChecked(id: bought.id, checked: true)
        try secondService.purchase([PurchaseDraft(id: bought.id, quantity: 2, unit: .piece, storage: .refrigerated, purchasedAt: .now)])
        try secondService.select(recipe: recipe("registered", [ingredient("egg", 5)]), servings: 1, addShortagesToShopping: false)
        XCTAssertEqual(try secondService.addMaterialShortages(from: today, days: 1, materialIDs: ["egg-piece-exact-required"]), 1)
        let remaining = try ModelContext(second).fetch(FetchDescriptor<ShoppingListItem>()).filter { !$0.isAddedToInventory }
        XCTAssertEqual(remaining.first?.quantity, 3)
    }
    func testBundledNotoSansJPWeightsJapaneseGlyphsAndAccessibilityScaling() throws {
        for name in AppFont.names {
            let font = try XCTUnwrap(UIFont(name: name, size: 17))
            XCTAssertEqual(font.familyName, "Noto Sans JP")
            let text = Array("今日の献立 食材 冷蔵庫 買い物 鶏もも肉".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: text.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, text, &glyphs, text.count))
            let large = UIFontMetrics(forTextStyle: .body).scaledFont(for: font,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
            XCTAssertGreaterThan(large.pointSize, font.pointSize)
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "otf", subdirectory: "fonts"))
        }
    }
    func testMaterialPurchaseCoverageConsumesOnceAndTracksEditsDeletionAndUnits() {
        let egg = RecipeFood(id: UUID(), key: "egg", name: "卵"), meal = UUID(), otherDay = UUID()
        let exact = PlannedMaterial(id: "exact", key: "egg", name: "卵", unit: .piece,
            optional: false, mode: "exact", required: 2, shortage: 2)
        let uncertain = PlannedMaterial(id: "rough", key: "egg", name: "卵", unit: .piece,
            optional: false, mode: "presence", required: 1, unconfirmed: 1)
        func coverage(_ quantity: Double, registered: Bool = false, source: UUID? = nil, unit: IngredientUnit = .piece) -> MaterialShoppingCoverage {
            MaterialShoppingCoverage.assess([exact, uncertain], foods: [egg], purchases: [MaterialPurchase(id: UUID(),
                masterID: egg.id, quantity: quantity, unit: unit, sourceMealID: source, isAddedToInventory: registered)], visibleMealIDs: [meal])
        }
        XCTAssertEqual(coverage(2).addedIDs, ["exact"])
        XCTAssertEqual(coverage(2).remaining["rough"], 1, "One shopping amount must not cover two modes twice")
        XCTAssertEqual(coverage(3).addedIDs, ["exact", "rough"])
        XCTAssertTrue(coverage(1).addedIDs.isEmpty)
        XCTAssertEqual(coverage(1).credited["exact"], 1)
        for invalid in [coverage(0), coverage(.nan), coverage(.infinity), coverage(3, registered: true),
            coverage(3, source: otherDay), coverage(3, unit: .gram)] {
            XCTAssertTrue(invalid.addedIDs.isEmpty); XCTAssertEqual(invalid.remaining["exact"], 2)
        }
        XCTAssertEqual(coverage(3, source: meal).addedIDs.count, 2)
        let deleted = MaterialShoppingCoverage.assess([exact], foods: [egg], purchases: [], visibleMealIDs: [meal])
        XCTAssertTrue(deleted.addedIDs.isEmpty); XCTAssertEqual(deleted.remaining["exact"], 2)
        let milk = RecipeFood(id: UUID(), key: "milk", name: "牛乳")
        let ml = PlannedMaterial(id: "milk", key: milk.key, name: milk.name, unit: .milliliter,
            optional: false, mode: "exact", required: 300, shortage: 300)
        let converted = MaterialShoppingCoverage.assess([ml], foods: [milk], purchases: [MaterialPurchase(id: UUID(),
            masterID: milk.id, quantity: 0.3, unit: .liter)], visibleMealIDs: [])
        XCTAssertEqual(converted.addedIDs, ["milk"])
    }
    func testMaterialShoppingCoverageAndSavingShareMixedModeAllocation() throws {
        let c = try store(), service = MealService(container: c)
        let egg = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let exact = recipe("exact-egg", [ingredient("egg", 2)])
        let presence = recipe("presence-egg", [RecipeIngredient(ingredientKey: "egg", quantity: 1, unit: .piece,
            requirement: "required", inventoryMode: "presence", scaling: "linear", thawing: "none", note: nil)])
        try service.select(recipe: exact, servings: 1, addShortagesToShopping: false)
        try service.select(recipe: presence, servings: 1, addShortagesToShopping: false)
        try service.saveManual(name: "卵", quantity: 2, unit: .piece, masterID: egg.id)
        let ids: Set<String> = ["egg-piece-presence-required"]
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: ids), 1)
        let rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.reduce(0) { $0 + $1.quantity }, 3)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: ids), 0)
        let last = try XCTUnwrap(rows.first { $0.quantity == 1 })
        try service.removeShopping(id: last.id)
        XCTAssertEqual(try service.addMaterialShortages(from: today, days: 1, materialIDs: ids), 1)
    }

    private func purchaseCoverage(_ container: ModelContainer, visibleDay: Date) throws -> MaterialShoppingCoverage {
        let context = ModelContext(container)
        let meals = try context.fetch(FetchDescriptor<MealSelection>()).filter(\.isActive)
        let plans = meals.map { PlannedMeal(id: $0.id, day: $0.plannedDay(), createdAt: $0.date,
            ingredients: $0.plannedIngredients(recipes: []) ?? [], hasKnownIngredients: $0.plannedIngredients(recipes: []) != nil) }
        return MaterialShoppingCoverage.assess(plans: plans,
            foods: try context.fetch(FetchDescriptor<IngredientMaster>()).map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
            stock: try context.fetch(FetchDescriptor<InventoryItem>()).map(StockLot.init),
            purchases: try context.fetch(FetchDescriptor<ShoppingListItem>()).map(MaterialPurchase.init),
            visibleMealIDs: Set(meals.filter { $0.plannedDay() == visibleDay }.map(\.id)))
    }
    func testSeparateDaysNeverCreditSameShoppingQuantityTwice() throws {
        for reverse in [false, true] {
            let c = try store(), service = MealService(container: c)
            let dish = recipe("two-days", [ingredient()]), id = "egg-piece-exact-required"
            try service.select(recipe: dish, servings: 1, scheduledDate: today, addShortagesToShopping: false)
            try service.select(recipe: dish, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
            let first = reverse ? day(1) : today, second = reverse ? today : day(1)
            XCTAssertEqual(try service.addMaterialShortages(from: first, days: 1, materialIDs: [id]), 1)
            XCTAssertEqual(try purchaseCoverage(c, visibleDay: first).addedIDs, [id])
            XCTAssertEqual(try purchaseCoverage(c, visibleDay: second).remaining[id], 2)
            XCTAssertEqual(try service.addMaterialShortages(from: second, days: 1, materialIDs: [id]), 1)
            XCTAssertEqual(try service.addMaterialShortages(from: today, days: 7, materialIDs: [id]), 0)
            XCTAssertEqual(try purchaseCoverage(c, visibleDay: second).addedIDs, [id])
            XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).reduce(0) { $0 + $1.quantity }, 4)
        }
    }
    func testAutomaticShoppingCreditsManualPurchaseOnlyOnceAcrossDays() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("manual-covered", [ingredient()])
        try service.saveManual(name: "卵", quantity: 2, unit: .piece)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 0)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1, scheduledDate: day(1)), 1)
        let rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.reduce(0) { $0 + $1.quantity }, 4)
        XCTAssertEqual(rows.filter { $0.sourceMealID == nil }.count, 1)
        for date in [today, day(1)] { XCTAssertEqual(try purchaseCoverage(c, visibleDay: date).addedIDs, ["egg-piece-exact-required"]) }
    }
    func testEarlierSelectionReallocatesManualPurchaseAndLaterAutomaticShortage() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("future-first", [ingredient()])
        try service.saveManual(name: "卵", quantity: 2, unit: .piece)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1, scheduledDate: day(1)), 0)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 0)
        var rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.reduce(0) { $0 + $1.quantity }, 4)
        let early = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first { $0.plannedDay() == today })
        try service.cancel(mealID: early.id)
        rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.quantity, 2)
        XCTAssertEqual(try purchaseCoverage(c, visibleDay: day(1)).addedIDs, ["egg-piece-exact-required"])
    }
    func testAutomaticShoppingCreditsConvertibleAmountsAndKeepsUnconvertiblePurchases() throws {
        let c = try store(), service = MealService(container: c)
        try service.saveManual(name: "牛乳", quantity: 0.5, unit: .liter)
        let dish = recipe("milk", [ingredient("milk", 300, unit: .milliliter)])
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 0)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1, scheduledDate: day(1)), 1)
        let rows = try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>())
        XCTAssertEqual(rows.first { $0.sourceMealID != nil }?.quantity, 100)
        XCTAssertEqual(rows.first { $0.sourceMealID != nil }?.unit, .milliliter)
        XCTAssertEqual(try purchaseCoverage(c, visibleDay: day(1)).addedIDs, ["milk-milliliter-exact-required"])
        let other = try store(), otherService = MealService(container: other)
        try otherService.saveManual(name: "卵", quantity: 1, unit: .pack)
        XCTAssertEqual(try otherService.select(recipe: recipe("eggs", [ingredient()]), servings: 1), 1)
        XCTAssertEqual(try ModelContext(other).fetch(FetchDescriptor<ShoppingListItem>()).count, 2)
    }
    func testExplicitScopeSurvivesReopenPurchaseAndUndo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = AppPersistence.schema
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        try IngredientMasterImporter.load(into: c)
        let service = MealService(container: c), dish = recipe("persistent-scope", [ingredient()])
        try service.select(recipe: dish, servings: 1, addShortagesToShopping: false)
        try service.select(recipe: dish, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
        XCTAssertEqual(try service.addMaterialShortages(from: day(1), days: 1, materialIDs: ["egg-piece-exact-required"]), 1)
        let row = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        let data = try XCTUnwrap(row.materialScopeData)
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        XCTAssertEqual(try purchaseCoverage(reopened, visibleDay: day(1)).addedIDs, ["egg-piece-exact-required"])
        XCTAssertEqual(try purchaseCoverage(reopened, visibleDay: today).remaining["egg-piece-exact-required"], 2)
        try service.setChecked(id: row.id, checked: true)
        let undo = InventoryUndoCenter(container: c)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 2, unit: .piece, storage: .refrigerated, purchasedAt: .now)])
        try undo.undo(id: XCTUnwrap(undo.offer).id)
        let after = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        XCTAssertEqual(after.materialScopeData, data); XCTAssertFalse(after.isAddedToInventory)
    }
    func testCancelledExplicitScopeBecomesSharedWithoutDroppingThePurchase() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("cancel-scope", [ingredient()])
        try service.select(recipe: dish, servings: 1, addShortagesToShopping: false)
        try service.addMaterialShortages(from: today, days: 1, materialIDs: ["egg-piece-exact-required"])
        let meal = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<MealSelection>()).first)
        try service.cancel(mealID: meal.id)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1, scheduledDate: day(1)), 0)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).count, 1)
    }
    func testCorruptPurchaseScopeNeverSilentlyCreditsAnotherDay() throws {
        let c = try store(), service = MealService(container: c)
        try service.select(recipe: recipe("bad-scope", [ingredient()]), servings: 1, addShortagesToShopping: false)
        let context = ModelContext(c)
        let master = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let row = ShoppingListItem(masterID: master.id, name: "卵", quantity: 2, unit: .piece)
        row.materialScopeData = Data("broken".utf8); context.insert(row); try context.save()
        XCTAssertEqual(try purchaseCoverage(c, visibleDay: today).remaining["egg-piece-exact-required"], 2)
    }

    func testEditedExplicitPurchaseSurplusCoversOtherMealsAfterItsOwnReservation() throws {
        let c = try store(), service = MealService(container: c), dish = recipe("scope-surplus", [ingredient()])
        try service.select(recipe: dish, servings: 1, scheduledDate: day(1), addShortagesToShopping: false)
        try service.addMaterialShortages(from: day(1), days: 1, materialIDs: ["egg-piece-exact-required"])
        let row = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.updateShopping(id: row.id, quantity: 4, unit: .piece)
        XCTAssertEqual(try service.select(recipe: dish, servings: 1), 0)
        XCTAssertEqual(try purchaseCoverage(c, visibleDay: today).addedIDs, ["egg-piece-exact-required"])
        XCTAssertEqual(try purchaseCoverage(c, visibleDay: day(1)).addedIDs, ["egg-piece-exact-required"])
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<ShoppingListItem>()).count, 1)
    }

}
