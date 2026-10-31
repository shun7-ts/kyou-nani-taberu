import XCTest
import SwiftData
@testable import KyouNaniTaberu

@MainActor
final class VoiceTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let container = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: container); return container
    }
    private func masters(_ store: ModelContainer) throws -> [IngredientMaster] { try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()) }
    private func ingredients(_ store: ModelContainer) throws -> [ReceiptIngredient] {
        try masters(store).filter { $0.trackInventory && $0.status == .active }.map {
            ReceiptIngredient(id: $0.id, name: $0.canonicalName, aliases: $0.aliases, unit: $0.defaultUnit, allowedUnits: $0.allowedUnits, storage: $0.defaultStorage, category: $0.category)
        }
    }
    private func parsed(_ text: String, store: ModelContainer) throws -> VoiceRow { try XCTUnwrap(VoiceParser.parse(text, ingredients: ingredients(store)).first) }
    private func stock(_ store: ModelContainer, _ key: String, _ value: Double, _ unit: IngredientUnit) throws -> UUID {
        let master = try XCTUnwrap(masters(store).first { $0.key == key })
        // These fixtures deliberately represent separate pre-existing lots.
        return try InventoryService(container: store, mergeDuplicates: false).save(InventoryDraft(masterID: master.id, amount: .exact(value, unit)))
    }
    private func target(_ row: inout VoiceRow, id: UUID, store: ModelContainer) throws {
        let item = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id })
        row.targetID = id; row.targetVersion = item.syncVersion; row.draft.confirmed = true
    }
    private func item(_ id: UUID, store: ModelContainer) throws -> InventoryItem { try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id }) }

    func testJapaneseQuantityActionsAndAliasesAreOnlyCandidates() throws {
        let store = try store()
        let rows = try VoiceParser.parse("たまごを六個買った\n牛乳を二百ミリリットル使った\n卵は残り三個\n牛乳を冷凍に移す", ingredients: ingredients(store))
        XCTAssertEqual(rows.map(\.action), [.add, .consume, .setAmount, .move])
        XCTAssertEqual(Double(rows[0].draft.quantity), 6); XCTAssertEqual(Double(rows[1].draft.quantity), 200)
        XCTAssertEqual(rows[1].draft.unit, .milliliter); XCTAssertEqual(Double(rows[2].draft.quantity), 3)
        XCTAssertEqual(rows[3].draft.storage, .frozen)
        XCTAssertTrue(rows.allSatisfy { !$0.draft.confirmed && $0.targetID == nil && $0.draft.expiresAt == nil })
    }
    func testFractionsZeroNegationAndAmbiguityRequireReview() throws {
        let store = try store()
        XCTAssertEqual(VoiceParser.quantity("牛乳1/2リットル使った")?.0, 0.5)
        XCTAssertEqual(VoiceParser.quantity("牛乳二分の一リットル使った")?.0, 0.5)
        XCTAssertEqual(VoiceParser.quantity("卵残り零個")?.0, 0)
        XCTAssertNil(VoiceParser.quantity("牛乳を半分使った")); XCTAssertNil(VoiceParser.quantity("牛乳1/0リットル使った"))
        XCTAssertNil(VoiceParser.quantity("卵6個×2買った"))
        XCTAssertFalse(try parsed("牛乳を買わなかった", store: store).draft.included)
        XCTAssertEqual(try parsed("牛乳200ml買った使った", store: store).action, .choose)
        XCTAssertNil(try parsed("卵と牛乳を買った", store: store).draft.masterID)
        XCTAssertFalse(try parsed("スポンジを買った", store: store).draft.included)
        XCTAssertThrowsError(try VoiceParser.parse("", ingredients: []))
        XCTAssertThrowsError(try VoiceParser.parse(Array(repeating: "卵買った", count: 21).joined(separator: "\n"), ingredients: []))
    }
    func testAddRequiresConfirmationAndNoTranscriptIsPersisted() throws {
        let store = try store(), service = VoiceImportService(container: store), session = UUID()
        var row = try parsed("卵6個買った", store: store)
        XCTAssertThrowsError(try service.save(rows: [row], sessionID: session))
        row.draft.confirmed = true
        try service.save(rows: [row], sessionID: session)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 1)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first?.quantity, 6)
        XCTAssertThrowsError(try service.save(rows: [row], sessionID: session))
        XCTAssertFalse(try ModelContext(store).fetch(FetchDescriptor<InventoryEvent>()).contains { $0.note.contains("卵") || $0.note.contains("買った") })
    }
    func testConsumptionRequiresSpecificLotAndConvertsOnlyCompatibleUnits() throws {
        let store = try store(), service = VoiceImportService(container: store)
        let a = try stock(store, "milk", 1000, .milliliter), b = try stock(store, "milk", 500, .milliliter)
        var row = try parsed("牛乳0.2リットル使った", store: store); row.draft.confirmed = true
        XCTAssertThrowsError(try service.save(rows: [row], sessionID: UUID()))
        try target(&row, id: a, store: store)
        try service.save(rows: [row], sessionID: UUID())
        XCTAssertEqual(try item(a, store: store).quantity, 800); XCTAssertEqual(try item(b, store: store).quantity, 500)
        row.draft.quantity = "0"; try target(&row, id: a, store: store)
        try service.save(rows: [row], sessionID: UUID())
        XCTAssertEqual(try item(a, store: store).quantity, 800)
        row.draft.unit = .pack; row.draft.quantity = "1"; try target(&row, id: a, store: store)
        XCTAssertThrowsError(try service.save(rows: [row], sessionID: UUID()))
        XCTAssertEqual(try item(a, store: store).quantity, 800)
    }
    func testOverdraftRollsBackAddAndRejectsStaleAndDuplicateTargets() throws {
        let store = try store(), service = VoiceImportService(container: store)
        let id = try stock(store, "milk", 100, .milliliter)
        var addition = try parsed("卵6個買った", store: store); addition.draft.confirmed = true
        var used = try parsed("牛乳200ml使った", store: store); try target(&used, id: id, store: store)
        XCTAssertThrowsError(try service.save(rows: [addition, used], sessionID: UUID()))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 1)
        used.draft.quantity = "20"; used.targetVersion = -1
        XCTAssertThrowsError(try service.save(rows: [used], sessionID: UUID()))
        try target(&used, id: id, store: store)
        var second = try parsed("牛乳残り80ml", store: store); try target(&second, id: id, store: store)
        XCTAssertThrowsError(try service.save(rows: [used, second], sessionID: UUID()))
        XCTAssertEqual(try item(id, store: store).quantity, 100)
    }
    func testRoughUseRequiresExplicitPostUseState() throws {
        let store = try store(), service = VoiceImportService(container: store)
        let id = try stock(store, "milk", 100, .milliliter)
        var row = try parsed("牛乳を半分使った", store: store); try target(&row, id: id, store: store)
        XCTAssertFalse(row.draft.exact)
        XCTAssertThrowsError(try service.save(rows: [row], sessionID: UUID()))
        row.postUseState = .low
        try service.save(rows: [row], sessionID: UUID())
        let changed = try item(id, store: store)
        XCTAssertEqual(changed.stockMode, .rough); XCTAssertEqual(changed.roughState, .low); XCTAssertNil(changed.quantity)
        row.draft.exact = true; row.draft.quantity = "20"; try target(&row, id: id, store: store)
        XCTAssertThrowsError(try service.save(rows: [row], sessionID: UUID()))
    }
    func testSetZeroAndMovePreserveLotDates() throws {
        let store = try store(), service = VoiceImportService(container: store)
        let id = try stock(store, "egg", 6, .piece), originalDate = try item(id, store: store).purchasedAt
        var moved = try parsed("卵を冷凍に移す", store: store); try target(&moved, id: id, store: store)
        try service.save(rows: [moved], sessionID: UUID())
        XCTAssertEqual(try item(id, store: store).storage, .frozen); XCTAssertEqual(try item(id, store: store).quantity, 6)
        XCTAssertEqual(try item(id, store: store).purchasedAt, originalDate)
        var remaining = try parsed("卵は残り0個", store: store); try target(&remaining, id: id, store: store)
        try service.save(rows: [remaining], sessionID: UUID())
        XCTAssertEqual(try item(id, store: store).quantity, 0)
        remaining.draft.quantity = "-1"; try target(&remaining, id: id, store: store)
        XCTAssertThrowsError(try service.save(rows: [remaining], sessionID: UUID()))
    }
    func testMergeIsExplicitAndCustomIngredientCanBeAdded() throws {
        let store = try store(), service = VoiceImportService(container: store)
        let id = try stock(store, "milk", 500, .milliliter)
        var row = try parsed("牛乳1リットル買った", store: store); row.draft.confirmed = true; row.draft.merge = true
        try service.save(rows: [row], sessionID: UUID())
        XCTAssertEqual(try item(id, store: store).quantity, 1500)
        row.draft.expiresAt = .now.addingTimeInterval(86400 * 4)
        try service.save(rows: [row], sessionID: UUID())
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 2)
        var custom = VoiceRow(draft: ReceiptRow(name: "手作りジャム"), action: .add)
        custom.draft.confirmed = true; custom.draft.category = .processed
        try service.save(rows: [custom], sessionID: UUID())
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.category, .processed)
    }
}

@MainActor
private final class ControlledVoiceClient: VoiceRecordingClient {
    var supportsOnDeviceRecognition = true
    var isAvailable = true
    var speech = VoicePermission.authorized
    var microphone = true
    var holdSpeech = false
    var holdMicrophone = false
    var failStart = false
    var speechCalls = 0, microphoneCalls = 0, startCalls = 0, stopCalls = 0, cancelCalls = 0
    var speechContinuation: CheckedContinuation<VoicePermission, Never>?
    var microphoneContinuation: CheckedContinuation<Bool, Never>?
    var hints: [String] = []
    func configure(hints: [String]) { self.hints = hints }
    var results: [@MainActor (String?, Bool, Bool) -> Void] = []
    var interruptions: [@MainActor () -> Void] = []
    func speechPermission() async -> VoicePermission {
        speechCalls += 1
        if holdSpeech { return await withCheckedContinuation { speechContinuation = $0 } }
        return speech
    }
    func microphonePermission() async -> Bool {
        microphoneCalls += 1
        if holdMicrophone { return await withCheckedContinuation { microphoneContinuation = $0 } }
        return microphone
    }
    func resolveSpeech(_ value: VoicePermission) {
        let pending = speechContinuation; speechContinuation = nil; pending?.resume(returning: value)
    }
    func resolveMicrophone(_ value: Bool) {
        let pending = microphoneContinuation; microphoneContinuation = nil; pending?.resume(returning: value)
    }
    func start(result: @escaping @MainActor (String?, Bool, Bool) -> Void,
               interrupted: @escaping @MainActor () -> Void) throws {
        startCalls += 1
        if failStart { throw CocoaError(.featureUnsupported) }
        results.append(result); interruptions.append(interrupted)
    }
    func stop() { stopCalls += 1 }
    func cancel() { cancelCalls += 1 }
}

@MainActor
final class VoiceRecorderTests: XCTestCase {
    func testNonFinalUtterancesKeepEarlierAudioAndStillAcceptRevisions() {
        let buffer = VoiceTranscriptAccumulator()
        XCTAssertEqual(buffer.update("卵6個", range: .init(start: 0, end: 1), now: 1), "卵6個")
        XCTAssertEqual(buffer.update("牛乳", range: .init(start: 3, end: 4), now: 4), "卵6個\n牛乳")
        XCTAssertEqual(buffer.update("牛乳200ml", range: .init(start: 3, end: 4.5), now: 4.5), "卵6個\n牛乳200ml")
        XCTAssertEqual(buffer.update("白菜半分", range: .init(start: 6, end: 7), now: 7), "卵6個\n牛乳200ml\n白菜半分")
        XCTAssertEqual(buffer.update("卵3個", range: .init(start: 9, end: 10), now: 10), "卵6個\n牛乳200ml\n白菜半分\n卵3個")
        XCTAssertEqual(buffer.update("", range: nil, now: 11), "卵6個\n牛乳200ml\n白菜半分\n卵3個")
    }
    func testCumulativeResultDoesNotDuplicateRetainedUtterances() {
        let buffer = VoiceTranscriptAccumulator()
        _ = buffer.update("卵6個", range: .init(start: 0, end: 1), now: 1)
        _ = buffer.update("牛乳", range: .init(start: 3, end: 4), now: 4)
        XCTAssertEqual(buffer.update("卵6個、牛乳200ml", range: .init(start: 0, end: 4.5), now: 4.5), "卵6個、牛乳200ml")
    }
    func testUntimedPauseRetainsPhraseButQuantityAndKanjiRevisionsReplace() {
        let buffer = VoiceTranscriptAccumulator()
        _ = buffer.update("ご飯200グラム", range: nil, now: 0)
        XCTAssertEqual(buffer.update("御飯200グラム", range: nil, now: 2), "御飯200グラム")
        XCTAssertEqual(buffer.update("白菜半分", range: nil, now: 4), "御飯200グラム\n白菜半分")
        XCTAssertEqual(buffer.update("白菜半分、牛乳", range: nil, now: 4.2), "御飯200グラム\n白菜半分、牛乳")
    }
    func testResetAudioTimestampAndRepeatedUnchangedPartialsDoNotEraseEarlierFoods() {
        let buffer = VoiceTranscriptAccumulator()
        _ = buffer.update("卵6個", range: .init(start: 0, end: 1), now: 1)
        _ = buffer.update("卵6個", range: .init(start: 0, end: 1), now: 2.5)
        XCTAssertEqual(buffer.update("牛乳", range: .init(start: 0, end: 1), now: 3), "卵6個\n牛乳")
        XCTAssertEqual(buffer.update("白菜半分", range: .init(start: 0, end: 1), now: 5), "卵6個\n牛乳\n白菜半分")
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }
    func testFirstPermissionDialogsWaitForActiveBeforeRequestingMicAndRecording() async throws {
        let client = ControlledVoiceClient(); client.holdSpeech = true; client.holdMicrophone = true
        let recorder = VoiceRecorder(client: client)
        let start = Task { await recorder.start() }
        try await eventually { client.speechContinuation != nil }
        recorder.activityChanged(.inactive); client.resolveSpeech(.authorized)
        try await eventually { recorder.phase == .waitingForActive }
        XCTAssertEqual(client.microphoneCalls, 0); XCTAssertEqual(client.startCalls, 0)
        XCTAssertTrue(recorder.busy); XCTAssertFalse(recorder.recording)
        recorder.activityChanged(.active)
        try await eventually { client.microphoneContinuation != nil }
        recorder.activityChanged(.inactive); client.resolveMicrophone(true)
        try await eventually { recorder.phase == .waitingForActive }
        XCTAssertEqual(client.startCalls, 0)
        recorder.activityChanged(.active); await start.value
        XCTAssertEqual(client.startCalls, 1); XCTAssertTrue(recorder.recording)
        recorder.cancel()
    }
    func testBackgroundDuringSpeechPermissionDoesNotContinueAfterLateApproval() async throws {
        let client = ControlledVoiceClient(); client.holdSpeech = true
        let recorder = VoiceRecorder(client: client)
        let pending = Task { await recorder.start() }
        try await eventually { client.speechContinuation != nil }
        recorder.activityChanged(.background); client.resolveSpeech(.authorized); await pending.value
        recorder.activityChanged(.active)
        XCTAssertFalse(recorder.busy); XCTAssertEqual(client.microphoneCalls, 0); XCTAssertEqual(client.startCalls, 0)
        XCTAssertNotNil(recorder.message)
    }
    func testCancelWhileWaitingForActiveReleasesWaitAndDoesNotRestart() async throws {
        let client = ControlledVoiceClient(); client.holdSpeech = true
        let recorder = VoiceRecorder(client: client)
        let pending = Task { await recorder.start() }
        try await eventually { client.speechContinuation != nil }
        recorder.activityChanged(.inactive); client.resolveSpeech(.authorized)
        try await eventually { recorder.phase == .waitingForActive }
        recorder.cancel(erase: true); await pending.value; recorder.activityChanged(.active)
        XCTAssertFalse(recorder.busy); XCTAssertEqual(client.startCalls, 0); XCTAssertEqual(client.microphoneCalls, 0)
    }
    func testDeniedAndRestrictedSpeechDoNotAskForMic() async {
        for permission in [VoicePermission.denied, .restricted] {
            let client = ControlledVoiceClient(); client.speech = permission
            let recorder = VoiceRecorder(client: client); await recorder.start()
            XCTAssertEqual(recorder.settingsNeeded, permission == .denied)
            XCTAssertFalse(recorder.busy); XCTAssertNotNil(recorder.message)
            XCTAssertEqual(client.microphoneCalls, 0); XCTAssertEqual(client.startCalls, 0)
        }
    }
    func testMicrophoneDenialCanRetryAfterPermissionChange() async {
        let client = ControlledVoiceClient(); client.microphone = false
        let recorder = VoiceRecorder(client: client); await recorder.start()
        XCTAssertTrue(recorder.settingsNeeded); XCTAssertFalse(recorder.busy); XCTAssertEqual(client.startCalls, 0)
        client.microphone = true; await recorder.start()
        XCTAssertFalse(recorder.settingsNeeded); XCTAssertNil(recorder.message); XCTAssertTrue(recorder.recording)
        recorder.cancel()
    }
    func testUnsupportedUnavailableAndStartFailureAllowManualFallback() async {
        let unsupported = ControlledVoiceClient(); unsupported.supportsOnDeviceRecognition = false
        let first = VoiceRecorder(client: unsupported); await first.start()
        XCTAssertFalse(first.busy); XCTAssertEqual(unsupported.speechCalls, 0); XCTAssertNotNil(first.message)
        let unavailable = ControlledVoiceClient(); unavailable.isAvailable = false
        let second = VoiceRecorder(client: unavailable); await second.start()
        XCTAssertFalse(second.busy); XCTAssertEqual(unavailable.startCalls, 0); XCTAssertNotNil(second.message)
        let failing = ControlledVoiceClient(); failing.failStart = true
        let third = VoiceRecorder(client: failing); await third.start()
        XCTAssertFalse(third.busy); XCTAssertNotNil(third.message); XCTAssertGreaterThan(failing.cancelCalls, 1)
    }
    func testLeavingRecordingStopsMicAndPreservesOnlyCurrentPartialText() async {
        let client = ControlledVoiceClient(), recorder = VoiceRecorder(client: client)
        await recorder.start(); client.results[0]("卵6個", false, false)
        let before = client.cancelCalls
        recorder.activityChanged(.inactive)
        XCTAssertFalse(recorder.busy); XCTAssertGreaterThan(client.cancelCalls, before)
        client.results[0]("遅い結果", true, false)
        XCTAssertEqual(recorder.transcript, "卵6個"); XCTAssertNotNil(recorder.message)
        recorder.activityChanged(.active); XCTAssertFalse(recorder.recording)
        recorder.cancel(erase: true); XCTAssertEqual(recorder.transcript, "")
    }
    func testStopKeepsFinalResultAndRejectsCallbacksAfterCompletion() async {
        let client = ControlledVoiceClient(), recorder = VoiceRecorder(client: client)
        await recorder.start(); client.results[0]("牛乳", false, false)
        recorder.stop()
        XCTAssertEqual(client.stopCalls, 1); XCTAssertFalse(recorder.recording); XCTAssertTrue(recorder.busy)
        XCTAssertEqual(recorder.phase, .finishing)
        client.results[0]("牛乳200ml使った", true, false)
        XCTAssertFalse(recorder.busy); XCTAssertEqual(recorder.transcript, "牛乳200ml使った")
        client.results[0]("古い結果", false, true); XCTAssertEqual(recorder.transcript, "牛乳200ml使った")
        XCTAssertNil(recorder.message)
    }
    func testPauseStartsNextSegmentWithoutLosingEarlierFoods() async {
        let client = ControlledVoiceClient(), recorder = VoiceRecorder(client: client)
        await recorder.start()
        client.results[0]("卵が6個", false, false)
        client.results[0]("卵が6個", true, false)
        XCTAssertTrue(recorder.recording)
        XCTAssertEqual(client.startCalls, 2)
        client.results[0]("古い結果", false, false)
        XCTAssertEqual(recorder.transcript, "卵が6個")
        client.results[1]("牛乳とキャベツ", false, false)
        XCTAssertEqual(recorder.transcript, "卵が6個\n牛乳とキャベツ")
        client.results[1]("牛乳とキャベツ", true, false)
        XCTAssertEqual(client.startCalls, 3)
        client.results[2]("しょうゆ少なめ", false, false)
        recorder.stop()
        client.results[2]("しょうゆ少なめ", true, false)
        XCTAssertFalse(recorder.busy)
        XCTAssertEqual(recorder.transcript, "卵が6個\n牛乳とキャベツ\nしょうゆ少なめ")
    }
    func testInterruptionAndLateCallbacksCannotAffectRetry() async {
        let client = ControlledVoiceClient(), recorder = VoiceRecorder(client: client)
        await recorder.start(); client.results[0]("卵", false, false); client.interruptions[0]()
        XCTAssertFalse(recorder.busy); XCTAssertEqual(recorder.transcript, "卵"); XCTAssertNotNil(recorder.message)
        await recorder.start(); client.results[1]("牛乳", false, false)
        client.results[0]("古い結果", true, false); client.interruptions[0]()
        XCTAssertTrue(recorder.recording); XCTAssertEqual(recorder.transcript, "牛乳"); XCTAssertNil(recorder.message)
        client.results[1](nil, false, true)
        XCTAssertFalse(recorder.busy); XCTAssertEqual(recorder.transcript, "牛乳"); XCTAssertNotNil(recorder.message)
    }
    func testCancelDuringMicrophonePermissionRejectsLateApproval() async throws {
        let client = ControlledVoiceClient(); client.holdMicrophone = true
        let recorder = VoiceRecorder(client: client)
        let pending = Task { await recorder.start() }
        try await eventually { client.microphoneContinuation != nil }
        recorder.cancel(); client.resolveMicrophone(true); await pending.value
        XCTAssertEqual(client.startCalls, 0); XCTAssertFalse(recorder.busy)
    }
    func testRepeatedStartDoesNotCreateOverlappingPermissionRequests() async throws {
        let client = ControlledVoiceClient(); client.holdSpeech = true
        let recorder = VoiceRecorder(client: client)
        let pending = Task { await recorder.start() }
        try await eventually { client.speechContinuation != nil }
        await recorder.start(); XCTAssertEqual(client.speechCalls, 1)
        client.resolveSpeech(.authorized); await pending.value
        XCTAssertEqual(client.startCalls, 1); recorder.cancel()
        recorder.activityChanged(.background); await recorder.start(); XCTAssertEqual(client.speechCalls, 1)
    }
    func testRecordingAndFinalizationTimeoutStopAndRejectLateResults() async throws {
        let client = ControlledVoiceClient()
        let recorder = VoiceRecorder(client: client, recordingLimit: .milliseconds(10), finishingLimit: .milliseconds(10))
        await recorder.start(); client.results[0]("卵6個", false, false)
        try await eventually { !recorder.busy }
        XCTAssertEqual(client.stopCalls, 1); XCTAssertFalse(recorder.recording); XCTAssertEqual(recorder.transcript, "卵6個")
        client.results[0]("遅い文章", true, false); XCTAssertEqual(recorder.transcript, "卵6個")
    }
}


@MainActor
final class VoiceSnapshotTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store); return store
    }
    private func ingredients(_ store: ModelContainer) throws -> [ReceiptIngredient] {
        try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).filter { $0.trackInventory && $0.status == .active }.map {
            ReceiptIngredient(id: $0.id, name: $0.canonicalName, aliases: $0.aliases, unit: $0.defaultUnit, allowedUnits: $0.allowedUnits, storage: $0.defaultStorage, category: $0.category)
        }
    }
    private func parse(_ text: String, _ store: ModelContainer) throws -> [VoiceRow] {
        let rows = try VoiceSnapshotParser.parse(text, ingredients: ingredients(store))
        return VoiceSnapshotParser.prepare(rows, inventory: try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()))
    }
    private func stocks(_ store: ModelContainer) throws -> [InventoryItem] { try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()) }
    private func stock(_ store: ModelContainer, key: String, amount: StockAmount, storage: StorageMethod = .refrigerated) throws -> UUID {
        let master = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == key })
        // Keep distinct lots for target selection and stale-review regression tests.
        return try InventoryService(container: store, mergeDuplicates: false).save(InventoryDraft(masterID: master.id, amount: amount, storage: storage))
    }
    private func confirm(_ rows: [VoiceRow]) -> [VoiceRow] { rows.map { var row = $0; row.draft.confirmed = true; return row } }
    func testKanjiRiceDictationAndHints() throws {
        let store = try store(), foods = try ingredients(store)
        let rice = try XCTUnwrap(foods.first { $0.name == "ごはん" })
        for text in ["ご飯が200グラム", "御飯が200グラム", "ごはん200グラム"] {
            let row = try XCTUnwrap(parse(text, store).first)
            XCTAssertEqual(row.draft.masterID, rice.id, text)
            XCTAssertEqual(Double(row.draft.quantity), 200)
            XCTAssertTrue(VoiceSnapshotParser.ready(row, inventory: []))
        }
        XCTAssertTrue(VoiceRecognitionHints.make(ingredients: foods, stockedIDs: [rice.id]).contains("ご飯"))
    }
    func testIngredientChoiceResolvesUnknownWithoutDoneAndKeepsLotSafety() throws {
        let store = try store(), foods = try ingredients(store)
        let egg = try XCTUnwrap(foods.first { $0.name == "卵" })
        var unknown = try XCTUnwrap(parse("未認識の野菜", store).first)
        unknown.storageSpoken = true
        XCTAssertFalse(VoiceSnapshotParser.ready(unknown, inventory: []))
        var row = VoiceSnapshotParser.selecting(egg, for: unknown, inventory: [])
        XCTAssertTrue(VoiceSnapshotParser.ready(row, inventory: []))
        XCTAssertTrue(row.draft.included); XCTAssertFalse(row.draft.exact); XCTAssertFalse(row.storageSpoken)
        _ = try stock(store, key: "egg", amount: .exact(6, .piece))
        _ = try stock(store, key: "egg", amount: .exact(4, .piece), storage: .frozen)
        row = VoiceSnapshotParser.selecting(egg, for: unknown, inventory: try stocks(store))
        XCTAssertFalse(VoiceSnapshotParser.ready(row, inventory: try stocks(store)))
        row.targetID = row.snapshotLots.keys.first; row.targetVersion = row.snapshotLots[row.targetID!]
        XCTAssertTrue(VoiceSnapshotParser.ready(row, inventory: try stocks(store)))
    }
    func testExplicitAmountEditResolvesIssueButInvalidQuantityCannotSave() throws {
        let store = try store()
        var row = try XCTUnwrap(parse("牛乳だいたい200ml", store).first)
        XCTAssertNotNil(row.issue)
        row.draft.exact = true; row.draft.quantity = "-1"
        VoiceSnapshotParser.resolveEditedAmount(&row)
        XCTAssertNotNil(row.issue); XCTAssertFalse(VoiceSnapshotParser.ready(row, inventory: []))
        row.draft.quantity = "200"; VoiceSnapshotParser.resolveEditedAmount(&row)
        XCTAssertTrue(VoiceSnapshotParser.ready(row, inventory: []))
        row.draft.quantity = "nan"; XCTAssertFalse(VoiceSnapshotParser.ready(row, inventory: []))
    }
    func testNaturalSixFoodsIncludeUnknownAmountsAndSeasoningState() throws {
        let store = try store()
        let rows = try parse("卵が6個、玉ねぎが半分、鶏むねが300グラム。牛乳とキャベツもある。しょうゆは少なめ", store)
        XCTAssertEqual(rows.count, 6)
        XCTAssertTrue(rows.allSatisfy { $0.action == .snapshot && $0.draft.included && $0.issue == nil && !$0.draft.confirmed })
        XCTAssertEqual(rows[0].draft.quantity, "6.0"); XCTAssertEqual(rows[1].draft.quantity, "0.5")
        XCTAssertEqual(rows[2].draft.quantity, "300.0"); XCTAssertEqual(rows[2].draft.unit, .gram)
        XCTAssertFalse(rows[3].draft.exact); XCTAssertEqual(rows[3].draft.rough, .available)
        XCTAssertEqual(rows[5].draft.rough, .low)
        XCTAssertEqual(try stocks(store).count, 0)
        try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID())
        XCTAssertEqual(try stocks(store).count, 6)
    }
    func testNoPunctuationKanaMetricAndLongestAliases() throws {
        let store = try store()
        let rows = try parse("たまご六個牛乳1リットル玉ねぎ半分にんじん2本", store)
        XCTAssertEqual(rows.count, 4); XCTAssertTrue(rows.allSatisfy { $0.issue == nil })
        XCTAssertEqual(rows[0].draft.quantity, "6.0"); XCTAssertEqual(rows[1].draft.quantity, "1.0")
        XCTAssertEqual(rows[1].draft.unit, .liter); XCTAssertEqual(rows[3].draft.unit, .piece)
        let names = try parse("トマトととうもろこしと豆腐", store)
        XCTAssertEqual(names.count, 3); XCTAssertTrue(names.allSatisfy { $0.draft.included && $0.issue == nil })
    }
    func testUnknownFoodAndUnsupportedAmountsStayVisible() throws {
        let store = try store()
        let rows = try parse("牛乳半分、スポンジ、卵6個", store)
        XCTAssertEqual(rows.count, 3); XCTAssertNotNil(rows[0].issue)
        XCTAssertFalse(rows[1].draft.included); XCTAssertNil(rows[1].draft.masterID); XCTAssertNotNil(rows[1].issue)
        XCTAssertNil(rows[2].issue)
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID()))
        XCTAssertEqual(try stocks(store).count, 0)
        let unknown = try parse("卵とスポンジ", store)
        XCTAssertEqual(unknown.count, 2); XCTAssertFalse(unknown[1].draft.included)
    }
    func testSameNamesDeduplicateAndConflictingAmountsRequireResolution() throws {
        let store = try store()
        let same = try parse("卵6個、卵6個", store)
        XCTAssertEqual(same.count, 1); XCTAssertTrue(same[0].repeated); XCTAssertNil(same[0].issue)
        let different = try parse("卵6個、卵3個", store)
        XCTAssertEqual(different.count, 1); XCTAssertNotNil(different[0].issue)
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: confirm(different), sessionID: UUID()))
        try VoiceImportService(container: store).save(rows: confirm(same), sessionID: UUID())
        XCTAssertEqual(try stocks(store).count, 1); XCTAssertEqual(try stocks(store).first?.quantity, 6)
    }
    func testOnlyKnownCandidatesMayCommitAndSessionCannotRepeat() throws {
        let store = try store(), service = VoiceImportService(container: store), session = UUID()
        let rows = try parse("卵、牛乳", store)
        XCTAssertThrowsError(try service.save(rows: rows, sessionID: session))
        try service.save(rows: confirm(rows), sessionID: session)
        XCTAssertThrowsError(try service.save(rows: confirm(rows), sessionID: session))
        XCTAssertEqual(try stocks(store).count, 2)
        let notes = try ModelContext(store).fetch(FetchDescriptor<InventoryEvent>()).map(\.note)
        XCTAssertTrue(notes.allSatisfy { !$0.contains("卵") && !$0.contains("牛乳") })
    }
    func testSnapshotReplacesAmountAndPreservesDatesStorage() throws {
        let store = try store()
        let id = try stock(store, key: "egg", amount: .exact(8, .piece), storage: .frozen)
        let original = try XCTUnwrap(stocks(store).first)
        let date = original.purchasedAt
        let rows = try parse("卵6個", store)
        XCTAssertEqual(rows[0].targetID, id)
        try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID())
        let result = try XCTUnwrap(stocks(store).first)
        XCTAssertEqual(result.quantity, 6); XCTAssertEqual(result.storage, .frozen); XCTAssertEqual(result.purchasedAt, date)
        XCTAssertEqual(try stocks(store).count, 1)
    }
    func testQuantityOmissionPreservesExactAmountUnitAndExpiry() throws {
        let store = try store()
        let master = try XCTUnwrap(ingredients(store).first { $0.name == "牛乳" })
        let date = Date(timeIntervalSince1970: 1600000000), expiry = Date.now.addingTimeInterval(86400 * 4)
        let context = ModelContext(store)
        let item = try InventoryItem(ingredient: .master(master.id), amount: .exact(0.7, .liter), storage: .frozen, purchasedAt: date, expiresAt: expiry, expiryKind: .useBy)
        context.insert(item); try context.save()
        let rows = try parse("牛乳がある", store)
        try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID())
        let result = try XCTUnwrap(stocks(store).first)
        XCTAssertEqual(result.quantity, 0.7); XCTAssertEqual(result.unit, .liter); XCTAssertEqual(result.purchasedAt, date)
        XCTAssertEqual(result.expiresAt, expiry); XCTAssertEqual(result.expiryKind, .useBy); XCTAssertEqual(result.storage, .frozen)
    }
    func testOnlySpokenStorageChangesExistingStock() throws {
        let store = try store()
        _ = try stock(store, key: "milk", amount: .exact(500, .milliliter))
        let rows = try parse("冷凍の牛乳", store)
        XCTAssertTrue(rows[0].storageSpoken)
        try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID())
        XCTAssertEqual(try stocks(store).first?.storage, .frozen); XCTAssertEqual(try stocks(store).first?.quantity, 500)
    }
    func testMultipleLotsNeedExplicitTargetAndOtherLotIsPreserved() throws {
        let store = try store()
        let a = try stock(store, key: "egg", amount: .exact(6, .piece))
        let b = try stock(store, key: "egg", amount: .exact(2, .piece))
        var rows = try parse("卵3個", store)
        XCTAssertNil(rows[0].targetID)
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID()))
        rows[0].targetID = a; rows[0].targetVersion = rows[0].snapshotLots[a]
        try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID())
        XCTAssertEqual(try stocks(store).first { $0.id == a }?.quantity, 3)
        XCTAssertEqual(try stocks(store).first { $0.id == b }?.quantity, 2)
    }
    func testStaleReviewAndNewLotsRejectWholeBatch() throws {
        let store = try store()
        _ = try stock(store, key: "egg", amount: .exact(6, .piece))
        let rows = try parse("牛乳、卵3個", store)
        _ = try stock(store, key: "egg", amount: .exact(2, .piece))
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID()))
        XCTAssertEqual(try stocks(store).count, 2)
        let missing = try parse("玉ねぎ", store)
        _ = try stock(store, key: "onion", amount: .exact(2, .piece))
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: confirm(missing), sessionID: UUID()))
        XCTAssertEqual(try stocks(store).count, 3)
    }
    func testSetNoneZeroAndSeasoningsUseThreeStates() throws {
        let store = try store()
        _ = try stock(store, key: "egg", amount: .exact(6, .piece))
        try VoiceImportService(container: store).save(rows: confirm(parse("卵はない", store)), sessionID: UUID())
        XCTAssertEqual(try stocks(store).first?.roughState, .unavailable)
        let rows = try parse("しょうゆ200ml、みそ少なめ、塩はない", store)
        XCTAssertEqual(rows.count, 3); XCTAssertTrue(rows.allSatisfy { !$0.draft.exact && $0.issue == nil })
        XCTAssertEqual(rows.map { $0.draft.rough }, [.available, .low, .unavailable])
    }
    func testBatchUndoRestoresOldLotAndRemovesNewLots() throws {
        let store = try store()
        let attached = InventoryUndoCenter(container: store)
        let id = try stock(store, key: "egg", amount: .exact(6, .piece))
        let rows = try parse("卵3個、牛乳", store)
        try VoiceImportService(container: store).save(rows: confirm(rows), sessionID: UUID())
        XCTAssertNotNil(attached.offer)
        try attached.undo(id: XCTUnwrap(attached.offer).id)
        XCTAssertEqual(try stocks(store).first { $0.id == id }?.quantity, 6)
        XCTAssertEqual(try stocks(store).filter { !$0.isDeleted }.count, 1)
    }
    func testHintsAreBoundedUniqueAndIncludeCurrentStock() throws {
        let store = try store(), foods = try ingredients(store)
        let food = try XCTUnwrap(foods.first { $0.name == "はちみつ" })
        let hints = VoiceRecognitionHints.make(ingredients: foods, stockedIDs: [food.id])
        XCTAssertLessThanOrEqual(hints.count, 100); XCTAssertEqual(hints.count, Set(hints).count)
        XCTAssertEqual(hints.first, food.name); XCTAssertTrue(hints.contains("卵")); XCTAssertTrue(hints.contains("牛乳"))
    }
    func testFillersNegationColloquialCountsAndLimits() throws {
        let store = try store()
        let rows = try parse("えっと、冷蔵庫にはトマトひとつ、あと玉ねぎ二分の一個、小ねぎ", store)
        XCTAssertEqual(rows.count, 3); XCTAssertTrue(rows.allSatisfy { $0.issue == nil })
        XCTAssertEqual(rows[0].draft.quantity, "1.0"); XCTAssertEqual(rows[1].draft.quantity, "0.5")
        XCTAssertThrowsError(try VoiceSnapshotParser.parse(String(repeating: "卵", count: 4001), ingredients: ingredients(store)))
        XCTAssertThrowsError(try VoiceSnapshotParser.parse(Array(repeating: "未知の食品", count: 21).joined(separator: "、"), ingredients: ingredients(store)))
        XCTAssertNotNil(try parse("牛乳だいたい200ml", store).first?.issue)
        XCTAssertNotNil(try parse("卵じゃない", store).first?.issue)
    }
    func testPurchaseAndConsumptionRetainExplicitConfirmationFlow() throws {
        let store = try store()
        let rows = try parse("卵6個買った、牛乳200ml使った", store)
        XCTAssertEqual(rows.map(\.action), [.add, .consume]); XCTAssertTrue(rows.allSatisfy { !$0.draft.confirmed })
    }
    func testRecognitionClientReceivesAtMost100HintsAndLateTextCannotOverwriteRetry() async {
        let client = ControlledVoiceClient()
        let recording = VoiceRecorder(client: client)
        await recording.start(hints: (0..<150).map { "食材\($0)" })
        XCTAssertEqual(client.hints.count, 100)
        client.results[0]("卵6個", false, false); recording.stop(); client.results[0]("卵六個", true, false)
        let first = recording.transcript
        await recording.start(hints: ["牛乳"])
        client.results[1]("牛乳", false, false)
        client.results[0]("古い結果", true, false)
        XCTAssertEqual(first, "卵六個"); XCTAssertEqual(recording.transcript, "牛乳"); XCTAssertEqual(client.hints, ["牛乳"])
        recording.cancel(erase: true); XCTAssertEqual(recording.transcript, "")
    }
    func testNegativeSharedStateAndSpokenCorrectionRequireSafeResolution() throws {
        let store = try store()
        let none = try parse("卵と牛乳はありません", store)
        XCTAssertEqual(none.count, 2); XCTAssertTrue(none.allSatisfy { $0.draft.rough == .unavailable && $0.issue == nil })
        let mixed = try parse("卵はあると牛乳はない", store)
        XCTAssertEqual(mixed.map { $0.draft.rough }, [.available, .unavailable])
        let correction = try parse("卵6個、じゃなくて3個", store)
        XCTAssertNotNil(correction[0].issue)
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: confirm(correction), sessionID: UUID()))
        XCTAssertNotNil(try parse("卵6個ない", store)[0].issue)
        XCTAssertNotNil(try parse("玉ねぎ1個半", store)[0].issue)
        XCTAssertNotNil(try parse("卵2〜3個", store)[0].issue)
        XCTAssertNotNil(try parse("牛乳があるか分からない", store)[0].issue)
        XCTAssertEqual(try parse("卵2つ", store)[0].draft.quantity, "2.0")
    }
    func testChangingMatchedIngredientClearsOldTargetAndDuplicateIDsCannotSave() throws {
        let store = try store()
        _ = try stock(store, key: "egg", amount: .exact(6, .piece))
        var row = try XCTUnwrap(parse("卵", store).first)
        XCTAssertNotNil(row.targetID)
        let milk = try XCTUnwrap(ingredients(store).first { $0.name == "牛乳" })
        row.draft.masterID = milk.id; row.draft.name = milk.name
        row = VoiceSnapshotParser.prepare([row], inventory: try stocks(store))[0]
        XCTAssertNil(row.targetID); XCTAssertTrue(row.snapshotLots.isEmpty)
        XCTAssertTrue(VoiceSnapshotParser.ready(row, inventory: try stocks(store)))
        var second = try XCTUnwrap(parse("牛乳", store).first)
        second.draft.confirmed = true; row.draft.confirmed = true
        XCTAssertThrowsError(try VoiceImportService(container: store).save(rows: [row, second], sessionID: UUID()))
        XCTAssertEqual(try stocks(store).count, 1)
    }

}
