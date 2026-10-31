import XCTest

final class ReceiptCameraUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        let attempts = app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") ? 40 : 10
        for _ in 0..<attempts {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let footer = app.buttons["receipt-save"]
            var bottom = footer.exists ? footer.frame.minY - 12 : app.frame.maxY - 44
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 12) }
            guard bottom > top + 44 else { XCTFail("フォームを操作する領域が確保されていません"); return }
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            // Drag within the visible Form, outside the fixed footer and keyboard.
            let goingDown = element.exists ? (element.frame.height > 0 && element.frame.midY <= top) : towardTop
            let high = top + (bottom - top) * 0.2, low = top + (bottom - top) * 0.8
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: goingDown ? high : low))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: goingDown ? low : high))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("入力・確認の項目をフォーム内へスクロールできませんでした：\(element.identifier)")
    }
    @MainActor private func openReceipt(_ app: XCUIApplication) {
        app.tabBars.buttons["マイ冷蔵庫"].tap(); app.buttons["inventory-receipt"].tap()
        XCTAssertTrue(app.navigationBars["レシートから登録"].waitForExistence(timeout: 5))
    }
    @MainActor private func acceptReceipt(_ app: XCUIApplication) {
        let consent = app.buttons["receipt-consent"]; scrollTo(consent, app: app); consent.tap()
        XCTAssertTrue(app.buttons["receipt-camera"].waitForExistence(timeout: 5))
    }
    @MainActor private func start(_ flag: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", flag]; if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--ui-dark"] }; app.launch()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15)); app.buttons["bulk-skip"].tap()
        openReceipt(app); return app
    }
    @MainActor func testCameraCancelAndCapturedImageRequireReviewBeforeSaving() throws {
        let app = start("--ui-camera-fixture")
        XCTAssertFalse(app.buttons["receipt-camera"].exists); XCTAssertFalse(app.buttons["receipt-photo-picker"].exists)
        acceptReceipt(app)
        app.buttons["receipt-camera"].tap()
        let capture = app.buttons["camera-fixture-capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5)); app.buttons["camera-fixture-cancel"].tap()
        XCTAssertTrue(app.buttons["receipt-camera"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["receipt-save"].isEnabled); XCTAssertFalse(app.switches["receipt-confirm"].exists)
        app.buttons["receipt-camera"].tap(); XCTAssertTrue(capture.waitForExistence(timeout: 5)); capture.tap()
        XCTAssertTrue(app.navigationBars["読み取り結果"].waitForExistence(timeout: 15))
        let save = app.buttons["receipt-save"]; XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.staticTexts["スーパー牛乳 町田店"].exists)
        XCTAssertFalse(app.staticTexts["卵 6個 98円"].exists)
        XCTAssertEqual(save.label, "1品を冷蔵庫へ登録")
        XCTAssertFalse(app.switches["receipt-confirm"].exists)
        XCTAssertFalse(app.buttons["receipt-photo-picker"].exists)
        XCTAssertTrue(app.datePickers["receipt-common-date"].exists)
        XCTAssertFalse(app.staticTexts["種類：乳・卵"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "撮影画像のOCR確認"; shot.lifetime = .keepAlways; add(shot)
        save.tap()
        let milk = app.buttons["inventory-row-milk"]; XCTAssertTrue(milk.waitForExistence(timeout: 5))
        XCTAssertTrue(milk.label.replacingOccurrences(of: ",", with: "").contains("1000ml"), milk.label)
    }
    @MainActor func testCompactReceiptSearchMissingDakutenAndOptionalExpiry() throws { try compactReview(large: false) }
    @MainActor func testLargestCompactReceiptSearchMissingDakutenAndOptionalExpiry() throws { try compactReview(large: true) }
    @MainActor private func compactReview(large: Bool) throws {
        let app = start("--ui-receipt-fixture", largeText: large); acceptReceipt(app)
        app.buttons["receipt-fixture"].tap()
        XCTAssertTrue(app.navigationBars["読み取り結果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["receipt-common-date"].exists)
        XCTAssertFalse(app.staticTexts["レジ袋（大） ¥5"].exists)
        XCTAssertFalse(app.staticTexts["有料袋 ¥3"].exists)
        XCTAssertFalse(app.staticTexts["支払い レモン"].exists)
        XCTAssertFalse(app.buttons["receipt-food-egg"].exists)
        XCTAssertFalse(app.buttons["receipt-camera"].exists)
        XCTAssertFalse(app.switches["receipt-confirm"].exists)
        XCTAssertEqual(app.buttons["receipt-save"].label, "1品を冷蔵庫へ登録")
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = large ? "最大文字・コンパクトな読み取り結果" : "コンパクトな読み取り結果"; top.lifetime = .keepAlways; add(top)
        let hint = app.buttons["receipt-suggestion-broccoli"]
        scrollTo(hint, app: app); XCTAssertTrue(app.staticTexts["receipt-unresolved"].firstMatch.exists)
        let unknown = XCTAttachment(screenshot: app.screenshot()); unknown.name = large ? "最大文字・濁点抜けの候補" : "濁点抜けの候補"; unknown.lifetime = .keepAlways; add(unknown)
        hint.tap()
        let food = app.buttons["receipt-food-broccoli"]; scrollTo(food, app: app); food.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription); search.tap(); search.typeText("ふろっこりー")
        let match = app.buttons["receipt-search-food-broccoli"]
        XCTAssertTrue(match.waitForExistence(timeout: 5)); match.tap()
        XCTAssertTrue(app.navigationBars["読み取り結果"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["receipt-save"].label, "2品を冷蔵庫へ登録")
        let quantity = app.textFields.matching(NSPredicate(format: "identifier == %@ AND label == %@", "receipt-quantity", "ブロッコリーの数量")).firstMatch; scrollTo(quantity, app: app)
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 200)
        let details = app.buttons["receipt-details-broccoli"]; scrollTo(details, app: app); details.tap()
        let expiry = app.buttons["receipt-expiry"].firstMatch; scrollTo(expiry, app: app)
        XCTAssertFalse(app.switches["期限を入力する"].exists)
        XCTAssertEqual(expiry.label, "期限")
        expiry.tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["読み取り結果"].tap()
        let clear = app.buttons["receipt-expiry-clear"].firstMatch; scrollTo(clear, app: app); clear.tap()
        XCTAssertFalse(clear.exists)
        let storage = app.buttons["receipt-storage"].firstMatch; scrollTo(storage, app: app); storage.tap(); app.buttons["冷凍"].tap()
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = large ? "最大文字・保存と期限の詳細" : "保存と期限の詳細"; after.lifetime = .keepAlways; add(after)
        let commonStorage = app.buttons["receipt-common-storage"]
        scrollTo(commonStorage, app: app, towardTop: true); commonStorage.tap(); app.buttons["常温"].tap()
        app.buttons["receipt-save"].tap()
        let broccoli = app.buttons["inventory-row-broccoli"]
        for _ in 0..<8 where !broccoli.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(broccoli.waitForExistence(timeout: 5)); XCTAssertTrue(broccoli.label.contains("200g"), broccoli.label)
        XCTAssertTrue(broccoli.label.contains("冷凍"), broccoli.label)
        XCTAssertFalse(app.buttons["inventory-row-custom"].exists)
    }
    @MainActor func testDeniedCameraPreservesManualDraftAndPhotoFallback() throws { try deniedCameraFlow(largeText: false) }
    @MainActor func testLargestTextManualReceiptConfirmationAndSave() throws { try deniedCameraFlow(largeText: true) }
    @MainActor private func deniedCameraFlow(largeText: Bool) throws {
        let app = start("--ui-camera-denied", largeText: largeText); acceptReceipt(app)
        let addRow = app.buttons["receipt-add-row"]; scrollTo(addRow, app: app); addRow.tap()
        XCTAssertFalse(app.buttons["receipt-save"].isEnabled)
        let name = app.textFields["receipt-custom-name"]; scrollTo(name, app: app); name.tap(); name.typeText("Camera fallback sauce")
        let done = app.buttons["receipt-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        XCTAssertTrue(name.isHittable)
        XCTAssertLessThanOrEqual(name.frame.maxY, done.frame.minY + 1)
        XCTAssertGreaterThan(name.frame.midY, app.navigationBars.firstMatch.frame.maxY)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5)); XCTAssertFalse(done.exists)
        XCTAssertEqual(name.value as? String, "Camera fallback sauce")
        let exact = app.switches["receipt-exact"].firstMatch; scrollTo(exact, app: app); exact.switches.firstMatch.tap()
        XCTAssertFalse(app.buttons["receipt-save"].isEnabled)
        let quantity = app.textFields["receipt-quantity"]; scrollTo(quantity, app: app)
        if largeText { XCTAssertGreaterThan(quantity.frame.height, 40) }
        quantity.tap(); quantity.typeText("2")
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        XCTAssertTrue(quantity.isHittable)
        XCTAssertLessThanOrEqual(quantity.frame.maxY, done.frame.minY + 1)
        XCTAssertGreaterThan(quantity.frame.midY, app.navigationBars.firstMatch.frame.maxY)
        let typing = XCTAttachment(screenshot: app.screenshot()); typing.name = largeText ? "最大文字・数量入力中" : "数量入力中"; typing.lifetime = .keepAlways; add(typing)
        done.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(quantity.value as? String, "2")
        let keyboard = XCTAttachment(screenshot: app.screenshot()); keyboard.name = largeText ? "最大文字・レシートの名前と数量" : "レシート手入力・名前と数量の保持"; keyboard.lifetime = .keepAlways; add(keyboard)
        if !largeText {
            app.buttons["receipt-add-menu"].tap()
            app.buttons["receipt-camera"].tap()
            let message = app.staticTexts["receipt-camera-message"]
            XCTAssertTrue(message.waitForExistence(timeout: 5)); XCTAssertTrue(message.label.contains("許可されていません"))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "receipt-camera-settings").firstMatch.exists)
            app.buttons["receipt-add-menu"].tap()
            XCTAssertTrue(app.buttons["receipt-photo-picker"].isEnabled)
            app.tap()
        }
        XCTAssertFalse(app.switches["receipt-confirm"].exists)
        XCTAssertTrue(app.buttons["receipt-save"].isEnabled); app.buttons["receipt-save"].tap()
        let item = app.buttons["inventory-row-custom"]
        for _ in 0..<8 where !item.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.label.contains("Camera fallback sauce")); XCTAssertTrue(item.label.contains("2個"))
    }
    @MainActor func testVersionOneConsentsRequireUpdatedExplanationWithoutLosingInventory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset-fixture", "--ui-old-consent-fixture", "--ui-camera-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["はじめに"].waitForExistence(timeout: 15))
        let reviewed = app.switches["privacy-policy-reviewed"]; scrollTo(reviewed, app: app); reviewed.switches.firstMatch.tap()
        app.buttons["privacy-start"].tap()
        XCTAssertTrue(app.tabBars.buttons["マイ冷蔵庫"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["bulk-skip"].exists)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let egg = app.buttons["inventory-row-egg"]; XCTAssertTrue(egg.waitForExistence(timeout: 5)); XCTAssertTrue(egg.label.contains("6個"))
        app.buttons["inventory-receipt"].tap()
        XCTAssertFalse(app.buttons["receipt-camera"].exists); XCTAssertFalse(app.buttons["receipt-photo-picker"].exists)
        acceptReceipt(app)
        XCTAssertTrue(app.buttons["receipt-photo-picker"].exists)
        app.buttons["閉じる"].tap(); XCTAssertTrue(egg.waitForExistence(timeout: 5)); XCTAssertTrue(egg.label.contains("6個"))
    }
}
