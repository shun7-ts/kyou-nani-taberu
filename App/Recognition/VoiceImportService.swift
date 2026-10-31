import Foundation
import SwiftData

@MainActor
struct VoiceImportService {
    let container: ModelContainer
    var mergeDuplicates = true
    func save(rows: [VoiceRow], sessionID: UUID) throws {
        let selected = rows.filter { $0.draft.included }
        guard !selected.isEmpty, selected.allSatisfy({ $0.draft.confirmed && $0.action != .choose }),
              Set(rows.map(\.id)).count == rows.count else { throw VoiceError.invalid }
        try InventoryUndoCenter.transaction(container: container, title: "音声からの在庫更新") { context in
            let marker = "音声登録:" + sessionID.uuidString
            guard !(try context.fetch(FetchDescriptor<InventoryEvent>())).contains(where: { $0.note == marker }) else { throw VoiceError.duplicate }
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            var items = try context.fetch(FetchDescriptor<InventoryItem>())
            // Multiple changes to one lot in a batch have no reliable order; ask for one final change.
            let targets = selected.filter { $0.action != .add }.compactMap(\.targetID)
            guard Set(targets).count == targets.count else { throw VoiceError.invalid }
            let snapshotIDs = selected.filter { $0.action == .snapshot }.compactMap { $0.draft.masterID }
            guard snapshotIDs.count == selected.filter({ $0.action == .snapshot }).count,
                  Set(snapshotIDs).count == snapshotIDs.count,
                  !selected.contains(where: { $0.action != .snapshot && snapshotIDs.contains($0.draft.masterID ?? UUID()) }) else { throw VoiceError.invalid }
            // Validate every snapshot before mutation, including newly added/deleted lots.
            for row in selected where row.action == .snapshot {
                guard VoiceSnapshotParser.ready(row, inventory: items) else { throw VoiceError.stockChanged }
            }
            for row in selected {
                let draft = row.draft
                if row.action == .snapshot {
                    guard let master = masters.first(where: { $0.id == draft.masterID && $0.trackInventory && $0.status == .active }),
                          !draft.exact || (master.category != .seasoning && master.allowedUnits.contains(draft.unit)) else { throw VoiceError.invalid }
                    if let item = items.first(where: { $0.id == row.targetID && !$0.isDeleted }) {
                        let before = InventoryService.rawAmount(item), beforeStorage = item.storage.rawValue
                        // Saying only "あり" must preserve positive exact stock, dates, and unit.
                        if !draft.exact && draft.rough == .available && item.stockMode == .exact && (item.quantity ?? 0) > 0 {
                            if row.storageSpoken && item.storage != draft.storage {
                                item.storage = draft.storage; item.updatedAt = .now; item.syncVersion += 1
                            }
                        } else {
                            try item.setAmount(Self.amount(draft, positive: false))
                            if row.storageSpoken { item.storage = draft.storage }
                        }
                        context.insert(InventoryEvent(item: item, kind: "corrected", beforeAmount: before, beforeStorage: beforeStorage, note: marker))
                    } else {
                        let item = try InventoryItem(ingredient: .master(master.id), amount: Self.amount(draft, positive: false),
                            storage: draft.storage, purchasedAt: draft.purchasedAt, expiresAt: draft.expiresAt, expiryKind: draft.expiryKind)
                        context.insert(item); items.append(item)
                        context.insert(InventoryEvent(item: item, kind: "added", note: marker))
                    }
                    continue
                }
                if row.action == .add {
                    let amount = try Self.amount(draft, positive: true)
                    let reference: IngredientReference
                    if let id = draft.masterID {
                        guard let master = masters.first(where: { $0.id == id && $0.trackInventory && $0.status == .active }),
                              !draft.exact || master.allowedUnits.contains(draft.unit) else { throw VoiceError.invalid }
                        reference = .master(id)
                    } else {
                        let custom = try CustomIngredient(name: draft.name, category: draft.category)
                        context.insert(custom); reference = .custom(custom.id)
                    }
                    try InventoryAddition.add(reference: reference, amount: amount, storage: draft.storage,
                        purchasedAt: draft.purchasedAt, expiresAt: draft.expiresAt, expiryKind: draft.expiryKind,
                        merge: mergeDuplicates && draft.merge, inventory: &items, context: context, note: marker)
                    continue
                }
                guard let item = items.first(where: { $0.id == row.targetID && !$0.isDeleted }),
                      item.ingredientMasterID == draft.masterID, item.syncVersion == row.targetVersion else { throw VoiceError.target }
                if let id = item.ingredientMasterID {
                    guard let master = masters.first(where: { $0.id == id }), !draft.exact || row.action == .move || master.allowedUnits.contains(draft.unit) else { throw VoiceError.invalid }
                }
                let before = InventoryService.rawAmount(item), beforeStorage = item.storage.rawValue
                let kind: String
                switch row.action {
                case .consume:
                    kind = "consumed"
                    if draft.exact {
                        guard let value = Double(draft.quantity), value.isFinite, value >= 0 else { throw VoiceError.invalid }
                        guard item.stockMode == .exact, let unit = item.unit, let current = item.quantity,
                              let used = Units.convert(value, from: draft.unit, to: unit) else { throw VoiceError.incompatible }
                        guard used <= current else { throw VoiceError.exceeds }
                        try item.setAmount(.exact(current - used, unit))
                    } else {
                        // Explicitly chosen post-use state replaces amount; no arithmetic on rough stock.
                        guard let state = row.postUseState else { throw VoiceError.invalid }
                        try item.setAmount(.rough(state))
                    }
                case .setAmount: kind = "corrected"; try item.setAmount(Self.amount(draft, positive: false))
                case .move:
                    kind = "moved"; item.storage = draft.storage; item.updatedAt = .now; item.syncVersion += 1
                default: throw VoiceError.invalid
                }
                context.insert(InventoryEvent(item: item, kind: kind, beforeAmount: before, beforeStorage: beforeStorage, note: marker))
            }
        }
    }
    static func amount(_ row: ReceiptRow, positive: Bool) throws -> StockAmount {
        guard row.exact else { return .rough(row.rough) }
        guard let value = Double(row.quantity), value.isFinite, positive ? value > 0 : value >= 0 else { throw VoiceError.invalid }
        return .exact(value, row.unit)
    }
}
