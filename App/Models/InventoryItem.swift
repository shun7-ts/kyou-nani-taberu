import Foundation
import SwiftData

@Model
final class InventoryItem {
    @Attribute(.unique) private(set) var id: UUID
    private(set) var ingredientMasterID: UUID?
    private(set) var customIngredientID: UUID?
    private(set) var stockMode: StockMode
    private(set) var quantity: Double?
    private(set) var unit: IngredientUnit?
    private(set) var roughState: RoughStockState?
    var storage: StorageMethod
    var purchasedAt: Date
    var expiresAt: Date?
    var expiryKind: ExpiryKind
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var syncVersion: Int

    init(id: UUID = UUID(), ingredient: IngredientReference, amount: StockAmount,
         storage: StorageMethod, purchasedAt: Date, expiresAt: Date? = nil,
         expiryKind: ExpiryKind = .unspecified, now: Date = .now) throws {
        if case let .exact(value, _) = amount {
            guard value.isFinite && value >= 0 else {
                throw InventoryValidationError.invalidQuantity
            }
        }
        self.id = id
        switch ingredient {
        case let .master(value): ingredientMasterID = value; customIngredientID = nil
        case let .custom(value): ingredientMasterID = nil; customIngredientID = value
        }
        switch amount {
        case let .exact(value, unit):
            stockMode = .exact; quantity = value; self.unit = unit; roughState = nil
        case let .rough(state):
            stockMode = .rough; quantity = nil; unit = nil; roughState = state
        }
        self.storage = storage
        self.purchasedAt = purchasedAt
        self.expiresAt = expiresAt
        self.expiryKind = expiryKind
        createdAt = now
        updatedAt = now
        isDeleted = false
        syncVersion = 0
    }

    func setAmount(_ amount: StockAmount, now: Date = .now) throws {
        switch amount {
        case let .exact(value, unit):
            guard value.isFinite && value >= 0 else {
                throw InventoryValidationError.invalidQuantity
            }
            stockMode = .exact; quantity = value; self.unit = unit; roughState = nil
        case let .rough(state):
            stockMode = .rough; quantity = nil; unit = nil; roughState = state
        }
        updatedAt = now
        syncVersion += 1
    }
}
