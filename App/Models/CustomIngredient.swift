import Foundation
import SwiftData

@Model
final class CustomIngredient {
    @Attribute(.unique) private(set) var id: UUID
    var name: String
    var category: IngredientCategory = IngredientCategory.other
    var mappedIngredientMasterID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var syncVersion: Int

    init(id: UUID = UUID(), name: String, mappedIngredientMasterID: UUID? = nil,
         category: IngredientCategory = .other, now: Date = .now) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InventoryValidationError.emptyName }
        self.id = id
        self.name = trimmed
        self.category = category
        self.mappedIngredientMasterID = mappedIngredientMasterID
        createdAt = now
        updatedAt = now
        isDeleted = false
        syncVersion = 0
    }
}
