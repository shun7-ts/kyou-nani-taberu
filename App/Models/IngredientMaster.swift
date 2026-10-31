import Foundation
import SwiftData

@Model
final class IngredientMaster {
    @Attribute(.unique) private(set) var id: UUID
    @Attribute(.unique) private(set) var key: String
    var canonicalName: String
    var aliases: [String]
    var category: IngredientCategory
    var defaultUnit: IngredientUnit
    var allowedUnits: [IngredientUnit]
    var defaultStorage: StorageMethod
    var stockMode: StockMode
    var isPantryStaple: Bool
    var trackInventory: Bool
    var shoppingEligible: Bool
    var allergens: [String]
    var status: IngredientStatus
    var catalogVersion: String
    var createdAt: Date
    var updatedAt: Date

    init(seed: IngredientSeed, catalogVersion: String, now: Date = .now) {
        id = seed.id
        key = seed.key
        canonicalName = seed.canonicalName
        aliases = seed.aliases
        category = seed.category
        defaultUnit = seed.defaultUnit
        allowedUnits = seed.allowedUnits
        defaultStorage = seed.defaultStorage
        stockMode = seed.stockMode
        isPantryStaple = seed.isPantryStaple
        trackInventory = seed.trackInventory
        shoppingEligible = seed.shoppingEligible
        allergens = seed.allergens
        status = seed.status
        self.catalogVersion = catalogVersion
        createdAt = now
        updatedAt = now
    }

    func update(from seed: IngredientSeed, catalogVersion: String, now: Date = .now) {
        // UUID and fixed key remain unchanged across catalog updates.
        canonicalName = seed.canonicalName
        aliases = seed.aliases
        category = seed.category
        defaultUnit = seed.defaultUnit
        allowedUnits = seed.allowedUnits
        defaultStorage = seed.defaultStorage
        stockMode = seed.stockMode
        isPantryStaple = seed.isPantryStaple
        trackInventory = seed.trackInventory
        shoppingEligible = seed.shoppingEligible
        allergens = seed.allergens
        status = seed.status
        self.catalogVersion = catalogVersion
        updatedAt = now
    }
}
