import XCTest
import SwiftData
import UserNotifications
@testable import KyouNaniTaberu

@MainActor
final class ExpiryNotificationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return value
    }
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter(); return formatter.date(from: value)!
    }
    func testCalendarDaysFilteringAndNoRetroactiveOrDuplicateReminders() {
        let expiry = date("2026-10-10T15:00:00Z") // Oct 11 in Japan
        let valid = ExpiryStock(id: UUID(), name: "卵", expiresAt: expiry, kind: .useBy, hasStock: true)
        let plan = ExpiryNoticePlanner.plan([valid,
            ExpiryStock(id: UUID(), name: "なし", expiresAt: nil, kind: .unspecified, hasStock: true),
            ExpiryStock(id: UUID(), name: "消費済み", expiresAt: expiry, kind: .bestBefore, hasStock: false),
            ExpiryStock(id: UUID(), name: "期限切れ", expiresAt: date("2026-09-01T00:00:00Z"), kind: .useBy, hasStock: true)],
            days: 2, hour: 9, minute: 30, now: date("2026-10-01T00:00:00Z"), calendar: calendar)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireAt, date("2026-10-09T00:30:00Z"))
        XCTAssertEqual(plan.first?.inventoryID, valid.id)
        XCTAssertTrue(ExpiryNoticePlanner.plan([valid], days: 2, hour: 9, minute: 30,
            now: date("2026-10-09T00:31:00Z"), calendar: calendar).isEmpty)
        XCTAssertEqual(ExpiryNoticePlanner.plan([valid], days: 0, hour: 20, minute: 0,
            now: date("2026-10-01T00:00:00Z"), calendar: calendar).first?.fireAt, date("2026-10-11T11:00:00Z"))
    }
    func testCalendarAcrossDaylightSavingUsesWallClock() throws {
        var cal = calendar; cal.timeZone = TimeZone(identifier: "America/New_York")!
        let item = ExpiryStock(id: UUID(), name: "Milk", expiresAt: date("2026-03-09T16:00:00Z"), kind: .bestBefore, hasStock: true)
        let notice = try XCTUnwrap(ExpiryNoticePlanner.plan([item], days: 2, hour: 9, minute: 0,
            now: date("2026-03-01T00:00:00Z"), calendar: cal).first)
        XCTAssertEqual(notice.fireAt, date("2026-03-07T14:00:00Z"))
    }
    func testSystemRequestCarriesStableIdentityKindAndCalendarTime() throws {
        let id = UUID()
        let notice = ExpiryNotice(identifier: ExpiryNoticePlanner.prefix + id.uuidString,
            inventoryID: id, name: "卵", fireAt: date("2026-10-09T00:30:00Z"),
            expiresAt: date("2026-10-11T00:00:00Z"), kind: .useBy)
        let request = SystemExpiryNotificationClient.request(for: notice)
        XCTAssertEqual(request.identifier, notice.identifier)
        XCTAssertEqual(request.content.userInfo["inventoryID"] as? String, id.uuidString)
        XCTAssertTrue(request.content.title.contains("卵"))
        XCTAssertTrue(request.content.body.contains("消費期限"))
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.calendar?.identifier, Calendar.current.identifier)
        XCTAssertEqual(trigger.dateComponents.hour, Calendar.current.component(.hour, from: notice.fireAt))
        XCTAssertEqual(trigger.dateComponents.minute, 30)
        XCTAssertNotNil(request.content.sound)
    }
    private func preferences() -> UserDefaults {
        let name = "ExpiryTests." + UUID().uuidString
        let value = UserDefaults(suiteName: name)!; value.removePersistentDomain(forName: name); return value
    }
    func testSaveEditConsumeDiscardRestorePermissionAndDisableReconcile() async throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let master = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let service = InventoryService(container: store)
        let expiry = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        let id = try service.save(InventoryDraft(masterID: master.id, amount: .exact(3, .piece), expiresAt: expiry, expiryKind: .useBy))
        let client = TestExpiryNotificationClient()
        let notices = ExpiryNotifications(defaults: preferences(), client: client, testing: true)
        await notices.reconcile(container: store)
        XCTAssertEqual(notices.scheduledCount, 0)
        client.status = .denied
        await notices.reconcile(container: store)
        XCTAssertTrue(client.notices.isEmpty)
        client.status = .authorized
        await notices.reconcile(container: store)
        XCTAssertEqual(notices.scheduledCount, 1)
        XCTAssertEqual(client.notices.values.first?.inventoryID, id)
        let firstTime = client.notices.values.first?.fireAt
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1)
        let later = Calendar.current.date(byAdding: .day, value: 2, to: expiry)!
        try service.save(InventoryDraft(masterID: master.id, amount: .rough(.low), expiresAt: later), editingID: id)
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1)
        XCTAssertNotEqual(client.notices.values.first?.fireAt, firstTime)
        try service.discard(id: id)
        await notices.reconcile(container: store)
        XCTAssertTrue(client.notices.isEmpty)
        try service.restore(id: id)
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1)
        try service.save(InventoryDraft(masterID: master.id, amount: .exact(0, .piece), expiresAt: later), editingID: id)
        await notices.reconcile(container: store)
        XCTAssertTrue(client.notices.isEmpty)
        try service.save(InventoryDraft(masterID: master.id, amount: .rough(.unavailable), expiresAt: later), editingID: id)
        await notices.reconcile(container: store)
        XCTAssertTrue(client.notices.isEmpty)
        try service.save(InventoryDraft(masterID: master.id, amount: .rough(.available), expiresAt: later), editingID: id)
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1)
        notices.days = 1; notices.hour = 18; notices.minute = 15
        await notices.reconcile(container: store)
        XCTAssertEqual(Calendar.current.component(.hour, from: try XCTUnwrap(client.notices.values.first?.fireAt)), 18)
        notices.enabled = false
        await notices.reconcile(container: store)
        XCTAssertTrue(client.notices.isEmpty)
    }
    func testPurchasedStockSchedulesAndCookingCancelsOnlyConsumedLot() async throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let chicken = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "chicken_thigh" })
        let service = MealService(container: store)
        let expiry = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        try service.saveManual(name: chicken.canonicalName, quantity: 100, unit: .gram)
        let row = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<ShoppingListItem>()).first)
        try service.setChecked(id: row.id, checked: true)
        try service.purchase([PurchaseDraft(id: row.id, quantity: 100, unit: .gram, storage: .refrigerated,
            purchasedAt: .now, expiresAt: expiry, expiryKind: .useBy)])
        let laterID = try InventoryService(container: store).save(InventoryDraft(masterID: chicken.id,
            amount: .exact(100, .gram), expiresAt: Calendar.current.date(byAdding: .day, value: 2, to: expiry)))
        let client = TestExpiryNotificationClient(); client.status = .authorized
        let notices = ExpiryNotifications(defaults: preferences(), client: client, testing: true)
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 2)
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "teriyaki_chicken" })
        try service.select(recipe: recipe, servings: 1)
        let meal = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first)
        let drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map {
            CookingDraft(ingredientKey: $0.ingredientKey, quantity: $0.ingredientKey == "chicken_thigh" ? 100 : 0)
        }
        try service.cook(mealID: meal.id, recipe: recipe, drafts: drafts)
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 1)
        XCTAssertEqual(client.notices.values.first?.inventoryID, laterID)
    }
    func testCapacityEarliestFirstAndPreferencesPersist() async throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        let context = ModelContext(store)
        for index in 0..<65 {
            context.insert(try InventoryItem(ingredient: .custom(UUID()), amount: .rough(.available), storage: .refrigerated,
                purchasedAt: .now, expiresAt: Calendar.current.date(byAdding: .day, value: index + 10, to: .now)))
        }
        try context.save()
        let defaults = preferences()
        let client = TestExpiryNotificationClient(); client.status = .authorized
        let notices = ExpiryNotifications(defaults: defaults, client: client, testing: true)
        XCTAssertEqual(notices.days, 2); XCTAssertEqual(notices.hour, 9)
        await notices.reconcile(container: store)
        XCTAssertEqual(client.notices.count, 60)
        XCTAssertEqual(notices.omittedCount, 5)
        notices.days = 3; notices.hour = 12; notices.minute = 45; notices.enabled = false
        let reopened = ExpiryNotifications(defaults: defaults, client: client, testing: true)
        XCTAssertFalse(reopened.enabled); XCTAssertEqual(reopened.days, 3)
        XCTAssertEqual(reopened.hour, 12); XCTAssertEqual(reopened.minute, 45)
    }
}

@MainActor
final class AppNoticeFeedTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testInboxIncludesOverdueTodayAndEntireFinalDayButExcludesAbsentAndFutureStock() {
        let now = date("2026-10-07T02:00:00Z")
        let stocks = [
            ExpiryStock(id: UUID(), name: "期限切れ", expiresAt: date("2026-10-05T15:00:00Z"), kind: .useBy, hasStock: true),
            ExpiryStock(id: UUID(), name: "今日", expiresAt: date("2026-10-07T14:59:59Z"), kind: .bestBefore, hasStock: true),
            ExpiryStock(id: UUID(), name: "最終日", expiresAt: date("2026-10-09T14:59:59Z"), kind: .useBy, hasStock: true),
            ExpiryStock(id: UUID(), name: "翌日", expiresAt: date("2026-10-09T15:00:00Z"), kind: .useBy, hasStock: true),
            ExpiryStock(id: UUID(), name: "在庫なし", expiresAt: now, kind: .useBy, hasStock: false),
            ExpiryStock(id: UUID(), name: "期限なし", expiresAt: nil, kind: .unspecified, hasStock: true)]
        let feed = AppNoticeFeed.expiry(stocks, days: 2, now: now, calendar: calendar)
        XCTAssertEqual(feed.map(\.title), ["期限切れ", "今日", "最終日"])
        XCTAssertTrue(feed[0].overdue); XCTAssertFalse(feed[1].overdue)
        XCTAssertTrue(feed[1].body.contains("今日が期限")); XCTAssertTrue(feed[1].body.contains("賞味期限"))
        XCTAssertTrue(feed[2].body.contains("あと2日"))
        XCTAssertEqual(AppNoticeFeed.expiry(stocks, days: 0, now: now, calendar: calendar).map(\.title), ["期限切れ", "今日"])
    }
    func testNoticeIdentitySurvivesClockChangesAndExpiryEditsBecomeUnread() throws {
        let id = UUID(), expiry = date("2026-10-09T00:00:00Z")
        let stock = ExpiryStock(id: id, name: "牛乳", expiresAt: expiry, kind: .bestBefore, hasStock: true)
        let first = AppNoticeFeed.expiry([stock], now: date("2026-10-07T00:00:00Z"), calendar: calendar)
        let nextDay = AppNoticeFeed.expiry([stock], now: date("2026-10-08T00:00:00Z"), calendar: calendar)
        XCTAssertEqual(first.first?.id, nextDay.first?.id)
        let raw = NoticeReadState.marking(first.map(\.id), in: "", current: first)
        XCTAssertTrue(NoticeReadState.ids(raw).contains(try XCTUnwrap(nextDay.first?.id)))
        let changed = ExpiryStock(id: id, name: "牛乳", expiresAt: date("2026-10-08T00:00:00Z"), kind: .bestBefore, hasStock: true)
        let revised = AppNoticeFeed.expiry([changed], now: date("2026-10-07T00:00:00Z"), calendar: calendar)
        XCTAssertFalse(NoticeReadState.ids(raw).contains(try XCTUnwrap(revised.first?.id)))
        let all = NoticeReadState.marking(revised.map(\.id), in: raw, current: revised)
        XCTAssertEqual(NoticeReadState.ids(all), Set(revised.map(\.id)))
        XCTAssertTrue(NoticeReadState.ids("broken JSON").isEmpty)
        let suite = "NoticeReadTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(all, forKey: AppPreferences.readNoticeIDs)
        XCTAssertEqual(UserDefaults(suiteName: suite)?.string(forKey: AppPreferences.readNoticeIDs), all)
        AppPreferences.reset(defaults)
        XCTAssertNil(defaults.object(forKey: AppPreferences.readNoticeIDs))
    }
    func testDeletedZeroAndUnavailableStockStayOutOfInbox() throws {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        let ctx = ModelContext(store), masters = try ctx.fetch(FetchDescriptor<IngredientMaster>())
        let milk = try XCTUnwrap(masters.first { $0.key == "milk" })
        let now = date("2026-10-07T00:00:00Z")
        func item(_ amount: StockAmount) throws -> InventoryItem {
            try InventoryItem(ingredient: .master(milk.id), amount: amount, storage: .refrigerated,
                purchasedAt: now, expiresAt: now, expiryKind: .bestBefore)
        }
        let zero = try item(.exact(0, .milliliter)), absent = try item(.rough(.unavailable))
        let deleted = try item(.exact(100, .milliliter)); deleted.isDeleted = true
        let available = try item(.rough(.available)), low = try item(.rough(.low))
        let stocks = AppNoticeFeed.stock([zero, absent, deleted, available, low], masters: masters, customs: [])
        let notices = AppNoticeFeed.expiry(stocks, now: now, calendar: calendar)
        XCTAssertEqual(Set(notices.compactMap(\.inventoryID)), Set([available.id, low.id]))
        XCTAssertTrue(notices.allSatisfy { $0.title == "牛乳" })
    }
    func testBundledUpdatesLinkToRealRecipesAndPhotos() throws {
        let recipes = try RecipeCatalog.load(), notices = AppNoticeFeed.updates()
        XCTAssertEqual(Set(notices.map(\.id)).count, notices.count)
        XCTAssertEqual(AppNoticeFeed.newRecipeKeys.count, 6)
        for key in notices.flatMap(\.recipeKeys) { XCTAssertTrue(recipes.contains { $0.key == key }, key) }
        for key in ["milk_carbonara", "pumpkin_potage", "drumette_vinegar_simmer"] {
            XCTAssertNotNil(RecipeImageLibrary.image(for: key), key)
        }
    }
}
