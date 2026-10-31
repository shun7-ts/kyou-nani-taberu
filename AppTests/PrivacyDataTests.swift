import XCTest
import SwiftData
import UserNotifications
@testable import KyouNaniTaberu

@MainActor
final class PrivacyDataTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store); return store
    }
    private func preferences() -> UserDefaults {
        let suite = "PrivacyDataTests." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        for key in AppPreferences.resetKeys { defaults.set(1, forKey: key) }
        defaults.set("retain", forKey: "unrelated-test-setting")
        return defaults
    }
    private func seed(_ store: ModelContainer) throws {
        let context = ModelContext(store)
        let egg = try XCTUnwrap(context.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "egg" })
        let service = InventoryService(container: store)
        try service.save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece), expiresAt: Calendar.current.date(byAdding: .day, value: 10, to: .now)))
        let removed = try service.save(InventoryDraft(customName: "テスト用ソース")); try service.discard(id: removed)
        let meal = MealSelection(recipe: try XCTUnwrap(RecipeCatalog.load().first), servings: 1); meal.state = "cooked"; context.insert(meal)
        let bought = ShoppingListItem(masterID: egg.id, name: "卵", quantity: 1, unit: .piece, meal: meal)
        bought.isChecked = true; bought.isAddedToInventory = true; context.insert(bought)
        context.insert(ShoppingListItem(masterID: nil, name: "未購入品", quantity: 1, unit: .piece))
        try context.save()
    }
    func testDeleteIncludesRemovedCompletedRecordsAndPreservesMasterIdentities() throws {
        let store = try store(); try seed(store)
        let service = UserDataService(container: store)
        XCTAssertEqual(try service.summary(), UserDataSummary(inventory: 2, customs: 1, events: 3, meals: 1, shopping: 2))
        let ids = Set(try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).map(\.id))
        XCTAssertEqual(ids.count, 244)
        try service.deleteAll(); XCTAssertEqual(try service.summary(), UserDataSummary())
        try IngredientMasterImporter.load(into: store)
        XCTAssertEqual(Set(try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).map(\.id)), ids)
        try service.deleteAll(); XCTAssertEqual(try service.summary(), UserDataSummary())
    }
    func testCommittedDeletionStaysDeletedAfterDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-store-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(schema: AppPersistence.schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
        let ids: Set<UUID> = try autoreleasepool {
            let container = try ModelContainer(for: AppPersistence.schema, configurations: [configuration])
            try IngredientMasterImporter.load(into: container); try seed(container)
            let ids = Set(try ModelContext(container).fetch(FetchDescriptor<IngredientMaster>()).map(\.id))
            try UserDataService(container: container).deleteAll(); return ids
        }
        let reopened = try ModelContainer(for: AppPersistence.schema, configurations: [configuration])
        XCTAssertEqual(try UserDataService(container: reopened).summary(), UserDataSummary())
        XCTAssertEqual(Set(try ModelContext(reopened).fetch(FetchDescriptor<IngredientMaster>()).map(\.id)), ids)
    }
    func testSaveFailureRollsBackAllRecordsAndKeepsSettingsAndNotifications() async throws {
        let store = try store(); try seed(store)
        let defaults = preferences(), client = TestExpiryNotificationClient(); client.status = .authorized
        let notices = ExpiryNotifications(defaults: defaults, client: client, testing: true)
        await notices.reconcile(container: store)
        let session = AppSession(preferences: defaults), beforeGeneration = session.generation
        let before = try UserDataService(container: store).summary(), notificationIDs = Set(client.notices.keys)
        enum Failure: Error { case save }
        let failing = UserDataService(container: store, saveContext: { _ in throw Failure.save })
        do { try await session.reset(service: failing, notices: notices); XCTFail("Expected commit failure") }
        catch { }
        XCTAssertEqual(try UserDataService(container: store).summary(), before)
        XCTAssertEqual(defaults.integer(forKey: AppPreferences.policyVersion), 1)
        XCTAssertEqual(defaults.integer(forKey: "voiceConsentVersion"), 1)
        XCTAssertEqual(session.generation, beforeGeneration); XCTAssertFalse(session.isResetting)
        await notices.reconcile(container: store); XCTAssertEqual(Set(client.notices.keys), notificationIDs)
    }
    func testSuccessfulResetClearsConsentAndNoticesButPreservesOSPermissionAndOtherDefaults() async throws {
        let store = try store(); try seed(store)
        let defaults = preferences(), client = TestExpiryNotificationClient(); client.status = .authorized
        let notices = ExpiryNotifications(defaults: defaults, client: client, testing: true)
        notices.days = 5; notices.hour = 12; notices.minute = 45; notices.openedInventoryID = UUID()
        await notices.reconcile(container: store); XCTAssertEqual(notices.scheduledCount, 1)
        let session = AppSession(preferences: defaults), beforeGeneration = session.generation
        try await session.reset(service: UserDataService(container: store), notices: notices)
        XCTAssertEqual(try UserDataService(container: store).summary(), UserDataSummary())
        XCTAssertTrue(AppPreferences.resetKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        XCTAssertEqual(defaults.string(forKey: "unrelated-test-setting"), "retain")
        XCTAssertTrue(client.notices.isEmpty); XCTAssertEqual(client.status, .authorized)
        XCTAssertNil(notices.openedInventoryID); XCTAssertEqual(notices.scheduledCount, 0)
        XCTAssertTrue(notices.enabled); XCTAssertEqual(notices.days, 2); XCTAssertEqual(notices.hour, 9); XCTAssertEqual(notices.minute, 0)
        XCTAssertNotEqual(session.generation, beforeGeneration); XCTAssertFalse(session.isResetting)
        await notices.reconcile(container: store); XCTAssertTrue(client.notices.isEmpty)
    }
    func testResetWaitsForInFlightNoticeAndNeverReaddsOldInventory() async throws {
        let store = try store(); try seed(store)
        let defaults = preferences(), client = DelayedExpiryClient()
        let notices = ExpiryNotifications(defaults: defaults, client: client, testing: true)
        let began = expectation(description: "OS notification add began"); client.began = { began.fulfill() }
        notices.requestRefresh(container: store)
        await fulfillment(of: [began], timeout: 5)
        let session = AppSession(preferences: defaults)
        let resetting = Task { try await session.reset(service: UserDataService(container: store), notices: notices) }
        for _ in 0..<20 where !session.isResetting { await Task.yield() }
        XCTAssertTrue(session.isResetting)
        XCTAssertEqual(try UserDataService(container: store).summary().inventory, 2)
        client.finishAdd()
        try await resetting.value
        XCTAssertEqual(try UserDataService(container: store).summary(), UserDataSummary())
        XCTAssertTrue(client.backend.notices.isEmpty)
        XCTAssertEqual(notices.scheduledCount, 0); XCTAssertEqual(client.clearCount, 1)
        await notices.reconcile(container: store); XCTAssertTrue(client.backend.notices.isEmpty)
    }
}

@MainActor
private final class DelayedExpiryClient: ExpiryNotificationClient {
    let backend = TestExpiryNotificationClient()
    var began: (() -> Void)?
    var waiting: CheckedContinuation<Void, Never>?
    var clearCount = 0
    init() { backend.status = .authorized }
    func authorization() async -> UNAuthorizationStatus { backend.status }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async -> [UNNotificationRequest] { await backend.pending() }
    func remove(_ ids: [String]) { backend.remove(ids) }
    func removeDelivered(_ ids: [String]) { backend.removeDelivered(ids) }
    func clearAll() { clearCount += 1; backend.clearAll() }
    func add(_ notice: ExpiryNotice) async throws {
        await withCheckedContinuation { continuation in waiting = continuation; began?() }
        try await backend.add(notice)
    }
    func finishAdd() { waiting?.resume(); waiting = nil }
}
