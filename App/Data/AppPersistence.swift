import SwiftData

@MainActor
enum AppPersistence {
    static let schema = Schema([IngredientMaster.self, CustomIngredient.self, InventoryItem.self, InventoryEvent.self, MealSelection.self, ShoppingListItem.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
