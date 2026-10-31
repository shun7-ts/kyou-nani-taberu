import XCTest

final class PrivacyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<9 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func acceptPolicy(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["はじめに"].waitForExistence(timeout: 10))
        let start = app.buttons["privacy-start"]; XCTAssertFalse(start.isEnabled)
        let review = app.switches["privacy-policy-reviewed"]
        scrollTo(review, app: app); review.switches.firstMatch.tap()
        XCTAssertTrue(start.isEnabled); start.tap()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 10)); app.buttons["bulk-skip"].tap()
    }
    @MainActor private func openDelete(_ app: XCUIApplication) {
        app.openMyPage()
        let link = app.buttons["settings-delete-data"]; scrollTo(link, app: app); link.tap()
        XCTAssertTrue(app.navigationBars["端末内データを全削除"].waitForExistence(timeout: 5))
        let request = app.buttons["delete-data-request"]; scrollTo(request, app: app); XCTAssertFalse(request.isEnabled)
        app.switches["delete-data-reviewed"].switches.firstMatch.tap()
        XCTAssertTrue(request.isEnabled); request.tap()
        XCTAssertTrue(app.alerts["すべての利用データを削除しますか？"].waitForExistence(timeout: 5))
    }
    @MainActor private func assertSeparateRecognitionConsents(_ app: XCUIApplication) {
        app.tabBars.buttons["マイ冷蔵庫"].tap(); app.buttons["inventory-voice"].tap()
        XCTAssertTrue(app.navigationBars["音声でまとめて登録"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["voice-record"].exists)
        scrollTo(app.buttons["voice-consent"], app: app)
        app.buttons["閉じる"].tap()
        app.buttons["inventory-receipt"].tap()
        XCTAssertTrue(app.navigationBars["レシートから登録"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["receipt-photo-picker"].exists)
        scrollTo(app.buttons["receipt-consent"], app: app)
    }
    @MainActor func testFirstLaunchPolicyBeforeSetupAndSeparateRecognitionOptIn() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-privacy-intro"]; app.launch()
        XCTAssertTrue(app.navigationBars["はじめに"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["privacy-start"].isEnabled)
        XCTAssertFalse(app.buttons["bulk-skip"].exists)
        let link = app.buttons["privacy-policy-link"]; scrollTo(link, app: app); link.tap()
        XCTAssertTrue(app.navigationBars["プライバシーポリシー"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["保存するデータと目的"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "初回プライバシー案内"; screenshot.lifetime = .keepAlways; add(screenshot)
        acceptPolicy(app)
        app.openMyPage(); app.buttons["settings-privacy-policy"].tap()
        let accepted = app.staticTexts["privacy-policy-accepted"]; scrollTo(accepted, app: app)
        assertSeparateRecognitionConsents(app)
    }
    @MainActor func testDeleteCancelPreservesDataAndConfirmedResetRestartsOnboarding() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-reset-fixture"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 15))
        app.openMyPage(); app.buttons["期限通知"].tap()
        let count = app.staticTexts["expiry-notification-count"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1件"), evaluatedWith: count); waitForExpectations(timeout: 5)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openDelete(app); app.alerts.buttons["キャンセル"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let egg = app.buttons["inventory-row-egg"]; XCTAssertTrue(egg.waitForExistence(timeout: 5)); XCTAssertTrue(egg.label.contains("6個"))
        openDelete(app)
        let deletion = XCTAttachment(screenshot: app.screenshot()); deletion.name = "全削除の最終確認"; deletion.lifetime = .keepAlways; add(deletion)
        app.alerts.buttons["すべて削除する"].tap()
        acceptPolicy(app)
        app.tabBars.buttons["マイ冷蔵庫"].tap(); XCTAssertFalse(app.buttons["inventory-row-egg"].exists); XCTAssertFalse(app.buttons["inventory-row-custom"].exists)
        app.tabBars.buttons["買い物"].tap(); XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["ホーム"].tap(); XCTAssertFalse(app.buttons["meal-cook"].exists)
        app.openMyPage(); app.buttons["取り除いた食材を戻す"].tap()
        XCTAssertTrue(app.staticTexts["取り除いた食材はありません。"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["期限通知"].tap()
        XCTAssertTrue(app.staticTexts["expiry-notification-authorized"].waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.contains("0件"))
        assertSeparateRecognitionConsents(app)
    }
}
