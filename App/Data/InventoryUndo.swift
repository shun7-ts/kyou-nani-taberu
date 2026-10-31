import Foundation
import SwiftData
import Combine

private struct StockSnapshot: Equatable {
    let id: UUID
    let masterID: UUID?
    let customID: UUID?
    let mode: StockMode
    let quantity: Double?
    let unit: IngredientUnit?
    let rough: RoughStockState?
    let storage: StorageMethod
    let purchasedAt: Date
    let expiresAt: Date?
    let expiryKind: ExpiryKind
    let createdAt: Date
    let updatedAt: Date
    let deleted: Bool
    let version: Int
    init(_ item: InventoryItem) {
        id = item.id; masterID = item.ingredientMasterID; customID = item.customIngredientID
        mode = item.stockMode; quantity = item.quantity; unit = item.unit; rough = item.roughState
        storage = item.storage; purchasedAt = item.purchasedAt; expiresAt = item.expiresAt
        expiryKind = item.expiryKind; createdAt = item.createdAt; updatedAt = item.updatedAt
        deleted = item.isDeleted; version = item.syncVersion
    }
    func restore(to item: InventoryItem) throws {
        if mode == .exact, let quantity, let unit { try item.setAmount(.exact(quantity, unit)) }
        else if mode == .rough, let rough { try item.setAmount(.rough(rough)) }
        else { throw InventoryUndoError.conflict }
        item.storage = storage; item.purchasedAt = purchasedAt; item.expiresAt = expiresAt
        item.expiryKind = expiryKind; item.createdAt = createdAt; item.isDeleted = deleted
        // Keep the new update timestamp/version: an old voice draft must stay stale after undo.
    }
}

private struct MealSnapshot: Equatable {
    let addsShortagesToShopping: Bool?
    let scheduledDate: Date?
    let ingredientPlanData: Data?
    let id: UUID
    let recipeID: UUID
    let title: String
    let servings: Int
    let date: Date
    let state: String
    let updatedAt: Date
    init(_ value: MealSelection) {
        addsShortagesToShopping = value.addsShortagesToShopping
        scheduledDate = value.scheduledDate; ingredientPlanData = value.ingredientPlanData
        id = value.id; recipeID = value.recipeID; title = value.recipeTitle
        servings = value.servings; date = value.date; state = value.state; updatedAt = value.updatedAt
    }
}
private struct ShoppingSnapshot: Equatable {
    let materialScopeData: Data?
    let automaticallyManaged: Bool?
    let id: UUID
    let masterID: UUID?
    let name: String
    let quantity: Double
    let unit: IngredientUnit
    let required: Double?
    let mealID: UUID?
    let title: String?
    let needsConfirmation: Bool
    let checked: Bool
    let added: Bool
    let createdAt: Date
    init(_ value: ShoppingListItem) {
        materialScopeData = value.materialScopeData
        automaticallyManaged = value.automaticallyManaged
        id = value.id; masterID = value.ingredientMasterID; name = value.name
        quantity = value.quantity; unit = value.unit; required = value.requiredQuantity
        mealID = value.sourceMealID; title = value.sourceRecipeTitle; needsConfirmation = value.needsConfirmation
        checked = value.isChecked; added = value.isAddedToInventory; createdAt = value.createdAt
    }
}

private struct CustomMappingSnapshot: Equatable {
    let id: UUID
    let masterID: UUID?
    let category: IngredientCategory
    let updatedAt: Date
    let version: Int
    init(_ custom: CustomIngredient) {
        id = custom.id; masterID = custom.mappedIngredientMasterID; category = custom.category
        updatedAt = custom.updatedAt; version = custom.syncVersion
    }
}
private struct UndoSnapshot {
    var customs: [UUID: CustomMappingSnapshot]
    var stock: [UUID: StockSnapshot]
    var meals: [UUID: MealSnapshot]
    var shopping: [UUID: ShoppingSnapshot]
    @MainActor init(context: ModelContext) throws {
        customs = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CustomIngredient>()).map { ($0.id, CustomMappingSnapshot($0)) })
        stock = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<InventoryItem>()).map { ($0.id, StockSnapshot($0)) })
        meals = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<MealSelection>()).map { ($0.id, MealSnapshot($0)) })
        shopping = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ShoppingListItem>()).map { ($0.id, ShoppingSnapshot($0)) })
    }
    func changed(from before: Self) -> Self {
        var result = self
        result.customs = customs.filter { before.customs[$0.key] != $0.value }
        result.stock = stock.filter { before.stock[$0.key] != $0.value }
        result.meals = meals.filter { before.meals[$0.key] != $0.value }
        result.shopping = shopping.filter { before.shopping[$0.key] != $0.value }
        return result
    }
    var isEmpty: Bool { stock.isEmpty && meals.isEmpty && shopping.isEmpty && customs.isEmpty }
}

enum InventoryUndoError: LocalizedError {
    case unavailable, conflict
    var errorDescription: String? {
        switch self {
        case .unavailable: "取り消せる操作はありません。"
        case .conflict: "対象の在庫・購入品・献立が変更されているため、取り消せません。現在の内容を確認してください。"
        }
    }
}

/// One committed operation per container, held only in memory. No recognition source is retained.
@MainActor
final class InventoryUndoCenter: ObservableObject {
    struct Offer: Identifiable {
        let id = UUID()
        let title: String
        let stockCount: Int
    }
    private struct Entry {
        let offer: Offer
        let before: UndoSnapshot
        let after: UndoSnapshot
    }
    private final class WeakCenter {
        weak var value: InventoryUndoCenter?
        init(_ value: InventoryUndoCenter) { self.value = value }
    }
    private static var centers: [ObjectIdentifier: WeakCenter] = [:]
    private let container: ModelContainer?
    private var entry: Entry?
    @Published private(set) var offer: Offer?
    init(container: ModelContainer?) {
        self.container = container
        if let container {
            Self.centers = Self.centers.filter { $0.value.value != nil }
            Self.centers[ObjectIdentifier(container)] = WeakCenter(self)
        }
    }
    static func attached(to container: ModelContainer) -> InventoryUndoCenter? {
        centers[ObjectIdentifier(container)]?.value
    }
    func clear() {
        guard entry != nil || offer != nil else { return }
        entry = nil; offer = nil
    }
    private func record(title: String, before: UndoSnapshot, after: UndoSnapshot) {
        let changes = after.changed(from: before)
        guard !changes.isEmpty else { return }
        let offer = Offer(title: title, stockCount: changes.stock.count)
        // Retain only affected records, not the entire inventory or any raw OCR/audio data.
        var originals = before
        originals.customs = before.customs.filter { changes.customs[$0.key] != nil }
        originals.stock = before.stock.filter { changes.stock[$0.key] != nil }
        originals.meals = before.meals.filter { changes.meals[$0.key] != nil }
        originals.shopping = before.shopping.filter { changes.shopping[$0.key] != nil }
        entry = Entry(offer: offer, before: originals, after: changes)
        self.offer = offer
    }
    func undo(id: UUID, saveContext: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard let entry, entry.offer.id == id, let container else { throw InventoryUndoError.unavailable }
        let context = ModelContext(container); context.autosaveEnabled = false
        do {
            let current = try UndoSnapshot(context: context)
            guard entry.after.customs.allSatisfy({ current.customs[$0.key] == $0.value }),
                  entry.after.stock.allSatisfy({ current.stock[$0.key] == $0.value }),
                  entry.after.meals.allSatisfy({ current.meals[$0.key] == $0.value }),
                  entry.after.shopping.allSatisfy({ current.shopping[$0.key] == $0.value }) else {
                clear(); throw InventoryUndoError.conflict
            }
            // Validate every participant before mutating any of them; one save commits the batch.
            for item in try context.fetch(FetchDescriptor<InventoryItem>()) where entry.after.stock[item.id] != nil {
                let amount = InventoryService.rawAmount(item), storage = item.storage.rawValue
                if let original = entry.before.stock[item.id] { try original.restore(to: item) }
                else {
                    // Undoing an addition removes it from usable stock but preserves its history.
                    item.isDeleted = true; item.updatedAt = .now; item.syncVersion += 1
                }
                context.insert(InventoryEvent(item: item, kind: "undone", beforeAmount: amount,
                    beforeStorage: storage, note: entry.offer.title))
            }
            for meal in try context.fetch(FetchDescriptor<MealSelection>()) where entry.after.meals[meal.id] != nil {
                guard let original = entry.before.meals[meal.id] else { throw InventoryUndoError.conflict }
                meal.scheduledDate = original.scheduledDate; meal.ingredientPlanData = original.ingredientPlanData
                meal.addsShortagesToShopping = original.addsShortagesToShopping
                meal.state = original.state; meal.updatedAt = .now
            }
            for row in try context.fetch(FetchDescriptor<ShoppingListItem>()) where entry.after.shopping[row.id] != nil {
                guard let original = entry.before.shopping[row.id] else { throw InventoryUndoError.conflict }
                row.isAddedToInventory = original.added
            }
            for custom in try context.fetch(FetchDescriptor<CustomIngredient>()) where entry.after.customs[custom.id] != nil {
                if let original = entry.before.customs[custom.id] {
                    custom.mappedIngredientMasterID = original.masterID; custom.category = original.category
                    custom.updatedAt = .now; custom.syncVersion += 1
                }
            }
            try saveContext(context)
            clear()
            NotificationCenter.default.post(name: ExpiryNotifications.inventoryChanged, object: nil)
        } catch { context.rollback(); throw error }
    }

    /// Used by every user mutation path; failed saves preserve the previous offer.
    static func transaction<T>(container: ModelContainer, title: String? = nil, changesInventory: Bool = true,
                               _ body: (ModelContext) throws -> T) throws -> T {
        let context = ModelContext(container); context.autosaveEnabled = false
        let center = attached(to: container)
        do {
            let before = title != nil && center != nil ? try UndoSnapshot(context: context) : nil
            let result = try body(context)
            let after = before != nil ? try UndoSnapshot(context: context) : nil
            if let before, let after {
                // Undoable operations only insert stock and update existing meal/purchase states.
                guard Set(before.customs.keys).isSubset(of: Set(after.customs.keys)),
                      Set(before.stock.keys).isSubset(of: Set(after.stock.keys)),
                      Set(before.meals.keys) == Set(after.meals.keys),
                      Set(before.shopping.keys) == Set(after.shopping.keys) else { throw InventoryUndoError.conflict }
            }
            try context.save()
            if let title, let before, let after { center?.record(title: title, before: before, after: after) }
            else { center?.clear() }
            if changesInventory { NotificationCenter.default.post(name: ExpiryNotifications.inventoryChanged, object: nil) }
            return result
        } catch { context.rollback(); throw error }
    }
}
