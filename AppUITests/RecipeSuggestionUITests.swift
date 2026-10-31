import XCTest

final class RecipeSuggestionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testWesternRecipesAppearWithImagesAndStepsAcrossCourses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        for (key, title) in [("pork_chap", "ポークチャップ"), ("german_potato", "ジャーマンポテト"), ("corn_potage", "コーンポタージュ")] {
            app.launch()
            let all = app.buttons["home-recipe-entry"]; scrollTo(all, app: app); all.tap()
            choose("recipe-kind-filter", option: "すべて", app: app, towardTop: true)
            let search = app.searchFields.firstMatch; scrollTo(search, app: app, towardTop: true)
            search.tap(); search.typeText(title + "\n")
            let row = app.buttons["recipe-" + key]; scrollTo(row, app: app)
            capture(app, "洋風追加・一覧・" + key); row.tap()
            let heading = app.staticTexts["recipe-detail-title"]
            XCTAssertTrue(heading.waitForExistence(timeout: 5)); XCTAssertEqual(heading.label, title)
            XCTAssertTrue(app.staticTexts["recipe-time-total"].exists)
            capture(app, "洋風追加・詳細・" + key)
            let mode = app.segmentedControls["recipe-detail-mode"]; scrollTo(mode, app: app)
            mode.buttons["作り方"].tap()
            let first = app.staticTexts["recipe-step-text-1"]; scrollTo(first, app: app)
            XCTAssertFalse(first.label.isEmpty); capture(app, "洋風追加・作り方・" + key)
            app.terminate()
        }
    }
    @MainActor func testPorkThighRecipesAppearWithImagesAndDetailedSteps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        for (key, title) in [("pork_thigh_ginger", "豚ももの生姜焼き"),
                             ("pork_thigh_bowl", "豚ももの豚丼"),
                             ("pork_thigh_sprout_steam", "豚ももともやしの蒸ししゃぶ")] {
            app.launch()
            let all = app.buttons["home-recipe-entry"]; scrollTo(all, app: app); all.tap()
            choose("recipe-kind-filter", option: "すべて", app: app, towardTop: true)
            let search = app.searchFields.firstMatch; scrollTo(search, app: app, towardTop: true)
            search.tap(); search.typeText(title + "\n")
            let row = app.buttons["recipe-" + key]; scrollTo(row, app: app)
            capture(app, "豚もも・一覧・" + key); row.tap()
            let heading = app.staticTexts["recipe-detail-title"]
            XCTAssertTrue(heading.waitForExistence(timeout: 5)); XCTAssertEqual(heading.label, title)
            XCTAssertTrue(app.staticTexts["recipe-time-total"].exists)
            capture(app, "豚もも・詳細・" + key)
            let mode = app.segmentedControls["recipe-detail-mode"]; scrollTo(mode, app: app)
            mode.buttons["作り方"].tap()
            let first = app.staticTexts["recipe-step-text-1"]; scrollTo(first, app: app)
            XCTAssertFalse(first.label.isEmpty); capture(app, "豚もも・作り方・" + key)
            app.terminate()
        }
    }
    @MainActor func testNapaRecipesAppearWithPhotosAcrossCourses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        for (key, query) in [("napa_pork_layered_pot", "白菜と豚バラのミルフィーユ鍋"),
                             ("napa_sesame_side", "白菜のごま和え"),
                             ("napa_enoki_miso_soup", "白菜とえのきのみそ汁")] {
            app.launch()
            let all = app.buttons["home-recipe-entry"]; scrollTo(all, app: app); all.tap()
            choose("recipe-kind-filter", option: "すべて", app: app, towardTop: true)
            let search = app.searchFields.firstMatch; scrollTo(search, app: app, towardTop: true)
            search.tap(); search.typeText(query + "\n")
            let row = app.buttons["recipe-" + key]; scrollTo(row, app: app); row.tap()
            let title = app.staticTexts["recipe-detail-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, query)
            XCTAssertTrue(app.staticTexts["recipe-time-total"].exists)
            capture(app, "白菜レシピ・" + key)
            app.terminate()
        }
    }
    @MainActor func testFridgeCategoryIconsKeepRowsCompactAndExpiryFooterIsRemoved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact", "--ui-fridge-frame-fixture"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["マイ冷蔵庫"].waitForExistence(timeout: 15))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        app.buttons["inventory-search-toggle"].tap()
        let search = app.textFields["inventory-search"]
        for (index, pair) in [("shimeji", "しめじ"), ("tofu", "豆腐"), ("frozen_udon", "うどん"), ("canned_tuna", "ツナ")].enumerated() {
            if index > 0 { app.buttons["inventory-list-search-clear"].tap() }
            search.tap(); search.typeText(pair.1 + "\n")
            let row = app.buttons["inventory-row-" + pair.0]; XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(row.frame.height, 52); XCTAssertLessThanOrEqual(row.frame.height, 68)
            capture(app, "冷蔵庫・ジャンルアイコン・" + pair.0)
        }
        app.openMyPage(); let settings = app.buttons["期限通知"]; scrollTo(settings, app: app); settings.tap()
        XCTAssertTrue(app.navigationBars["期限通知"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "全食材に共通の設定です")).firstMatch.exists)
        capture(app, "期限通知・補足文を削除")
    }
    @MainActor func testRecipeBasketRegistersFoundStockAndRefreshesDetail() throws { try foundStockFlow(large: false) }
    @MainActor func testLargestRecipeBasketRegistersFoundStockAndRefreshesDetail() throws { try foundStockFlow(large: true) }
    @MainActor func testAddedSaladsAppearWithImagesInListAndDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        for (key, query) in [("cobb_salad", "コブサラダ"),
                             ("chinese_glass_noodle_salad", "中華風春雨サラダ"),
                             ("pumpkin_salad", "かぼちゃサラダ")] {
            app.launch()
            let all = app.buttons["home-recipe-entry"]; scrollTo(all, app: app); all.tap()
            choose("recipe-kind-filter", option: "副菜", app: app, towardTop: true)
            let search = app.searchFields.firstMatch; scrollTo(search, app: app, towardTop: true)
            search.tap(); search.typeText(query + "\n")
            let row = app.buttons["recipe-" + key]; scrollTo(row, app: app)
            capture(app, "サラダ・一覧・" + key); row.tap()
            let title = app.staticTexts["recipe-detail-title"]
            expectation(for: NSPredicate { _, _ in title.exists && title.frame.minX < 40 }, evaluatedWith: title)
            waitForExpectations(timeout: 5)
            XCTAssertEqual(title.label, query)
            XCTAssertTrue(app.staticTexts["recipe-time-total"].exists)
            capture(app, "サラダ・詳細・" + key)
            app.terminate()
        }
    }
    @MainActor private func foundStockFlow(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let all = app.buttons["home-recipe-entry"]; scrollTo(all, app: app); all.tap()
        choose("recipe-kind-filter", option: "すべて", app: app, towardTop: true)
        let search = app.searchFields.firstMatch; scrollTo(search, app: app, towardTop: true)
        search.tap(); search.typeText("シーザーサラダ\n")
        let recipe = app.buttons["recipe-caesar_salad"]; scrollTo(recipe, app: app)
        capture(app, large ? "最大文字・サラダ一覧" : "サラダ一覧")
        recipe.tap(); XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        let basket = app.buttons["recipe-detail-shortages"]; scrollTo(basket, app: app)
        capture(app, "タップ前・買い足しのカゴ"); basket.tap()
        capture(app, "タップ後・冷蔵庫に追加")
        XCTAssertTrue(app.buttons["recipe-stock-add-cancel"].waitForExistence(timeout: 5), app.debugDescription)
        let lettuce = app.buttons["recipe-stock-choose-lettuce"]; scrollTo(lettuce, app: app); lettuce.tap()
        let save = app.buttons["recipe-stock-add-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.textFields["recipe-stock-add-quantity"].exists)
        capture(app, large ? "最大文字・見つかった食材の追加" : "カゴから冷蔵庫へ追加")
        app.buttons["recipe-stock-add-cancel"].tap()
        let lettuceBasket = app.buttons["recipe-stock-add-lettuce"]; scrollTo(lettuceBasket, app: app); lettuceBasket.tap()
        app.segmentedControls["recipe-stock-add-mode"].buttons["数量"].tap()
        let quantity = app.textFields["recipe-stock-add-quantity"]; scrollTo(quantity, app: app)
        XCTAssertFalse(save.isEnabled)
        quantity.tap(); quantity.typeText("80")
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertFalse(lettuceBasket.exists)
        capture(app, large ? "最大文字・レタスの不足を解消" : "追加後に不足表示を更新")
        let bread = app.buttons["recipe-stock-add-bread"]; scrollTo(bread, app: app); bread.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        let breadPeek = app.buttons["recipe-stock-peek-bread"]; scrollTo(breadPeek, app: app)
        XCTAssertTrue(breadPeek.exists)
        let mayo = app.buttons["recipe-stock-add-olive_oil"]; scrollTo(mayo, app: app); mayo.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["recipe-stock-add-mode"].exists)
        let states = app.segmentedControls["recipe-stock-add-state"]
        for label in ["あり", "少なめ", "なし"] { XCTAssertTrue(states.buttons[label].exists) }
        capture(app, large ? "最大文字・調味料の在庫登録" : "調味料は3状態で登録")
        save.tap(); XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertFalse(mayo.exists)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let stock = app.buttons["inventory-row-lettuce"]; scrollTo(stock, app: app)
        XCTAssertTrue(stock.label.contains("80g"))
    }
    @MainActor func testRecipePhotosAndImageCreditsAreVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        app.launch()
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app)
        XCTAssertTrue(hero.label.contains("ツナマヨ丼")); capture(app, "料理別画像・ホーム")
        hero.tap(); XCTAssertTrue(app.staticTexts["recipe-time-total"].waitForExistence(timeout: 5))
        capture(app, "料理別画像・生成したツナマヨ丼")
        app.navigationBars.buttons.firstMatch.tap()
        let all = app.buttons["home-recipes"]; scrollTo(all, app: app); all.tap()
        XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
        let beef = app.buttons["recipe-gyudon"]; scrollTo(beef, app: app); beef.tap()
        XCTAssertTrue(app.staticTexts["recipe-time-total"].waitForExistence(timeout: 5))
        capture(app, "料理別画像・フリー素材の牛丼")
        app.openMyPage()
        let credits = app.buttons["settings-photo-credits"]; scrollTo(credits, app: app); credits.tap()
        XCTAssertTrue(app.navigationBars["画像の出典"].waitForExistence(timeout: 5))
        let source = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "写真の出典")).firstMatch; scrollTo(source, app: app)
        XCTAssertTrue(source.exists)
        let creator = app.staticTexts["Ocdp"].firstMatch; scrollTo(creator, app: app)
        XCTAssertTrue(creator.exists); capture(app, "料理画像の作者・出典・利用条件")
    }

    @MainActor func testAddedMainSoupAndNoodlePhotosAppearInListAndDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        for (key, query) in [("chicken_yurinchi", "油淋鶏"),
                             ("chicken_seri_soup", "鶏だんごとせり"),
                             ("chicken_soba", "鶏南蛮そば")] {
            app.launch()
            let all = app.buttons["home-recipes"]; scrollTo(all, app: app); all.tap()
            XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
            choose("recipe-kind-filter", option: "すべて", app: app, towardTop: true)
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(query)
            let row = app.buttons["recipe-" + key]
            XCTAssertTrue(row.waitForExistence(timeout: 5)); capture(app, "追加画像・一覧・" + key)
            row.tap()
            XCTAssertTrue(app.staticTexts["recipe-time-total"].waitForExistence(timeout: 5))
            capture(app, "追加画像・詳細・" + key)
            app.terminate()
        }
    }

    @MainActor func testFrenchItalianRecipesAppearWithPhotosInListAndDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        for (key, query) in [("cod_acqua_pazza", "アクアパッツァ"),
                             ("caprese_salad", "カプレーゼ"),
                             ("vegetable_minestrone", "野菜たっぷりミネストローネ")] {
            app.launch()
            let all = app.buttons["home-recipes"]; scrollTo(all, app: app); all.tap()
            XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
            choose("recipe-kind-filter", option: "すべて", app: app, towardTop: true)
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(query)
            let row = app.buttons["recipe-" + key]
            XCTAssertTrue(row.waitForExistence(timeout: 5)); capture(app, "仏伊料理・一覧・" + key)
            row.tap()
            XCTAssertTrue(app.staticTexts["recipe-time-total"].waitForExistence(timeout: 5))
            capture(app, "仏伊料理・詳細・" + key)
            app.terminate()
        }
    }

    @MainActor func testRequiredIngredientAliasAndShortagesReachShopping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        app.launch()
        selectIngredient("canned_tuna", search: "シーチキン", app: app)
        XCTAssertEqual(app.buttons["recipe-ingredient-picker"].value as? String, "ツナ缶")
        capture(app, "必ず使う食材と献立候補")
        let hero = app.buttons["home-recipe-hero"]
        scrollTo(hero, app: app)
        XCTAssertTrue(hero.label.contains("ツナマヨ丼")); hero.tap()
        let increase = app.steppers["recipe-servings"].buttons["recipe-servings-Increment"]
        scrollTo(increase, app: app); increase.tap()
        XCTAssertTrue(app.buttons["recipe-detail-shortages"].label.contains("買い足し 2品"))
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        app.tabBars.buttons["買い物"].tap()
        XCTAssertTrue(app.buttons["shopping-row-ごはん"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shopping-row-ツナ缶"].exists)
        capture(app, "食材指定から不足材料を買い物へ")
    }
    @MainActor func testIngredientWithoutRecipesShowsEmptyAndClearingRestoresHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]; app.launch()
        selectIngredient("blueberries", search: "ブルーベリー", app: app)
        let empty = app.staticTexts["home-ingredient-empty"]
        scrollTo(empty, app: app); XCTAssertFalse(app.buttons["home-recipe-hero"].exists)
        let recipes = app.buttons["home-recipes"]
        scrollTo(recipes, app: app); recipes.tap()
        XCTAssertTrue(app.staticTexts["recipe-filter-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-tuna_mayo_bowl"].exists)
        app.buttons["recipe-ingredient-clear"].tap()
        scrollTo(app.buttons["recipe-tuna_mayo_bowl"], app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let hero = app.buttons["home-recipe-hero"]
        scrollTo(hero, app: app, towardTop: true)
        XCTAssertTrue(hero.label.contains("ツナマヨ丼"))
        XCTAssertFalse(app.buttons["recipe-ingredient-clear"].exists)
    }
    @MainActor func testRecipeKindsWithoutPurposeTagsAndCompactCooking() throws { try recipeKindsFlow(large: false) }
    @MainActor func testLargestRecipeKindsWithoutPurposeTagsAndCompactCooking() throws { try recipeKindsFlow(large: true) }
    @MainActor private func recipeKindsFlow(large: Bool) throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let entry = app.buttons["home-recipe-entry"]; XCTAssertTrue(entry.waitForExistence(timeout: 15))
        capture(app, large ? "最大文字・シンプルなおすすめ見出し" : "シンプルなおすすめ見出し")
        scrollTo(entry, app: app, towardTop: true); entry.tap()
        XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
        if !large { XCTAssertLessThan(app.navigationBars["レシピ"].staticTexts["レシピ"].frame.height, 35) }
        XCTAssertFalse(app.buttons["recipe-focus-filter"].exists)
        for tag in ["筋トレ", "低カロリー", "時短"] { XCTAssertFalse(app.staticTexts[tag].exists) }
        choose("recipe-kind-filter", option: "主食・主菜", app: app)
        let search = app.searchFields.firstMatch; scrollTo(search, app: app, towardTop: true)
        search.tap(); search.typeText("たらときのこ\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let fish = app.buttons["recipe-cod_mushroom_foil"]; scrollTo(fish, app: app)
        capture(app, large ? "最大文字・目的タグなしのレシピ一覧" : "目的タグなしのレシピ一覧")
        fish.tap(); XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recipe-detail-title"].label, "たらときのこのホイル蒸し")
        for tag in ["筋トレ", "低カロリー", "時短"] { XCTAssertFalse(app.buttons[tag + "の目安"].exists) }
        app.navigationBars.buttons.firstMatch.tap()
        let closeSearch = app.navigationBars.buttons["閉じる"]
        if closeSearch.exists { closeSearch.tap() }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        scrollTo(entry, app: app, towardTop: true); entry.tap()
        XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
        choose("recipe-kind-filter", option: "副菜", app: app, towardTop: true)
        let side = app.buttons["recipe-chilled_tofu"]; scrollTo(side, app: app); XCTAssertTrue(side.exists)
        app.navigationBars.buttons.firstMatch.tap()
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app); hero.tap()
        app.buttons["recipe-select"].tap()
        let cook = app.buttons["recipe-cook"].firstMatch; scrollTo(cook, app: app); cook.tap()
        XCTAssertTrue(app.navigationBars["調理後の在庫"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cooking-options"].exists)
        let expand = app.descendants(matching: .any).matching(identifier: "cooking-expand-cooked_rice").firstMatch
        scrollTo(expand, app: app); expand.tap()
        let quantity = app.textFields["cooking-quantity-cooked_rice"]; scrollTo(quantity, app: app)
        XCTAssertTrue(quantity.exists); XCTAssertTrue(quantity.label.contains("g"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "使用 ")).firstMatch.exists)
        capture(app, large ? "最大文字・横並びの在庫入力" : "使った量と単位を横並びに")
        let skip = app.buttons["cooking-skip-stock"]; XCTAssertTrue(skip.isHittable); skip.tap()
        XCTAssertTrue(app.buttons["cooking-save"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let stock = app.buttons["inventory-row-cooked_rice"]; scrollTo(stock, app: app); XCTAssertTrue(stock.label.contains("200g"))
    }
    @MainActor func testCompactIngredientCategorySortAndNewThighRecipe() throws { try thighFlow(large: false) }
    @MainActor func testLargestCompactIngredientCategorySortAndNewThighRecipe() throws { try thighFlow(large: true) }
    @MainActor private func thighFlow(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let picker = app.buttons["recipe-ingredient-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15)); picker.tap()
        XCTAssertEqual(app.buttons["ingredient-filter-controls"].value as? String, "閉じています")
        XCTAssertTrue(app.buttons["ingredient-category-filter"].exists)
        choose("ingredient-sort", option: "種類順", app: app)
        choose("ingredient-sort", option: "名前順", app: app)
        choose("ingredient-sort", option: "冷蔵庫優先", app: app)
        choose("ingredient-category-filter", option: "肉", app: app)
        capture(app, large ? "最大文字・コンパクトな種類と並べ替え" : "コンパクトな種類と並べ替え")
        let field = app.searchFields.firstMatch
        scrollTo(field, app: app, towardTop: true); field.tap(); field.typeText("とりもも")
        let chicken = app.buttons["recipe-ingredient-chicken_thigh"]
        XCTAssertTrue(chicken.waitForExistence(timeout: 5)); scrollTo(chicken, app: app); chicken.tap()
        XCTAssertTrue(app.navigationBars["今日何作る？"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value == %@", "鶏もも肉"), evaluatedWith: picker)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(picker.value as? String, "鶏もも肉")
        let entry = app.buttons["home-recipe-entry"]; scrollTo(entry, app: app, towardTop: true); entry.tap()
        XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("油淋鶏\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let dish = app.buttons["recipe-chicken_yurinchi"]; scrollTo(dish, app: app); dish.tap()
        XCTAssertEqual(app.staticTexts["recipe-detail-title"].label, "油淋鶏")
        let increase = app.steppers["recipe-servings"].buttons["recipe-servings-Increment"]
        scrollTo(increase, app: app); increase.tap()
        let instructions = app.segmentedControls["recipe-detail-mode"].buttons["作り方"]
        scrollTo(instructions, app: app); instructions.tap()
        let first = app.staticTexts["recipe-step-ingredients-1"]; scrollTo(first, app: app)
        XCTAssertTrue(first.label.contains("鶏もも肉 360g"), first.label)
        let safety = app.staticTexts["recipe-step-text-4"]; scrollTo(safety, app: app)
        XCTAssertTrue(safety.label.contains("75℃")); XCTAssertTrue(safety.label.contains("1分"))
        let finish = app.buttons["recipe-step-5"]; scrollTo(finish, app: app)
        capture(app, large ? "最大文字・油淋鶏の工程" : "油淋鶏の工程と2人分")
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        app.tabBars.buttons["買い物"].tap()
        let purchase = app.buttons["shopping-row-鶏もも肉"]; scrollTo(purchase, app: app)
        XCTAssertTrue(purchase.label.contains("360g"), purchase.label)
        XCTAssertFalse(app.buttons["inventory-undo"].exists)
    }

    @MainActor func testNewChickenRecipeFromIngredientShowsScaledInstructionsAndShopping() throws {
        try newChickenRecipe(large: false)
    }
    @MainActor func testLargestNewChickenRecipeShowsLastStep() throws {
        try newChickenRecipe(large: true)
    }
    @MainActor private func newChickenRecipe(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        selectIngredient("chicken_breast", search: "とりむね", app: app)
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app)
        XCTAssertTrue(hero.label.contains("棒々鶏")); hero.tap()
        let servings = app.steppers["recipe-servings"]
        let increase = servings.buttons["recipe-servings-Increment"]
        scrollTo(increase, app: app); increase.tap()
        let modes = app.segmentedControls["recipe-detail-mode"]
        let instructions = modes.buttons["作り方"]
        scrollTo(instructions, app: app); instructions.tap()
        let first = app.buttons["recipe-step-1"]; scrollTo(first, app: app)
        XCTAssertTrue(first.label.contains("約5分"))
        let ingredients = app.staticTexts["recipe-step-ingredients-1"]; scrollTo(ingredients, app: app)
        XCTAssertTrue(ingredients.label.contains("鶏むね肉 300g"), ingredients.label)
        let last = app.buttons["recipe-step-4"]; scrollTo(last, app: app)
        XCTAssertTrue(last.label.contains("約2分"))
        let finish = app.staticTexts["recipe-step-text-4"]; scrollTo(finish, app: app)
        XCTAssertTrue(finish.label.contains("ごまドレッシング"))
        capture(app, large ? "最大文字・追加した棒々鶏の仕上げ" : "追加した棒々鶏・2人分と工程時間")
        if !large {
            app.buttons["recipe-select"].tap()
            XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
            app.tabBars.buttons["買い物"].tap()
            let chicken = app.buttons["shopping-row-鶏むね肉"]; scrollTo(chicken, app: app)
            XCTAssertTrue(chicken.label.contains("300g"), chicken.label)
            XCTAssertFalse(app.buttons["shopping-row-水"].exists)
            capture(app, "追加レシピから2人分の食材を買い物へ")
        }
    }

    @MainActor func testUnusedWingIngredientReachesScaledInstructionsAndShopping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        app.launch()
        selectIngredient("chicken_wings", search: "てばさき", app: app)
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app)
        XCTAssertTrue(hero.label.contains("手羽先の七味しょうゆ焼き")); hero.tap()
        let increase = app.steppers["recipe-servings"].buttons["recipe-servings-Increment"]
        scrollTo(increase, app: app); increase.tap()
        let mode = app.segmentedControls["recipe-detail-mode"].buttons["作り方"]
        scrollTo(mode, app: app); mode.tap()
        let ingredients = app.staticTexts["recipe-step-ingredients-1"]; scrollTo(ingredients, app: app)
        XCTAssertTrue(ingredients.label.contains("鶏手羽先 360g"), ingredients.label)
        let last = app.buttons["recipe-step-3"]; scrollTo(last, app: app)
        XCTAssertTrue(last.label.contains("約2分"))
        let finish = app.staticTexts["recipe-step-text-3"]; scrollTo(finish, app: app)
        XCTAssertTrue(finish.label.contains("七味"))
        capture(app, "未使用食材・手羽先の分量と工程")
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        app.tabBars.buttons["買い物"].tap()
        let row = app.buttons["shopping-row-鶏手羽先"]; scrollTo(row, app: app)
        XCTAssertTrue(row.label.contains("360g"), row.label)
        XCTAssertFalse(app.buttons["shopping-row-水"].exists)
        capture(app, "未使用食材・手羽先を買い物へ")
    }
    @MainActor func testLargestUnusedZucchiniSideRecipeShowsFinalInstructions() throws {
        let app = launchLargest(exact: true)
        selectIngredient("zucchini", search: "ずっきーに", app: app)
        choose("recipe-kind-filter", option: "副菜", app: app)
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app, towardTop: true)
        XCTAssertTrue(hero.label.contains("野菜のラタトゥイユ")); hero.tap()
        let mode = app.segmentedControls["recipe-detail-mode"].buttons["作り方"]
        scrollTo(mode, app: app); mode.tap()
        let first = app.buttons["recipe-step-1"]; scrollTo(first, app: app)
        XCTAssertTrue(first.label.contains("約6分"))
        let ingredients = app.staticTexts["recipe-step-ingredients-1"]; scrollTo(ingredients, app: app)
        XCTAssertTrue(ingredients.label.contains("ズッキーニ 60g"), ingredients.label)
        let last = app.buttons["recipe-step-3"]; scrollTo(last, app: app)
        XCTAssertTrue(last.label.contains("約13分"))
        let finish = app.staticTexts["recipe-step-text-3"]; scrollTo(finish, app: app)
        XCTAssertTrue(finish.label.contains("野菜が柔らかく"))
        capture(app, "最大文字・ズッキーニの料理と仕上げ")
    }

    @MainActor func testLargestIngredientChoiceAndResetRemainReachable() throws {
        let app = launchLargest(exact: false)
        selectIngredient("egg", search: "たまご", app: app)
        let picker = app.buttons["recipe-ingredient-picker"]
        XCTAssertEqual(picker.value as? String, "卵")
        capture(app, "最大文字・必ず使う食材")
        let hero = app.buttons["home-recipe-hero"]
        scrollTo(hero, app: app)
        XCTAssertFalse(hero.label.contains("ツナマヨ丼"))
        let clear = app.buttons["recipe-ingredient-clear"]
        scrollTo(clear, app: app, towardTop: true); clear.tap()
        scrollTo(picker, app: app, towardTop: true)
        XCTAssertEqual(picker.value as? String, "指定なし")
        scrollTo(hero, app: app); XCTAssertTrue(hero.label.contains("ツナマヨ丼"))
    }
    @MainActor private func selectIngredient(_ key: String, search: String, app: XCUIApplication) {
        let picker = app.buttons["recipe-ingredient-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15)); scrollTo(picker, app: app, towardTop: true); picker.tap()
        XCTAssertTrue(app.navigationBars["食材を選ぶ"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(search)
        let row = app.buttons["recipe-ingredient-" + key]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.navigationBars["今日何作る？"].waitForExistence(timeout: 5))
    }
    @MainActor func testRoughHundredPercentExplainsConfirmationAndSeparatesExpiredStock() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]; app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        XCTAssertTrue(hero.label.contains("ツナマヨ丼")); XCTAssertTrue(hero.label.contains("100%"))
        XCTAssertTrue(hero.label.contains("量を要確認：")); XCTAssertFalse(hero.label.contains("必須材料は冷蔵庫にそろっています"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "一致100パーセントでも量の確認"; screenshot.lifetime = .keepAlways; add(screenshot)
        let near = app.staticTexts["期限が近いもの（1品）"]
        for _ in 0..<5 where !near.exists { app.swipeUp() }
        XCTAssertTrue(near.exists)
        XCTAssertFalse(app.staticTexts["期限切れ（献立の計算対象外）"].exists)
        let expiredHome = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home-expiry-", "卵")).firstMatch
        XCTAssertFalse(expiredHome.exists)
        app.buttons["home-notifications"].tap()
        let expired = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "notice-", "卵")).firstMatch
        XCTAssertTrue(expired.waitForExistence(timeout: 5)); XCTAssertTrue(expired.label.contains("期限を過ぎています"))
        app.buttons["閉じる"].tap()
        for _ in 0..<5 where !hero.isHittable { app.swipeDown() }
        hero.tap()
        let confirmation = app.buttons["recipe-detail-confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); XCTAssertTrue(confirmation.label.contains("量を要確認："))
        XCTAssertFalse(app.buttons["recipe-detail-shortages"].exists)
    }
    @MainActor func testServingsUpdateMatchingAndActualShoppingShortages() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact", "--ui-dark"]; app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15)); XCTAssertTrue(hero.label.contains("100%"))
        hero.tap()
        let match = app.staticTexts["recipe-detail-match"]
        XCTAssertTrue(match.waitForExistence(timeout: 5)); XCTAssertTrue(match.label.contains("100%"))
        let stepper = app.steppers["recipe-servings"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5)); stepper.buttons["recipe-servings-Increment"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "50%"), evaluatedWith: match)
        waitForExpectations(timeout: 5)
        let shortages = app.buttons["recipe-detail-shortages"]
        XCTAssertTrue(shortages.exists); XCTAssertTrue(shortages.label.contains("買い足し 2品"))
        XCTAssertFalse(app.buttons["recipe-detail-confirmation"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "人数変更で一致度と不足分を更新"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recipe-completion"].label.contains("2品"))
        app.tabBars.buttons["買い物"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shopping-row-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allElementsBoundByIndex.contains { $0.label.contains("200g") })
        XCTAssertTrue(rows.allElementsBoundByIndex.contains { $0.label.contains("1缶") })
    }
    @MainActor func testLargestHomeKeepsConfirmationAndExpiryLinksReadable() throws {
        let app = launchLargest(exact: false)
        let hero = app.buttons["home-recipe-hero"]
        scrollTo(hero, app: app)
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertTrue(hero.label.contains("100%"))
        XCTAssertTrue(hero.label.contains("量を要確認："))
        XCTAssertFalse(hero.label.contains("必須材料は冷蔵庫にそろっています"))
        capture(app, "最大文字・ホーム候補")
        let confirmation = app.staticTexts["home-hero-confirmation"]
        scrollTo(confirmation, app: app)
        XCTAssertTrue(confirmation.label.contains("量を要確認："))
        capture(app, "最大文字・一致度と量の確認説明")
        let near = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home-expiry-", "牛乳")).firstMatch
        scrollTo(near, app: app)
        XCTAssertTrue(near.label.contains("まで")); XCTAssertGreaterThan(near.frame.height, 70)
        capture(app, "最大文字・期限の独立表示")
        let expiredHome = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home-expiry-", "卵")).firstMatch
        XCTAssertFalse(expiredHome.exists)
        app.buttons["home-notifications"].tap()
        let expired = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "notice-", "卵")).firstMatch
        scrollTo(expired, app: app)
        XCTAssertTrue(expired.label.contains("期限を過ぎています")); expired.tap()
        XCTAssertTrue(app.navigationBars["卵"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inventory-save"].isEnabled)
    }
    @MainActor func testLargestRefrigeratorFiltersAndStockDetails() throws {
        let app = launchLargest(exact: true)
        XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let category = app.buttons["inventory-tag-egg_dairy"]
        let tags = app.scrollViews.firstMatch
        scrollTo(tags, app: app)
        for _ in 0..<16 {
            let viewport = tags.frame
            let target = category.frame
            if category.isHittable && target.minX >= viewport.minX && target.maxX <= viewport.maxX { break }
            let right = target.midX < viewport.midX
            let start = tags.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.2 : 0.8, dy: 0.5))
            let end = tags.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.65 : 0.35, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(category.isHittable); category.tap()
        choose("inventory-sort", option: "名前順", app: app)
        choose("inventory-storage", option: "冷凍", app: app)
        let empty = app.staticTexts["冷蔵庫に食材を追加しましょう"]
        scrollTo(empty, app: app)
        XCTAssertFalse(app.buttons["inventory-row-milk"].exists)
        choose("inventory-storage", option: "冷蔵", app: app, towardTop: true)
        XCTAssertFalse(app.buttons["inventory-category"].exists)
        XCTAssertEqual(app.buttons["inventory-sort"].value as? String, "名前順")
        capture(app, "最大文字・冷蔵庫の選択内容")
        let milk = app.buttons["inventory-row-milk"]
        scrollTo(milk, app: app)
        XCTAssertTrue(milk.label.contains("500ml")); XCTAssertTrue(milk.label.contains("冷蔵"))
        XCTAssertGreaterThan(milk.frame.height, 130)
        capture(app, "最大文字・冷蔵庫の食材数量期限")
        milk.tap(); XCTAssertTrue(app.navigationBars["牛乳"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inventory-save"].isEnabled)
        XCTAssertEqual(Double(app.textFields["inventory-quantity"].value as? String ?? ""), 500)
    }
    @MainActor func testLargestServingsShoppingFiltersAndPurchaseConfirmation() throws {
        let app = launchLargest(exact: true)
        let hero = app.buttons["home-recipe-hero"]
        scrollTo(hero, app: app)
        XCTAssertTrue(hero.waitForExistence(timeout: 5)); hero.tap()
        let stepper = app.steppers["recipe-servings"]
        let increase = stepper.buttons["recipe-servings-Increment"]
        scrollTo(increase, app: app)
        increase.tap()
        let match = app.staticTexts["recipe-detail-match"]
        scrollTo(match, app: app)
        XCTAssertTrue(match.label.contains("50%"))
        let shortages = app.buttons["recipe-detail-shortages"]
        scrollTo(shortages, app: app)
        XCTAssertTrue(shortages.label.contains("買い足し 2品"))
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        let completion = app.staticTexts["recipe-completion"]
        scrollTo(completion, app: app, towardTop: true)
        XCTAssertTrue(completion.label.contains("2品"))
        XCTAssertGreaterThanOrEqual(completion.frame.minY + 0.5, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThan(completion.frame.maxY, app.buttons["recipe-start"].frame.minY)
        capture(app, "最大文字・献立決定後")
        let cook = app.buttons["recipe-cook"]
        scrollTo(cook, app: app); cook.tap()
        XCTAssertTrue(app.navigationBars["調理後の在庫"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["recipe-start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["買い物"].tap()
        let rice = app.buttons["shopping-row-ごはん"]
        scrollTo(rice, app: app)
        XCTAssertTrue(rice.label.contains("200g")); rice.tap()
        XCTAssertEqual(rice.value as? String, "購入済み")
        choose("shopping-filter", option: "購入済み", app: app, towardTop: true)
        scrollTo(rice, app: app)
        XCTAssertTrue(rice.exists); XCTAssertFalse(app.buttons["shopping-row-ツナ缶"].exists)
        capture(app, "最大文字・購入済みと確認操作")
        choose("shopping-filter", option: "未購入", app: app, towardTop: true)
        let tuna = app.buttons["shopping-row-ツナ缶"]
        scrollTo(tuna, app: app)
        XCTAssertTrue(tuna.label.contains("1缶")); XCTAssertFalse(rice.exists)
        tuna.tap()
        let complete = app.buttons["shopping-complete"]
        XCTAssertTrue(complete.isHittable); XCTAssertTrue(complete.label.contains("2品")); complete.tap()
        XCTAssertTrue(app.navigationBars["購入品を確認"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["purchase-save"].isEnabled)
        capture(app, "最大文字・購入品確認へ移動")
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        choose("shopping-filter", option: "購入済み", app: app, towardTop: true)
        scrollTo(rice, app: app); XCTAssertEqual(rice.value as? String, "購入済み")
        scrollTo(tuna, app: app); XCTAssertEqual(tuna.value as? String, "購入済み")
    }
    @MainActor private func launchLargest(exact: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        if exact { app.launchArguments += ["--ui-suggestion-exact", "--ui-dark"] }
        app.launch(); return app
    }
    @MainActor private func choose(_ identifier: String, option: String, app: XCUIApplication, towardTop: Bool = false) {
        let menu = app.buttons[identifier]
        scrollTo(menu, app: app, towardTop: towardTop); menu.tap()
        let choice = app.buttons[option].firstMatch
        for _ in 0..<12 {
            if choice.exists && choice.isHittable { break }
            // The large-text system menu virtualizes choices below its viewport.
            let list = app.collectionViews.element(boundBy: app.collectionViews.count - 1)
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
                thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        }
        XCTAssertTrue(choice.exists); XCTAssertTrue(choice.isHittable); choice.tap()
        expectation(for: NSPredicate(format: "value == %@", option), evaluatedWith: menu)
        waitForExpectations(timeout: 5)
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<40 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let tabs = app.tabBars.firstMatch
            var bottom = tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY
            for id in ["recipe-add-shortages", "recipe-select", "recipe-stock-add-save", "shopping-complete", "purchase-save", "cooking-save", "store-amount-save"] {
                let footer = app.buttons[id]
                if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY - (element.exists && element.elementType == .staticText ? 0 : 16)) }
            }
            if app.keyboards.firstMatch.exists {
                bottom = min(bottom, app.keyboards.firstMatch.frame.minY)
                let search = app.searchFields.firstMatch
                if search.exists && search.frame.minY > top + 44 { bottom = min(bottom, search.frame.minY - 8) }
            }
            if element.exists && element.isHittable && element.frame.maxY <= top
                && element.frame.minY >= app.navigationBars.firstMatch.frame.minY { return }
            let available = max(44, bottom - top)
            var down = towardTop
            var distance = available * 0.6
            if element.exists {
                let frame = element.frame
                let fits = frame.height <= available
                let visible = fits ? frame.minY >= top - 1 && frame.maxY <= bottom + 1
                    : frame.midY > top && frame.midY < bottom
                if visible && (element.isHittable || element.elementType == .staticText) { return }
                down = fits ? frame.minY < top : frame.midY <= top
                let missing = fits ? (down ? top - frame.minY : frame.maxY - bottom)
                    : abs(frame.midY - (top + bottom) / 2)
                // Tiny drags may not cross the list scrolling threshold.
                distance = min(max(missing + 30, 60), available * 0.6)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + available * (down ? 0.2 : 0.8)
            let end = start + (down ? distance : -distance)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        print("SCROLL TARGET: \(element.debugDescription)\n\(app.debugDescription)")
        XCTFail("画面内に移動できません: \(element)")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor func testJapaneseFoodSearchAndNewIngredientFilter() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]; app.launch()
        XCTAssertTrue(app.navigationBars["今日何作る？"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["スーパーで見つけた食材も選べます。"].exists)
        scrollTo(app.buttons["home-recipe-hero"], app: app)
        capture(app, "ホーム・共通料理画像")
        selectIngredient("chicken_thigh", search: "とりもも", app: app)
        XCTAssertEqual(app.buttons["recipe-ingredient-picker"].value as? String, "鶏もも肉")
        selectIngredient("spinach", search: "ほうれん", app: app)
        XCTAssertEqual(app.buttons["recipe-ingredient-picker"].value as? String, "ほうれん草")
        let spinachHero = app.buttons["home-recipe-hero"]
        scrollTo(spinachHero, app: app)
        XCTAssertTrue(spinachHero.label.contains("ほうれん草"))
        let clear = app.buttons["recipe-ingredient-clear"]; scrollTo(clear, app: app, towardTop: true); clear.tap()
        let alternatives = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-alternative-")).firstMatch
        scrollTo(alternatives, app: app); XCTAssertTrue(alternatives.isHittable)
        capture(app, "候補カード・共通画像と情報アイコン")
        alternatives.tap()
        XCTAssertTrue(app.buttons["recipe-select"].waitForExistence(timeout: 5))
        capture(app, "レシピ詳細・料理画像と材料")
        app.buttons["recipe-select"].tap()
        let completion = app.staticTexts["recipe-completion"]
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertTrue(completion.label.hasPrefix("買い物リストに"))
        XCTAssertTrue(completion.label.hasSuffix("品を追加しました。"))
    }

    @MainActor func testFoodPresenceCategoryAndRecipeKinds() throws { try browseFilters(large: false) }
    @MainActor func testLargestFoodPresenceCategoryAndRecipeKinds() throws { try browseFilters(large: true) }
    @MainActor private func browseFilters(large: Bool) throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        let picker = app.buttons["recipe-ingredient-picker"]; scrollTo(picker, app: app); picker.tap()
        let filters = app.buttons["ingredient-filter-controls"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        XCTAssertEqual(filters.value as? String, "閉じています")
        XCTAssertFalse(app.buttons["ingredient-stock-filter"].exists)
        XCTAssertFalse(app.buttons["ingredient-category-filter"].exists)
        scrollTo(filters, app: app); filters.tap()
        choose("ingredient-stock-filter", option: "冷蔵庫にある", app: app)
        let milk = app.buttons["recipe-ingredient-milk"]; scrollTo(milk, app: app); XCTAssertTrue(milk.exists)
        choose("ingredient-stock-filter", option: "冷蔵庫にない", app: app, towardTop: true)
        XCTAssertFalse(milk.exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("たまご")
        let egg = app.buttons["recipe-ingredient-egg"]; XCTAssertTrue(egg.waitForExistence(timeout: 5)) // Expired stock is unavailable.
        scrollTo(egg, app: app); egg.tap()
        scrollTo(picker, app: app, towardTop: true); picker.tap()
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        XCTAssertEqual(filters.value as? String, "閉じています")
        scrollTo(filters, app: app); filters.tap()
        choose("ingredient-stock-filter", option: "冷蔵庫にない", app: app)
        choose("ingredient-category-filter", option: "肉", app: app)
        let chicken = app.buttons["recipe-ingredient-chicken_thigh"]; scrollTo(chicken, app: app)
        XCTAssertTrue(chicken.exists); XCTAssertFalse(app.buttons["recipe-ingredient-cabbage"].exists)
        capture(app, large ? "最大文字・在庫と肉の絞り込み" : "在庫と肉の絞り込み")
        chicken.tap(); XCTAssertFalse(app.switches["recipe-store-mode"].exists)
        XCTAssertFalse(app.staticTexts["選んだ食材を使う料理を表示します。"].exists)
        let clear = app.buttons["recipe-ingredient-clear"]; scrollTo(clear, app: app); clear.tap()
        let kindMenu = app.buttons["recipe-kind-filter"]
        scrollTo(kindMenu, app: app)
        let alternatives = app.staticTexts["ほかの候補"]
        XCTAssertTrue(alternatives.exists)
        if large {
            XCTAssertGreaterThanOrEqual(kindMenu.frame.minY, alternatives.frame.minY)
        } else {
            XCTAssertLessThan(abs(kindMenu.frame.midY - alternatives.frame.midY), 16)
            XCTAssertGreaterThan(kindMenu.frame.minX, alternatives.frame.maxX)
            let more = app.buttons["home-more-candidates"]
            scrollTo(more, app: app)
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-alternative-"))
            // List virtualizes offscreen rows: compare visible recipe identities,
            // rather than assuming every displayed row exists in the UI snapshot.
            let previous = Set(rows.allElementsBoundByIndex.map(\.identifier))
            XCTAssertFalse(previous.isEmpty)
            more.tap()
            scrollTo(more, app: app)
            let current = Set(rows.allElementsBoundByIndex.map(\.identifier))
            XCTAssertFalse(current.subtracting(previous).isEmpty)
            capture(app, "候補を8品から16品へ追加表示")
            scrollTo(kindMenu, app: app, towardTop: true)
        }
        capture(app, large ? "最大文字・ほかの候補の料理絞り込み" : "ほかの候補の料理絞り込み")
        choose("recipe-kind-filter", option: "副菜", app: app)
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app, towardTop: true); hero.tap()
        XCTAssertTrue(app.navigationBars["レシピ詳細"].waitForExistence(timeout: 5))
        let memo = app.staticTexts["ひとくちメモ"]
        scrollTo(memo, app: app)
        XCTAssertTrue(memo.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        choose("recipe-kind-filter", option: "汁物", app: app)
        scrollTo(hero, app: app, towardTop: true); XCTAssertTrue(hero.label.contains("スープ") || hero.label.contains("汁"))
        XCTAssertFalse(app.staticTexts["home-hero-reason"].exists)
        capture(app, large ? "最大文字・汁物の候補" : "汁物の候補")
    }
    @MainActor func testDefaultServingsChangesHomeAndNewRecipeDetail() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        app.launch(); XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        app.openMyPage()
        choose("settings-default-servings", option: "2人分", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["ホーム"].tap()
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app); hero.tap()
        let stepper = app.steppers["recipe-servings"]; scrollTo(stepper, app: app)
        XCTAssertTrue(stepper.label.contains("2人分")); stepper.buttons["recipe-servings-Increment"].tap()
        XCTAssertTrue(stepper.label.contains("3人分"))
        app.navigationBars.buttons.element(boundBy: 0).tap(); scrollTo(hero, app: app); hero.tap()
        scrollTo(stepper, app: app); XCTAssertTrue(stepper.label.contains("2人分"))
        capture(app, "設定した2人分で詳細を開く")
    }

    @MainActor func testRecipeImageTagsAndMyPageNavigation() throws { try verifyImageTags(large: false) }
    @MainActor func testLargestRecipeImageTagsAndMyPageNavigation() throws { try verifyImageTags(large: true) }
    @MainActor private func verifyImageTags(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15)); scrollTo(hero, app: app)
        XCTAssertTrue(hero.label.contains("作れる")); XCTAssertTrue(hero.label.contains("主食・主菜"))
        let homeTags = app.descendants(matching: .any).matching(identifier: "home-hero-tags").firstMatch
        XCTAssertTrue(homeTags.exists); scrollTo(homeTags, app: app, towardTop: true)
        capture(app, large ? "最大文字・画像上の料理タグ" : "画像上の料理タグ")
        hero.tap()
        let tags = app.descendants(matching: .any).matching(identifier: "recipe-detail-tags").firstMatch
        XCTAssertTrue(tags.waitForExistence(timeout: 5)); scrollTo(tags, app: app)
        XCTAssertTrue(tags.label.contains("作れる"))
        let totalTime = app.staticTexts["recipe-time-total"]
        scrollTo(totalTime, app: app)
        XCTAssertEqual(totalTime.label, "合計 約5分")
        for (id, text) in [("recipe-time-prep", "準備 3分"), ("recipe-time-cook", "調理 2分")] {
            let value = app.staticTexts[id]; scrollTo(value, app: app)
            XCTAssertEqual(value.label, text)
        }
        capture(app, large ? "最大文字・レシピの時間内訳" : "レシピの時間内訳")
        let increase = app.steppers["recipe-servings"].buttons["recipe-servings-Increment"]
        scrollTo(increase, app: app); increase.tap()
        scrollTo(tags, app: app, towardTop: true)
        XCTAssertTrue(tags.label.contains("買い足し")); XCTAssertFalse(tags.label.contains("作れる"))
        capture(app, large ? "最大文字・人数変更で買い足しタグ" : "人数変更で買い足しタグ")
        let memo = app.staticTexts["ひとくちメモ"]; scrollTo(memo, app: app)
        XCTAssertTrue(memo.exists); capture(app, large ? "最大文字・円形電球のひとくちメモ" : "円形電球のひとくちメモ")
        app.openMyPage()
        XCTAssertTrue(app.navigationBars["マイページ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-default-servings"].exists)
        capture(app, large ? "最大文字・マイページ" : "マイページ")
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        XCTAssertTrue(app.navigationBars["マイ冷蔵庫"].waitForExistence(timeout: 5))
        let sort = app.buttons["inventory-sort"]
        XCTAssertTrue(sort.isHittable); XCTAssertGreaterThan(sort.frame.height, 0)
        XCTAssertFalse(app.buttons["inventory-category"].exists)
        for option in ["名前順", "登録順", "種類順", "期限順"] { choose("inventory-sort", option: option, app: app) }
        capture(app, large ? "最大文字・マイ冷蔵庫の並べ替え" : "マイ冷蔵庫の並べ替え")
    }

    @MainActor func testDetailedInstructionsIncludeAmountsTimesAndCheckState() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15)); scrollTo(hero, app: app); hero.tap()
        let modes = app.segmentedControls["recipe-detail-mode"]
        let instructions = modes.buttons["作り方"]
        scrollTo(instructions, app: app); instructions.tap()
        let first = app.buttons["recipe-step-1"]
        scrollTo(first, app: app)
        XCTAssertTrue(first.label.contains("ツナマヨを作る"))
        XCTAssertTrue(first.label.contains("約3分"))
        let firstIngredients = app.staticTexts["recipe-step-ingredients-1"]
        scrollTo(firstIngredients, app: app); XCTAssertTrue(firstIngredients.label.contains("マヨネーズ 大さじ1"))
        scrollTo(first, app: app, towardTop: true)
        XCTAssertEqual(first.value as? String, "未完了"); first.tap()
        expectation(for: NSPredicate(format: "value == %@", "完了"), evaluatedWith: first)
        waitForExpectations(timeout: 5)
        capture(app, "作り方・見出し、材料、時間、工程チェック")
        let stepper = app.steppers["recipe-servings"]
        scrollTo(stepper, app: app, towardTop: true); stepper.buttons["recipe-servings-Increment"].tap()
        scrollTo(first, app: app)
        scrollTo(firstIngredients, app: app); XCTAssertTrue(firstIngredients.label.contains("マヨネーズ 大さじ2"))
        XCTAssertEqual(first.value as? String, "未完了")
        let last = app.buttons["recipe-step-2"]; scrollTo(last, app: app)
        XCTAssertTrue(last.label.contains("約2分"))
        let lastIngredients = app.staticTexts["recipe-step-ingredients-2"]
        scrollTo(lastIngredients, app: app); XCTAssertTrue(lastIngredients.label.contains("ごはん 400g"))
        capture(app, "2人分・手順の材料も人数に連動")
    }
    @MainActor func testLargestDetailedChickenInstructionsStayReadable() throws {
        let app = launchLargest(exact: true)
        selectIngredient("chicken_thigh", search: "とりもも", app: app)
        let all = app.buttons["home-recipes"]; scrollTo(all, app: app); all.tap()
        let recipe = app.buttons["recipe-teriyaki_chicken"]; scrollTo(recipe, app: app); recipe.tap()
        XCTAssertTrue(app.navigationBars["レシピ詳細"].waitForExistence(timeout: 5))
        let modes = app.segmentedControls["recipe-detail-mode"]
        let instructions = modes.buttons["作り方"]
        scrollTo(instructions, app: app); instructions.tap()
        let first = app.buttons["recipe-step-1"]; scrollTo(first, app: app)
        XCTAssertTrue(first.label.contains("鶏肉とたれを準備する"))
        XCTAssertTrue(first.label.contains("約4分"))
        let ingredients = app.staticTexts["recipe-step-ingredients-1"]
        scrollTo(ingredients, app: app); XCTAssertTrue(ingredients.label.contains("鶏もも肉 180g"))
        capture(app, "最大文字・下ごしらえと材料・工程時間")
        let cooking = app.buttons["recipe-step-3"]; scrollTo(cooking, app: app)
        let text = app.staticTexts["recipe-step-text-3"]; scrollTo(text, app: app)
        XCTAssertTrue(text.label.contains("弱めの中火"))
        let tip = app.descendants(matching: .any).matching(identifier: "recipe-step-tip-3").firstMatch
        scrollTo(tip, app: app); XCTAssertTrue(tip.label.contains("中心75℃"))
        scrollTo(cooking, app: app, towardTop: true)
        cooking.tap()
        expectation(for: NSPredicate(format: "value == %@", "完了"), evaluatedWith: cooking)
        waitForExpectations(timeout: 5)
        let last = app.buttons["recipe-step-4"]; scrollTo(last, app: app)
        XCTAssertTrue(last.label.contains("約2分"))
        let finish = app.staticTexts["recipe-step-text-4"]; scrollTo(finish, app: app)
        XCTAssertTrue(finish.label.contains("余分な脂"))
        capture(app, "最大文字・蒸し焼きからたれの仕上げ")
        XCTAssertTrue(app.buttons["recipe-select"].isHittable)
    }

    @MainActor func testAmbiguousManualShoppingWaitsForChoice() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        app.tabBars.buttons["買い物"].tap(); app.navigationBars.buttons["買うものを追加"].tap()
        let name = app.textFields["shopping-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("さば")
        let save = app.buttons["shopping-manual-save"]
        XCTAssertFalse(save.isEnabled)
        let fresh = app.buttons["shopping-candidate-mackerel_fillet"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shopping-candidate-canned_mackerel"].exists)
        fresh.tap(); XCTAssertTrue(save.isEnabled); capture(app, "さばの候補を利用者が選択")
        save.tap(); XCTAssertTrue(app.buttons["shopping-row-さば"].waitForExistence(timeout: 5))
    }
    @MainActor func testCustomFoodCanBeMappedFromHomeIngredientPicker() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        app.tabBars.buttons["マイ冷蔵庫"].tap(); app.buttons["inventory-add"].tap()
        app.buttons["inventory-custom-mode"].tap()
        let name = app.textFields["inventory-custom-name"]; name.tap(); name.typeText("お店の玉ねぎ")
        app.buttons["inventory-save"].tap()
        let savedCustom = app.buttons["inventory-row-custom"]
        scrollTo(savedCustom, app: app); XCTAssertTrue(savedCustom.exists)
        app.tabBars.buttons["ホーム"].tap(); app.buttons["recipe-ingredient-picker"].tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("お店の玉ねぎ")
        let custom = app.buttons["recipe-custom-お店の玉ねぎ"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5)); custom.tap()
        XCTAssertTrue(app.navigationBars["献立に使う食材"].waitForExistence(timeout: 5))
        let mappingSearch = app.searchFields.firstMatch
        XCTAssertTrue(mappingSearch.waitForExistence(timeout: 5))
        scrollTo(mappingSearch, app: app, towardTop: true); mappingSearch.tap(); mappingSearch.typeText("たまねぎ")
        let onion = app.buttons["mapping-food-onion"]
        XCTAssertTrue(onion.waitForExistence(timeout: 5)); onion.tap()
        XCTAssertTrue(app.navigationBars["今日何作る？"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["recipe-ingredient-picker"].value as? String, "玉ねぎ")
        let hero = app.buttons["home-recipe-hero"]; scrollTo(hero, app: app); XCTAssertTrue(hero.exists)
        capture(app, "自分用食材から玉ねぎの献立へ")
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let original = app.buttons["inventory-row-custom"]; scrollTo(original, app: app)
        XCTAssertTrue(original.label.contains("お店の玉ねぎ"))
    }
    @MainActor func testRoughFoodResidualRecordedWithoutMealTimePrompts() throws { try lightCooking(large: false, skip: false) }
    @MainActor func testLargestRoughFoodResidualRecordedWithoutMealTimePrompts() throws { try lightCooking(large: true, skip: false) }
    @MainActor func testLargestLightCookingCanFinishWithoutChangingInventory() throws { try lightCooking(large: true, skip: true) }
    @MainActor private func lightCooking(large: Bool, skip: Bool) throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let hero = app.buttons["home-recipe-hero"]; XCTAssertTrue(hero.waitForExistence(timeout: 15)); scrollTo(hero, app: app); hero.tap()
        XCTAssertFalse(app.switches["recipe-buy-uncertain"].exists)
        app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recipe-completion"].label, "買い物リストに0品を追加しました。")
        let cook = app.buttons["recipe-cook"].firstMatch
        if !cook.isHittable { scrollTo(cook, app: app) }; cook.tap()
        if skip {
            XCTAssertFalse(app.buttons["cooking-options"].exists)
            let finish = app.buttons["cooking-skip-stock"]
            XCTAssertTrue(finish.waitForExistence(timeout: 5)); finish.tap()
        } else {
            let expandTuna = app.descendants(matching: .any).matching(identifier: "cooking-expand-canned_tuna").firstMatch; scrollTo(expandTuna, app: app); expandTuna.tap()
            let toggle = app.switches["cooking-record-remaining-canned_tuna"]
            scrollTo(toggle, app: app); toggle.switches.firstMatch.tap()
            let half = app.buttons["½缶"]
            scrollTo(half, app: app); half.tap()
            capture(app, "量が不明なツナ缶の残り半分を記録")
            app.buttons["cooking-save"].tap()
        }
        XCTAssertTrue(app.buttons["cooking-save"].waitForNonExistence(timeout: 5))
        if large, app.buttons["inventory-undo-dismiss"].exists { app.buttons["inventory-undo-dismiss"].tap() }
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let tuna = app.buttons["inventory-row-canned_tuna"]
        scrollTo(tuna, app: app); XCTAssertTrue(tuna.label.contains(skip ? "ある" : "0.5缶"))
        capture(app, large ? "最大文字・在庫を変えずに調理完了" : "残量の記録で在庫が正確になる")
    }

}


final class MultipleMealUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func scroll(_ item: XCUIElement, app: XCUIApplication, up: Bool = false) {
        for _ in 0..<24 {
            var towardTop = up
            if item.exists {
                let frame = item.frame
                if frame.width > 0 && frame.height > 0 {
                    if item.isHittable { return }
                    let top = app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? 0
                    towardTop = frame.midY <= top
                }
            }
            let list = app.collectionViews.firstMatch
            if list.exists { if towardTop { list.swipeDown() } else { list.swipeUp() } }
            else { if towardTop { app.swipeDown() } else { app.swipeUp() } }
        }
        print(app.debugDescription)
        XCTFail("操作する項目が見つかりません: \(item)")
    }
    @MainActor func testMultipleSelectionStartResumeCancelAndCompactCompletion() throws { try flow(large: false) }
    @MainActor func testLargestMultipleSelectionStartResumeCancelAndCompactCompletion() throws { try flow(large: true) }
    @MainActor private func flow(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let hero = app.buttons["home-recipe-hero"]; XCTAssertTrue(hero.waitForExistence(timeout: 15)); scroll(hero, app: app)
        let homeShot = XCTAttachment(screenshot: app.screenshot()); homeShot.name = large ? "最大文字・画像キャプション削除" : "画像キャプション削除"; homeShot.lifetime = .keepAlways; add(homeShot)
        hero.tap()
        app.buttons["recipe-select"].tap(); XCTAssertTrue(app.buttons["recipe-start"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let kind = app.buttons["recipe-kind-filter"]; scroll(kind, app: app, up: true); kind.tap(); app.buttons["副菜"].firstMatch.tap()
        scroll(hero, app: app); hero.tap(); app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.buttons["recipe-start"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["献立"].tap()
        let starts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal-start-"))
        if large {
            let heading = app.navigationBars["献立"]
            scroll(heading, app: app, up: true); XCTAssertTrue(heading.exists)
        } else {
            scroll(starts.firstMatch, app: app, up: true); XCTAssertEqual(starts.count, 2)
        }
        let selectedShot = XCTAttachment(screenshot: app.screenshot()); selectedShot.name = large ? "最大文字・複数の献立" : "主菜と副菜を選択"; selectedShot.lifetime = .keepAlways; add(selectedShot)
        let detail = app.buttons["meal-detail-21000000-0000-4000-8000-000000000010"]
        reveal(detail, app: app, towardTop: true); detail.tap()
        XCTAssertTrue(app.navigationBars["レシピ詳細"].waitForExistence(timeout: 5))
        let title = app.staticTexts["recipe-detail-title"]
        reveal(title, app: app); XCTAssertEqual(title.label, "ブロッコリーとツナのサラダ")
        let servings = app.steppers["recipe-servings"]
        reveal(servings.buttons["recipe-servings-Increment"], app: app)
        XCTAssertTrue(servings.label.contains("1人分")); XCTAssertFalse(servings.buttons["recipe-servings-Increment"].isEnabled)
        let detailShot = XCTAttachment(screenshot: app.screenshot()); detailShot.name = large ? "最大文字・献立タップで詳細" : "献立タップで詳細"; detailShot.lifetime = .keepAlways; add(detailShot)
        app.buttons["recipe-start"].tap(); XCTAssertTrue(app.navigationBars["作り方"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap(); XCTAssertTrue(app.buttons["recipe-start"].label.contains("作り方を見る"))
        if large {
            app.navigationBars.buttons.firstMatch.tap()
            let cancel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal-cancel-")).firstMatch
            scroll(cancel, app: app, up: true)
            let cancelledIdentifier = cancel.identifier
            cancel.tap()
            XCTAssertTrue(app.buttons[cancelledIdentifier].waitForNonExistence(timeout: 5))
        } else {
            app.buttons["recipe-cancel"].tap()
            XCTAssertTrue(app.buttons["recipe-select"].waitForExistence(timeout: 5)); app.navigationBars.buttons.firstMatch.tap()
        }
        let firstStart = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal-start-")).firstMatch
        scroll(firstStart, app: app, up: true)
        let made = app.buttons["meal-cook"].firstMatch
        reveal(made, app: app); made.tap()
        XCTAssertTrue(app.navigationBars["調理後の在庫"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
        reveal(firstStart, app: app); firstStart.tap()
        XCTAssertTrue(app.navigationBars["作り方"].waitForExistence(timeout: 5))
        app.buttons["meal-session-finish"].tap(); XCTAssertTrue(app.navigationBars["調理後の在庫"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["cooking-quantity-cooked_rice"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "cooking-expand-cooked_rice").firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = large ? "最大文字・コンパクトな在庫確認" : "コンパクトな在庫確認"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["cooking-save"].tap()
        XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 8))
        if app.buttons["inventory-undo-dismiss"].exists { app.buttons["inventory-undo-dismiss"].tap() }
        XCTAssertFalse(firstStart.exists)
        app.tabBars.buttons["ホーム"].tap()
        scroll(hero, app: app)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]; scroll(rice, app: app); XCTAssertTrue(rice.label.contains("0g"))
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<40 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let tabs = app.tabBars.firstMatch
            var bottom = tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY
            for id in ["recipe-select", "recipe-start", "meal-session-finish", "shopping-complete", "purchase-save", "cooking-save", "store-amount-save"] {
                let footer = app.buttons[id]
                if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY - (element.exists && element.elementType == .staticText ? 0 : 16)) }
            }
            if app.keyboards.firstMatch.exists {
                bottom = min(bottom, app.keyboards.firstMatch.frame.minY)
                let search = app.searchFields.firstMatch
                if search.exists && search.frame.minY > top + 44 { bottom = min(bottom, search.frame.minY - 8) }
            }
            if element.exists && element.isHittable && element.frame.maxY <= top
                && element.frame.minY >= app.navigationBars.firstMatch.frame.minY { return }
            let available = max(44, bottom - top)
            var down = towardTop
            var distance = available * 0.6
            if element.exists {
                let frame = element.frame
                let fits = frame.height <= available
                let visible = fits ? frame.minY >= top - 1 && frame.maxY <= bottom + 1
                    : frame.midY > top && frame.midY < bottom
                if visible && (element.isHittable || element.elementType == .staticText) { return }
                down = fits ? frame.minY < top : frame.midY <= top
                let missing = fits ? (down ? top - frame.minY : frame.maxY - bottom)
                    : abs(frame.midY - (top + bottom) / 2)
                // Tiny drags may not cross the list scrolling threshold.
                distance = min(max(missing + 30, 60), available * 0.6)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + available * (down ? 0.2 : 0.8)
            let end = start + (down ? distance : -distance)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        print("SCROLL TARGET: \(element.debugDescription)\n\(app.debugDescription)")
        XCTFail("画面内に移動できません: \(element)")
    }
    @MainActor func testRecipePagerKeepsStepsServingsAndCompletionSeparate() throws { try pagerFlow(large: false) }
    @MainActor func testLargestRecipePagerKeepsStepsServingsAndCompletionSeparate() throws { try pagerFlow(large: true) }
    @MainActor private func pagerFlow(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15)); scroll(hero, app: app); hero.tap()
        let servings = app.steppers["recipe-servings"]
        let increase = servings.buttons["recipe-servings-Increment"]
        reveal(increase, app: app); increase.tap()
        XCTAssertTrue(servings.label.contains("2人分"))
        XCTAssertEqual(app.buttons["recipe-select"].label, "献立に加える")
        app.buttons["recipe-select"].tap(); XCTAssertTrue(app.buttons["recipe-start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recipe-start"].label.contains("作り方を見る"))
        app.navigationBars.buttons.firstMatch.tap()
        let kind = app.buttons["recipe-kind-filter"]; scroll(kind, app: app, up: true); kind.tap(); app.buttons["副菜"].firstMatch.tap()
        scroll(hero, app: app); hero.tap(); app.buttons["recipe-select"].tap()
        XCTAssertTrue(app.buttons["recipe-start"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["献立"].tap()
        let mainKey = "tuna_mayo_bowl", sideKey = "broccoli_tuna_salad"
        let mainStart = app.buttons["meal-start-20000000-0000-4000-8000-000000000013"]
        scroll(mainStart, app: app, up: true)
        let cardShot = XCTAttachment(screenshot: app.screenshot()); cardShot.name = large ? "最大文字・画像と小さい献立操作" : "画像と小さい献立操作"; cardShot.lifetime = .keepAlways; add(cardShot)
        mainStart.tap(); XCTAssertTrue(app.navigationBars["作り方"].waitForExistence(timeout: 5))
        let mainList = app.collectionViews["meal-instructions-" + mainKey]
        let sideList = app.collectionViews["meal-instructions-" + sideKey]
        let mainTab = app.buttons["meal-recipe-tab-" + mainKey], sideTab = app.buttons["meal-recipe-tab-" + sideKey]
        let mainServings = app.descendants(matching: .any).matching(identifier: "meal-session-servings-" + mainKey).firstMatch
        reveal(mainServings, app: app); XCTAssertTrue(mainServings.label.contains("2人分"))
        let mainCheck = mainList.buttons["recipe-step-1"]
        reveal(mainCheck, app: app); XCTAssertEqual(mainCheck.value as? String, "未完了"); mainCheck.tap()
        XCTAssertEqual(mainCheck.value as? String, "完了")
        mainList.swipeRight()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: sideTab)], timeout: 5), .completed)
        let sideServings = app.descendants(matching: .any).matching(identifier: "meal-session-servings-" + sideKey).firstMatch
        reveal(sideServings, app: app); XCTAssertTrue(sideServings.label.contains("1人分"))
        let sideCheck = sideList.buttons["recipe-step-1"]
        reveal(sideCheck, app: app); XCTAssertEqual(sideCheck.value as? String, "未完了")
        sideList.swipeLeft()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: mainTab)], timeout: 5), .completed)
        XCTAssertEqual(mainCheck.value as? String, "完了")
        sideTab.tap()
        XCTAssertTrue(sideTab.isSelected)
        let pageShot = XCTAttachment(screenshot: app.screenshot()); pageShot.name = large ? "最大文字・献立の横スワイプ" : "人数と手順が混ざらない横スワイプ"; pageShot.lifetime = .keepAlways; add(pageShot)
        app.buttons["meal-session-finish"].tap(); XCTAssertTrue(app.navigationBars["調理後の在庫"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ブロッコリーとツナのサラダ"].exists)
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.navigationBars["作り方"].waitForExistence(timeout: 5)); XCTAssertTrue(sideTab.isSelected)
        app.buttons["meal-session-finish"].tap()
        app.buttons["cooking-skip-stock"].tap()
        XCTAssertTrue(app.navigationBars["作り方"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cooking-save"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(mainList.exists)
        XCTAssertTrue(sideList.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal-recipe-tab-" + sideKey].waitForNonExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.navigationBars["献立"].waitForExistence(timeout: 5))
        if app.buttons["inventory-undo-dismiss"].exists { app.buttons["inventory-undo-dismiss"].tap() }
        scroll(mainStart, app: app, up: true); XCTAssertTrue(mainStart.exists)
        XCTAssertFalse(app.buttons["meal-start-21000000-0000-4000-8000-000000000010"].exists)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]; scroll(rice, app: app); XCTAssertTrue(rice.label.contains("200g"))
    }
    @MainActor func testRecommendationFilterIsBesideHeadingAndFoodStartsWithStock() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]; app.launch()
        let kind = app.buttons["recipe-kind-filter"]; XCTAssertTrue(kind.waitForExistence(timeout: 15))
        let heading = app.staticTexts["今日のおすすめ"]
        XCTAssertLessThan(abs(kind.frame.midY - heading.frame.midY), 25)
        XCTAssertGreaterThan(kind.frame.midX, heading.frame.midX)
        app.buttons["recipe-ingredient-picker"].tap()
        XCTAssertTrue(app.buttons["recipe-ingredient-milk"].waitForExistence(timeout: 5))
        let stocked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recipe-ingredient-")).allElementsBoundByIndex.filter { $0.identifier != "recipe-ingredient-picker" }
        XCTAssertTrue(stocked.prefix(4).allSatisfy { $0.label.contains("冷蔵庫にある") })
        XCTAssertFalse(app.buttons["ingredient-stock-filter"].exists)
    }
}

final class HomeStreamlineUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testHomeAndSwipeRemoval() throws { try flow(large: false) }
    @MainActor func testLargestHomeAndSwipeRemoval() throws { try flow(large: true) }
    @MainActor private func flow(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let hero = app.buttons["home-recipe-hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15)); reveal(hero, app: app)
        XCTAssertTrue(hero.label.contains("量を要確認："))
        XCTAssertFalse(hero.label.contains("ひとくちメモ"))
        XCTAssertFalse(hero.label.contains("AIイメージ"))
        XCTAssertFalse(app.buttons["home-suggestion-explanation"].exists)
        capture(app, large ? "最大文字・すっきりしたホーム" : "すっきりしたホーム")
        hero.tap()
        XCTAssertEqual(app.staticTexts["recipe-detail-title"].label, "ツナマヨ丼")
        let memo = app.staticTexts["ひとくちメモ"]
        reveal(memo, app: app); XCTAssertTrue(memo.exists)
        let confirmation = app.buttons["recipe-detail-confirmation"]
        reveal(confirmation, app: app); XCTAssertTrue(confirmation.label.contains("量を要確認："))
        app.navigationBars.buttons.firstMatch.tap()
        let alternate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-alternative-")).firstMatch
        reveal(alternate, app: app)
        let match = app.staticTexts[alternate.identifier + "-match"]
        XCTAssertTrue(match.exists); XCTAssertTrue(match.label.contains("%")); XCTAssertTrue(match.label.contains("品"))
        capture(app, large ? "最大文字・候補のアイコンと品数" : "候補のアイコンと品数")
        alternate.tap()
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["recipe-detail-title"].label, "ツナマヨ丼")
        app.openMyPage()
        let help = app.buttons["settings-suggestion-explanation"]
        reveal(help, app: app); help.tap()
        XCTAssertTrue(app.navigationBars["おすすめの見方"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]
        reveal(rice, app: app); let originalStock = rice.label; rice.swipeLeft()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inventory-remove-")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        capture(app, large ? "最大文字・スワイプで取り除く" : "スワイプで取り除く")
        remove.tap(); XCTAssertTrue(rice.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventory-undo"].exists)
        app.openMyPage()
        let removed = app.buttons["取り除いた食材を戻す"]
        reveal(removed, app: app); removed.tap()
        XCTAssertTrue(app.navigationBars["取り除いた食材"].waitForExistence(timeout: 5))
        let restore = app.buttons["戻す"].firstMatch
        reveal(restore, app: app); restore.tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        reveal(rice, app: app); XCTAssertEqual(rice.label, originalStock)
        capture(app, large ? "最大文字・元の在庫を復元" : "元の在庫を復元")
    }
    @MainActor func testFramedRefrigerator() throws { try framedFridge(large: false) }
    @MainActor func testLargestFramedRefrigerator() throws { try framedFridge(large: true) }
    @MainActor private func framedFridge(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact", "--ui-fridge-frame-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let picker = app.buttons["recipe-ingredient-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15)); reveal(picker, app: app, towardTop: true)
        XCTAssertEqual(picker.label, "食材から選ぶ")
        capture(app, large ? "最大文字ダーク・一体の線画ボタン" : "ホーム・一体の線画と白文字")
        let add = app.buttons["home-recommendation-add"]
        reveal(add, app: app); XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        if !large { XCTAssertLessThanOrEqual(add.frame.height, 45) }
        capture(app, large ? "最大文字ダーク・白文字の献立追加" : "44ptの白文字ボタン")
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let count = app.staticTexts["inventory-visible-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertGreaterThan(Int(count.label) ?? 0, 25)
        for id in ["inventory-voice", "inventory-receipt", "inventory-bulk", "inventory-sort", "inventory-add", "inventory-group", "inventory-storage"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        let searchField = app.textFields["inventory-search"]
        let sortControl = app.buttons["inventory-sort"]
        let searchToggle = app.buttons["inventory-search-toggle"]
        XCTAssertFalse(searchField.exists)
        XCTAssertTrue(searchToggle.isHittable)
        XCTAssertLessThan(app.buttons["inventory-add"].frame.midX, searchToggle.frame.midX)
        XCTAssertLessThan(searchToggle.frame.midX, sortControl.frame.midX)
        XCTAssertEqual(searchToggle.frame.midY, sortControl.frame.midY, accuracy: 6)
        let list = app.collectionViews["inventory-scroll-list"]
        XCTAssertTrue(list.exists); XCTAssertGreaterThan(list.frame.height, large ? 140 : 300)
        capture(app, large ? "最大文字ダーク・冷蔵庫の固定枠" : "冷蔵庫・実データと上部フィルター")
        app.buttons["inventory-bulk"].tap()
        XCTAssertTrue(app.buttons["bulk-skip"].waitForExistence(timeout: 5)); app.buttons["bulk-skip"].tap()
        app.buttons["inventory-group"].tap(); app.buttons["食材"].firstMatch.tap()
        app.buttons["inventory-sort"].tap(); app.buttons["登録順"].firstMatch.tap()
        XCTAssertEqual(app.buttons["inventory-sort"].value as? String, "登録順")
        let total = Int(count.label) ?? 0; XCTAssertGreaterThan(total, 20)
        let fixedY = count.frame.minY
        let rice = app.buttons["inventory-row-cooked_rice"]
        fridgeReveal(rice, app: app)
        XCTAssertEqual(count.frame.minY, fixedY, accuracy: 1)
        XCTAssertEqual(Int(count.label), total)
        XCTAssertTrue(rice.label.contains("200g")); XCTAssertTrue(rice.label.contains("期限なし"))
        capture(app, large ? "最大文字・最後の食材までスクロール" : "最後の食材までスクロール・上部固定")
        rice.tap(); XCTAssertTrue(app.buttons["inventory-save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["inventory-exact-toggle"].exists)
        app.buttons["キャンセル"].firstMatch.tap()
        fridgeReveal(rice, app: app); let original = rice.label
        rice.swipeLeft()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inventory-remove-")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertEqual(Int(count.label), total - 1)
        XCTAssertFalse(app.buttons["inventory-undo"].exists)
        app.openMyPage()
        let removed = app.buttons["取り除いた食材を戻す"]
        reveal(removed, app: app); removed.tap()
        let restore = app.buttons["戻す"].firstMatch
        reveal(restore, app: app); restore.tap()
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        fridgeReveal(rice, app: app); XCTAssertEqual(rice.label, original); XCTAssertEqual(Int(count.label), total)
        app.buttons["inventory-group"].tap(); app.buttons["調味料"].firstMatch.tap()
        XCTAssertFalse(rice.exists)
        let soy = app.buttons["inventory-row-soy_sauce"]; fridgeReveal(soy, app: app)
        XCTAssertTrue(soy.label.contains("ある")); XCTAssertFalse(app.buttons["inventory-tag-vegetable"].exists)
        app.buttons["inventory-storage"].tap(); app.buttons["冷蔵"].firstMatch.tap()
        XCTAssertEqual(app.buttons["inventory-storage"].value as? String, "冷蔵")
        app.buttons["inventory-storage"].tap(); app.buttons["すべて"].firstMatch.tap()
        app.buttons["inventory-group"].tap(); app.buttons["食材"].firstMatch.tap()
        app.buttons["inventory-tag-vegetable"].tap(); XCTAssertFalse(rice.exists)
        let onion = app.buttons["inventory-row-onion"]; fridgeReveal(onion, app: app)
        XCTAssertTrue(onion.label.contains("野菜")); capture(app, large ? "最大文字・野菜で絞り込み" : "野菜で絞り込み")
        app.buttons["inventory-tag-all"].tap()
        searchToggle.tap()
        let search = app.textFields["inventory-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.otherElements["inventory-search-container"].frame.height, 44)
        app.otherElements["inventory-search-container"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("たまねぎ")
        XCTAssertTrue(onion.waitForExistence(timeout: 5))
        capture(app, large ? "最大文字・検索とキーボード表示" : "検索とキーボード表示")
        search.typeText("\n"); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        fridgeReveal(onion, app: app)
        XCTAssertEqual(Int(count.label), 1); XCTAssertTrue(onion.isHittable)
        capture(app, large ? "最大文字・別名検索の結果" : "別名検索・玉ねぎ")
        onion.tap(); XCTAssertTrue(app.buttons["inventory-save"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].firstMatch.tap()
        app.buttons["inventory-list-search-clear"].tap()
        XCTAssertEqual(Int(count.label), total)
        XCTAssertFalse(app.buttons["inventory-list-search-clear"].exists)
        search.tap(); search.typeText("たまねぎ")
        XCTAssertEqual(Int(count.label), 1)
        searchToggle.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(Int(count.label), total)
        capture(app, large ? "最大文字・検索を閉じて一覧に戻る" : "検索を閉じて一覧に戻る")
    }
    @MainActor private func fridgeReveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<120 {
            let list = app.collectionViews["inventory-scroll-list"]
            let top = list.frame.minY + 5
            var bottom = list.frame.maxY - 5
            let tabs = app.tabBars.firstMatch
            if tabs.exists && tabs.isHittable { bottom = min(bottom, tabs.frame.minY - 5) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            let h = bottom - top
            guard h >= 44 else { XCTFail("冷蔵庫のスクロール領域が小さすぎます: \(list.frame)"); return }
            var down = false
            var distance = h * 0.6
            var velocity = XCUIGestureVelocity.fast
            var hold = 0.0
            if element.exists {
                let f = element.frame
                if element.isHittable && f.midY > top && f.midY < bottom { return }
                down = f.midY <= top
                distance = min(max(abs(f.midY - (top + bottom) / 2), 30), h * 0.6)
                velocity = .slow; hold = 0.2
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = top + h * (down ? 0.2 : 0.8), to = from + (down ? distance : -distance)
            origin.withOffset(CGVector(dx: list.frame.midX, dy: from)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: list.frame.midX, dy: to)), withVelocity: velocity, thenHoldForDuration: hold)
        }
        XCTFail("冷蔵庫の項目へ移動できません\n\(app.debugDescription)")
    }
    @MainActor func testHomeRecipeEntrySearchAndKinds() throws { try recipeEntryFlow(large: false, stacked: false, completeMeal: true) }
    @MainActor func testNarrowHomeRecipeEntrySearchAndKinds() throws { try recipeEntryFlow(large: false, stacked: true, completeMeal: false) }
    @MainActor func testLargestHomeRecipeEntrySearchAndKinds() throws { try recipeEntryFlow(large: true, stacked: true, completeMeal: false) }
    @MainActor private func recipeEntryFlow(large: Bool, stacked: Bool, completeMeal: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let dish = app.buttons["home-recipe-entry"], food = app.buttons["recipe-ingredient-picker"]
        XCTAssertTrue(dish.waitForExistence(timeout: 15)); reveal(dish, app: app, towardTop: true)
        XCTAssertEqual(dish.label, "料理から選ぶ"); XCTAssertEqual(food.label, "食材から選ぶ")
        XCTAssertGreaterThanOrEqual(dish.frame.height, 44); XCTAssertGreaterThanOrEqual(food.frame.height, 44)
        if stacked { XCTAssertLessThan(dish.frame.maxY, food.frame.minY) }
        else { XCTAssertEqual(dish.frame.midY, food.frame.midY, accuracy: 4); XCTAssertLessThan(dish.frame.maxX, food.frame.minX) }
        capture(app, large ? "最大文字ダーク・対になる入口" : (stacked ? "狭い画面・縦の入口" : "通常・横並びの入口"))
        dish.tap(); XCTAssertTrue(app.navigationBars["レシピ"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-ingredient-picker"].exists)
        let kind = app.buttons["recipe-kind-filter"]
        XCTAssertEqual(kind.value as? String, "すべて")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        func query(_ value: String) {
            search.tap()
            let old = search.value as? String ?? ""
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value + "\n")
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        func chooseKind(_ value: String) {
            reveal(kind, app: app, towardTop: true); kind.tap(); app.buttons[value].firstMatch.tap()
            XCTAssertEqual(kind.value as? String, value)
        }
        query("つな")
        let tuna = app.buttons["recipe-tuna_mayo_bowl"]
        reveal(tuna, app: app)
        XCTAssertTrue(tuna.exists)
        chooseKind("副菜")
        XCTAssertFalse(tuna.exists)
        let salad = app.buttons["recipe-broccoli_tuna_salad"]; reveal(salad, app: app)
        XCTAssertTrue(salad.exists)
        capture(app, large ? "最大文字・検索と副菜を併用" : "料理名のかな検索と副菜")
        chooseKind("汁物")
        let empty = app.staticTexts["recipe-filter-empty"]; reveal(empty, app: app)
        XCTAssertTrue(empty.exists)
        capture(app, large ? "最大文字・該当なしと解除" : "該当なしと条件リセット")
        let reset = app.buttons["recipe-filter-reset"]; reveal(reset, app: app); reset.tap()
        reveal(kind, app: app, towardTop: true); XCTAssertEqual(kind.value as? String, "すべて")
        XCTAssertFalse(empty.exists)
        query("存在しない料理")
        reveal(empty, app: app); XCTAssertTrue(empty.exists)
        reveal(reset, app: app); reset.tap()
        query("つな まよ")
        reveal(tuna, app: app); XCTAssertTrue(tuna.exists)
        capture(app, large ? "最大文字・複数語で料理名検索" : "複数語で料理名検索")
        tuna.tap(); XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recipe-detail-title"].label, "ツナマヨ丼")
        if completeMeal {
            let increase = app.steppers["recipe-servings"].buttons["recipe-servings-Increment"]
            reveal(increase, app: app); increase.tap()
            XCTAssertTrue(app.buttons["recipe-detail-shortages"].label.contains("買い足し 2品"))
            let add = app.buttons["recipe-select"]; reveal(add, app: app); add.tap()
            XCTAssertTrue(app.staticTexts["recipe-completion"].waitForExistence(timeout: 5))
            app.tabBars.buttons["買い物"].tap()
            XCTAssertTrue(app.buttons["shopping-row-ごはん"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["shopping-row-ツナ缶"].exists)
            capture(app, "料理の入口から献立・買い物へ")
        }
    }
    @MainActor func testIllustratedIngredientChoice() throws { try illustratedChoice(large: false) }
    @MainActor func testLargestIllustratedIngredientChoice() throws { try illustratedChoice(large: true) }
    @MainActor private func illustratedChoice(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let picker = app.buttons["recipe-ingredient-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15)); reveal(picker, app: app, towardTop: true)
        XCTAssertEqual(picker.label, "食材から選ぶ"); XCTAssertEqual(picker.value as? String, "指定なし")
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        XCTAssertGreaterThanOrEqual(picker.frame.width, 44)
        XCTAssertEqual(app.staticTexts.matching(identifier: "食材を選ぶ").count, picker.staticTexts.matching(identifier: "食材を選ぶ").count, "ボタン以外に重複する見出しは表示しない")
        let recipeEntry = app.buttons["home-recipe-entry"]
        XCTAssertTrue(recipeEntry.exists)
        XCTAssertGreaterThanOrEqual(recipeEntry.frame.height, 44)
        if large { XCTAssertLessThan(recipeEntry.frame.maxY, picker.frame.minY) }
        else { XCTAssertEqual(recipeEntry.frame.midY, picker.frame.midY, accuracy: 4) }

        capture(app, large ? "最大文字ライト・線画の食材ボタン" : "ホーム・コーラル線画と二本線")
        picker.tap(); XCTAssertTrue(app.navigationBars["食材を選ぶ"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("シーチキン")
        let tuna = app.buttons["recipe-ingredient-canned_tuna"]
        XCTAssertTrue(tuna.waitForExistence(timeout: 5)); reveal(tuna, app: app); tuna.tap()
        XCTAssertTrue(app.navigationBars["今日何作る？"].waitForExistence(timeout: 5))
        reveal(picker, app: app, towardTop: true)
        XCTAssertEqual(picker.label, "ツナ缶"); XCTAssertEqual(picker.value as? String, "ツナ缶")
        let clear = app.buttons["recipe-ingredient-clear"]
        reveal(clear, app: app); XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        capture(app, large ? "最大文字ライト・選択と解除" : "線画ボタン・選択と解除")
        clear.tap(); reveal(picker, app: app, towardTop: true)
        XCTAssertEqual(picker.label, "食材から選ぶ"); XCTAssertEqual(picker.value as? String, "指定なし")
        XCTAssertFalse(clear.exists)
        let hero = app.buttons["home-recipe-hero"]
        reveal(hero, app: app); hero.tap()
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
    }
    @MainActor func testCoralRecommendationQuickAdd() throws { try quickAdd(large: false) }
    @MainActor func testLargestCoralRecommendationQuickAdd() throws { try quickAdd(large: true) }
    @MainActor private func quickAdd(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        else { app.launchArguments.append("--ui-suggestion-exact") }
        app.launch()
        XCTAssertTrue(app.buttons["home-recipe-hero"].waitForExistence(timeout: 15))
        app.openMyPage()
        let setting = app.buttons["settings-default-servings"]
        reveal(setting, app: app); setting.tap(); app.buttons["2人分"].firstMatch.tap()
        app.tabBars.buttons["ホーム"].tap()
        let add = app.buttons["home-recommendation-add"]
        reveal(add, app: app)
        XCTAssertEqual(add.label, "献立に加える"); XCTAssertEqual(add.value as? String, "2人分")
        XCTAssertTrue(add.isEnabled); XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        if !large { XCTAssertLessThanOrEqual(add.frame.height, 45) }
        capture(app, large ? "最大文字・コーラルのおすすめ追加" : "コーラルのおすすめ追加")
        add.tap()
        XCTAssertTrue(app.navigationBars["今日何作る？"].exists)
        XCTAssertFalse(app.staticTexts["recipe-detail-title"].exists)
        reveal(add, app: app)
        XCTAssertEqual(add.label, "献立に追加済み"); XCTAssertFalse(add.isEnabled)
        if large { XCTAssertFalse(app.staticTexts["home-shopping-completion"].exists) }
        else {
            let notice = app.staticTexts["home-shopping-completion"]
            reveal(notice, app: app); XCTAssertTrue(notice.label.hasPrefix("買い物リストに"))
        }
        capture(app, large ? "最大文字・追加済みで重複を防止" : "追加済み・買い足しを登録")
        app.tabBars.buttons["献立"].tap()
        let header = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal-detail-")).firstMatch
        reveal(header, app: app, towardTop: true); XCTAssertTrue(header.label.contains("2人分"))
        XCTAssertTrue(app.navigationBars["献立"].exists)
        header.tap()
        XCTAssertTrue(app.staticTexts["recipe-detail-title"].waitForExistence(timeout: 5))
        let servings = app.steppers["recipe-servings"]
        reveal(servings, app: app); XCTAssertTrue(servings.label.contains("2人分"))
        XCTAssertFalse(servings.buttons["recipe-servings-Increment"].isEnabled)
        capture(app, large ? "最大文字・追加した献立の人数" : "追加した献立の人数")
        app.navigationBars.buttons.firstMatch.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal-cancel-")).firstMatch
        reveal(cancel, app: app); cancel.tap()
        XCTAssertFalse(app.buttons["献立を解除"].exists)
        app.tabBars.buttons["ホーム"].tap()
        reveal(add, app: app); XCTAssertEqual(add.label, "献立に加える"); XCTAssertTrue(add.isEnabled)
        add.tap()
        app.tabBars.buttons["献立"].tap()
        reveal(header, app: app, towardTop: true); XCTAssertTrue(header.label.contains("2人分"))
        XCTAssertTrue(app.navigationBars["献立"].exists)
        app.tabBars.buttons["マイ冷蔵庫"].tap()
        let rice = app.buttons["inventory-row-cooked_rice"]
        reveal(rice, app: app); XCTAssertTrue(rice.label.contains(large ? "ある" : "200g"))
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<40 {
            if element.exists, element.isHittable, ["recipe-select", "recipe-start", "meal-session-finish", "shopping-complete", "purchase-save", "cooking-save", "store-amount-save"].contains(element.identifier) { return }
            var top = app.navigationBars.firstMatch.frame.maxY
            let fridge = app.collectionViews["inventory-scroll-list"]
            if fridge.exists { top = max(top, fridge.frame.minY) }
            let tabs = app.tabBars.firstMatch
            var bottom = tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY
            let list = app.collectionViews.firstMatch
            if list.exists { bottom = min(bottom, list.frame.maxY) }
            for id in ["recipe-select", "recipe-start", "meal-session-finish", "shopping-complete", "purchase-save", "cooking-save", "store-amount-save"] {
                let footer = app.buttons[id]
                if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY - (element.exists && element.elementType == .staticText ? 0 : 16)) }
            }
            if app.keyboards.firstMatch.exists {
                bottom = min(bottom, app.keyboards.firstMatch.frame.minY)
                let search = app.searchFields.firstMatch
                if search.exists && search.frame.minY > top + 44 { bottom = min(bottom, search.frame.minY - 8) }
            }
            if element.exists && element.isHittable && element.frame.maxY <= top
                && element.frame.minY >= app.navigationBars.firstMatch.frame.minY { return }
            let available = max(44, bottom - top)
            var down = towardTop
            var distance = available * 0.6
            if element.exists {
                let frame = element.frame
                let fits = frame.height <= available
                let visible = fits ? frame.minY >= top - 1 && frame.maxY <= bottom + 1
                    : frame.midY > top && frame.midY < bottom
                if visible && (element.isHittable || element.elementType == .staticText || !element.isEnabled) { return }
                down = fits ? frame.minY < top : frame.midY <= top
                let missing = fits ? (down ? top - frame.minY : frame.maxY - bottom)
                    : abs(frame.midY - (top + bottom) / 2)
                // Tiny drags may not cross the list scrolling threshold.
                distance = min(max(missing + 30, 60), available * 0.6)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + available * (down ? 0.2 : 0.8)
            let end = start + (down ? distance : -distance)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        print("SCROLL TARGET: \(element.debugDescription)\n\(app.debugDescription)")
        XCTFail("画面内に移動できません: \(element)")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}

final class NoticeInboxUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testUnreadExpiryAndUpdateRecipeNavigation() throws { try inbox(large: false) }
    @MainActor func testLargestDarkInboxAndReadyTagRemainReadable() throws { try inbox(large: true) }
    @MainActor private func inbox(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-suggestion-fixture", "--ui-suggestion-exact"]
        if large { app.launchArguments += ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let bell = app.buttons["home-notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5)); XCTAssertTrue(bell.isHittable)
        XCTAssertEqual(bell.value as? String, "未読4件")
        capture(app, large ? "最大文字・ダーク・ホームの通知" : "ホームの通知アイコンと未読件数")
        bell.tap()
        XCTAssertTrue(app.navigationBars["お知らせ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "notice-", "卵")).firstMatch.exists)
        let milk = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "notice-", "牛乳")).firstMatch
        reveal(milk, app: app); XCTAssertTrue(milk.label.contains("あと2日"), milk.label)
        milk.tap()
        XCTAssertTrue(app.navigationBars["牛乳"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        let update = app.buttons["notice-recipe-update-2026-10-07-1"]
        reveal(update, app: app); update.tap()
        XCTAssertTrue(app.navigationBars["更新情報"].waitForExistence(timeout: 5))
        let carbonara = app.buttons["notice-recipe-milk_carbonara"]
        reveal(carbonara, app: app); carbonara.tap()
        reveal(app.staticTexts["recipe-time-total"], app: app)
        XCTAssertTrue(app.staticTexts["recipe-time-total"].exists)
        capture(app, large ? "最大文字・追加カルボナーラ画像" : "追加カルボナーラの画像・詳細")
        let instructions = app.segmentedControls["recipe-detail-mode"].buttons["作り方"]
        reveal(instructions, app: app); instructions.tap()
        let last = app.buttons["recipe-step-6"]
        reveal(last, app: app); XCTAssertTrue(last.label.contains("約1分"), last.label)
        capture(app, large ? "最大文字・追加レシピの工程時間" : "追加レシピの工程と分量")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let all = app.buttons["notice-read-all"]
        XCTAssertTrue(all.isHittable); all.tap(); XCTAssertFalse(all.isEnabled)
        capture(app, large ? "最大文字・ダーク・お知らせ既読" : "食材期限と更新情報の一覧・既読")
        app.buttons["閉じる"].tap()
        XCTAssertEqual(bell.value as? String, "未読0件")
        bell.tap(); XCTAssertFalse(app.buttons["notice-read-all"].isEnabled)
        app.buttons["閉じる"].tap()
        let hero = app.buttons["home-recipe-hero"]
        reveal(hero, app: app); XCTAssertTrue(hero.label.contains("作れる"), hero.label)
        capture(app, large ? "最大文字・ダーク・緑の作れるタグ" : "緑背景と白字の作れるタグ")
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<40 {
            if element.exists, element.isHittable, ["recipe-select", "recipe-start", "meal-session-finish", "shopping-complete", "purchase-save", "cooking-save", "store-amount-save"].contains(element.identifier) { return }
            var top = app.navigationBars.firstMatch.frame.maxY
            let fridge = app.collectionViews["inventory-scroll-list"]
            if fridge.exists { top = max(top, fridge.frame.minY) }
            let tabs = app.tabBars.firstMatch
            var bottom = tabs.exists && tabs.isHittable ? tabs.frame.minY : app.frame.maxY
            let list = app.collectionViews.firstMatch
            if list.exists { bottom = min(bottom, list.frame.maxY) }
            for id in ["recipe-select", "recipe-start", "meal-session-finish", "shopping-complete", "purchase-save", "cooking-save", "store-amount-save"] {
                let footer = app.buttons[id]
                if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY - (element.exists && element.elementType == .staticText ? 0 : 16)) }
            }
            if app.keyboards.firstMatch.exists {
                bottom = min(bottom, app.keyboards.firstMatch.frame.minY)
                let search = app.searchFields.firstMatch
                if search.exists && search.frame.minY > top + 44 { bottom = min(bottom, search.frame.minY - 8) }
            }
            if element.exists && element.isHittable && element.frame.maxY <= top
                && element.frame.minY >= app.navigationBars.firstMatch.frame.minY { return }
            let available = max(44, bottom - top)
            var down = towardTop
            var distance = available * 0.6
            if element.exists {
                let frame = element.frame
                let fits = frame.height <= available
                let visible = fits ? frame.minY >= top - 1 && frame.maxY <= bottom + 1
                    : frame.midY > top && frame.midY < bottom
                if visible && (element.isHittable || element.elementType == .staticText || !element.isEnabled) { return }
                down = fits ? frame.minY < top : frame.midY <= top
                let missing = fits ? (down ? top - frame.minY : frame.maxY - bottom)
                    : abs(frame.midY - (top + bottom) / 2)
                // Tiny drags may not cross the list scrolling threshold.
                distance = min(max(missing + 30, 60), available * 0.6)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = top + available * (down ? 0.2 : 0.8)
            let end = start + (down ? distance : -distance)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        print("SCROLL TARGET: \(element.debugDescription)\n\(app.debugDescription)")
        XCTFail("画面内に移動できません: \(element)")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
