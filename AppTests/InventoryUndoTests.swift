import XCTest
import SwiftData
@testable import KyouNaniTaberu

@MainActor
final class InventoryUndoTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store); return store
    }
    private func master(_ key: String, _ store: ModelContainer) throws -> IngredientMaster {
        try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == key })
    }
    private func item(_ id: UUID, _ store: ModelContainer) throws -> InventoryItem {
        try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id })
    }
    private func perform(_ center: InventoryUndoCenter) throws { try center.undo(id: XCTUnwrap(center.offer).id) }
    private func events(_ store: ModelContainer) throws -> [InventoryEvent] { try ModelContext(store).fetch(FetchDescriptor<InventoryEvent>()) }
    private func shopping(_ store: ModelContainer) throws -> [ShoppingListItem] { try ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()) }

    func testEditRestoresAllStockFieldsAndAdvancesVersion() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = InventoryService(container: store)
        let egg = try master("egg", store), purchased = Date(timeIntervalSince1970: 1_600_000_000)
        let expires = purchased.addingTimeInterval(86400)
        let id = try service.save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece), storage: .refrigerated,
            purchasedAt: purchased, expiresAt: expires, expiryKind: .useBy))
        let created = try item(id, store).createdAt
        try service.save(InventoryDraft(amount: .rough(.low), storage: .frozen, expiresAt: nil), editingID: id)
        let savedVersion = try item(id, store).syncVersion
        try perform(center)
        let restored = try item(id, store)
        XCTAssertEqual(restored.quantity, 6); XCTAssertEqual(restored.unit, .piece); XCTAssertNil(restored.roughState)
        XCTAssertEqual(restored.storage, .refrigerated); XCTAssertEqual(restored.purchasedAt, purchased)
        XCTAssertEqual(restored.expiresAt, expires); XCTAssertEqual(restored.expiryKind, .useBy)
        XCTAssertEqual(restored.createdAt, created); XCTAssertGreaterThan(restored.syncVersion, savedVersion)
        XCTAssertFalse(InventoryService.usable(restored, on: .now))
        XCTAssertNil(center.offer); XCTAssertEqual(try events(store).filter { $0.kind == "undone" }.count, 1)
    }
    func testUndoAdditionSoftDeletesAndRetainsCustomAndHistory() throws {
        let store = try store(), center = InventoryUndoCenter(container: store)
        let id = try InventoryService(container: store).save(InventoryDraft(customName: "手作りソース"))
        try perform(center)
        XCTAssertTrue(try item(id, store).isDeleted)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<CustomIngredient>()), 1)
        XCTAssertEqual(try events(store).map(\.kind).sorted(), ["added", "undone"])
        try InventoryService(container: store).restore(id: id)
        XCTAssertFalse(try item(id, store).isDeleted)
    }
    func testUndoDiscardAndRestoreRespectOriginalDeletedState() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = InventoryService(container: store)
        let id = try service.save(InventoryDraft(customName: "ソース"))
        try service.discard(id: id); try perform(center); XCTAssertFalse(try item(id, store).isDeleted)
        try service.discard(id: id); try service.restore(id: id); try perform(center)
        XCTAssertTrue(try item(id, store).isDeleted)
    }
    func testBulkUndoAndNoOpOrInvalidMutationKeepsPriorOffer() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = InventoryService(container: store)
        XCTAssertEqual(try service.bulkRegister(keys: ["egg", "soy_sauce"]), 2)
        let token = try XCTUnwrap(center.offer).id
        XCTAssertEqual(try service.bulkRegister(keys: ["egg", "soy_sauce"]), 0)
        XCTAssertThrowsError(try service.bulkRegister(keys: ["egg", "missing"]))
        XCTAssertEqual(center.offer?.id, token); XCTAssertEqual(center.offer?.stockCount, 2)
        try perform(center)
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).allSatisfy(\.isDeleted))
    }
    func testNewOperationReplacesTokenAndUndoHasNoRedo() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = InventoryService(container: store)
        let old = try service.save(InventoryDraft(customName: "以前")), oldToken = try XCTUnwrap(center.offer).id
        let last = try service.save(InventoryDraft(customName: "直前")), lastToken = try XCTUnwrap(center.offer).id
        XCTAssertThrowsError(try center.undo(id: oldToken)); XCTAssertEqual(center.offer?.id, lastToken)
        try perform(center)
        XCTAssertFalse(try item(old, store).isDeleted); XCTAssertTrue(try item(last, store).isDeleted)
        XCTAssertThrowsError(try center.undo(id: lastToken))
    }
    func testConflictOnOneLotRejectsWholeBatch() throws {
        let store = try store(), center = InventoryUndoCenter(container: store)
        try InventoryService(container: store).bulkRegister(keys: ["egg", "soy_sauce"])
        let context = ModelContext(store), items = try context.fetch(FetchDescriptor<InventoryItem>())
        try items[0].setAmount(.rough(.low)); try context.save()
        let beforeEvents = try events(store).count
        XCTAssertThrowsError(try perform(center))
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).allSatisfy { !$0.isDeleted })
        XCTAssertEqual(try events(store).count, beforeEvents); XCTAssertNil(center.offer)
    }
    func testSaveFailureRollsBackUndoAndAllowsRetry() throws {
        enum Failure: Error { case save }
        let store = try store(), center = InventoryUndoCenter(container: store)
        let id = try InventoryService(container: store).save(InventoryDraft(customName: "ソース"))
        let token = try XCTUnwrap(center.offer).id
        XCTAssertThrowsError(try center.undo(id: token, saveContext: { _ in throw Failure.save }))
        XCTAssertFalse(try item(id, store).isDeleted); XCTAssertEqual(try events(store).count, 1)
        XCTAssertEqual(center.offer?.id, token); try perform(center); XCTAssertTrue(try item(id, store).isDeleted)
    }
    func testReceiptBatchRestoresMergedStockAndKeepsSessionMarker() throws {
        let store = try store(), center = InventoryUndoCenter(container: store)
        let milk = try master("milk", store)
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: milk.id, amount: .exact(500, .milliliter)))
        var row = ReceiptRow(source: "source must not survive", masterID: milk.id, name: milk.canonicalName)
        row.confirmed = true; row.exact = true; row.quantity = "1"; row.unit = .liter; row.merge = true
        var custom = ReceiptRow(name: "ソース"); custom.confirmed = true
        let session = UUID(), service = ReceiptImportService(container: store)
        try service.save(rows: [row, custom], sessionID: session); XCTAssertEqual(try item(id, store).quantity, 1500)
        try perform(center); XCTAssertEqual(try item(id, store).quantity, 500)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).filter(\.isDeleted).count, 1)
        XCTAssertThrowsError(try service.save(rows: [row, custom], sessionID: session))
        XCTAssertFalse(try events(store).contains { $0.note.contains("source must") })
    }
    func testPurchaseUndoRestoresMergedStockAndAllPurchaseFlags() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = MealService(container: store)
        let milk = try master("milk", store)
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: milk.id, amount: .exact(500, .milliliter)))
        try service.saveManual(name: milk.canonicalName, quantity: 1, unit: .liter)
        try service.saveManual(name: "スポンジ", quantity: 1, unit: .piece)
        let rows = try shopping(store)
        for row in rows { try service.setChecked(id: row.id, checked: true) }
        let drafts = rows.map { PurchaseDraft(id: $0.id, quantity: $0.quantity, unit: $0.unit,
            storage: .refrigerated, purchasedAt: .now, addToInventory: $0.ingredientMasterID != nil) }
        try service.purchase(drafts); try perform(center)
        XCTAssertEqual(try item(id, store).quantity, 500)
        XCTAssertTrue(try shopping(store).allSatisfy { $0.isChecked && !$0.isAddedToInventory })
        try service.purchase(drafts); XCTAssertEqual(try item(id, store).quantity, 1500)
    }
    func testCookingUndoRestoresFEFOAndAllowsCookingAgain() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = MealService(container: store)
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "teriyaki_chicken" })
        let chicken = try master("chicken_thigh", store), inventory = InventoryService(container: store)
        let early = try inventory.save(InventoryDraft(masterID: chicken.id, amount: .exact(100, .gram), expiresAt: .now.addingTimeInterval(86400)))
        let late = try inventory.save(InventoryDraft(masterID: chicken.id, amount: .exact(100, .gram), expiresAt: .now.addingTimeInterval(5 * 86400)))
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        let drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "chicken_thigh" ? 180 : 0)
        }
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts); try perform(center)
        XCTAssertEqual(try item(early, store).quantity, 100); XCTAssertEqual(try item(late, store).quantity, 100)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first?.state, "selected")
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts)
        XCTAssertEqual(try item(late, store).quantity, 20)
    }
    func testVoiceUndoAdvancesVersionAndRejectsOldDraft() throws {
        let store = try store(), center = InventoryUndoCenter(container: store)
        let egg = try master("egg", store)
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece)))
        var rows = try VoiceParser.parse("卵を二個使った", ingredients: [ReceiptIngredient(id: egg.id, name: egg.canonicalName, aliases: egg.aliases,
            unit: egg.defaultUnit, allowedUnits: egg.allowedUnits, storage: egg.defaultStorage)])
        rows[0].targetID = id; rows[0].targetVersion = try item(id, store).syncVersion; rows[0].draft.confirmed = true
        try VoiceImportService(container: store).save(rows: rows, sessionID: UUID()); try perform(center)
        XCTAssertEqual(try item(id, store).quantity, 6)
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: rows, sessionID: UUID()))
    }
    func testDeletionClearsOfferOnlyAfterSuccessfulCommit() throws {
        enum Failure: Error { case save }
        let store = try store(), center = InventoryUndoCenter(container: store)
        try InventoryService(container: store).save(InventoryDraft(customName: "ソース"))
        let token = try XCTUnwrap(center.offer).id
        XCTAssertThrowsError(try UserDataService(container: store, saveContext: { _ in throw Failure.save }).deleteAll())
        XCTAssertEqual(center.offer?.id, token)
        try UserDataService(container: store).deleteAll(); XCTAssertNil(center.offer)
        XCTAssertThrowsError(try center.undo(id: token)); XCTAssertEqual(try UserDataService(container: store).summary(), UserDataSummary())
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<IngredientMaster>()), 244)
    }
    func testOtherMealMutationInvalidatesAndCentersAreIsolatedAndEphemeral() throws {
        let a = try store(), b = try store(), first = InventoryUndoCenter(container: a), second = InventoryUndoCenter(container: b)
        try InventoryService(container: a).save(InventoryDraft(customName: "A"))
        XCTAssertNotNil(first.offer); XCTAssertNil(second.offer)
        try MealService(container: a).saveManual(name: "スポンジ", quantity: 1, unit: .piece)
        XCTAssertNil(first.offer)
        try InventoryService(container: a).save(InventoryDraft(customName: "B"))
        let replacement = InventoryUndoCenter(container: a)
        XCTAssertNil(replacement.offer); XCTAssertTrue(InventoryUndoCenter.attached(to: a) === replacement)
        XCTAssertTrue(InventoryUndoCenter.attached(to: b) === second)
    }
    func testChangedPurchaseParticipantBlocksStockUndo() throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = MealService(container: store)
        try service.saveManual(name: "卵", quantity: 3, unit: .piece)
        let row = try XCTUnwrap(shopping(store).first)
        try service.setChecked(id: row.id, checked: true)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 3, unit: .piece, storage: .refrigerated, purchasedAt: .now)])
        let context = ModelContext(store)
        let edited = try XCTUnwrap(context.fetch(FetchDescriptor<ShoppingListItem>()).first)
        edited.quantity = 4; try context.save()
        XCTAssertThrowsError(try perform(center))
        XCTAssertFalse(try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first).isDeleted)
        XCTAssertTrue(try XCTUnwrap(shopping(store).first).isAddedToInventory)
        XCTAssertEqual(try events(store).count, 1)
    }
    func testUndoRestoresExpiryReminderAndUndoAdditionRemovesIt() async throws {
        let store = try store(), center = InventoryUndoCenter(container: store), service = InventoryService(container: store)
        let suite = "InventoryUndoTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let client = TestExpiryNotificationClient(); client.status = .authorized
        let notices = ExpiryNotifications(defaults: defaults, client: client, testing: true)
        let egg = try master("egg", store), expiry = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        let id = try service.save(InventoryDraft(masterID: egg.id, amount: .exact(3, .piece), expiresAt: expiry, expiryKind: .useBy))
        await notices.reconcile(container: store)
        let original = try XCTUnwrap(client.notices.values.first)
        let later = Calendar.current.date(byAdding: .day, value: 2, to: expiry)!
        try service.save(InventoryDraft(amount: .exact(0, .piece), expiresAt: later), editingID: id)
        await notices.reconcile(container: store); XCTAssertTrue(client.notices.isEmpty)
        try perform(center); await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1)
        XCTAssertEqual(client.notices.values.first?.identifier, original.identifier)
        XCTAssertEqual(client.notices.values.first?.fireAt, original.fireAt)
        let milk = try master("milk", store)
        try service.save(InventoryDraft(masterID: milk.id, amount: .rough(.available), expiresAt: expiry))
        await notices.reconcile(container: store); XCTAssertEqual(client.notices.count, 2)
        try perform(center); await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1); XCTAssertEqual(client.notices.values.first?.inventoryID, id)
    }

}
