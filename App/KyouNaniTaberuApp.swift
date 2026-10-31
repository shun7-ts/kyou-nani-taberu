import SwiftUI
import SwiftData

@main
struct KyouNaniTaberuApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    private let recipes: [Recipe]
    private let preferences: UserDefaults
    @StateObject private var notices: ExpiryNotifications
    @StateObject private var session: AppSession
    @StateObject private var inventoryUndo: InventoryUndoCenter

    init() {
        AppFont.register(); AppFont.configureNativeControls()
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let appPreferences: UserDefaults = testing ? UserDefaults(suiteName: "com.kyounanitaberu.uitests")! : .standard
        preferences = appPreferences
        if testing { preferences.removePersistentDomain(forName: "com.kyounanitaberu.uitests") }
        if testing && !ProcessInfo.processInfo.arguments.contains("--ui-privacy-intro") {
            appPreferences.set(PrivacyPolicy.version, forKey: AppPreferences.policyVersion)
            appPreferences.set(Date.now.timeIntervalSince1970, forKey: AppPreferences.policyDate)
        }
        var notificationClient: ExpiryNotificationClient?
        if testing && ProcessInfo.processInfo.arguments.contains("--ui-reset-fixture") {
            let client = TestExpiryNotificationClient(); client.status = .authorized; notificationClient = client
        }
        _session = StateObject(wrappedValue: AppSession(preferences: appPreferences))
        _notices = StateObject(wrappedValue: ExpiryNotifications(defaults: appPreferences, client: notificationClient, testing: testing))
        do {
            let store = try AppPersistence.makeContainer(inMemory: testing)
            try IngredientMasterImporter.load(into: store)
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-expiry") {
                let context = ModelContext(store)
                if let egg = try context.fetch(FetchDescriptor<IngredientMaster>()).first(where: { $0.key == "egg" }) {
                    try InventoryService(container: store).save(InventoryDraft(masterID: egg.id, amount: .rough(.available),
                        expiresAt: Calendar.current.date(byAdding: .day, value: 10, to: .now), expiryKind: .useBy))
                }
                appPreferences.set(true, forKey: "initialInventorySetupCompleted")
            }
            let loadedRecipes = try RecipeCatalog.load()
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-reset-fixture") {
                try Self.seedResetFixture(store: store, recipes: loadedRecipes, preferences: appPreferences)
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-old-consent-fixture") {
                appPreferences.set(1, forKey: AppPreferences.policyVersion)
                appPreferences.set(1, forKey: "receiptConsentVersion")
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-suggestion-fixture") {
                let context = ModelContext(store)
                let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
                let service = InventoryService(container: store)
                let exact = ProcessInfo.processInfo.arguments.contains("--ui-suggestion-exact")
                let fixtures: [(String, StockAmount, Int?)] = [
                    ("cooked_rice", exact ? .exact(200, .gram) : .rough(.available), nil), ("canned_tuna", exact ? .exact(1, .can) : .rough(.available), nil),
                    ("mayonnaise", ProcessInfo.processInfo.arguments.contains("--ui-seasoning-exact") ? .exact(200, .gram) : .rough(.available), nil), ("soy_sauce", .rough(.available), nil),
                    ("egg", .exact(6, .piece), -1), ("milk", .exact(500, .milliliter), 2)]
                for (key, amount, days) in fixtures {
                    if let master = masters.first(where: { $0.key == key }) {
                        try service.save(InventoryDraft(masterID: master.id, amount: amount,
                            expiresAt: days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }, expiryKind: .useBy))
                    }
                }
                appPreferences.set(true, forKey: "initialInventorySetupCompleted")
                appPreferences.set(true, forKey: "expiryNotificationIntroductionShown")
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-fridge-frame-fixture") {
                let ctx = ModelContext(store)
                let masters = try ctx.fetch(FetchDescriptor<IngredientMaster>())
                let existing = Set(try ctx.fetch(FetchDescriptor<InventoryItem>()).compactMap(\.ingredientMasterID))
                let service = InventoryService(container: store)
                let keys = ["onion", "carrot", "potato", "tomato", "cabbage", "eggplant", "cucumber", "spinach", "lettuce", "broccoli", "green_pepper", "bean_sprouts", "shimeji", "enoki", "shiitake", "chicken_thigh", "chicken_breast", "ground_pork", "pork_slices", "salmon", "tofu", "frozen_udon", "natto", "butter", "cheese", "flour", "sugar", "salt", "black_pepper", "sesame_oil", "olive_oil", "miso", "vinegar", "mirin", "cooking_sake", "ketchup", "ponzu", "zucchini", "apple", "banana"]
                for key in keys {
                    if let food = masters.first(where: { $0.key == key }), !existing.contains(food.id) {
                        try service.save(InventoryDraft(masterID: food.id, amount: .rough(.available), storage: food.defaultStorage))
                    }
                }
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-week-plan-fixture"),
               let recipe = loadedRecipes.first(where: { $0.key == "tuna_mayo_bowl" }) {
                let service = MealService(container: store)
                try service.select(recipe: recipe, servings: 1, scheduledDate: .now)
                try service.select(recipe: recipe, servings: 2, scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-archive-fixture") {
                let service = MealService(container: store)
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: MealPlanning.day(.now))!
                let rice = loadedRecipes.first { $0.isPlainRice }!
                let side = loadedRecipes.first { $0.key == "chilled_tofu" }!
                try service.select(recipe: rice, servings: 1, scheduledDate: yesterday, addShortagesToShopping: false)
                let meal = try ModelContext(store).fetch(FetchDescriptor<MealSelection>()).first { $0.recipeID == rice.id }!
                try service.cook(mealID: meal.id, recipe: rice, drafts: [], updateInventory: false)
                try service.select(recipe: side, servings: 1, scheduledDate: yesterday, addShortagesToShopping: false)
                try service.saveManual(name: "手入力の商品", quantity: 1, unit: .piece)
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-stock-peek-fixture") {
                let ctx = ModelContext(store)
                let master = try ctx.fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "canned_tuna" }!
                let custom = try CustomIngredient(name: "開封したツナ", mappedIngredientMasterID: master.id)
                ctx.insert(custom)
                for (amount, days, deleted) in [(0.25, 2, false), (1.0, -1, false), (99.0, 2, true)] {
                    let item = try InventoryItem(ingredient: .master(master.id), amount: .exact(amount, .can), storage: .frozen,
                        purchasedAt: .now, expiresAt: Calendar.current.date(byAdding: .day, value: days, to: .now))
                    item.isDeleted = deleted; ctx.insert(item)
                }
                ctx.insert(try InventoryItem(ingredient: .custom(custom.id), amount: .rough(.low), storage: .refrigerated, purchasedAt: .now))
                try ctx.save()
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-purchase-compact-fixture") {
                let ctx = ModelContext(store)
                let masters = try ctx.fetch(FetchDescriptor<IngredientMaster>())
                for (key, name) in [("egg", "卵"), ("onion", "玉ねぎ"), ("", "キッチンペーパー")] {
                    let row = ShoppingListItem(masterID: masters.first { $0.key == key }?.id, name: name, quantity: 1, unit: .piece)
                    row.isChecked = true; ctx.insert(row)
                }
                try ctx.save()
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-purchase-seasoning-fixture") {
                let ctx = ModelContext(store)
                let masters = try ctx.fetch(FetchDescriptor<IngredientMaster>())
                for key in ["soy_sauce", "salt"] {
                    let master = masters.first { $0.key == key }!
                    for item in try ctx.fetch(FetchDescriptor<InventoryItem>()) where item.ingredientMasterID == master.id {
                        item.storage = .roomTemperature; item.expiryKind = .unspecified
                    }
                    let row = ShoppingListItem(masterID: master.id, name: master.canonicalName, quantity: 1, unit: master.defaultUnit)
                    row.isChecked = true; ctx.insert(row)
                }
                try ctx.save()
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-materials-fixture") {
                let service = MealService(container: store)
                let tuna = loadedRecipes.first { $0.key == "tuna_mayo_bowl" }!
                let chicken = loadedRecipes.first { $0.key == "teriyaki_chicken" }!
                let master = try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()).first { $0.key == "chicken_thigh" }!
                try InventoryService(container: store).save(InventoryDraft(masterID: master.id, amount: .rough(.available)))
                try service.select(recipe: tuna, servings: 2, scheduledDate: .now, addShortagesToShopping: false)
                try service.select(recipe: tuna, servings: 1, scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)!, addShortagesToShopping: false)
                try service.select(recipe: chicken, servings: 1, scheduledDate: .now, addShortagesToShopping: false)
                try service.saveManual(name: "保存する手入力", quantity: 1, unit: .piece)
            }
            if testing && ProcessInfo.processInfo.arguments.contains("--ui-store-screenshots") {
                let ctx = ModelContext(store)
                let masters = try ctx.fetch(FetchDescriptor<IngredientMaster>())
                let service = InventoryService(container: store)
                let stock: [(String, StockAmount, Int?)] = [
                    ("cooked_rice", .exact(400, .gram), nil), ("canned_tuna", .exact(1, .can), nil),
                    ("chicken_thigh", .exact(100, .gram), 2), ("tofu", .exact(300, .gram), 3),
                    ("egg", .exact(6, .piece), 5), ("milk", .exact(500, .milliliter), 2),
                    ("onion", .exact(2, .piece), nil), ("carrot", .exact(1, .piece), nil),
                    ("shimeji", .rough(.available), 4), ("cucumber", .exact(1, .piece), nil)]
                for (key, amount, days) in stock {
                    if let master = masters.first(where: { $0.key == key }) {
                        try service.save(InventoryDraft(masterID: master.id, amount: amount, storage: master.defaultStorage,
                            expiresAt: days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }, expiryKind: .useBy))
                    }
                }
                for key in ["soy_sauce", "mirin", "sugar", "cooking_sake", "mayonnaise", "miso", "sesame_oil", "salt"] {
                    if let master = masters.first(where: { $0.key == key }) {
                        try service.save(InventoryDraft(masterID: master.id, amount: .rough(.available), storage: master.defaultStorage))
                    }
                }
                try MealService(container: store).saveManual(name: "トマト", quantity: 2, unit: .piece)
                appPreferences.set(true, forKey: "initialInventorySetupCompleted")
                appPreferences.set(true, forKey: "expiryNotificationIntroductionShown")
            }
            recipes = loadedRecipes
            container = store
            startupError = nil
        } catch {
            container = nil
            recipes = []
            startupError = error.localizedDescription
        }
        let undoContainer = container
        _inventoryUndo = StateObject(wrappedValue: InventoryUndoCenter(container: undoContainer))
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView(recipes: recipes).id(session.generation).environmentObject(session).environmentObject(notices).environmentObject(inventoryUndo).modelContainer(container).defaultAppStorage(preferences).tint(AppTheme.accent).font(AppFont.body)
                    .allowsHitTesting(!session.isResetting)
                    .overlay {
                        if session.isResetting {
                            ZStack { AppTheme.background.opacity(0.95).ignoresSafeArea(); ProgressView("データを削除しています…") }
                        }
                    }
                    .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-dark") ? .dark : nil)
            } else {
                ContentUnavailableView("食材データを読み込めませんでした",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(startupError ?? "起動に失敗しました。"))
            }
        }
    }
    private static func seedResetFixture(store: ModelContainer, recipes: [Recipe], preferences: UserDefaults) throws {
        let context = ModelContext(store)
        guard let egg = try context.fetch(FetchDescriptor<IngredientMaster>()).first(where: { $0.key == "egg" }), let recipe = recipes.first else { return }
        let service = InventoryService(container: store)
        try service.save(InventoryDraft(masterID: egg.id, amount: .exact(6, .piece), expiresAt: Calendar.current.date(byAdding: .day, value: 10, to: .now)))
        let removed = try service.save(InventoryDraft(customName: "Reset test sauce"))
        try service.discard(id: removed)
        let meal = MealSelection(recipe: recipe, servings: 1); context.insert(meal)
        context.insert(ShoppingListItem(masterID: egg.id, name: "卵", quantity: 2, unit: .piece, meal: meal))
        let bought = ShoppingListItem(masterID: nil, name: "購入済みの記録", quantity: 1, unit: .piece)
        bought.isChecked = true; bought.isAddedToInventory = true; context.insert(bought)
        try context.save()
        preferences.set(true, forKey: "initialInventorySetupCompleted")
        preferences.set(ReceiptPrivacyView.currentVersion, forKey: "receiptConsentVersion"); preferences.set(1.0, forKey: "receiptConsentDate")
        preferences.set(1, forKey: "voiceConsentVersion"); preferences.set(1.0, forKey: "voiceConsentDate")
    }

}
