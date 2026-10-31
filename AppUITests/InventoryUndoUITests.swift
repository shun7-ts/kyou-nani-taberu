import XCTest

final class InventoryUndoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testSaveDoesNotShowUndoAndKeepsNavigationUsable() throws { try saveWithoutBanner(large: false) }
    @MainActor func testLargestSaveDoesNotShowUndoAndKeepsNavigationUsable() throws { try saveWithoutBanner(large: true) }
    @MainActor private func saveWithoutBanner(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["マイ冷蔵庫"].waitForExistence(timeout: 15))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let milk = app.buttons["inventory-row-milk"]
        reveal(milk, app: app); milk.tap()
        XCTAssertTrue(app.buttons["inventory-save"].waitForExistence(timeout: 5))
        app.buttons["inventory-save"].tap()
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventory-undo"].exists)
        XCTAssertFalse(app.buttons["inventory-undo-dismiss"].exists)
        XCTAssertFalse(app.staticTexts["inventory-undo-explanation"].exists)
        app.tabBars.buttons["買い物"].tap()
        XCTAssertFalse(app.buttons["inventory-undo"].exists)
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["recipe-ingredient-picker"].waitForExistence(timeout: 5))
        capture(app, large ? "最大文字・取り消し案内のないホーム" : "取り消し案内のないホーム")
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<30 {
            let navigation = app.navigationBars.allElementsBoundByIndex.filter { $0.isHittable }
            var top = navigation.last?.frame.maxY ?? 0
            let lists = app.collectionViews.allElementsBoundByIndex.filter { $0.isHittable }
            let visibleList = lists.max { $0.frame.height < $1.frame.height }
            if let visibleList { top = max(top, visibleList.frame.minY) }
            var bottom = min(visibleList?.frame.maxY ?? app.frame.maxY - 20, app.frame.maxY - 20)
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            let height = bottom - top
            guard height > 44 else { XCTFail("一覧の操作領域がありません"); return }
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            let down = element.exists && element.frame.midY <= top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + height * (down ? 0.2 : 0.8)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: start + height * (down ? 0.6 : -0.6))), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("項目へ移動できません：\(app.debugDescription)")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
