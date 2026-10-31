import Foundation
import SwiftData

@Model
final class MealSelection {
    @Attribute(.unique) var id: UUID
    var recipeID: UUID
    var recipeTitle: String
    var servings: Int
    var date: Date
    var state: String
    var updatedAt: Date
    // Optional for lightweight migration of existing selected meals.
    var ingredientPlanData: Data?
    // Nil keeps legacy undated active meals visible as today; never rewrites old selections.
    var scheduledDate: Date?
    // Nil preserves the shopping behavior of selections saved before this option existed.
    var addsShortagesToShopping: Bool?
    var shouldAddShortagesToShopping: Bool { addsShortagesToShopping ?? true }
    func plannedDay(on today: Date = .now) -> Date {
        MealPlanning.day(scheduledDate ?? (isActive ? today : updatedAt))
    }
    func plannedIngredients(recipes: [Recipe]) -> [RecipeIngredient]? {
        if let data = ingredientPlanData { return try? JSONDecoder().decode([RecipeIngredient].self, from: data) }
        return recipes.first { $0.id == recipeID }.map { recipe in
            recipe.ingredients.map { ingredient in
                RecipeIngredient(ingredientKey: ingredient.ingredientKey,
                    quantity: ingredient.amount(servings: servings, base: recipe.baseServings),
                    unit: ingredient.unit, requirement: ingredient.requirement, inventoryMode: ingredient.inventoryMode,
                    scaling: "fixed", thawing: ingredient.thawing, note: ingredient.note)
            }
        }
    }
    // A frozen empty plan deliberately represents a prepared dish: no raw ingredients are reserved or consumed.
    // Nil remains the legacy catalog fallback; corrupt data never becomes a prepared dish.
    var isPrepared: Bool {
        guard let data = ingredientPlanData,
              let plan = try? JSONDecoder().decode([RecipeIngredient].self, from: data) else { return false }
        return plan.isEmpty
    }
    var isActive: Bool { state == "selected" || state == "cooking" }
    init(recipe: Recipe, servings: Int, date: Date = .now) {
        id = UUID(); recipeID = recipe.id; recipeTitle = recipe.title
        self.servings = servings; self.date = date; state = "selected"; updatedAt = date
    }
}
