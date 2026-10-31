import Foundation
import SwiftData

@Model
final class InventoryEvent {
    @Attribute(.unique) var id: UUID
    var inventoryItemID: UUID
    var kind: String
    var occurredAt: Date
    var beforeAmount: String
    var afterAmount: String
    var beforeStorage: String
    var afterStorage: String
    var note: String

    init(item: InventoryItem, kind: String, beforeAmount: String = "", beforeStorage: String = "",
         note: String = "", now: Date = .now) {
        id = UUID()
        inventoryItemID = item.id
        self.kind = kind
        occurredAt = now
        self.beforeAmount = beforeAmount
        afterAmount = item.stockMode == .exact
            ? "\(item.quantity ?? 0) \(item.unit?.rawValue ?? "")"
            : item.roughState?.rawValue ?? ""
        self.beforeStorage = beforeStorage
        afterStorage = item.storage.rawValue
        self.note = note
    }
}
