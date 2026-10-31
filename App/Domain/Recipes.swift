import Foundation

struct RecipeCatalog: Decodable {
    let schemaVersion: Int
    let recipes: [Recipe]
    enum LoadError: LocalizedError {
        case missingResource, unsupportedSchema, invalidCatalog
        var errorDescription: String? {
            switch self {
            case .missingResource: "同梱のレシピデータが見つかりません。"
            case .unsupportedSchema: "レシピデータの形式に対応していません。"
            case .invalidCatalog: "レシピデータの内容またはIDが不正です。"
            }
        }
    }
    static func load() throws -> [Recipe] {
        let data = try ["recipe-seed-v1", "recipe-additions-v1"].map { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw LoadError.missingResource
            }
            return try Data(contentsOf: url)
        }
        guard let instructions = Bundle.main.url(forResource: "recipe-instructions-v1", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try decode(data, instructionsData: Data(contentsOf: instructions))
    }
    // Existing identities remain intact; additions cannot silently override them.
    static func decode(_ sources: [Data], instructionsData: Data? = nil) throws -> [Recipe] {
        guard !sources.isEmpty else { throw LoadError.invalidCatalog }
        var recipes: [Recipe] = []
        var ids = Set<UUID>(), keys = Set<String>()
        for source in sources {
            let catalog = try JSONDecoder().decode(Self.self, from: source)
            guard catalog.schemaVersion == 1 else { throw LoadError.unsupportedSchema }
            guard !catalog.recipes.isEmpty else { throw LoadError.invalidCatalog }
            for recipe in catalog.recipes {
                guard ids.insert(recipe.id).inserted, keys.insert(recipe.key).inserted,
                      !recipe.key.isEmpty, !recipe.title.isEmpty, recipe.baseServings == 1,
                      recipe.prepMinutes >= 0, recipe.cookMinutes > 0,
                      ["main", "side"].contains(recipe.role), recipe.kind != .all,
                      recipe.kind == nil || recipe.role == (recipe.kind == .main ? "main" : "side"),
                      !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else { throw LoadError.invalidCatalog }
                recipes.append(recipe)
            }
        }
        let active = recipes.filter { $0.status == "active" }
        return try instructionsData.map { try RecipeInstructionsCatalog.apply($0, to: active) } ?? active
    }
}
struct Recipe: Decodable, Identifiable, Equatable {
    let id: UUID
    let key: String
    let title: String
    let summary: String
    let role: String
    var kind: RecipeKind? = nil
    let baseServings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    let ingredients: [RecipeIngredient]
    var steps: [Step]
    let allergens: [String]
    let status: String
    var isPlainRice: Bool { key == "plain_rice" }
    var minutes: Int { prepMinutes + cookMinutes }
    struct Step: Decodable, Identifiable, Equatable {
        var id: Int { order }
        let order: Int
        let text: String
        let timerMinutes: Int?
        var title: String? = nil
        var ingredients: [IngredientUse]? = nil
        var timeNote: String? = nil
        var tip: String? = nil
        struct IngredientUse: Decodable, Equatable {
            let ingredientKey: String
            let fraction: Double
        }
    }
    struct InstructionIngredient {
        let ingredient: RecipeIngredient
        let quantity: Double
    }
    func instructionIngredients(for step: Step, servings: Int) -> [InstructionIngredient] {
        (step.ingredients ?? []).compactMap { use in
            guard let ingredient = ingredients.first(where: { $0.ingredientKey == use.ingredientKey }) else { return nil }
            return InstructionIngredient(ingredient: ingredient,
                quantity: ingredient.amount(servings: servings, base: baseServings) * use.fraction)
        }
    }
}
/// A complete instruction revision leaves identity, ingredient quantities and stock rules intact.
struct RecipeInstructionsCatalog: Decodable {
    let schemaVersion: Int
    let recipes: [Revision]
    struct Revision: Decodable {
        let recipeKey: String
        let prepMinutes: Int
        let cookMinutes: Int
        let steps: [Recipe.Step]
    }
    static func apply(_ data: Data, to originals: [Recipe]) throws -> [Recipe] {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1 else { throw RecipeCatalog.LoadError.unsupportedSchema }
        let keys = Set(originals.map(\.key))
        guard catalog.recipes.count == keys.count,
              Set(catalog.recipes.map(\.recipeKey)) == keys else { throw RecipeCatalog.LoadError.invalidCatalog }
        let revisions = Dictionary(uniqueKeysWithValues: catalog.recipes.map { ($0.recipeKey, $0) })
        return try originals.map { original in
            guard let revision = revisions[original.key] else { throw RecipeCatalog.LoadError.invalidCatalog }
            let allowed = Set(original.ingredients.map(\.ingredientKey))
            var referenced = Set<String>()
            var minutes = 0
            guard revision.prepMinutes >= 0, revision.cookMinutes > 0, !revision.steps.isEmpty,
                  revision.steps.map(\.order) == Array(1...revision.steps.count) else {
                throw RecipeCatalog.LoadError.invalidCatalog
            }
            for step in revision.steps {
                guard let title = step.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !step.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let duration = step.timerMinutes, duration > 0, duration <= 120,
                      let uses = step.ingredients, !uses.isEmpty,
                      Set(uses.map(\.ingredientKey)).count == uses.count else {
                    throw RecipeCatalog.LoadError.invalidCatalog
                }
                minutes += duration
                for use in uses {
                    guard allowed.contains(use.ingredientKey), use.fraction.isFinite,
                          use.fraction > 0, use.fraction <= 1 else { throw RecipeCatalog.LoadError.invalidCatalog }
                    referenced.insert(use.ingredientKey)
                }
            }
            guard referenced == allowed, minutes == revision.prepMinutes + revision.cookMinutes else {
                throw RecipeCatalog.LoadError.invalidCatalog
            }
            var updated = original
            updated.steps = revision.steps
            updated.prepMinutes = revision.prepMinutes
            updated.cookMinutes = revision.cookMinutes
            return updated
        }
    }
}
struct RecipeIngredient: Codable, Identifiable, Equatable {
    var id: String { ingredientKey }
    let ingredientKey: String
    let quantity: Double
    let unit: IngredientUnit
    let requirement: String
    let inventoryMode: String
    let scaling: String
    let thawing: String
    let note: String?
    func amount(servings: Int, base: Int = 1) -> Double {
        quantity * (scaling == "linear" ? Double(servings) / Double(base) : 1)
    }
}
struct StockLot: Equatable {
    let id: UUID
    let masterID: UUID?
    let quantity: Double?
    let unit: IngredientUnit?
    let roughState: RoughStockState?
    let storage: StorageMethod
    let expiresAt: Date?
    let purchasedAt: Date
    let isDeleted: Bool

    init(id: UUID, masterID: UUID? = nil, quantity: Double? = nil, unit: IngredientUnit? = nil,
         roughState: RoughStockState? = nil, storage: StorageMethod = .refrigerated,
         expiresAt: Date? = nil, purchasedAt: Date = .now, isDeleted: Bool = false) {
        self.id = id; self.masterID = masterID; self.quantity = quantity; self.unit = unit
        self.roughState = roughState; self.storage = storage; self.expiresAt = expiresAt
        self.purchasedAt = purchasedAt; self.isDeleted = isDeleted
    }
}
struct Availability {
    enum Status: String { case available, shortage, confirmation, optionalMissing = "optional_missing", ignored }
    let status: Status
    let required: Double
    let shortage: Double
    let unit: IngredientUnit
    let consumption: [(id: UUID, quantity: Double)]
    let thawing: String
    var label: String {
        switch status {
        case .available: "あり"; case .shortage: "不足"
        case .confirmation: "要確認"; case .optionalMissing: "任意・なくても可"; case .ignored: "在庫管理なし"
        }
    }
}
enum RecipeAvailability {
    static func matches(_ ingredient: RecipeIngredient, lots: [StockLot], servings: Int = 1, base: Int = 1, on date: Date = .now) -> Bool {
        if evaluate(ingredient, servings: servings, base: base, lots: lots, on: date).status == .available { return true }
        return lots.contains {
            !$0.isDeleted && $0.roughState == .available && ($0.expiresAt.map {
                Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: date)
            } ?? true)
        }
    }
    /// Calculation takes value snapshots rather than depending on a database context.
    static func evaluate(_ ingredient: RecipeIngredient, servings: Int, base: Int = 1,
                         lots: [StockLot], on date: Date = .now) -> Availability {
        let required = ingredient.amount(servings: servings, base: base)
        let valid = lots.filter {
            !$0.isDeleted && ($0.expiresAt.map {
                Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: date)
            } ?? true)
        }.sorted {
            if $0.expiresAt != $1.expiresAt { return ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
            if $0.purchasedAt != $1.purchasedAt { return $0.purchasedAt < $1.purchasedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let thawing = valid.contains { $0.storage == .frozen }
            ? (ingredient.thawing == "none" ? "thaw_before_cooking" : ingredient.thawing) : ingredient.thawing
        func result(_ status: Availability.Status, shortage: Double = 0,
                    consumption: [(id: UUID, quantity: Double)] = []) -> Availability {
            Availability(status: status, required: required, shortage: shortage, unit: ingredient.unit,
                         consumption: consumption, thawing: thawing)
        }
        if ingredient.inventoryMode == "ignored" { return result(.ignored) }
        if ingredient.inventoryMode == "presence" {
            if valid.contains(where: { $0.roughState == .available || ($0.quantity ?? 0) > 0 }) {
                return result(.available)
            }
            if valid.contains(where: { $0.roughState == .low }) { return result(.confirmation, shortage: required) }
            return result(ingredient.requirement == "optional" ? .optionalMissing : .shortage, shortage: required)
        }
        var remaining = required
        var uncertain = false
        var consumption: [(id: UUID, quantity: Double)] = []
        for lot in valid {
            guard let quantity = lot.quantity, let unit = lot.unit else {
                if lot.roughState == .available || lot.roughState == .low { uncertain = true }
                continue
            }
            guard let available = Units.convert(quantity, from: unit, to: ingredient.unit) else {
                if quantity > 0 { uncertain = true }; continue
            }
            let used = min(remaining, available)
            if used > 0 { consumption.append((lot.id, used)); remaining -= used }
        }
        if remaining < 0.0000001 { return result(.available, consumption: consumption) }
        if uncertain { return result(.confirmation, shortage: remaining, consumption: consumption) }
        if ingredient.requirement == "optional" { return result(.optionalMissing, consumption: consumption) }
        return result(.shortage, shortage: remaining, consumption: consumption)
    }
}


enum RecipeKind: String, CaseIterable, Decodable {
    case main, side, soup, all
    var label: String {
        switch self { case .main: "主食・主菜"; case .side: "副菜"; case .soup: "汁物"; case .all: "すべて" }
    }
    // The original catalog has no kind; its two soup identities remain compatible.
    func includes(_ recipe: Recipe) -> Bool {
        if self == .all { return true }
        if let kind = recipe.kind { return kind == self }
        let soup = ["tofu_wakame_miso_soup", "egg_green_onion_soup"].contains(recipe.key)
        switch self {
        case .all: return true
        case .main: return recipe.role == "main"
        case .side: return recipe.role == "side" && !soup
        case .soup: return soup
        }
    }
}
