import Foundation

enum IngredientCategory: String, Codable, CaseIterable {
    case staple, vegetable, mushroom, meat, fish, eggDairy = "egg_dairy"
    case soyProduct = "soy_product", processed, seasoning, other
}
enum IngredientUnit: String, Codable, CaseIterable {
    case piece, gram, kilogram, milliliter, liter, pack, bag, can, block, bunch
    case stalk, clove, slice, serving, portion, tablespoon, teaspoon
}
enum StorageMethod: String, Codable, CaseIterable {
    case refrigerated, frozen, roomTemperature = "room_temperature"
}
enum StockMode: String, Codable { case exact, rough }
enum RoughStockState: String, Codable { case available, low, unavailable }
enum IngredientStatus: String, Codable { case active, deprecated }
enum ExpiryKind: String, Codable { case unspecified, bestBefore, useBy }

/// Exactly one ingredient identity per inventory lot.
enum IngredientReference {
    case master(UUID)
    case custom(UUID)
}
/// Exact and rough stock cannot be supplied simultaneously.
enum StockAmount {
    case exact(Double, IngredientUnit)
    case rough(RoughStockState)
}
enum InventoryValidationError: Error { case invalidQuantity, emptyName }
