import Foundation

extension MaterialPurchase {
    @MainActor init(_ row: ShoppingListItem) {
        self.init(id: row.id, masterID: row.ingredientMasterID, quantity: row.quantity, unit: row.unit,
            sourceMealID: row.sourceMealID, isAddedToInventory: row.isAddedToInventory,
            scope: row.materialScopeData.map { (try? JSONDecoder().decode(MaterialPurchaseScope.self, from: $0))
                ?? MaterialPurchaseScope(mealIDs: [], materialID: "") })
    }
}

extension StockLot {
    init(_ item: InventoryItem) {
        id = item.id; masterID = item.ingredientMasterID; quantity = item.quantity
        unit = item.unit; roughState = item.roughState; storage = item.storage
        expiresAt = item.expiresAt; purchasedAt = item.purchasedAt; isDeleted = item.isDeleted
    }
}

/// Resolves identities for calculation only. Original custom lot IDs remain unchanged.
@MainActor
enum IngredientIdentity {
    static func masterID(for item: InventoryItem, customs: [CustomIngredient], masters: [IngredientMaster]) -> UUID? {
        if let id = item.ingredientMasterID { return id }
        guard let custom = customs.first(where: { $0.id == item.customIngredientID && !$0.isDeleted }),
              let id = custom.mappedIngredientMasterID,
              masters.contains(where: { $0.id == id && $0.status == .active && $0.trackInventory }) else { return nil }
        return id
    }
    static func snapshots(_ items: [InventoryItem], customs: [CustomIngredient], masters: [IngredientMaster]) -> [StockLot] {
        let activeIDs = Set(masters.filter { $0.status == .active && $0.trackInventory }.map(\.id))
        let mapped = Dictionary(uniqueKeysWithValues: customs.filter { !$0.isDeleted }.compactMap { custom in
            custom.mappedIngredientMasterID.flatMap { activeIDs.contains($0) ? (custom.id, $0) : nil }
        })
        return items.map { item in
            StockLot(id: item.id, masterID: item.ingredientMasterID ?? item.customIngredientID.flatMap { mapped[$0] },
                quantity: item.quantity, unit: item.unit, roughState: item.roughState, storage: item.storage,
                expiresAt: item.expiresAt, purchasedAt: item.purchasedAt, isDeleted: item.isDeleted)
        }
    }
    static func accepts(_ unit: IngredientUnit, master: IngredientMaster) -> Bool {
        master.allowedUnits.contains { Units.convert(1, from: unit, to: $0) != nil }
    }
}

@MainActor
enum IngredientNameResolver {
    static func candidates(_ name: String, masters: [IngredientMaster]) -> [IngredientMaster] {
        let query = IngredientSearch.normalized(name)
        guard !query.isEmpty else { return [] }
        return masters.filter { $0.status == .active && $0.trackInventory
            && ([$0.canonicalName] + $0.aliases).contains { IngredientSearch.normalized($0) == query } }
            .sorted { $0.key < $1.key }
    }
}
