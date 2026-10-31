import XCTest

final class InventoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testAutomaticMergePreviewSingleRowAndSettingDisablesIt() throws {
        try automaticMerge(large: false)
    }
    @MainActor func testLargestAutomaticMergePreviewSingleRowAndSettingDisablesIt() throws {
        try automaticMerge(large: true)
    }
    @MainActor private func automaticMerge(large: Bool) throws {
        let app = formApp(large: large)
        app.openMyPage()
        let setting = app.switches["settings-merge-inventory"]; formScroll(setting, app: app)
        XCTAssertEqual(setting.value as? String, "1")
        captureForm(app, "同じ条件の在庫へ自動合算・初期オン")
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        for (index, amount) in ["200", "300"].enumerated() {
            app.buttons["inventory-add"].tap()
            let search = app.textFields["inventory-ingredient-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("ぶたもも\n")
            let food = app.buttons["inventory-search-food-pork_thigh"]; formScroll(food, app: app); food.tap()
            let quantity = app.textFields["inventory-quantity"]; formScroll(quantity, app: app); quantity.tap()
            quantity.typeText(XCUIKeyboardKey.delete.rawValue + amount)
            app.buttons["inventory-keyboard-done"].tap()
            if index == 1 {
                let preview = app.staticTexts["inventory-merge-preview"]; formScroll(preview, app: app)
                XCTAssertTrue(preview.label.contains("500g")); captureForm(app, "現在200gに300gを追加・500g")
            }
            app.buttons["inventory-save"].tap()
        }
        app.buttons["inventory-search-toggle"].tap()
        let search = app.textFields["inventory-search"]; search.tap(); search.typeText("豚もも\n")
        let rows = app.buttons.matching(identifier: "inventory-row-pork_thigh")
        XCTAssertEqual(rows.count, 1); XCTAssertTrue(rows.firstMatch.label.contains("500g"))
        captureForm(app, "豚もも肉を1行に合算")
        app.openMyPage(); formScroll(setting, app: app)
        print("Merge setting hierarchy: " + setting.debugDescription)
        // SwiftUI exposes the labeled row and its native switch as separate AX elements.
        let control = setting.switches.firstMatch
        if control.exists { control.tap() } else { setting.tap() }
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: setting)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(setting.value as? String, "0")
        app.tabBars.buttons["マイ冷蔵庫"].tap(); app.buttons["inventory-add"].tap()
        let input = app.textFields["inventory-ingredient-search"]; input.tap(); input.typeText("豚もも\n")
        let food = app.buttons["inventory-search-food-pork_thigh"]; formScroll(food, app: app); food.tap()
        XCTAssertFalse(app.staticTexts["inventory-merge-preview"].exists)
        app.buttons["inventory-save"].tap()
        XCTAssertTrue(app.buttons["inventory-save"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        formScroll(rows.firstMatch, app: app)
        expectation(for: NSPredicate { _, _ in rows.count == 2 }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(rows.count, 2); captureForm(app, "自動合算をオフにすると分けて保存")
    }
    @MainActor func testPurchaseSeasoningStatesAndOptionalExpiryWithoutToggles() throws { try seasoningPurchase(large: false) }
    @MainActor func testLargestPurchaseSeasoningStatesAndOptionalExpiry() throws { try seasoningPurchase(large: true) }
    @MainActor private func seasoningPurchase(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-purchase-seasoning-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["買い物"].waitForExistence(timeout: 15)); app.tabBars.buttons["買い物"].tap()
        app.buttons["shopping-complete"].tap(); XCTAssertTrue(app.navigationBars["購入品を確認"].waitForExistence(timeout: 5))
        let checkbox = app.buttons["purchase-inventory-しょうゆ"]
        formScroll(checkbox, app: app)
        let name = app.staticTexts["purchase-name-しょうゆ"]
        XCTAssertTrue(name.exists); XCTAssertLessThan(abs(name.frame.midY - checkbox.frame.midY), 22)
        XCTAssertLessThanOrEqual(name.frame.maxX, checkbox.frame.minX + 1)
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 44)
        checkbox.tap(); XCTAssertEqual(checkbox.value as? String, "オフ")
        checkbox.tap(); XCTAssertEqual(checkbox.value as? String, "オン")
        XCTAssertFalse(app.textFields["purchase-quantity-しょうゆ"].exists)
        let state = large ? app.buttons["purchase-state-しょうゆ"] : app.segmentedControls["purchase-state-しょうゆ"]
        formScroll(state, app: app)
        if large { state.tap(); app.buttons["少なめ"].firstMatch.tap() }
        else { state.buttons["少なめ"].tap() }
        captureForm(app, large ? "最大文字・調味料は3つの状態" : "調味料はあり・少なめ・なし")
        let details = app.buttons["purchase-details-しょうゆ"]; formScroll(details, app: app); details.tap()
        XCTAssertFalse(app.switches["期限を登録"].exists); XCTAssertFalse(app.switches["既存在庫と合算する"].exists)
        let expiry = app.buttons["purchase-expiry-しょうゆ"]; formScroll(expiry, app: app)
        XCTAssertEqual(expiry.value as? String, "指定なし")
        expiry.tap(); captureForm(app, large ? "最大文字・購入日と同じ期限入力" : "購入日と同じ期限入力")
        let components = Calendar.current.dateComponents([.day, .month], from: .now)
        let month = DateFormatter(); month.locale = Locale(identifier: "en_US"); month.dateFormat = "MMMM"
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label == %@",
            "\(components.month!)月\(components.day!)日", month.string(from: .now) + " \(components.day!)", String(components.day!))).firstMatch
        if !day.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(day.exists); day.tap()
        let clear = app.buttons["purchase-expiry-clear-しょうゆ"]
        if !clear.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(clear.exists, "今日と同じ日を選んでも期限を登録できる")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        formScroll(clear, app: app)
        XCTAssertTrue(expiry.isHittable)
        captureForm(app, large ? "最大文字・期限の日付欄" : "期限の日付欄")
        clear.tap()
        XCTAssertEqual(expiry.value as? String, "指定なし")
        XCTAssertFalse(app.navigationBars["期限を選ぶ"].exists)
        app.buttons["purchase-save"].tap(); XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-group"].tap(); app.buttons["調味料"].firstMatch.tap()
        let soy = app.buttons["inventory-row-soy_sauce"]; formScroll(soy, app: app)
        XCTAssertEqual(app.buttons.matching(identifier: "inventory-row-soy_sauce").count, 1)
        XCTAssertTrue(soy.label.contains("少ない"), soy.label)
        captureForm(app, large ? "最大文字・調味料の状態を保存" : "調味料の状態を保存")
    }
    @MainActor func testHomeReturnFromDetailsAndTabsKeepsRecommendationsUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        let original = hero.label
        for _ in 0..<3 {
            formScroll(hero, app: app, towardTop: true); hero.tap()
            XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(hero.waitForExistence(timeout: 5)); XCTAssertEqual(hero.label, original)
            app.tabBars.buttons["マイ冷蔵庫"].tap()
            app.tabBars.buttons["ホーム"].tap()
            XCTAssertTrue(hero.waitForExistence(timeout: 5)); XCTAssertEqual(hero.label, original)
        }
        let browse = app.buttons["home-recipe-entry"]
        formScroll(browse, app: app, towardTop: true); browse.tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("ツナマヨ\n")
        let recipe = app.buttons["recipe-tuna_mayo_bowl"]; formScroll(recipe, app: app); recipe.tap()
        XCTAssertEqual(app.staticTexts["recipe-detail-title"].label, "ツナマヨ丼")
        app.navigationBars.buttons.firstMatch.tap()
        // Search retains focus after returning from detail; dismiss it before the navigation back button.
        let cancelSearch = app.navigationBars.buttons["閉じる"]
        if cancelSearch.exists { cancelSearch.tap() }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(hero.waitForExistence(timeout: 5)); XCTAssertEqual(hero.label, original)
        captureForm(app, "詳細・一覧・冷蔵庫からホームに戻る")
    }
    @MainActor func testRecipeStockPopupShowsRoughExactExpiredAndMappedLots() throws { try stockPeek(large: false) }
    @MainActor func testLargestRecipeStockPopupRemainsReadableAndDismissible() throws { try stockPeek(large: true) }
    @MainActor private func stockPeek(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-stock-peek-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 15))
        let browse = app.buttons["home-recipe-entry"]; formScroll(browse, app: app); browse.tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("ツナマヨ\n")
        let recipe = app.buttons["recipe-tuna_mayo_bowl"]; formScroll(recipe, app: app); recipe.tap()
        XCTAssertFalse(app.switches["recipe-buy-uncertain"].exists)
        let peek = app.buttons["recipe-stock-peek-canned_tuna"]; formScroll(peek, app: app)
        XCTAssertTrue(peek.isHittable); XCTAssertGreaterThanOrEqual(peek.frame.height, 44); peek.tap()
        XCTAssertTrue(app.navigationBars["ツナ缶の在庫"].waitForExistence(timeout: 5))
        let exact = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "recipe-stock-lot-", "0.25缶")).firstMatch
        formScroll(exact, app: app); XCTAssertTrue(exact.label.contains("冷凍")); captureForm(app, large ? "最大文字・現在の在庫ポップ" : "現在の在庫ポップ・数量と保存場所")
        let expired = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "recipe-stock-lot-", "期限切れ")).firstMatch
        formScroll(expired, app: app); XCTAssertTrue(expired.exists)
        let mapped = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "recipe-stock-lot-", "開封したツナ")).firstMatch
        formScroll(mapped, app: app); XCTAssertTrue(mapped.label.contains("少ない")); XCTAssertFalse(app.staticTexts["99缶"].exists)
        captureForm(app, large ? "最大文字・対応付けた在庫の状態" : "対応付けた在庫・期限切れも区別")
        app.buttons["recipe-stock-peek-close"].tap()
        XCTAssertTrue(app.navigationBars["レシピ詳細"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["recipe-stock-peek-close"].exists)
        let summary = app.buttons["recipe-detail-confirmation"]; formScroll(summary, app: app, towardTop: true); summary.tap()
        XCTAssertTrue(app.navigationBars["冷蔵庫の在庫"].waitForExistence(timeout: 5))
        let rice = app.staticTexts["ごはん"].firstMatch; formScroll(rice, app: app); XCTAssertTrue(rice.exists)
        captureForm(app, large ? "最大文字・量確認の食材をまとめて表示" : "量確認の食材をまとめて表示")
        app.buttons["recipe-stock-peek-close"].tap()
        app.buttons["recipe-select"].tap()
        XCTAssertEqual(app.staticTexts["recipe-completion"].label, "買い物リストに0品を追加しました。")
    }
    @MainActor func testCompactPurchaseCheckboxQuantityAndCommonOverride() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact", "--ui-purchase-compact-fixture"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["買い物"].waitForExistence(timeout: 15)); app.tabBars.buttons["買い物"].tap()
        app.buttons["shopping-complete"].tap(); XCTAssertTrue(app.navigationBars["購入品を確認"].waitForExistence(timeout: 5))
        let checkbox = app.buttons["purchase-inventory-卵"]; formScroll(checkbox, app: app); XCTAssertEqual(checkbox.value as? String, "オン")
        let name = app.staticTexts["purchase-name-卵"]
        XCTAssertTrue(name.exists); XCTAssertLessThan(abs(name.frame.midY - checkbox.frame.midY), 22)
        XCTAssertLessThanOrEqual(name.frame.maxX, checkbox.frame.minX + 1)
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 44)
        checkbox.tap(); XCTAssertEqual(checkbox.value as? String, "オフ"); checkbox.tap()
        let quantity = app.textFields["purchase-quantity-卵"], unit = app.buttons["purchase-unit-卵"]
        formScroll(quantity, app: app); XCTAssertTrue(unit.isHittable); XCTAssertLessThan(abs(quantity.frame.midY - unit.frame.midY), 12)
        XCTAssertFalse(app.staticTexts["共通設定を変えると、個別変更していない品だけに反映します。"].exists)
        XCTAssertFalse(app.staticTexts["別の在庫として登録します。期限・保存方法・単位が一致する在庫だけ合算できます。"].exists)
        captureForm(app, "購入品確認・共通設定と数量をコンパクトに")
        let details = app.buttons["purchase-details-卵"]; formScroll(details, app: app); details.tap()
        let storage = app.buttons["purchase-storage-卵"]; formScroll(storage, app: app); storage.tap(); app.buttons["常温"].firstMatch.tap()
        let common = app.buttons["purchase-common-storage"]; formScroll(common, app: app); common.tap(); app.buttons["冷凍"].firstMatch.tap()
        formScroll(storage, app: app); XCTAssertTrue(storage.label.contains("常温"), storage.label)
        let nonfood = app.buttons["purchase-inventory-キッチンペーパー"]; formScroll(nonfood, app: app); XCTAssertEqual(nonfood.value as? String, "オフ")
        app.buttons["purchase-save"].tap(); XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let egg = app.buttons.matching(identifier: "inventory-row-egg").matching(NSPredicate(format: "label CONTAINS %@", "常温")).firstMatch
        formScroll(egg, app: app); XCTAssertTrue(egg.label.contains("常温"))
        let onion = app.buttons["inventory-row-onion"]; formScroll(onion, app: app); XCTAssertTrue(onion.label.contains("冷凍"))
    }
    @MainActor func testCheckedBasketRemovalKeepsInventoryAndUncheckedItem() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact", "--ui-purchase-compact-fixture", "--ui-check-delay"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["買い物"].waitForExistence(timeout: 15)); app.tabBars.buttons["買い物"].tap()
        let onion = app.buttons["shopping-row-玉ねぎ"]; formScroll(onion, app: app); onion.tap(); XCTAssertEqual(onion.value as? String, "未購入")
        let remove = app.buttons["shopping-remove-checked"]; XCTAssertTrue(remove.isHittable); remove.tap()
        XCTAssertTrue(app.buttons["shopping-row-卵"].waitForNonExistence(timeout: 10)); XCTAssertFalse(app.buttons["shopping-row-キッチンペーパー"].exists)
        XCTAssertTrue(onion.exists); XCTAssertFalse(remove.exists); captureForm(app, "購入済みだけをかごから取り除く")
        app.tabBars.buttons["マイ冷蔵庫"].tap(); XCTAssertFalse(app.buttons["inventory-row-onion"].exists)
        let egg = app.buttons["inventory-row-egg"]; formScroll(egg, app: app); XCTAssertTrue(egg.label.contains("6個"))
    }
    @MainActor func testShoppingCheckRespondsWhileSaveIsSuspendedAndRapidTapsPurchase() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset-fixture", "--ui-check-delay"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["買い物"].waitForExistence(timeout: 15))
        app.tabBars.buttons["買い物"].tap()
        let row = app.buttons["shopping-row-卵"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let started = Date()
        row.tap(); XCTAssertEqual(row.value as? String, "購入済み")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "保存を5秒止めても表示は先に反応する")
        XCTAssertTrue(app.buttons["shopping-complete"].exists)
        row.tap(); XCTAssertEqual(row.value as? String, "未購入")
        XCTAssertFalse(app.buttons["shopping-complete"].exists)
        row.tap(); XCTAssertEqual(row.value as? String, "購入済み")
        captureForm(app, "保存を待たずチェックと件数が反応")
        app.buttons["shopping-complete"].tap()
        XCTAssertEqual(app.buttons["shopping-complete"].value as? String, "保存中")
        XCTAssertFalse(app.buttons["買うものを追加"].isEnabled)
        XCTAssertTrue(app.navigationBars["購入品を確認"].waitForExistence(timeout: 15))
        let save = app.buttons["purchase-save"]; XCTAssertTrue(save.isHittable); save.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let purchased = app.buttons.matching(identifier: "inventory-row-egg").matching(NSPredicate(format: "label CONTAINS %@", "2個")).firstMatch
        formScroll(purchased, app: app); XCTAssertTrue(purchased.exists)
        captureForm(app, "連続チェックの最後の状態から購入・在庫登録")
    }
    @MainActor func testShoppingCheckFailedSaveRestoresRowAndCount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset-fixture", "--ui-check-delay", "--ui-check-failure"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["買い物"].waitForExistence(timeout: 15))
        app.tabBars.buttons["買い物"].tap()
        let row = app.buttons["shopping-row-卵"]; XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap(); XCTAssertEqual(row.value as? String, "購入済み")
        let alert = app.alerts["変更できませんでした"]; XCTAssertTrue(alert.waitForExistence(timeout: 12))
        captureForm(app, "チェック保存失敗のエラー表示")
        alert.buttons["閉じる"].tap()
        XCTAssertEqual(row.value as? String, "未購入"); XCTAssertFalse(app.buttons["shopping-complete"].exists)
        app.segmentedControls["shopping-filter"].buttons["購入済み"].tap()
        XCTAssertFalse(row.exists)
        app.segmentedControls["shopping-filter"].buttons["未購入"].tap()
        XCTAssertTrue(row.exists)
        captureForm(app, "失敗時にチェック・件数・フィルターを復元")
    }
    @MainActor func testCheckedShoppingRowQuantityEditAndRemovalRefreshDisplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset-fixture"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["買い物"].waitForExistence(timeout: 15))
        app.tabBars.buttons["買い物"].tap()
        let row = app.buttons["shopping-row-卵"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertEqual(row.value as? String, "購入済み")
        row.swipeLeft()
        let edit = app.buttons["数量を編集"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); XCTAssertTrue(edit.isEnabled); edit.tap()
        let quantity = app.textFields["shopping-quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5)); replaceInput(quantity, with: "3")
        app.buttons["shopping-manual-save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("3個"), row.label)
        XCTAssertEqual(row.value as? String, "購入済み")
        captureForm(app, "チェック後の数量変更も行に反映")
        row.swipeLeft(); app.buttons["削除"].firstMatch.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5)); XCTAssertFalse(app.buttons["shopping-complete"].exists)
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.navigationBars["今日何作る？"].waitForExistence(timeout: 5))
    }

    @MainActor func testManualInputKeyboardAndSave() throws { try manualInput(large: false) }
    @MainActor func testLargestManualInputKeyboardAndSave() throws { try manualInput(large: true) }
    @MainActor func testPurchaseQuantityKeyboardValidationAndSave() throws { try purchaseInput(large: false) }
    @MainActor func testLargestPurchaseQuantityKeyboardValidationAndSave() throws { try purchaseInput(large: true) }
    @MainActor func testCookingQuantityKeyboardOverdraftCancelAndSave() throws { try cookingInput(large: false) }
    @MainActor func testLargestCookingQuantityKeyboardOverdraftCancelAndSave() throws { try cookingInput(large: true) }
    @MainActor func testSearchIngredientFromAddFormAndChangeSelection() throws { try searchIngredientAdd(large: false) }
    @MainActor func testLargestSearchIngredientFromAddFormAndChangeSelection() throws { try searchIngredientAdd(large: true) }
    @MainActor private func searchIngredientAdd(large: Bool) throws {
        let app = formApp(large: large)
        app.tabBars.buttons["マイ冷蔵庫"].tap(); app.buttons["inventory-add"].tap()
        let search = app.textFields["inventory-ingredient-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("なす\n")
        let eggplant = app.buttons["inventory-search-food-eggplant"]
        formScroll(eggplant, app: app); XCTAssertTrue(eggplant.exists); eggplant.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["inventory-save"].isEnabled)
        let change = app.buttons["inventory-change-ingredient"]; formScroll(change, app: app); change.tap()
        XCTAssertFalse(app.buttons["inventory-save"].isEnabled)
        let clear = app.buttons["inventory-search-clear"]; formScroll(clear, app: app); clear.tap()
        formScroll(search, app: app); search.tap(); search.typeText("たまねぎ\n")
        let onion = app.buttons["inventory-search-food-onion"]; formScroll(onion, app: app); onion.tap()
        let selected = app.descendants(matching: .any).matching(identifier: "inventory-selected-ingredient").firstMatch
        XCTAssertTrue(selected.label.contains("玉ねぎ"), selected.label)
        captureForm(app, large ? "最大文字・検索から玉ねぎを追加" : "検索から玉ねぎを追加")
        app.buttons["inventory-save"].tap()
        let row = app.buttons["inventory-row-onion"]; formScroll(row, app: app)
        XCTAssertTrue(row.label.contains("玉ねぎ")); XCTAssertTrue(row.label.contains("1個"))
        XCTAssertFalse(app.buttons["inventory-row-eggplant"].exists)
        app.buttons["inventory-add"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("さば\n")
        let fresh = app.buttons["inventory-search-food-mackerel_fillet"]
        formScroll(fresh, app: app); XCTAssertTrue(fresh.exists)
        XCTAssertTrue(app.buttons["inventory-search-food-canned_mackerel"].exists)
        XCTAssertFalse(app.buttons["inventory-save"].isEnabled)
        fresh.tap(); XCTAssertTrue(app.buttons["inventory-save"].isEnabled)
        app.buttons["キャンセル"].tap()
        app.buttons["inventory-add"].tap()
        let all = app.buttons["inventory-master-picker"]; formScroll(all, app: app); all.tap()
        XCTAssertTrue(app.navigationBars["食材を選ぶ"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch; field.tap(); field.typeText("ぽんず")
        let ponzu = app.buttons["mapping-food-ponzu"]; formScroll(ponzu, app: app); ponzu.tap()
        XCTAssertTrue(app.navigationBars["食材を追加"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inventory-save"].isEnabled)
        app.buttons["inventory-save"].tap()
        let group = app.buttons["inventory-group"]; formScroll(group, app: app)
        group.tap(); app.buttons["調味料"].firstMatch.tap()
        let seasoning = app.buttons["inventory-row-ponzu"]; formScroll(seasoning, app: app)
        XCTAssertTrue(seasoning.label.contains("ある"))
    }
    @MainActor func testIngredientShoppingSelectionPurchasesIntoFridgeAndFreeEntryRemains() throws {
        let app = formApp(large: false)
        app.tabBars.buttons["買い物"].tap(); app.navigationBars.buttons["買うものを追加"].tap()
        app.buttons["shopping-master-picker"].tap()
        XCTAssertTrue(app.navigationBars["食材を選ぶ"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("なす")
        app.buttons["mapping-food-eggplant"].tap()
        XCTAssertEqual(app.textFields["shopping-name"].value as? String, "なす")
        XCTAssertTrue(app.buttons["shopping-manual-save"].isEnabled); app.buttons["shopping-manual-save"].tap()
        let shopping = app.buttons["shopping-row-なす"]; formScroll(shopping, app: app); shopping.tap()
        app.buttons["shopping-complete"].tap()
        XCTAssertTrue(app.navigationBars["購入品を確認"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["purchase-save"].isEnabled); app.buttons["purchase-save"].tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let stock = app.buttons["inventory-row-eggplant"]; formScroll(stock, app: app)
        XCTAssertTrue(stock.label.contains("なす")); XCTAssertTrue(stock.label.contains("1個"))
        captureForm(app, "選んだ食材を買い物から冷蔵庫へ")
        app.tabBars.buttons["買い物"].tap(); app.navigationBars.buttons["買うものを追加"].tap()
        let free = app.textFields["shopping-name"]; free.tap(); free.typeText("キッチンペーパー")
        XCTAssertTrue(app.buttons["shopping-manual-save"].isEnabled); app.buttons["shopping-manual-save"].tap()
        let freeRow = app.buttons["shopping-row-キッチンペーパー"]; formScroll(freeRow, app: app); XCTAssertTrue(freeRow.exists)
    }
    @MainActor private func formApp(large: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["マイ冷蔵庫"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func manualInput(large: Bool) throws {
        let app = formApp(large: large)
        app.tabBars.buttons["マイ冷蔵庫"].tap(); app.buttons["inventory-add"].tap()
        let custom = app.buttons["inventory-custom-mode"]
        formScroll(custom, app: app); custom.tap()
        let name = app.textFields["inventory-custom-name"]
        formScroll(name, app: app); name.tap(); name.typeText("確認用ソース")
        checkInput(name, done: "inventory-keyboard-done", title: "食材を追加", app: app)
        app.buttons["inventory-keyboard-done"].tap()
        XCTAssertEqual(name.value as? String, "確認用ソース")
        let exact = app.switches["inventory-exact-toggle"]
        formScroll(exact, app: app); exact.switches.firstMatch.tap()
        let quantity = app.textFields["inventory-quantity"]
        formScroll(quantity, app: app); replaceInput(quantity, with: "2")
        checkInput(quantity, done: "inventory-keyboard-done", title: "食材を追加", app: app)
        captureForm(app, large ? "最大文字・手入力の数量" : "通常・手入力の数量")
        app.buttons["inventory-keyboard-done"].tap()
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 2)
        app.buttons["inventory-save"].tap()
        let row = app.buttons["inventory-row-custom"]
        formScroll(row, app: app)
        XCTAssertTrue(row.label.contains("確認用ソース")); XCTAssertTrue(row.label.contains("2個")); row.tap()
        formScroll(quantity, app: app); replaceInput(quantity, with: "3")
        app.buttons["inventory-keyboard-done"].tap(); app.buttons["inventory-save"].tap()
        formScroll(row, app: app); XCTAssertTrue(row.label.contains("3個"))
        captureForm(app, large ? "最大文字・手入力と編集の保存" : "通常・手入力と編集の保存")
    }
    @MainActor private func purchaseInput(large: Bool) throws {
        let app = formApp(large: large)
        app.tabBars.buttons["買い物"].tap(); app.buttons["買うものを追加"].firstMatch.tap()
        let name = app.textFields["品名"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("卵")
        app.buttons["追加"].tap()
        let row = app.buttons["shopping-row-卵"]
        formScroll(row, app: app); row.tap(); app.buttons["shopping-complete"].tap()
        let quantity = app.textFields["purchase-quantity-卵"]
        formScroll(quantity, app: app); replaceInput(quantity, with: "0")
        checkInput(quantity, done: "purchase-keyboard-done", title: "購入品を確認", app: app)
        XCTAssertFalse(app.buttons["purchase-save"].exists)
        app.buttons["purchase-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5)); XCTAssertFalse(app.buttons["purchase-save"].isEnabled)
        formScroll(quantity, app: app); replaceInput(quantity, with: "5")
        checkInput(quantity, done: "purchase-keyboard-done", title: "購入品を確認", app: app)
        captureForm(app, large ? "最大文字・購入量の入力" : "通常・購入量の入力")
        app.buttons["purchase-keyboard-done"].tap()
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 5)
        XCTAssertTrue(app.buttons["purchase-save"].isEnabled); app.buttons["purchase-save"].tap()
        XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let purchased = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "inventory-row-egg", "5個")).firstMatch
        formScroll(purchased, app: app); XCTAssertFalse(purchased.label.contains("期限切れ"))
        captureForm(app, large ? "最大文字・購入量5個を保存" : "通常・購入量5個を保存")
    }
    @MainActor private func cookingInput(large: Bool) throws {
        let app = formApp(large: large)
        let hero = app.buttons["home-recipe-hero"]
        formScroll(hero, app: app); hero.tap(); app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        let cook = app.buttons["作った・使用量を確認"].firstMatch
        if !cook.isHittable { formScroll(cook, app: app) }; cook.tap()
        let expandRice = app.descendants(matching: .any).matching(identifier: "cooking-expand-cooked_rice").firstMatch; formScroll(expandRice, app: app); expandRice.tap()
        let quantity = app.textFields["cooking-quantity-cooked_rice"]
        formScroll(quantity, app: app); replaceInput(quantity, with: "300")
        checkInput(quantity, done: "cooking-keyboard-done", title: "調理後の在庫", app: app)
        XCTAssertFalse(app.buttons["cooking-save"].exists)
        finishCookingInput(app); app.buttons["cooking-save"].tap()
        XCTAssertTrue(app.alerts["使用量の確認が必要です"].waitForExistence(timeout: 5))
        app.alerts.buttons["入力に戻る"].tap()
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 300)
        formScroll(quantity, app: app); replaceInput(quantity, with: "150")
        checkInput(quantity, done: "cooking-keyboard-done", title: "調理後の在庫", app: app)
        captureForm(app, large ? "最大文字・使用量の入力" : "通常・使用量の入力")
        finishCookingInput(app); app.buttons["キャンセル"].tap()
        XCTAssertTrue(cook.waitForExistence(timeout: 5)); if !cook.isHittable { formScroll(cook, app: app) }; cook.tap()
        formScroll(quantity, app: app)
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 200)
        replaceInput(quantity, with: "150"); finishCookingInput(app)
        app.buttons["cooking-save"].tap()
        XCTAssertTrue(app.buttons["cooking-save"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]
        formScroll(rice, app: app); XCTAssertTrue(rice.label.contains("50g"))
        captureForm(app, large ? "最大文字・調理後に50g残る" : "通常・調理後に50g残る")
    }
    @MainActor private func finishCookingInput(_ app: XCUIApplication) {
        let done = app.buttons["cooking-keyboard-done"], keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in
            done.exists && done.isHittable && keyboard.exists && done.frame.maxY <= keyboard.frame.minY + 1
        }, evaluatedWith: done)
        waitForExpectations(timeout: 5)
        done.tap()
        XCTAssertTrue(app.buttons["cooking-save"].waitForExistence(timeout: 5))
    }
    @MainActor private func replaceInput(_ field: XCUIElement, with value: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
    }
    @MainActor private func checkInput(_ field: XCUIElement, done id: String, title: String, app: XCUIApplication) {
        let done = app.buttons[id]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        if app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") { XCTAssertGreaterThan(field.frame.height, 40) }
        XCTAssertGreaterThanOrEqual(field.frame.minY + 1, app.navigationBars[title].frame.maxY)
        XCTAssertLessThanOrEqual(field.frame.maxY, done.frame.minY + 1)
    }
    @MainActor private func formScroll(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<30 {
            let top = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
            let modal = app.navigationBars.count > 1
            let tabs = app.tabBars.firstMatch
            var bottom = !modal && tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY - 20
            let stockPopup = app.buttons["recipe-stock-peek-close"].exists
            for id in ["purchase-save", "cooking-save", "recipe-select", "recipe-add-shortages", "shopping-complete", "inventory-keyboard-done", "purchase-keyboard-done", "cooking-keyboard-done", "inventory-undo"] {
                if stockPopup { continue } // Underlying recipe controls are outside this sheet.
                let footer = app.buttons[id]
                if footer.exists && footer.isHittable && (id != "inventory-undo" || !modal) { bottom = min(bottom, footer.frame.minY - 8) }
            }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
            // Large Undo text can shrink the list above its action button. Drag inside the list.
            if let list = app.collectionViews.allElementsBoundByIndex.filter({ $0.frame.maxY > top + 40 && $0.frame.minY < bottom }).max(by: { $0.frame.height < $1.frame.height }) {
                bottom = min(bottom, list.frame.maxY)
            }
            let available = bottom - top
            var down = towardTop, distance = available * 0.6
            if element.exists {
                let frame = element.frame
                let fits = frame.height <= available
                let visible = fits ? frame.minY >= top - 1 && frame.maxY <= bottom + 1 : frame.midY > top && frame.midY < bottom
                if element.isHittable && visible { return }
                down = fits ? frame.minY < top : frame.midY <= top
                let missing = fits ? (down ? top - frame.minY : frame.maxY - bottom) : abs(frame.midY - (top + bottom) / 2)
                distance = stockPopup ? available * 0.6 : min(max(missing + 30, 60), available * 0.6)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + available * (down ? 0.2 : 0.8)
            let x = stockPopup ? app.frame.width * 0.9 : app.frame.midX
            origin.withOffset(CGVector(dx: x, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: start + (down ? distance : -distance))), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        print(app.debugDescription); XCTFail("入力項目へ移動できません: \(element)")
    }
    @MainActor private func captureForm(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication, footer: String? = nil) {
        for _ in 0..<20 {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let modal = app.navigationBars.count > 1
            let tabBar = app.tabBars.firstMatch
            var bottom = footer.map { app.buttons[$0].frame.minY - 12 } ?? (modal || !tabBar.exists ? app.frame.maxY - 20 : tabBar.frame.minY - 12)
            // A modal NavigationStack covers the tab banner; do not reserve its old frame.
            if app.navigationBars.count == 1 && app.buttons["inventory-undo"].exists && app.buttons["inventory-undo"].isHittable { bottom = min(bottom, app.buttons["inventory-undo"].frame.minY - 12) }
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            let down = element.exists && element.frame.height > 0 && element.frame.midY <= top
            let high = top + (bottom - top) * 0.2, low = top + (bottom - top) * 0.8
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: down ? high : low)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: down ? low : high)))
        }
        XCTFail("項目を表示できませんでした：\(element.identifier)")
    }
    @MainActor
    func testBulkSetupEditAndMealShoppingNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let soy = app.buttons["bulk-item-soy_sauce"]
        XCTAssertTrue(soy.waitForExistence(timeout: 15))
        let initialScreenshot = XCTAttachment(screenshot: app.screenshot())
        initialScreenshot.name = "初期在庫の一括登録"
        initialScreenshot.lifetime = .keepAlways
        add(initialScreenshot)
        scrollTo(soy, app: app, footer: "bulk-save"); soy.tap()
        XCTAssertTrue(app.buttons["bulk-save"].isEnabled)
        app.buttons["bulk-save"].tap()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let row = app.buttons["inventory-row-soy_sauce"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let toggle = app.switches["inventory-exact-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let quantity = app.textFields["inventory-quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 3))
        quantity.tap()
        quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (quantity.value as? String ?? "").count) + "3")
        app.buttons["inventory-save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("3ml"))
        app.tabBars.buttons["ホーム"].tap()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        hero.tap()
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        app.tabBars.buttons["買い物"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shopping-row-")).firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "買い物への不足分反映"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSkipSetupAndAddCustomIngredient() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-dark"]
        app.launch()
        let skip = app.buttons["bulk-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-add"].tap()
        app.buttons["inventory-custom-mode"].tap()
        let name = app.textFields["inventory-custom-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Homemade sauce")
        app.buttons["inventory-save"].tap()
        XCTAssertTrue(app.buttons["inventory-row-custom"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "自分用食材・ダークモード"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor
    func testSelectPurchaseAndCookEntireMeal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15))
        app.buttons["bulk-skip"].tap()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        hero.tap()
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        app.tabBars.buttons["買い物"].tap()
        let unchecked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "shopping-row-", "未購入"))
        XCTAssertTrue(unchecked.firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            let row = unchecked.firstMatch
            if !row.isHittable { app.swipeUp() }
            row.tap()
        }
        app.buttons["shopping-complete"].tap()
        XCTAssertTrue(app.buttons["purchase-save"].waitForExistence(timeout: 5))
        app.buttons["purchase-save"].tap()
        XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["ホーム"].tap()
        if app.buttons["BackButton"].exists { app.buttons["BackButton"].tap() }
        app.tabBars.buttons["献立"].tap()
        XCTAssertTrue(app.buttons["meal-cook"].waitForExistence(timeout: 5))
        app.buttons["meal-cook"].tap()
        XCTAssertTrue(app.buttons["cooking-save"].waitForExistence(timeout: 5))
        app.buttons["cooking-save"].tap()
        XCTAssertFalse(app.buttons["meal-cook"].exists)
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]
        XCTAssertTrue(rice.waitForExistence(timeout: 5))
        XCTAssertTrue(rice.label.contains("0g"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "購入と調理後の冷蔵庫"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testExpiryIntroductionPermissionSettingsAndDisable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-expiry"]
        app.launch()
        let later = app.buttons["expiry-introduction-later"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        later.tap()
        app.openMyPage()
        app.buttons["期限通知"].tap()
        let allow = app.buttons["expiry-notification-authorize"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        XCTAssertTrue(app.staticTexts["expiry-notification-authorized"].waitForExistence(timeout: 5))
        let count = app.staticTexts["expiry-notification-count"]
        let one = NSPredicate(format: "label CONTAINS %@", "1件")
        expectation(for: one, evaluatedWith: count)
        waitForExpectations(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "期限通知設定"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.switches["expiry-notifications-enabled"].switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "0件"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        XCTAssertTrue(app.buttons["inventory-row-egg"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReceiptConsentReviewSaveAndWithdraw() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-receipt-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15))
        app.buttons["bulk-skip"].tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-receipt"].tap()
        let consent = app.buttons["receipt-consent"]
        XCTAssertTrue(app.navigationBars["レシートから登録"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["receipt-photo-picker"].exists)
        scrollTo(consent, app: app)
        XCTAssertTrue(consent.isHittable)
        consent.tap()
        XCTAssertTrue(app.buttons["receipt-fixture"].waitForExistence(timeout: 5))
        app.buttons["receipt-fixture"].tap()
        let save = app.buttons["receipt-save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.switches["receipt-confirm"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "レシート確認・非食品除外"; screenshot.lifetime = .keepAlways; add(screenshot)
        save.tap()
        let milk = app.buttons["inventory-row-milk"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        XCTAssertTrue(milk.label.replacingOccurrences(of: ",", with: "").contains("1000ml"), milk.label)
        let savedScreenshot = XCTAttachment(screenshot: app.screenshot())
        savedScreenshot.name = "レシートから登録した冷蔵庫"; savedScreenshot.lifetime = .keepAlways; add(savedScreenshot)
        XCTAssertFalse(app.buttons["inventory-row-custom"].exists)
        app.openMyPage()
        app.buttons["レシート写真の扱い"].tap()
        let withdraw = app.buttons["レシート読み取りへの同意を取り消す"]
        scrollTo(withdraw, app: app)
        withdraw.tap()
        XCTAssertTrue(withdraw.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-receipt"].tap()
        XCTAssertTrue(app.navigationBars["レシートから登録"].waitForExistence(timeout: 5))
        scrollTo(consent, app: app)
        XCTAssertTrue(consent.isHittable)
    }

    @MainActor
    func testReceiptWithoutConsentManualDraftCanBeDiscarded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15))
        app.buttons["bulk-skip"].tap(); app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-receipt"].tap()
        let manual = app.buttons["receipt-manual-without-consent"]
        XCTAssertTrue(app.navigationBars["レシートから登録"].waitForExistence(timeout: 5))
        scrollTo(manual, app: app)
        XCTAssertTrue(manual.isHittable)
        manual.tap()
        XCTAssertFalse(app.buttons["receipt-photo-picker"].exists)
        let name = app.textFields["receipt-custom-name"]
        scrollTo(name, app: app, footer: "receipt-save")
        name.tap(); name.typeText("Draft sauce")
        XCTAssertFalse(app.buttons["receipt-save"].exists)
        app.buttons["receipt-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Draft sauce")
        XCTAssertFalse(app.buttons["receipt-save"].isEnabled)
        app.buttons["閉じる"].tap()
        app.buttons["破棄して閉じる"].tap()
        XCTAssertTrue(app.buttons["inventory-add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventory-row-custom"].exists)
    }

    @MainActor func testRemainingInputAndSeasoningStateSaves() throws { try refreshedCooking(large: false) }
    @MainActor func testLargestRemainingInputAndSeasoningStateSaves() throws { try refreshedCooking(large: true) }
    @MainActor private func refreshedCooking(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact", "--ui-seasoning-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let hero = app.buttons["home-recipe-hero"]; formScroll(hero, app: app); hero.tap()
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        let cook = app.buttons["作った・使用量を確認"].firstMatch
        if !cook.isHittable { formScroll(cook, app: app) }; cook.tap()
        let expandRice = app.descendants(matching: .any).matching(identifier: "cooking-expand-cooked_rice").firstMatch; formScroll(expandRice, app: app); expandRice.tap()
        let quantity = app.textFields["cooking-quantity-cooked_rice"]
        formScroll(quantity, app: app); XCTAssertEqual(Double(quantity.value as? String ?? ""), 200)
        let mode = large ? app.buttons["cooking-mode-cooked_rice"] : app.segmentedControls["cooking-mode-cooked_rice"]
        formScroll(mode, app: app)
        // Re-selecting the current input method must keep the recipe default amount.
        if large { mode.tap(); app.buttons["使った量"].firstMatch.tap() }
        else { mode.buttons["使った量"].tap() }
        XCTAssertEqual(Double(quantity.value as? String ?? ""), 200)
        if large { mode.tap(); app.buttons["残りの量"].firstMatch.tap() }
        else { mode.buttons["残りの量"].tap() }
        formScroll(quantity, app: app); replaceInput(quantity, with: "50")
        finishCookingInput(app)
        let expandMayo = app.descendants(matching: .any).matching(identifier: "cooking-expand-mayonnaise").firstMatch; formScroll(expandMayo, app: app); expandMayo.tap()
        let seasoning = large
            ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cooking-seasoning-mayonnaise-")).firstMatch
            : app.segmentedControls.matching(NSPredicate(format: "identifier BEGINSWITH %@", "cooking-seasoning-mayonnaise-")).firstMatch
        formScroll(seasoning, app: app)
        XCTAssertFalse(app.textFields["cooking-quantity-mayonnaise"].exists)
        if large { seasoning.tap(); app.buttons["少ない"].firstMatch.tap() }
        else { seasoning.buttons["少ない"].tap() }
        captureForm(app, large ? "最大文字・調味料を少ないに更新" : "調味料はある少ないないのみ")
        app.buttons["cooking-save"].tap()
        XCTAssertTrue(app.buttons["cooking-save"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]; formScroll(rice, app: app)
        XCTAssertTrue(rice.label.contains("50g"))
        let mayo = app.buttons["inventory-row-mayonnaise"]; formScroll(mayo, app: app)
        XCTAssertTrue(mayo.label.contains("少ない")); XCTAssertFalse(mayo.label.contains("200g"))
        captureForm(app, large ? "最大文字・残量と調味料の保存結果" : "残量50gと調味料少ないを保存")
    }

    @MainActor func testFridgeGroupsTagsAndRegistrationShortcuts() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]
        app.launch(); XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["今日のおすすめ"].exists)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        XCTAssertTrue(app.staticTexts["食材の追加"].exists)
        for id in ["inventory-voice", "inventory-receipt", "inventory-bulk"] { XCTAssertTrue(app.buttons[id].exists) }
        XCTAssertFalse(app.buttons["inventory-methods"].exists)
        let group = app.buttons["inventory-group"]; formScroll(group, app: app)
        group.tap(); app.buttons["調味料"].firstMatch.tap()
        let mayo = app.buttons["inventory-row-mayonnaise"]; formScroll(mayo, app: app); XCTAssertTrue(mayo.label.contains("調味料"))
        XCTAssertFalse(app.buttons["inventory-row-milk"].exists)
        formScroll(group, app: app); group.tap(); app.buttons["食材"].firstMatch.tap()
        XCTAssertFalse(mayo.exists)
        // The category raw value is read from the existing enum, so the ID remains stable.
        let dairy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "inventory-tag-", "乳・卵")).firstMatch
        formScroll(dairy, app: app); dairy.tap()
        let milk = app.buttons["inventory-row-milk"]; formScroll(milk, app: app)
        XCTAssertTrue(milk.label.contains("冷蔵")); XCTAssertFalse(app.buttons["inventory-row-canned_tuna"].exists)
        captureForm(app, "冷蔵庫の食材・調味料と分類タグ")
        let bulk = app.buttons["inventory-bulk"]; formScroll(bulk, app: app); bulk.tap()
        XCTAssertTrue(app.navigationBars["家にあるもの"].waitForExistence(timeout: 5)); app.buttons["bulk-skip"].tap()
        let receipt = app.buttons["inventory-receipt"]; formScroll(receipt, app: app); receipt.tap()
        XCTAssertTrue(app.navigationBars["レシートから登録"].waitForExistence(timeout: 5))
    }

    @MainActor func testCommonFoodsCanBeSearchedAndRegisteredTogether() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launch(); XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch
        for (query, key) in [("えのき", "enoki"), ("ぽんず", "ponzu"), ("みっくすべじ", "frozen_mixed_vegetables")] {
            formScroll(search, app: app)
            search.tap()
            let current = (search.value as? String) ?? ""
            if current != "食材・調味料を探す" && !current.isEmpty {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            search.typeText(query)
            let item = app.buttons["bulk-item-" + key]
            XCTAssertTrue(item.waitForExistence(timeout: 5)); formScroll(item, app: app)
            item.tap(); XCTAssertEqual(item.value as? String, "選択済み")
        }
        let save = app.buttons["bulk-save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.tabBars.buttons["マイ冷蔵庫"].waitForExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let enoki = app.buttons["inventory-row-enoki"], mixed = app.buttons["inventory-row-frozen_mixed_vegetables"]
        formScroll(enoki, app: app); XCTAssertTrue(enoki.label.contains("きのこ"))
        formScroll(mixed, app: app); XCTAssertTrue(mixed.label.contains("冷凍"))
        let group = app.buttons["inventory-group"]; formScroll(group, app: app)
        group.tap(); app.buttons["調味料"].firstMatch.tap()
        let ponzu = app.buttons["inventory-row-ponzu"]; formScroll(ponzu, app: app)
        XCTAssertTrue(ponzu.label.contains("ある")); XCTAssertTrue(ponzu.label.contains("調味料"))
        XCTAssertFalse(app.buttons["inventory-row-enoki"].exists)
        captureForm(app, "追加した一般食材の一括登録と分類")
    }

    @MainActor func testMoreCommonFoodsSearchRegisterAndKeepStorageTags() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launch(); XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch
        for (query, key) in [("なめこ", "nameko"), ("べーきんぐ", "baking_powder"), ("ふらいどぽてと", "frozen_french_fries")] {
            formScroll(search, app: app)
            search.tap()
            let current = (search.value as? String) ?? ""
            if current != "食材・調味料を探す" && !current.isEmpty {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            search.typeText(query)
            let item = app.buttons["bulk-item-" + key]
            XCTAssertTrue(item.waitForExistence(timeout: 5)); formScroll(item, app: app)
            item.tap(); XCTAssertEqual(item.value as? String, "選択済み")
        }
        let save = app.buttons["bulk-save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.tabBars.buttons["マイ冷蔵庫"].waitForExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let enoki = app.buttons["inventory-row-nameko"], mixed = app.buttons["inventory-row-frozen_french_fries"]
        formScroll(enoki, app: app); XCTAssertTrue(enoki.label.contains("きのこ"))
        formScroll(mixed, app: app); XCTAssertTrue(mixed.label.contains("冷凍"))
        let group = app.buttons["inventory-group"]; formScroll(group, app: app)
        group.tap(); app.buttons["調味料"].firstMatch.tap()
        let ponzu = app.buttons["inventory-row-baking_powder"]; formScroll(ponzu, app: app)
        XCTAssertTrue(ponzu.label.contains("ある")); XCTAssertTrue(ponzu.label.contains("調味料"))
        XCTAssertFalse(app.buttons["inventory-row-nameko"].exists)
        captureForm(app, "なめこ・冷凍ポテト・ベーキングパウダーの追加")
    }

}

@MainActor
extension XCUIApplication {
    func openMyPage() {
        tabBars.buttons["ホーム"].tap()
        if navigationBars["マイページ"].exists { return }
        for _ in 0..<6 {
            if buttons["home-menu"].exists { break }
            navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(buttons["home-menu"].waitForExistence(timeout: 5))
        buttons["home-menu"].tap()
        buttons["マイページ"].firstMatch.tap()
        XCTAssertTrue(navigationBars["マイページ"].waitForExistence(timeout: 5))
    }
}

final class MealPlanningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(large: Bool = false, seeded: Bool = false, archive: Bool = false, materials: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if seeded { app.launchArguments.append("--ui-week-plan-fixture") }
        if archive { app.launchArguments.append("--ui-archive-fixture") }
        if materials { app.launchArguments.append("--ui-materials-fixture") }
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication, down: Bool = false) {
        for _ in 0..<24 {
            var towardTop = down
            var distance: CGFloat?
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let footer = app.buttons["meal-material-add-shopping"]
            let bottom = footer.exists ? footer.frame.minY - 16 : app.tabBars.firstMatch.frame.minY
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
                if frame.minY < top { towardTop = true; distance = top - frame.minY + 8 }
                else if frame.maxY > bottom { towardTop = false; distance = frame.maxY - bottom + 8 }
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + (bottom - top) * (towardTop ? 0.25 : 0.75)
            let travel = min(max(distance ?? (bottom - top) * 0.5, 20), (bottom - top) * 0.5)
            let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: start))
            let to = origin.withOffset(CGVector(dx: app.frame.midX, dy: start + (towardTop ? travel : -travel)))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("対象を可視領域に表示できません")
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func addTuna(_ app: XCUIApplication, dayIndex: Int, twoServings: Bool) {
        let add = app.buttons["meal-tray-staple"]; reveal(add, app); add.tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("ツナマヨ")
        let recipe = app.buttons["plan-recipe-tuna_mayo_bowl"]; XCTAssertTrue(recipe.waitForExistence(timeout: 5)); recipe.tap()
        if twoServings {
            let increase = app.steppers["recipe-servings"].buttons["recipe-servings-Increment"]
            // Keep the control entirely above the fixed selection footer.
            for _ in 0..<18 {
                if increase.exists && increase.isHittable && increase.frame.maxY < app.buttons["recipe-select"].frame.minY - 8 { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43)))
            }
            increase.tap()
            XCTAssertTrue(app.steppers["recipe-servings"].label.contains("2人分"), app.steppers["recipe-servings"].debugDescription)
        }
        let select = app.buttons["recipe-select"]; XCTAssertTrue(select.waitForExistence(timeout: 5)); select.tap()
        XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-select"].exists)
    }
    @MainActor func testTodayMaterialsAndCancelReleasesStock() throws {
        let app = launch()
        app.tabBars.buttons["献立"].tap()
        XCTAssertFalse(app.segmentedControls["meal-plan-period"].exists)
        XCTAssertFalse(app.staticTexts["1週間"].exists)
        addTuna(app, dayIndex: 0, twoServings: true)
        let plate = app.buttons["meal-tray-staple"]; reveal(plate, app, down: true)
        XCTAssertTrue(plate.label.contains("ツナマヨ丼"))
        shot(app, "今日の献立・お盆に料理画像")
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app)
        XCTAssertTrue(summary.label.contains("1品の料理")); summary.tap()
        let rice = app.descendants(matching: .any).matching(identifier: "meal-material-cooked_rice-gram").firstMatch
        reveal(rice, app); XCTAssertTrue(rice.label.contains("400g")); XCTAssertTrue(rice.label.contains("不足 200g"))
        shot(app, "お盆の下の使用材料・不足量")
        app.navigationBars.buttons.firstMatch.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal-cancel-")).firstMatch
        reveal(cancel, app); cancel.tap(); XCTAssertFalse(app.buttons["献立を解除"].exists)
        reveal(plate, app, down: true); XCTAssertEqual(plate.label, "主食を選ぶ")
        reveal(summary, app); XCTAssertTrue(summary.label.contains("0品の料理"))
    }
    @MainActor func testSevenDaysFutureEmptyDayAndReturnToday() throws {
        let app = launch(seeded: true); app.tabBars.buttons["献立"].tap()
        let dates = (0..<7).map { app.buttons["meal-day-\($0)"] }
        XCTAssertEqual(dates[0].value as? String, "選択中")
        for index in 0..<6 { XCTAssertLessThan(dates[index].frame.minX, dates[index + 1].frame.minX) }
        shot(app, "今日が左端・7日間の日付とお盆")
        dates[1].tap(); XCTAssertEqual(app.staticTexts["meal-plan-day-title"].label, "明日の献立")
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app); summary.tap()
        let rice = app.descendants(matching: .any).matching(identifier: "meal-material-cooked_rice-gram").firstMatch
        reveal(rice, app); XCTAssertTrue(rice.label.contains("400g")); XCTAssertTrue(rice.label.contains("不足 400g"))
        shot(app, "明日の材料だけ・今日の予約を考慮")
        app.navigationBars.buttons.firstMatch.tap(); dates[2].tap()
        let staple = app.buttons["meal-tray-staple"]; reveal(staple, app, down: true); XCTAssertEqual(staple.label, "主食を選ぶ")
        staple.tap(); app.buttons["plan-recipe-plain_rice"].tap()
        app.buttons["recipe-add-shortages"].tap(); app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForNonExistence(timeout: 5))
        reveal(staple, app, down: true); XCTAssertTrue(staple.label.contains("ご飯"))
        app.buttons["meal-return-today"].tap(); XCTAssertEqual(app.staticTexts["meal-plan-day-title"].label, "今日の献立")
        XCTAssertTrue(staple.label.contains("ツナマヨ丼")); XCTAssertEqual(dates[0].value as? String, "選択中")
        dates[2].tap(); XCTAssertTrue(staple.label.contains("ご飯"))
    }
    @MainActor func testArchiveCompletedAndActiveMealsAreReadOnlyAndReturnToday() throws {
        let app = launch(archive: true); app.tabBars.buttons["買い物"].tap()
        let before = app.staticTexts["手入力の商品"].label
        XCTAssertEqual(before, "手入力の商品")
        app.tabBars.buttons["献立"].tap(); app.buttons["meal-archive-open"].tap()
        XCTAssertTrue(app.datePickers["meal-archive-calendar"].waitForExistence(timeout: 5))
        shot(app, "右上からカレンダーと過去の保存日")
        let saved = app.buttons["meal-archive-saved-0"]; reveal(saved, app); saved.tap()
        XCTAssertTrue(app.buttons["meal-return-today"].waitForExistence(timeout: 5))
        let rice = app.buttons["meal-tray-staple"]; reveal(rice, app, down: true)
        XCTAssertTrue(rice.label.contains("ご飯")); XCTAssertFalse(app.buttons["meal-tray-main"].isEnabled)
        shot(app, "過去の作った料理と未調理の料理")
        rice.tap(); XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-select"].exists); XCTAssertFalse(app.buttons["recipe-cook"].exists)
        XCTAssertFalse(app.buttons["recipe-cancel"].exists); XCTAssertFalse(app.buttons["recipe-add-shortages"].exists)
        shot(app, "過去のレシピは閲覧のみ")
        app.navigationBars.buttons.firstMatch.tap()
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app); summary.tap()
        XCTAssertTrue(app.navigationBars["使用材料"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["meal-material-period"].exists)
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["meal-return-today"].tap()
        XCTAssertEqual(app.staticTexts["meal-plan-day-title"].label, "今日の献立")
        app.tabBars.buttons["買い物"].tap(); XCTAssertEqual(app.staticTexts["手入力の商品"].label, before)
        XCTAssertFalse(app.staticTexts["冷ややっこ"].exists)
    }
    @MainActor func testHomeShoppingCheckboxDefaultsOnAndCanAddOff() throws {
        let app = launch()
        let checkbox = app.buttons["home-add-shortages"], add = app.buttons["home-recommendation-add"]
        reveal(checkbox, app); XCTAssertEqual(checkbox.value as? String, "オン")
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 44); checkbox.tap()
        XCTAssertEqual(checkbox.value as? String, "オフ"); reveal(add, app); add.tap()
        app.tabBars.buttons["献立"].tap()
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app)
        XCTAssertTrue(summary.label.contains("1品の料理")); XCTAssertFalse(summary.label.contains("材料0種類"))
        app.tabBars.buttons["買い物"].tap(); XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
    }
    @MainActor func testLargestDatesScrollToLastDayAndEmptyArchiveHasNoAdd() throws {
        let app = launch(large: true); app.tabBars.buttons["献立"].tap()
        let last = app.buttons["meal-day-6"], strip = app.scrollViews["meal-day-strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            let frame = last.frame
            if frame.width >= 44 && frame.height >= 44 && frame.minX >= 0 && frame.maxX <= app.frame.maxX { break }
            strip.swipeLeft()
        }
        XCTAssertTrue(last.isHittable); last.tap(); XCTAssertEqual(last.value as? String, "選択中")
        shot(app, "最大文字・横スクロールで7日目を選ぶ")
        let today = app.buttons["meal-return-today"]; reveal(today, app, down: true); today.tap()
        XCTAssertEqual(app.staticTexts["meal-plan-day-title"].label, "今日の献立")
        app.buttons["meal-archive-open"].tap()
        let select = app.buttons["meal-archive-select"]; reveal(select, app); select.tap()
        let main = app.buttons["meal-tray-main"]; reveal(main, app, down: true)
        XCTAssertFalse(main.isEnabled); XCTAssertEqual(main.label, "主菜、記録なし")
        shot(app, "最大文字・空の過去の日は追加できない")
        reveal(today, app, down: true); today.tap()
        XCTAssertTrue(main.isEnabled); XCTAssertEqual(main.label, "主菜を選ぶ")
    }
    @MainActor func testMaterialDayWeekCheckboxesAndBatchShoppingKeepManualItems() throws {
        let app = launch(materials: true); app.tabBars.buttons["献立"].tap()
        XCTAssertFalse(app.buttons["meal-day-0"].label.isEmpty)
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app); summary.tap()
        let period = app.segmentedControls["meal-material-period"]
        XCTAssertTrue(period.waitForExistence(timeout: 5)); XCTAssertFalse(app.segmentedControls["meal-material-filter"].exists)
        let rice = app.buttons["meal-material-cooked_rice-gram"]
        reveal(rice, app); XCTAssertTrue(rice.label.contains("400g")); XCTAssertTrue(rice.label.contains("不足 200g"))
        XCTAssertEqual(rice.value as? String, "選択")
        let dailyAdd = app.buttons["meal-material-add-shopping"]; XCTAssertTrue(dailyAdd.isHittable); dailyAdd.tap()
        XCTAssertTrue(app.staticTexts["meal-material-completion"].waitForExistence(timeout: 5))
        reveal(period, app, down: true); period.buttons["1週間分の材料"].tap(); reveal(rice, app)
        XCTAssertTrue(rice.label.contains("600g")); XCTAssertTrue(rice.label.contains("不足 400g"))
        XCTAssertTrue(rice.label.contains("一部追加済み"), rice.label)
        rice.tap(); XCTAssertEqual(rice.value as? String, "未選択")
        rice.tap(); XCTAssertEqual(rice.value as? String, "選択")
        let chicken = app.buttons["meal-material-chicken_thigh-gram"]
        reveal(chicken, app); XCTAssertEqual(chicken.value as? String, "未選択")
        XCTAssertTrue(chicken.label.contains("量を確認")); chicken.tap(); XCTAssertEqual(chicken.value as? String, "選択")
        shot(app, "1週間分・不足と量の確認を選んで買い物へ")
        let add = app.buttons["meal-material-add-shopping"]; XCTAssertTrue(add.isHittable); add.tap()
        let completion = app.staticTexts["meal-material-completion"]
        reveal(completion, app, down: true); XCTAssertTrue(completion.label.contains("品を追加しました"))
        XCTAssertEqual(add.label, "追加しました"); XCTAssertFalse(add.isEnabled)
        let addedRice = app.descendants(matching: .any).matching(identifier: "meal-material-cooked_rice-gram").firstMatch
        reveal(addedRice, app); XCTAssertTrue(addedRice.label.contains("買い物リストに追加済み"), addedRice.label)
        shot(app, "買い物追加後・材料に追加済みとチェック")
        app.navigationBars.buttons.firstMatch.tap()
        reveal(summary, app); summary.tap()
        reveal(addedRice, app); XCTAssertTrue(addedRice.label.contains("買い物リストに追加済み"), "Reopening preserves status from shopping data")
        shot(app, "材料を開き直しても追加済み")
        app.navigationBars.buttons.firstMatch.tap(); app.tabBars.buttons["買い物"].tap()
        let manual = app.staticTexts["保存する手入力"]; reveal(manual, app); XCTAssertEqual(manual.label, "保存する手入力")
        let boughtRice = app.staticTexts["ごはん"].firstMatch; reveal(boughtRice, app); XCTAssertTrue(boughtRice.exists)
        shot(app, "まとめて追加・手入力を保持")
        let shoppingRice = app.buttons["shopping-row-ごはん"].firstMatch; reveal(shoppingRice, app); shoppingRice.swipeLeft()
        let remove = app.buttons["削除"].firstMatch; XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        app.tabBars.buttons["献立"].tap(); reveal(summary, app); summary.tap()
        // Either day-scoped or week-scoped rice may be first in the shopping list.
        // Reopen the full week to verify the remaining shortage after deleting either purchase.
        XCTAssertTrue(period.waitForExistence(timeout: 5)); period.buttons["1週間分の材料"].tap()
        reveal(rice, app); XCTAssertTrue(rice.isEnabled)
        XCTAssertFalse(rice.label.contains("買い物リストに追加済み"))
        XCTAssertTrue(add.isEnabled)
        shot(app, "買い物から削除すると材料を再追加できる")
    }
    @MainActor func testLargestMaterialPeriodCheckboxAndAddStayTappable() throws {
        let app = launch(large: true, materials: true); app.tabBars.buttons["献立"].tap()
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app); summary.tap()
        let period = app.segmentedControls["meal-material-period"]; XCTAssertTrue(period.waitForExistence(timeout: 5))
        period.buttons["1週間分の材料"].tap()
        shot(app, "375pt最大文字・材料を開いた画面")
        let rice = app.buttons["meal-material-cooked_rice-gram"]; reveal(rice, app)
        XCTAssertGreaterThanOrEqual(rice.frame.height, 44); rice.tap(); XCTAssertEqual(rice.value as? String, "未選択")
        shot(app, "375pt最大文字・期間と不足チェック")
        let add = app.buttons["meal-material-add-shopping"]; XCTAssertTrue(add.isHittable); XCTAssertTrue(add.isEnabled)
        add.tap(); reveal(app.staticTexts["meal-material-completion"], app, down: true)
        shot(app, "375pt最大文字・一括追加の結果")
    }
    @MainActor func testEmptyPlatesChooseMatchingCoursesAndOpenSelectedRecipe() throws {
        let app = launch(); app.tabBars.buttons["献立"].tap()
        assertWidePlacement(app)
        shot(app, "横長のお盆・器の大小と箸")
        let choices = [("main", "teriyaki_chicken", "照り焼き"), ("side", "chilled_tofu", "冷ややっこ"),
                       ("staple", "tuna_mayo_bowl", "ツナマヨ"), ("soup", "tofu_wakame_miso_soup", "豆腐とわかめ")]
        for (course, key, query) in choices {
            let plate = app.buttons["meal-tray-" + course]; reveal(plate, app, down: true); plate.tap()
            XCTAssertFalse(app.buttons["plan-recipe-" + (course == "staple" ? "teriyaki_chicken" : "tuna_mayo_bowl")].exists)
            let titles = ["main": "主菜を選ぶ", "side": "副菜を選ぶ", "staple": "主食を選ぶ", "soup": "汁物を選ぶ"]
            XCTAssertTrue(app.navigationBars[titles[course]!].waitForExistence(timeout: 5))
            let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText(query)
            let recipe = app.buttons["plan-recipe-" + key]; XCTAssertTrue(recipe.waitForExistence(timeout: 5)); recipe.tap()
            let checkbox = app.buttons["recipe-add-shortages"]
            XCTAssertTrue(checkbox.waitForExistence(timeout: 5)); XCTAssertEqual(checkbox.value as? String, "オン")
            let select = app.buttons["recipe-select"]; XCTAssertTrue(select.waitForExistence(timeout: 5)); select.tap()
            XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForNonExistence(timeout: 5))
            reveal(plate, app, down: true); XCTAssertTrue(plate.label.contains("レシピを見る"))
        }
        let staple = app.buttons["meal-tray-staple"]; reveal(staple, app, down: true); shot(app, "四品を選んだお盆")
        staple.tap()
        let title = app.staticTexts["recipe-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, "ツナマヨ丼")
        shot(app, "料理の画像からレシピへ")
    }
    @MainActor func testMealPickerShowsCompactDateAndFridgeMatch() throws {
        let app = launch(); app.tabBars.buttons["献立"].tap()
        let plate = app.buttons["meal-tray-staple"]; reveal(plate, app, down: true); plate.tap()
        XCTAssertTrue(app.navigationBars["主食を選ぶ"].waitForExistence(timeout: 5))
        let date = app.staticTexts["meal-picker-date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(date.frame.midX, app.frame.midX)
        XCTAssertLessThanOrEqual(date.frame.maxY, app.navigationBars.firstMatch.frame.maxY)
        shot(app, "主食候補・右上の日付と冷蔵庫の一致率")
        let duplicateLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "主食"))
        for index in 0..<duplicateLabels.count { XCTAssertFalse(duplicateLabels.element(boundBy: index).isHittable) }
        let match = app.staticTexts["plan-candidate-plain_rice-match"]
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        XCTAssertTrue(match.label.contains("食材一致"))
        XCTAssertTrue(match.label.contains("%"))
    }
    @MainActor func testPlainRiceIllustrationMaterialsAndImmediateCancel() throws {
        let app = launch(); app.tabBars.buttons["献立"].tap()
        XCTAssertFalse(app.buttons["meal-plan-add-0"].exists)
        let staple = app.buttons["meal-tray-staple"]; staple.tap()
        let rice = app.buttons["plan-recipe-plain_rice"]; XCTAssertTrue(rice.waitForExistence(timeout: 5)); rice.tap()
        app.buttons["recipe-select"].tap(); XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForNonExistence(timeout: 5))
        shot(app, "ご飯を追加した直後")
        reveal(staple, app, down: true); XCTAssertTrue(staple.label.contains("ご飯"))
        shot(app, "ご飯は米粒と茶碗のイラスト")
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app); summary.tap()
        let material = app.descendants(matching: .any).matching(identifier: "meal-material-cooked_rice-gram").firstMatch
        reveal(material, app); XCTAssertTrue(material.label.contains("200g")); XCTAssertFalse(material.label.contains("不足"))
        app.navigationBars.buttons.firstMatch.tap(); reveal(staple, app, down: true); staple.tap()
        let cancel = app.buttons["recipe-cancel"]; XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["recipe-select"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["献立を解除"].exists)
        app.navigationBars.buttons.firstMatch.tap(); reveal(staple, app, down: true); XCTAssertEqual(staple.label, "主食を選ぶ")
    }
    @MainActor func testSideShoppingOffKeepsMaterialsAndNormalCooking() throws {
        let app = launch(); app.tabBars.buttons["献立"].tap()
        app.buttons["meal-tray-side"].tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("冷ややっこ")
        let recipe = app.buttons["plan-recipe-chilled_tofu"]; XCTAssertTrue(recipe.waitForExistence(timeout: 5)); recipe.tap()
        let checkbox = app.buttons["recipe-add-shortages"]; XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        XCTAssertEqual(checkbox.value as? String, "オン"); checkbox.tap()
        XCTAssertEqual(checkbox.value as? String, "オフ"); shot(app, "副菜も同じチェック・買い物追加オフ")
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForNonExistence(timeout: 5))
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app)
        XCTAssertTrue(summary.label.contains("1品の料理")); XCTAssertFalse(summary.label.contains("材料0種類"))
        app.tabBars.buttons["買い物"].tap()
        XCTAssertTrue(app.staticTexts["買うものはまだありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["献立"].tap()
        let plate = app.buttons["meal-tray-side"]; reveal(plate, app, down: true); plate.tap()
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        let cook = app.buttons["recipe-cook"]; XCTAssertTrue(cook.waitForExistence(timeout: 5)); cook.tap()
        XCTAssertTrue(app.navigationBars["調理後の在庫"].waitForExistence(timeout: 5))
        shot(app, "買い物を追加しなくても調理後の在庫を更新できる")
    }
    @MainActor func testLargestShoppingCheckboxIsReadableAndDoesNotOpenConfirmation() throws {
        let app = launch(large: true); app.tabBars.buttons["献立"].tap()
        let side = app.buttons["meal-tray-side"]; reveal(side, app); side.tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("冷ややっこ\n")
        let recipe = app.buttons["plan-recipe-chilled_tofu"]; XCTAssertTrue(recipe.waitForExistence(timeout: 5)); recipe.tap()
        let select = app.buttons["recipe-select"]; XCTAssertTrue(select.waitForExistence(timeout: 5))
        let checkbox = app.buttons["recipe-add-shortages"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5)); XCTAssertTrue(checkbox.isHittable)
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 44); XCTAssertEqual(checkbox.value as? String, "オン")
        checkbox.tap(); XCTAssertEqual(checkbox.value as? String, "オフ")
        XCTAssertTrue(select.isHittable); shot(app, "375pt最大文字・追加ボタン上の単独チェック")
        select.tap(); XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["副菜の追加"].exists)
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app)
        XCTAssertTrue(summary.label.contains("1品の料理"))
    }
    @MainActor private func assertWidePlacement(_ app: XCUIApplication) {
        let main = app.buttons["meal-tray-main"].frame
        let rice = app.buttons["meal-tray-staple"].frame
        let side = app.buttons["meal-tray-side"].frame
        let soup = app.buttons["meal-tray-soup"].frame
        XCTAssertEqual(main.midX, app.frame.midX, accuracy: 2, "主菜はトレイの中央")
        XCTAssertLessThan(rice.midX, main.midX); XCTAssertGreaterThan(rice.midY, main.midY)
        XCTAssertGreaterThan(side.midX, main.midX); XCTAssertLessThan(side.midY, soup.midY)
        XCTAssertGreaterThan(soup.midX, rice.midX); XCTAssertGreaterThan(main.width, rice.width)
        XCTAssertGreaterThan(rice.width, side.width)
        for f in [main, rice, side, soup] { XCTAssertGreaterThanOrEqual(f.width, 44); XCTAssertGreaterThanOrEqual(f.height, 44) }
        for (a, b) in [(main, rice), (main, side), (main, soup), (rice, soup), (side, soup)] {
            // Circular dishes can overlap bounding-box corners; their visible centers must stay independent.
            XCTAssertFalse(a.contains(CGPoint(x: b.midX, y: b.midY)), "ほかの器の中央を覆わない")
            XCTAssertFalse(b.contains(CGPoint(x: a.midX, y: a.midY)), "ほかの器の中央を覆わない")
        }
    }
    @MainActor func testNarrowWideTrayAllFourPlatesStayTappable() throws {
        let app = launch(seeded: true); app.tabBars.buttons["献立"].tap()
        shot(app, "375pt通常文字・横長のお盆と主食画像"); assertWidePlacement(app)
        app.buttons["meal-tray-staple"].tap()
        let title = app.staticTexts["recipe-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, "ツナマヨ丼")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["meal-tray-soup"].tap()
        XCTAssertTrue(app.navigationBars["汁物を選ぶ"].waitForExistence(timeout: 5))
        app.buttons["meal-picker-close"].tap()
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app)
        summary.tap(); XCTAssertTrue(app.navigationBars["使用材料・不足"].waitForExistence(timeout: 5))
    }
    @MainActor func testMyPageOpensFromHomeMenuAndTabsKeepNewOrder() throws {
        let app = launch()
        let tabs = app.tabBars.buttons
        XCTAssertEqual(tabs.count, 4)
        XCTAssertEqual(tabs.element(boundBy: 0).label, "ホーム"); XCTAssertEqual(tabs.element(boundBy: 1).label, "献立")
        XCTAssertEqual(tabs.element(boundBy: 2).label, "マイ冷蔵庫"); XCTAssertEqual(tabs.element(boundBy: 3).label, "買い物")
        shot(app, "ホーム左上にメニュー・献立を2番目のタブへ")
        app.openMyPage()
        XCTAssertTrue(app.buttons["settings-default-servings"].exists); shot(app, "ホームのメニューからマイページ")
        app.tabBars.buttons["献立"].tap(); XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
    }
    @MainActor func testLargestTrayAndMaterialShortagesStayReadable() throws {
        let app = launch(large: true, seeded: true)
        app.tabBars.buttons["献立"].tap()
        let dates = app.scrollViews["meal-day-strip"]
        let last = app.buttons["meal-day-6"]
        for _ in 0..<8 {
            let frame = last.frame
            if frame.width > 0 && frame.minX >= dates.frame.minX && frame.maxX <= dates.frame.maxX { break }
            dates.swipeLeft()
        }
        last.tap(); XCTAssertEqual(last.value as? String, "選択中")
        app.buttons["meal-return-today"].tap()
        let today = app.buttons["meal-day-0"]
        for _ in 0..<8 {
            let frame = today.frame
            if frame.width > 0 && frame.minX >= dates.frame.minX && frame.maxX <= dates.frame.maxX { break }
            dates.swipeRight()
        }
        XCTAssertEqual(today.value as? String, "選択中")
        shot(app, "375pt最大文字・お盆を一列にして器と文字を保持")
        let main = app.buttons["meal-tray-main"]; reveal(main, app, down: true); main.tap()
        XCTAssertTrue(app.navigationBars["主菜を選ぶ"].waitForExistence(timeout: 5))
        app.buttons["meal-picker-close"].tap()
        let summary = app.buttons["meal-plan-materials"]; reveal(summary, app)
        XCTAssertTrue(summary.label.contains("1品の料理")); shot(app, "最大文字・今日のお盆と材料の入口")
        summary.tap()
        let rice = app.descendants(matching: .any).matching(identifier: "meal-material-cooked_rice-gram").firstMatch
        reveal(rice, app); XCTAssertTrue(rice.label.contains("200g")); XCTAssertFalse(rice.label.contains("不足")); shot(app, "最大文字・明日の献立は合算しない")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["ホーム"].tap(); app.openMyPage()
        XCTAssertTrue(app.buttons["settings-default-servings"].isHittable); shot(app, "最大文字・メニューからマイページ")
    }
}
