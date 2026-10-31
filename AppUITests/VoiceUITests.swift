import XCTest

final class VoiceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func open(_ app: XCUIApplication) {
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-voice"].tap()
        XCTAssertTrue(app.navigationBars["音声でまとめて登録"].waitForExistence(timeout: 5))
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        let attempts = app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") ? 40 : 8
        for _ in 0..<attempts {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let footer = app.buttons["voice-save"]
            var bottom = footer.exists ? footer.frame.minY - 12 : app.frame.maxY - 44
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 12) }
            guard bottom > top + 44 else { XCTFail("フォームを操作する領域が確保されていません"); return }
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            // Drag within the visible Form, outside the fixed footer and keyboard.
            let goingDown = (element.exists && element.frame.height > 0 && element.frame.midY <= top) || (!element.exists && towardTop)
            let high = top + (bottom - top) * 0.2, low = top + (bottom - top) * 0.8
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: goingDown ? high : low))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: goingDown ? low : high))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("入力・確認の項目をフォーム内へスクロールできませんでした：\(element.identifier)")
    }
    @MainActor private func start(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-voice-fixture"]; if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }; app.launch()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15)); app.buttons["bulk-skip"].tap()
        return app
    }
    @MainActor func testManualTextAddAndConsumeRequireConfirmationAndTarget() throws { try addAndConsumeFlow(largeText: false) }
    @MainActor func testLargestTextAddAndConsumeRequireConfirmationAndTarget() throws { try addAndConsumeFlow(largeText: true) }
    @MainActor private func addAndConsumeFlow(largeText: Bool) throws {
        let app = start(largeText: largeText); open(app)
        XCTAssertFalse(app.buttons["voice-record"].exists)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        let fixture = app.buttons["voice-fixture"]; scrollTo(fixture, app: app); fixture.tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let save = app.buttons["voice-save"]; XCTAssertFalse(save.isEnabled)
        let confirm = app.switches["voice-confirm"].firstMatch; scrollTo(confirm, app: app); confirm.switches.firstMatch.tap()
        XCTAssertTrue(save.isEnabled); save.tap()
        let egg = app.buttons["inventory-row-egg"]
        showStock(egg, app: app)
        XCTAssertTrue(egg.label.contains("6個"))
        open(app); scrollTo(manual, app: app); manual.tap()
        let useFixture = app.buttons["voice-use-fixture"]; scrollTo(useFixture, app: app); useFixture.tap()
        scrollTo(parse, app: app); parse.tap()
        XCTAssertFalse(save.isEnabled)
        let target = app.buttons["voice-target"]; scrollTo(target, app: app); target.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "6個")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        scrollTo(confirm, app: app); confirm.switches.firstMatch.tap()
        XCTAssertTrue(save.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "音声候補・使用後の量を確認"; screenshot.lifetime = .keepAlways; add(screenshot)
        save.tap(); showStock(egg, app: app); XCTAssertTrue(egg.label.contains("4個"))
        let stock = XCTAttachment(screenshot: app.screenshot()); stock.name = "音声候補反映後の冷蔵庫"; stock.lifetime = .keepAlways; add(stock)
    }
    @MainActor private func showStock(_ row: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["マイ冷蔵庫"].waitForExistence(timeout: 5))
        for _ in 0..<30 {
            let top = app.navigationBars["マイ冷蔵庫"].frame.maxY
            let bottom = min(app.collectionViews.firstMatch.frame.maxY, app.tabBars.firstMatch.frame.minY)
            let height = bottom - top
            guard height > 44 else { XCTFail("在庫一覧の操作領域がありません"); return }
            if row.exists && row.isHittable && row.frame.midY > top && row.frame.midY < bottom { return }
            let down = row.exists && row.frame.midY <= top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + height * (down ? 0.2 : 0.8)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: start + height * (down ? 0.6 : -0.6))), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("保存した在庫へ移動できません：\(row.identifier)")
    }
    @MainActor func testTypedTextSurvivesKeyboardDismissalAndCanBeDiscarded() throws { try typedTextFlow(largeText: false) }
    @MainActor func testLargestTextTypingConfirmationAndDiscard() throws { try typedTextFlow(largeText: true) }
    @MainActor private func typedTextFlow(largeText: Bool) throws {
        let app = start(largeText: largeText); open(app)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        let editor = app.textViews["voice-text"]
        scrollTo(editor, app: app)
        XCTAssertTrue(editor.exists)
        XCTAssertFalse(app.buttons["voice-keyboard-done"].exists)
        editor.tap(); editor.typeText("卵を6個買った")
        let done = app.buttons["voice-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        XCTAssertTrue(editor.isHittable)
        XCTAssertLessThanOrEqual(editor.frame.maxY, done.frame.minY + 1)
        XCTAssertGreaterThan(editor.frame.midY, app.navigationBars.firstMatch.frame.maxY)
        let keyboard = XCTAttachment(screenshot: app.screenshot()); keyboard.name = largeText ? "最大文字・音声入力完了" : "音声手入力・キーボード完了操作"; keyboard.lifetime = .keepAlways; add(keyboard)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(done.exists)
        XCTAssertEqual(editor.value as? String, "卵を6個買った")
        XCTAssertFalse(app.buttons["voice-save"].isEnabled)
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let quantity = app.textFields["voice-quantity"]; scrollTo(quantity, app: app)
        if largeText { XCTAssertGreaterThan(quantity.frame.height, 40) }
        quantity.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        done.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 6)
        XCTAssertFalse(app.buttons["voice-save"].isEnabled)
        app.buttons["閉じる"].tap(); app.buttons["破棄して閉じる"].tap()
        XCTAssertTrue(app.buttons["inventory-add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventory-row-egg"].exists)
    }
    @MainActor func testConsentDiscardAndWithdrawDoNotRecordOrSave() throws {
        let app = start(); open(app)
        let consent = app.buttons["voice-consent"]; scrollTo(consent, app: app); consent.tap()
        XCTAssertTrue(app.buttons["voice-record"].waitForExistence(timeout: 5))
        let fixture = app.buttons["voice-fixture"]; scrollTo(fixture, app: app); fixture.tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        XCTAssertFalse(app.buttons["voice-save"].isEnabled)
        app.buttons["閉じる"].tap(); app.buttons["破棄して閉じる"].tap()
        XCTAssertTrue(app.buttons["inventory-add"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["inventory-row-egg"].exists)
        app.openMyPage(); app.buttons["音声の扱い"].tap()
        let withdraw = app.buttons["音声入力への同意を取り消す"]; scrollTo(withdraw, app: app); withdraw.tap()
        open(app); scrollTo(consent, app: app); XCTAssertFalse(app.buttons["voice-record"].exists)
    }
    @MainActor func testBulkStocktakingAppendAndRepeatPreservesExactQuantity() throws {
        let app = start(); open(app)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        let fixture = app.buttons["voice-stock-fixture"]; scrollTo(fixture, app: app); fixture.tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let save = app.buttons["voice-save"]; XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.label.contains("6件")); XCTAssertFalse(app.switches["voice-confirm"].exists)
        let eggEdit = app.buttons["voice-edit-egg"]; scrollTo(eggEdit, app: app); eggEdit.tap()
        let quantity = app.textFields["voice-snapshot-quantity"]; scrollTo(quantity, app: app); quantity.tap()
        quantity.tap(withNumberOfTaps: 3, numberOfTouches: 1); quantity.typeText(XCUIKeyboardKey.delete.rawValue + "4")
        app.buttons["voice-keyboard-done"].tap()
        XCTAssertFalse(app.buttons["voice-snapshot-done"].exists)
        let append = app.buttons["voice-append-fixture"]; scrollTo(append, app: app, towardTop: true); append.tap()
        XCTAssertFalse(save.isEnabled); scrollTo(parse, app: app, towardTop: true); parse.tap()
        XCTAssertTrue(save.isEnabled); XCTAssertTrue(save.label.contains("8件"))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "音声・一括登録8件"; image.lifetime = .keepAlways; add(image)
        save.tap()
        let egg = app.buttons["inventory-row-egg"]; showStock(egg, app: app); XCTAssertTrue(egg.label.contains("4個"))
        open(app); scrollTo(manual, app: app); manual.tap()
        let editor = app.textViews["voice-text"]; scrollTo(editor, app: app); editor.tap(); editor.typeText("卵と牛乳")
        app.buttons["voice-keyboard-done"].tap(); scrollTo(parse, app: app); parse.tap()
        XCTAssertTrue(save.isEnabled); save.tap(); showStock(egg, app: app); XCTAssertTrue(egg.label.contains("4個"))
    }
    @MainActor func testBulkUncertainAmountCanBeExcludedAndUnknownFoodRemainsVisible() throws {
        let app = start(); open(app)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        let fixture = app.buttons["voice-uncertain-fixture"]; scrollTo(fixture, app: app); fixture.tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let save = app.buttons["voice-save"]; XCTAssertFalse(save.isEnabled)
        let milk = app.buttons["voice-include-milk"]; scrollTo(milk, app: app); milk.tap()
        XCTAssertTrue(save.isEnabled); XCTAssertTrue(save.label.contains("1件"))
        let egg = app.buttons["voice-edit-egg"]; scrollTo(egg, app: app)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "音声・曖昧量と未対応語"; image.lifetime = .keepAlways; add(image)
        save.tap(); showStock(app.buttons["inventory-row-egg"], app: app)
        XCTAssertTrue(app.buttons["inventory-row-egg"].label.contains("6個")); XCTAssertFalse(app.buttons["inventory-row-milk"].exists)
    }
    @MainActor func testVoiceReviewCanRemoveOneFoodWithoutStartingOver() throws {
        let app = start(); open(app)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        XCTAssertFalse(app.buttons["voice-mode"].exists)
        let fixture = app.buttons["voice-stock-fixture"]; scrollTo(fixture, app: app); fixture.tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let save = app.buttons["voice-save"]; XCTAssertTrue(save.label.contains("6件"))
        XCTAssertFalse(app.buttons["voice-edit-text"].exists)
        let remove = app.buttons["voice-delete-egg"]; scrollTo(remove, app: app); remove.tap()
        XCTAssertFalse(app.buttons["voice-edit-egg"].exists)
        XCTAssertTrue(save.label.contains("5件"))
        XCTAssertTrue(save.isEnabled)
    }
    @MainActor func testLargestTextBulkStocktakingAndSeasoningEditor() throws {
        let app = start(largeText: true); open(app)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        let fixture = app.buttons["voice-stock-fixture"]; scrollTo(fixture, app: app); fixture.tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let soy = app.buttons["voice-edit-soy_sauce"]; scrollTo(soy, app: app); soy.tap()
        let state = app.buttons["voice-snapshot-state"]; scrollTo(state, app: app)
        XCTAssertFalse(app.switches["voice-exact"].exists)
        XCTAssertFalse(app.buttons["voice-snapshot-done"].exists)
        let save = app.buttons["voice-save"]; XCTAssertTrue(save.isEnabled)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "最大文字・音声まとめ登録"; image.lifetime = .keepAlways; add(image)
        save.tap(); showStock(app.buttons["inventory-row-egg"], app: app)
        XCTAssertTrue(app.buttons["inventory-row-egg"].label.contains("6個"))
    }

    @MainActor func testUnknownFoodCanBeSelectedFromSearchAndBulkRegistered() throws {
        let app = start(); open(app)
        let manual = app.buttons["voice-manual-without-consent"]; scrollTo(manual, app: app); manual.tap()
        let editor = app.textViews["voice-text"]; scrollTo(editor, app: app); editor.tap(); editor.typeText("未認識の野菜")
        app.buttons["voice-keyboard-done"].tap()
        let parse = app.buttons["voice-parse"]; scrollTo(parse, app: app); parse.tap()
        let save = app.buttons["voice-save"]; XCTAssertFalse(save.isEnabled)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "voice-edit-", "voice-edit-text")).firstMatch
        scrollTo(row, app: app); row.tap()
        let select = app.buttons["voice-select-food"]; scrollTo(select, app: app); select.tap()
        let selectionImage = XCTAttachment(screenshot: app.screenshot()); selectionImage.name = "音声・未認識食材の検索選択"; selectionImage.lifetime = .keepAlways; add(selectionImage)
        XCTAssertTrue(app.navigationBars["食材を選ぶ"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("ご飯")
        let onion = app.buttons["mapping-food-cooked_rice"]; XCTAssertTrue(onion.waitForExistence(timeout: 5)); onion.tap()
        XCTAssertFalse(app.buttons["voice-snapshot-done"].exists)
        XCTAssertTrue(save.isEnabled); save.tap(); showStock(app.buttons["inventory-row-cooked_rice"], app: app)
        XCTAssertTrue(app.buttons["inventory-row-cooked_rice"].exists)
    }

}
