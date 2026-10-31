import Foundation
import SwiftData

@Model
final class ShoppingListItem {
    @Attribute(.unique) var id: UUID
    var ingredientMasterID: UUID?
    var name: String
    var quantity: Double
    var unit: IngredientUnit
    var requiredQuantity: Double?
    var sourceMealID: UUID?
    var sourceRecipeTitle: String?
    // Optional for legacy stores; explicit day/week additions retain their reservation scope.
    var materialScopeData: Data?
    // Only newly generated, unedited rows may follow later reservation recalculations.
    var automaticallyManaged: Bool?
    var needsConfirmation: Bool
    var isChecked: Bool
    var isAddedToInventory: Bool
    var createdAt: Date
    init(masterID: UUID?, name: String, quantity: Double, unit: IngredientUnit,
         required: Double? = nil, meal: MealSelection? = nil, needsConfirmation: Bool = false) {
        id = UUID(); ingredientMasterID = masterID; self.name = name
        self.quantity = quantity; self.unit = unit; requiredQuantity = required
        sourceMealID = meal?.id; sourceRecipeTitle = meal?.recipeTitle
        materialScopeData = nil
        automaticallyManaged = meal == nil ? false : true
        self.needsConfirmation = needsConfirmation; isChecked = false; isAddedToInventory = false
        createdAt = .now
    }
}
