import XCTest

/// Release captures are opt-in; expiry navigation also has a functional regression check.
/// Run with TEST_RUNNER_CAPTURE_STORE_SCREENSHOTS=1 and -only-testing:.../StoreScreenshotCapture.
final class StoreScreenshotCapture: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testExpiryCardKeepsFoodsIndependentlyTappable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-store-screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 15))
        for food in ["鶏もも肉", "牛乳"] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home-expiry-", food)).firstMatch
            reveal(row, app)
            print("Expiry row: " + row.debugDescription)
            capture(app, "期限カード・" + food)
            row.tap()
            capture(app, "期限カード・遷移後・" + food)
            XCTAssertTrue(app.navigationBars[food].waitForExistence(timeout: 5), app.navigationBars.debugDescription)
            XCTAssertTrue(app.buttons["inventory-save"].isEnabled)
            app.buttons["キャンセル"].firstMatch.tap()
            XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 5))
        }
        app.terminate()
    }

    @MainActor func testCaptureJapaneseStoreScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_STORE_SCREENSHOTS"] == "1",
                          "App Store screenshot capture is opt-in")
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-store-screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 20))
        capture(app, "01-home")
        selectTab("献立", app)
        for (course, key, query) in [("staple", "plain_rice", "ご飯"),
                                     ("main", "teriyaki_chicken", "照り焼き"),
                                     ("side", "chilled_tofu", "冷ややっこ"),
                                     ("soup", "tofu_wakame_miso_soup", "豆腐とわかめ")] {
            let plate = app.buttons["meal-tray-" + course]
            reveal(plate, app, towardTop: true); plate.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(query)
            let recipe = app.buttons["plan-recipe-" + key]
            XCTAssertTrue(recipe.waitForExistence(timeout: 5)); recipe.tap()
            let select = app.buttons["recipe-select"]
            XCTAssertTrue(select.waitForExistence(timeout: 5)); select.tap()
            XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
        }
        reveal(app.buttons["meal-tray-main"], app, towardTop: true)
        capture(app, "02-meal-tray")
        let materials = app.buttons["meal-plan-materials"]
        reveal(materials, app); materials.tap()
        XCTAssertTrue(app.buttons["meal-material-add-shopping"].waitForExistence(timeout: 5))
        capture(app, "03-materials")
        app.navigationBars.buttons.firstMatch.tap()
        selectTab("買い物", app)
        XCTAssertTrue(app.segmentedControls["shopping-filter"].waitForExistence(timeout: 5))
        capture(app, "04-shopping")
        selectTab("マイ冷蔵庫", app)
        XCTAssertTrue(app.buttons["inventory-search-toggle"].waitForExistence(timeout: 5))
        capture(app, "05-fridge")
        selectTab("献立", app)
        let main = app.buttons["meal-tray-main"]; reveal(main, app, towardTop: true); main.tap()
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        capture(app, "06-recipe")
        let mode = app.segmentedControls["recipe-detail-mode"]
        reveal(mode, app); mode.buttons["作り方"].tap()
        let steps = app.staticTexts["recipe-step-text-1"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5)); reveal(steps, app)
        capture(app, "07-steps")
        app.terminate()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor private func selectTab(_ name: String, _ app: XCUIApplication) {
        let phoneTab = app.tabBars.buttons[name]
        if phoneTab.exists { phoneTab.tap() }
        else {
            // iPad's floating tab bar exposes cells instead of a TabBar element.
            let tabletTab = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(tabletTab.waitForExistence(timeout: 5)); tabletTab.tap()
        }
    }

    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<18 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : 0
            let bottom = tabTop > top + 200 ? tabTop : app.frame.maxY - 90
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY < bottom { return }
            let up = element.exists ? element.frame.minY < top : towardTop
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.68))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.68 : 0.4))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTFail("Screenshot content was not visible: " + element.description)
    }
}
