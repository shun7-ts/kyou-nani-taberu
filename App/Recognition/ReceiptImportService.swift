import Foundation
import SwiftData

/// One transaction and an event marker make retries for the same session idempotent.
@MainActor
struct ReceiptImportService {
    let container: ModelContainer
    var mergeDuplicates = true
    func save(rows: [ReceiptRow], sessionID: UUID) throws {
        let selected = rows.filter(\.included)
        guard !selected.isEmpty, selected.allSatisfy(\.confirmed) else { throw ReceiptError.unconfirmed }
        guard Set(rows.map(\.id)).count == rows.count else { throw ReceiptError.invalidRow }
        try InventoryUndoCenter.transaction(container: container, title: "レシートからの登録") { context in
            let marker = "レシート登録:" + sessionID.uuidString
            guard !(try context.fetch(FetchDescriptor<InventoryEvent>())).contains(where: { $0.note == marker }) else {
                throw ReceiptError.alreadySaved
            }
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            var inventory = try context.fetch(FetchDescriptor<InventoryItem>())
            for row in selected {
                let amount: StockAmount
                if row.exact {
                    guard let quantity = Double(row.quantity), quantity.isFinite, quantity > 0 else { throw ReceiptError.invalidRow }
                    amount = .exact(quantity, row.unit)
                } else { amount = .rough(row.rough) }
                let reference: IngredientReference
                if let id = row.masterID {
                    guard let master = masters.first(where: { $0.id == id && $0.status == .active && $0.trackInventory }),
                          !row.exact || master.allowedUnits.contains(row.unit) else { throw ReceiptError.invalidRow }
                    reference = .master(id)
                } else {
                    let custom = try CustomIngredient(name: row.name, category: row.category)
                    context.insert(custom); reference = .custom(custom.id)
                }
                try InventoryAddition.add(reference: reference, amount: amount, storage: row.storage,
                    purchasedAt: row.purchasedAt, expiresAt: row.expiresAt, expiryKind: row.expiryKind,
                    merge: mergeDuplicates && row.merge, inventory: &inventory, context: context, note: marker)
            }
        }
    }
    static func canMerge(_ row: ReceiptRow, into item: InventoryItem) -> Bool {
        guard let id = row.masterID else { return false }
        let amount: StockAmount
        if row.exact {
            guard let value = Double(row.quantity) else { return false }
            amount = .exact(value, row.unit)
        } else { amount = .rough(row.rough) }
        return InventoryAddition.canMerge(reference: .master(id), amount: amount, storage: row.storage,
            expiresAt: row.expiresAt, expiryKind: row.expiryKind, item: item)
    }
}
