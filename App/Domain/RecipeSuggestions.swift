import Foundation

/// A temporary purchase intention, never a persisted inventory lot.
struct StorePurchasePlan: Equatable {
    let ingredientKey: String
    let quantity: Double
    let unit: IngredientUnit
    var isValid: Bool {
        !ingredientKey.isEmpty && quantity.isFinite && quantity > 0
            && (!(unit == .kilogram || unit == .liter) || (quantity * 1000).isFinite)
    }
    static func parseQuantity(_ text: String) -> Double? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        if raw.contains(",") {
            guard raw.range(of: "^[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
            raw = raw.replacingOccurrences(of: ",", with: "")
        }
        guard raw.range(of: "^([0-9]+(\\.[0-9]*)?|\\.[0-9]+)$", options: .regularExpression) != nil,
              let value = Double(raw), value.isFinite, value > 0 else { return nil }
        return value
    }
    static func availability(_ ingredient: RecipeIngredient, plan: Self, masterID: UUID,
                             stock: [StockLot], servings: Int, base: Int, on date: Date) -> Availability? {
        guard plan.isValid, plan.ingredientKey == ingredient.ingredientKey,
              ingredient.requirement == "required", ingredient.inventoryMode != "ignored", ingredient.quantity > 0 else { return nil }
        // Presence alone cannot prove that the entered amount meets the recipe.
        let exact = RecipeIngredient(ingredientKey: ingredient.ingredientKey, quantity: ingredient.quantity,
            unit: ingredient.unit, requirement: ingredient.requirement, inventoryMode: "exact",
            scaling: ingredient.scaling, thawing: ingredient.thawing, note: ingredient.note)
        let hypothetical = StockLot(id: UUID(), masterID: masterID, quantity: plan.quantity, unit: plan.unit)
        return RecipeAvailability.evaluate(exact, servings: servings, base: base,
            lots: stock.filter { $0.masterID == masterID } + [hypothetical], on: date)
    }
}

struct RecipeFood: Equatable {
    let id: UUID
    let key: String
    let name: String
}
struct SuggestedIngredient: Identifiable {
    var id: String { ingredient.ingredientKey }
    let ingredient: RecipeIngredient
    let name: String
    let availability: Availability
    let matches: Bool
    let needsThawing: Bool
    let cookFromFrozen: Bool
    var isRequired: Bool { ingredient.requirement == "required" && ingredient.inventoryMode != "ignored" }
}
enum RecipeCookingTag: String {
    case ready, shopping, quantity, review
    var label: String {
        switch self { case .ready: "作れる"; case .shopping: "買い足し"; case .quantity: "食材あり"; case .review: "材料を確認" }
    }
}

struct RecipeSuggestion: Identifiable {
    var id: UUID { recipe.id }
    let recipe: Recipe
    let servings: Int
    let ingredients: [SuggestedIngredient]
    var shoppingIngredientKey: String? = nil
    var storePlan: StorePurchasePlan? = nil
    var plannedAvailability: Availability? = nil
    var required: [SuggestedIngredient] { ingredients.filter(\.isRequired) }
    var plannedIngredient: SuggestedIngredient? {
        required.first { $0.ingredient.ingredientKey == shoppingIngredientKey && $0.ingredient.quantity > 0 }
    }
    var comparisonIngredients: [SuggestedIngredient] {
        required.filter { $0.ingredient.ingredientKey != plannedIngredient?.ingredient.ingredientKey }
    }
    var additionalShortages: [SuggestedIngredient] { comparisonIngredients.filter { $0.availability.status == .shortage } }
    var additionalConfirmation: [SuggestedIngredient] { comparisonIngredients.filter { $0.availability.status == .confirmation } }
    var matchedCount: Int { comparisonIngredients.filter(\.matches).count }
    var coverage: Double {
        comparisonIngredients.isEmpty ? (plannedIngredient == nil ? 0 : 1)
            : Double(matchedCount) / Double(comparisonIngredients.count)
    }
    var confirmation: [SuggestedIngredient] { required.filter { $0.availability.status == .confirmation } }
    var shortages: [SuggestedIngredient] { required.filter { $0.availability.status == .shortage } }
    var ready: Bool { !required.isEmpty && required.allSatisfy { $0.availability.status == .available } }
    var cookingTags: [RecipeCookingTag] {
        if ready { return [.ready] }
        var tags: [RecipeCookingTag] = []
        if !shortages.isEmpty { tags.append(.shopping) }
        if !confirmation.isEmpty { tags.append(.quantity) }
        return tags.isEmpty ? [.review] : tags
    }
    var matchLabel: String {
        if plannedIngredient != nil && comparisonIngredients.isEmpty { return "ほかに必要な材料はありません" }
        return "\(plannedIngredient == nil ? "食材一致" : "ほかの食材一致") \(Int(coverage * 100))%（\(matchedCount)/\(comparisonIngredients.count)品）"
    }
    var plannedLabel: String? {
        plannedIngredient.map { "買う予定：\($0.name)（料理の必要量：\($0.availability.required.formatted())\($0.ingredient.unit.label)・\(servings)人分）" }
    }
    var plannedAmountLabel: String? {
        guard let plan = storePlan, let result = plannedAvailability else { return nil }
        let status: String
        switch result.status {
        case .available: status = "量は足ります（購入後）"
        case .shortage: status = "さらに\(result.shortage.formatted())\(result.unit.label)不足"
        default: status = "量・単位は要確認"
        }
        return "購入予定 \(plan.quantity.formatted())\(plan.unit.label)＋冷蔵庫：" + status
    }
    var plannedAmountRank: Int {
        switch plannedAvailability?.status {
        case .available: 0
        case .confirmation: 1
        case .shortage: 2
        default: 0
        }
    }
    var reason: String {
        if plannedIngredient != nil {
            if plannedAvailability?.status == .shortage { return "この食材の量が足りません。買う量か人数を変更してください" }
            if plannedAvailability?.status == .confirmation { return "この食材の量・単位を確認してください" }
            if comparisonIngredients.isEmpty { return "買う食材の量を確認しましょう" }
            if !additionalConfirmation.isEmpty && !additionalShortages.isEmpty { return "追加の買い足しと、冷蔵庫の量の確認が必要です" }
            if !additionalConfirmation.isEmpty { return "ほかの食材はありますが、量の確認が必要です" }
            if !additionalShortages.isEmpty { return "この食材と不足分を買うと作れます。量を確認しましょう" }
            return "この食材を必要量買えば、ほかの材料は冷蔵庫にそろっています"
        }
        if required.isEmpty { return "材料を確認して献立を選びましょう" }
        if ready { return "必須材料は冷蔵庫にそろっています" }
        if !confirmation.isEmpty && !shortages.isEmpty { return "買い足しと在庫量の確認が必要です" }
        if !confirmation.isEmpty { return "買い足す前に、在庫の量を確認しましょう" }
        return "足りない食材を買い足すと作れます"
    }
    private func names(_ values: [SuggestedIngredient]) -> String {
        values.prefix(3).map(\.name).joined(separator: "、") + (values.count > 3 ? " ほか\(values.count - 3)品" : "")
    }
    var shortageLabel: String? {
        let values = plannedIngredient == nil ? shortages : additionalShortages
        return values.isEmpty ? nil : "\(plannedIngredient == nil ? "買い足し" : "追加の買い足し") \(values.count)品：" + names(values)
    }
    var confirmationLabel: String? {
        let values = plannedIngredient == nil ? confirmation : additionalConfirmation
        return values.isEmpty ? nil : "量を要確認：" + values.map(\.name).joined(separator: "、")
    }
    var thawingLabel: String? {
        let foods = comparisonIngredients.filter(\.needsThawing)
        return foods.isEmpty ? nil : "解凍が必要：" + names(foods)
    }
    var frozenCookingLabel: String? {
        let foods = comparisonIngredients.filter(\.cookFromFrozen)
        return foods.isEmpty ? nil : "凍ったまま調理：" + names(foods)
    }
}

/// Inventory matching is distinct from guaranteed quantity sufficiency.
/// Expiry is used to exclude unusable lots, never to reorder the Home hero.
enum RecipeSuggestions {
    private struct EvaluationIndex {
        let foods: [String: RecipeFood]
        let lots: [UUID: [StockLot]]
        init(foods: [RecipeFood], stock: [StockLot]) {
            self.foods = Dictionary(uniqueKeysWithValues: foods.map { ($0.key, $0) })
            lots = Dictionary(grouping: stock.filter { $0.masterID != nil }, by: { $0.masterID! })
        }
    }
    /// Match the catalog's stable key, not titles or optional toppings. Missing stock
    /// changes availability only; it never relaxes the requested ingredient.
    static func includesRequiredIngredient(_ recipe: Recipe, key: String?) -> Bool {
        guard let key else { return true }
        return recipe.ingredients.contains {
            $0.ingredientKey == key && $0.requirement == "required"
                && $0.inventoryMode != "ignored" && $0.quantity > 0
        }
    }
    static func evaluate(_ recipe: Recipe, foods: [RecipeFood], stock: [StockLot],
                         servings: Int = 1, shoppingIngredientKey: String? = nil,
                         storePlan: StorePurchasePlan? = nil, on date: Date = .now) -> RecipeSuggestion {
        evaluate(recipe, index: EvaluationIndex(foods: foods, stock: stock), stock: stock,
            servings: servings, shoppingIngredientKey: shoppingIngredientKey, storePlan: storePlan, on: date)
    }
    private static func evaluate(_ recipe: Recipe, index: EvaluationIndex, stock: [StockLot],
                                 servings: Int, shoppingIngredientKey: String?,
                                 storePlan: StorePurchasePlan?, on date: Date) -> RecipeSuggestion {
        let byKey = index.foods, lots = index.lots
        let ingredients = recipe.ingredients.map { ingredient in
            let food = byKey[ingredient.ingredientKey]
            let matching = food.map { lots[$0.id] ?? [] } ?? []
            let result = RecipeAvailability.evaluate(ingredient, servings: servings, base: recipe.baseServings, lots: matching, on: date)
            let usesFrozen = matching.contains { $0.storage == .frozen && StockExpiry.hasStock($0)
                && StockExpiry.usable($0, on: date) }
            return SuggestedIngredient(ingredient: ingredient, name: food?.name ?? "未登録の食材",
                availability: result,
                matches: RecipeAvailability.matches(ingredient, lots: matching, servings: servings, base: recipe.baseServings, on: date),
                needsThawing: usesFrozen && result.thawing != "none" && result.thawing != "cook_from_frozen",
                cookFromFrozen: usesFrozen && result.thawing == "cook_from_frozen")
        }
        let plan = storePlan.flatMap { $0.isValid && $0.ingredientKey == shoppingIngredientKey ? $0 : nil }
        let assessment = plan.flatMap { plan in
            recipe.ingredients.first { $0.ingredientKey == plan.ingredientKey }.flatMap { ingredient in
                byKey[plan.ingredientKey].flatMap { food in
                    StorePurchasePlan.availability(ingredient, plan: plan, masterID: food.id, stock: stock,
                        servings: servings, base: recipe.baseServings, on: date)
                }
            }
        }
        return RecipeSuggestion(recipe: recipe, servings: servings, ingredients: ingredients,
            shoppingIngredientKey: shoppingIngredientKey, storePlan: assessment == nil ? nil : plan, plannedAvailability: assessment)
    }
    static func candidates(_ recipes: [Recipe], foods: [RecipeFood], stock: [StockLot],
                           requiredIngredientKey: String? = nil, shoppingIngredientKey: String? = nil,
                           storePlan: StorePurchasePlan? = nil, onlyEnoughForPlannedIngredient: Bool = false,
                           servings: Int = 1, allowedRoles: Set<String> = ["main"],
                           on date: Date = .now) -> [RecipeSuggestion] {
        let index = EvaluationIndex(foods: foods, stock: stock)
        // Plain rice is a tray staple, rather than a recommendation for a complete dish.
        return recipes.filter { !($0.isPlainRice) && allowedRoles.contains($0.role) && $0.status == "active"
            && includesRequiredIngredient($0, key: requiredIngredientKey) }
            .map { evaluate($0, index: index, stock: stock, servings: servings,
                shoppingIngredientKey: shoppingIngredientKey == requiredIngredientKey ? shoppingIngredientKey : nil,
                storePlan: storePlan, on: date) }
            .filter { !onlyEnoughForPlannedIngredient || $0.plannedAvailability?.status == .available }
            .map(RankedSuggestion.init)
            .sorted {
                if $0.amountRank != $1.amountRank { return $0.amountRank < $1.amountRank }
                if $0.coverage != $1.coverage { return $0.coverage > $1.coverage }
                if $0.hasPlanned && $1.hasPlanned && $0.shortages != $1.shortages {
                    return $0.shortages < $1.shortages
                }
                if $0.confirmation != $1.confirmation { return $0.confirmation < $1.confirmation }
                if $0.suggestion.recipe.minutes != $1.suggestion.recipe.minutes { return $0.suggestion.recipe.minutes < $1.suggestion.recipe.minutes }
                if $0.suggestion.recipe.key != $1.suggestion.recipe.key { return $0.suggestion.recipe.key < $1.suggestion.recipe.key }
                return $0.suggestion.id.uuidString < $1.suggestion.id.uuidString
            }.map(\.suggestion)
    }
    static func mealPickerCandidates(_ recipes: [Recipe], foods: [RecipeFood], stock: [StockLot],
                                     servings: Int, on date: Date) -> [RecipeSuggestion] {
        let index = EvaluationIndex(foods: foods, stock: stock)
        return recipes.map { evaluate($0, index: index, stock: stock, servings: servings,
            shoppingIngredientKey: nil, storePlan: nil, on: date) }
            .sorted { left, right in
                if left.recipe.isPlainRice != right.recipe.isPlainRice { return left.recipe.isPlainRice }
                func readiness(_ value: RecipeSuggestion) -> Int {
                    if value.ready { return 0 }
                    if value.required.isEmpty { return 3 }
                    return value.shortages.isEmpty ? 1 : 2
                }
                let leftReadiness = readiness(left), rightReadiness = readiness(right)
                if leftReadiness != rightReadiness { return leftReadiness < rightReadiness }
                if left.shortages.count != right.shortages.count { return left.shortages.count < right.shortages.count }
                if left.confirmation.count != right.confirmation.count { return left.confirmation.count < right.confirmation.count }
                if left.coverage != right.coverage { return left.coverage > right.coverage }
                if left.recipe.minutes != right.recipe.minutes { return left.recipe.minutes < right.recipe.minutes }
                return left.recipe.key < right.recipe.key
            }
    }
    private struct RankedSuggestion {
        let suggestion: RecipeSuggestion
        let amountRank: Int
        let coverage: Double
        let hasPlanned: Bool
        let shortages: Int
        let confirmation: Int
        init(_ suggestion: RecipeSuggestion) {
            self.suggestion = suggestion
            amountRank = suggestion.plannedAmountRank; coverage = suggestion.coverage
            hasPlanned = suggestion.plannedIngredient != nil
            shortages = suggestion.additionalShortages.count; confirmation = suggestion.additionalConfirmation.count
        }
    }
}

/// View-local, single-entry memoization. No model objects or persistent data are cached.
@MainActor
final class HomeSuggestionCache {
    private struct Input: Equatable {
        let recipes: [Recipe]
        let foods: [RecipeFood]
        let stock: [StockLot]
        let requiredKey: String?
        let servings: Int
        let day: Date
        let calendar: Calendar
    }
    private var input: Input?
    private var value: [RecipeSuggestion] = []
    private(set) var evaluationCount = 0
    func candidates(_ recipes: [Recipe], foods: [RecipeFood], stock: [StockLot],
                    requiredIngredientKey: String?, servings: Int, on date: Date) -> [RecipeSuggestion] {
        let next = Input(recipes: recipes, foods: foods, stock: stock, requiredKey: requiredIngredientKey,
            servings: servings, day: Calendar.current.startOfDay(for: date), calendar: .current)
        if input == next { return value }
        let result = RecipeSuggestions.candidates(recipes, foods: foods, stock: stock,
            requiredIngredientKey: requiredIngredientKey, servings: servings, allowedRoles: ["main", "side"], on: date)
        input = next; value = result; evaluationCount += 1
        return result
    }
}

enum StockExpiry {
    static func hasStock(_ lot: StockLot) -> Bool {
        (lot.quantity ?? 0) > 0 || lot.roughState == .available || lot.roughState == .low
    }
    static func usable(_ lot: StockLot, on date: Date, calendar: Calendar = .current) -> Bool {
        !lot.isDeleted && (lot.expiresAt.map { calendar.startOfDay(for: $0) >= calendar.startOfDay(for: date) } ?? true)
    }
    /// Calendar-day windows include the entire last day, and keep expired stock separate.
    static func near(_ stock: [StockLot], on date: Date, days: Int = 2, calendar: Calendar = .current) -> [UUID] {
        guard days >= 0, let end = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else { return [] }
        return ordered(stock.filter { lot in
            guard let expiry = lot.expiresAt else { return false }
            return hasStock(lot) && usable(lot, on: date, calendar: calendar) && calendar.startOfDay(for: expiry) <= end
        })
    }
    static func expired(_ stock: [StockLot], on date: Date, calendar: Calendar = .current) -> [UUID] {
        ordered(stock.filter { !$0.isDeleted && hasStock($0) && $0.expiresAt.map { calendar.startOfDay(for: $0) < calendar.startOfDay(for: date) } == true })
    }
    private static func ordered(_ stock: [StockLot]) -> [UUID] {
        stock.sorted {
            if $0.expiresAt != $1.expiresAt { return ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
            return $0.id.uuidString < $1.id.uuidString
        }.map(\.id)
    }
}
