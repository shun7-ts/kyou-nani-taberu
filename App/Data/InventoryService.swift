import Foundation
import SwiftData

enum InventoryError: LocalizedError {
    case missingIngredient, invalidUnit, missingItem
    var errorDescription: String? {
        switch self {
        case .missingIngredient: "食材を選んでください。"
        case .invalidUnit: "この食材では選択した単位を使えません。"
        case .missingItem: "在庫が見つかりません。画面を開き直してください。"
        }
    }
}

struct InventoryDraft {
    var masterID: UUID?
    var customName = ""
    var mappedMasterID: UUID?
    var updatesMapping = false
    var amount: StockAmount = .rough(.available)
    var storage: StorageMethod = .refrigerated
    var purchasedAt = Date.now
    var expiresAt: Date?
    var expiryKind: ExpiryKind = .unspecified
}

@MainActor
struct InventoryService {
    let container: ModelContainer
    var mergeDuplicates = true

    @discardableResult
    func save(_ draft: InventoryDraft, editingID: UUID? = nil) throws -> UUID {
        try transaction(title: editingID == nil ? "食材の追加" : "在庫の修正") { context in
            var items = try context.fetch(FetchDescriptor<InventoryItem>())
            let old = editingID.flatMap { id in items.first { $0.id == id && !$0.isDeleted } }
            if editingID != nil && old == nil { throw InventoryError.missingItem }
            let masterID = old == nil ? draft.masterID : old?.ingredientMasterID
            let reference: IngredientReference
            if let masterID {
                guard let master = try context.fetch(FetchDescriptor<IngredientMaster>()).first(where: {
                    $0.id == masterID && $0.trackInventory
                }) else { throw InventoryError.missingIngredient }
                if case let .exact(_, unit) = draft.amount, !master.allowedUnits.contains(unit) {
                    throw InventoryError.invalidUnit
                }
                reference = .master(masterID)
            } else if let customID = old?.customIngredientID {
                let custom = try context.fetch(FetchDescriptor<CustomIngredient>()).first { $0.id == customID }
                try Self.updateMapping(id: customID,
                    masterID: draft.updatesMapping ? draft.mappedMasterID : custom?.mappedIngredientMasterID,
                    context: context, replacingItem: old, amount: draft.amount)
                reference = .custom(customID)
            } else {
                let custom = try CustomIngredient(name: draft.customName)
                context.insert(custom)
                try Self.updateMapping(id: custom.id, masterID: draft.mappedMasterID, context: context,
                    replacingItem: nil, amount: draft.amount)
                reference = .custom(custom.id)
            }
            let item: InventoryItem
            let beforeAmount = old.map(Self.rawAmount) ?? ""
            let beforeStorage = old?.storage.rawValue ?? ""
            if let old {
                item = old
                try item.setAmount(draft.amount)
                item.storage = draft.storage
                item.purchasedAt = draft.purchasedAt
                item.expiresAt = draft.expiresAt
                item.expiryKind = draft.expiryKind
            } else {
                return try InventoryAddition.add(reference: reference, amount: draft.amount,
                    storage: draft.storage, purchasedAt: draft.purchasedAt, expiresAt: draft.expiresAt,
                    expiryKind: draft.expiryKind, merge: mergeDuplicates, inventory: &items, context: context).id
            }
            context.insert(InventoryEvent(item: item,
                kind: old == nil ? "added" : beforeStorage != item.storage.rawValue ? "moved" : "edited",
                beforeAmount: beforeAmount, beforeStorage: beforeStorage))
            return item.id
        }
    }

    func mapCustom(id: UUID, masterID: UUID?) throws {
        try transaction(title: "献立に使う食材の変更") { context in
            try Self.updateMapping(id: id, masterID: masterID, context: context)
        }
    }
    private static func updateMapping(id: UUID, masterID: UUID?, context: ModelContext,
                                     replacingItem: InventoryItem? = nil, amount: StockAmount? = nil) throws {
        guard let custom = try context.fetch(FetchDescriptor<CustomIngredient>()).first(where: { $0.id == id && !$0.isDeleted }) else {
            throw InventoryError.missingIngredient
        }
        if let masterID {
            guard let master = try context.fetch(FetchDescriptor<IngredientMaster>()).first(where: {
                $0.id == masterID && $0.status == .active && $0.trackInventory
            }) else { throw InventoryError.missingIngredient }
            let lots = try context.fetch(FetchDescriptor<InventoryItem>()).filter {
                $0.customIngredientID == id && !$0.isDeleted && $0.id != replacingItem?.id
            }
            guard lots.allSatisfy({ $0.unit.map { IngredientIdentity.accepts($0, master: master) } ?? true }) else {
                throw InventoryError.invalidUnit
            }
            if case let .exact(_, unit) = amount, !IngredientIdentity.accepts(unit, master: master) { throw InventoryError.invalidUnit }
            custom.category = master.category
        }
        if custom.mappedIngredientMasterID != masterID {
            custom.mappedIngredientMasterID = masterID; custom.updatedAt = .now; custom.syncVersion += 1
        }
    }

    /// Adds only selections without usable stock, leaving existing quantities and expiry untouched.
    @discardableResult
    func bulkRegister(keys: Set<String>, now: Date = .now) throws -> Int {
        try transaction(title: "初期在庫の一括登録") { context in
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            var items = try context.fetch(FetchDescriptor<InventoryItem>())
            let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
            let selected = masters.filter { keys.contains($0.key) && $0.trackInventory && $0.status == .active }
            guard selected.count == keys.count else { throw InventoryError.missingIngredient }
            var count = 0
            for master in selected {
                let hasStock = items.contains {
                    IngredientIdentity.masterID(for: $0, customs: customs, masters: masters) == master.id && !$0.isDeleted && Self.usable($0, on: now)
                        && (($0.quantity ?? 0) > 0 || $0.roughState == .available || $0.roughState == .low)
                }
                if hasStock { continue }
                try InventoryAddition.add(reference: .master(master.id), amount: .rough(.available),
                    storage: master.defaultStorage, purchasedAt: now, expiresAt: nil, expiryKind: .unspecified,
                    merge: mergeDuplicates, inventory: &items, context: context, note: "初期在庫一括登録")
                count += 1
            }
            return count
        }
    }

    func discard(id: UUID) throws {
        try transaction(title: "食材の取り除き") { context in
            guard let item = try context.fetch(FetchDescriptor<InventoryItem>()).first(where: {
                $0.id == id && !$0.isDeleted
            }) else { throw InventoryError.missingItem }
            context.insert(InventoryEvent(item: item, kind: "discarded"))
            item.isDeleted = true
            item.updatedAt = .now
            item.syncVersion += 1
        }
    }

    func restore(id: UUID) throws {
        try transaction(title: "食材の復元") { context in
            guard let item = try context.fetch(FetchDescriptor<InventoryItem>()).first(where: {
                $0.id == id && $0.isDeleted
            }) else { throw InventoryError.missingItem }
            item.isDeleted = false; item.updatedAt = .now; item.syncVersion += 1
            context.insert(InventoryEvent(item: item, kind: "restored"))
        }
    }

    static func usable(_ item: InventoryItem, on date: Date) -> Bool {
        !item.isDeleted && (item.expiresAt.map {
            Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: date)
        } ?? true)
    }
    static func rawAmount(_ item: InventoryItem) -> String {
        item.stockMode == .exact ? "\(item.quantity ?? 0) \(item.unit?.rawValue ?? "")"
            : item.roughState?.rawValue ?? ""
    }
    private func transaction<T>(title: String, _ body: (ModelContext) throws -> T) throws -> T {
        try InventoryUndoCenter.transaction(container: container, title: title, body)
    }
}

/// All addition routes share lot identity and amount rules. Edits and stocktaking remain replacements.
@MainActor
enum InventoryAddition {
    static func isEmpty(_ item: InventoryItem) -> Bool {
        item.stockMode == .exact ? item.quantity == 0 : item.roughState == .unavailable
    }
    static func precedes(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        if isEmpty(lhs) != isEmpty(rhs) { return !isEmpty(lhs) }
        return lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
    }
    static func sameConditions(reference: IngredientReference, storage: StorageMethod, expiresAt: Date?,
                               expiryKind: ExpiryKind, item: InventoryItem) -> Bool {
        guard !item.isDeleted, item.storage == storage, item.expiryKind == expiryKind else { return false }
        switch reference {
        case let .master(id): guard item.ingredientMasterID == id else { return false }
        case let .custom(id): guard item.customIngredientID == id else { return false }
        }
        switch (expiresAt, item.expiresAt) {
        case (nil, nil): return true
        case let (.some(a), .some(b)): return Calendar.current.isDate(a, inSameDayAs: b)
        default: return false
        }
    }
    static func canMerge(reference: IngredientReference, amount: StockAmount, storage: StorageMethod,
                         expiresAt: Date?, expiryKind: ExpiryKind, item: InventoryItem) -> Bool {
        guard sameConditions(reference: reference, storage: storage, expiresAt: expiresAt,
                             expiryKind: expiryKind, item: item) else { return false }
        switch amount {
        case let .exact(value, unit):
            guard value.isFinite, value >= 0 else { return false }
            if isEmpty(item) { return true }
            guard item.stockMode == .exact, let oldUnit = item.unit,
                  let converted = Units.convert(value, from: unit, to: oldUnit) else { return false }
            return converted.isFinite
        case .rough: return item.stockMode == .rough || isEmpty(item)
        }
    }
    @discardableResult
    static func add(reference: IngredientReference, amount: StockAmount, storage: StorageMethod,
                    purchasedAt: Date, expiresAt: Date?, expiryKind: ExpiryKind, merge: Bool,
                    inventory: inout [InventoryItem], context: ModelContext, note: String = "") throws -> InventoryItem {
        if case let .exact(value, _) = amount, !value.isFinite || value < 0 {
            throw InventoryValidationError.invalidQuantity
        }
        let target = merge ? inventory.filter {
            canMerge(reference: reference, amount: amount, storage: storage, expiresAt: expiresAt,
                     expiryKind: expiryKind, item: $0)
        }.min(by: precedes) : nil
        if let target {
            let before = InventoryService.rawAmount(target)
            let wasEmpty = isEmpty(target)
            switch amount {
            case let .exact(value, unit):
                if let oldUnit = target.unit, let converted = Units.convert(value, from: unit, to: oldUnit), converted.isFinite {
                    try target.setAmount(.exact((target.quantity ?? 0) + converted, oldUnit))
                } else if wasEmpty {
                    try target.setAmount(amount)
                } else {
                    throw InventoryError.invalidUnit
                }
            case let .rough(state):
                // Presence states are not quantities. Additional stock keeps the strongest evidence.
                let states = [target.roughState ?? .unavailable, state]
                try target.setAmount(.rough(states.contains(.available) ? .available : states.contains(.low) ? .low : .unavailable))
            }
            target.purchasedAt = wasEmpty ? purchasedAt : min(target.purchasedAt, purchasedAt)
            context.insert(InventoryEvent(item: target, kind: "added", beforeAmount: before, note: note))
            return target
        }
        let item = try InventoryItem(ingredient: reference, amount: amount, storage: storage,
            purchasedAt: purchasedAt, expiresAt: expiresAt, expiryKind: expiryKind)
        context.insert(item); inventory.append(item)
        context.insert(InventoryEvent(item: item, kind: "added", note: note))
        return item
    }
}
