import Foundation
import SwiftData
import Combine

struct ShoppingCheckSaveResult: Sendable {
    let milliseconds: Double
    let ranOnMainThread: Bool
}

enum ShoppingCheckPersistence {
    /// Only the requested, still-open row is materialized. The caller owns this context.
    static func update(_ context: ModelContext, id: UUID, checked: Bool) throws {
        var descriptor = FetchDescriptor<ShoppingListItem>(predicate: #Predicate { $0.id == id && !$0.isAddedToInventory })
        descriptor.fetchLimit = 1
        guard let row = try context.fetch(descriptor).first else { throw MealError.missingItem }
        row.isChecked = checked
    }
}

actor ShoppingCheckWriter {
    private let container: ModelContainer
    private let queue = DispatchQueue(label: "com.kyounanitaberu.shopping-checks", qos: .userInitiated)
    init(modelContainer: ModelContainer) { container = modelContainer }
    nonisolated static func background(container: ModelContainer) async -> ShoppingCheckWriter {
        ShoppingCheckWriter(modelContainer: container)
    }
    func save(id: UUID, checked: Bool, failBeforeSave: Bool = false) async throws -> ShoppingCheckSaveResult {
        let container = container
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let started = ContinuousClock.now
                // Created, fetched, changed and saved in one private-queue block. Never shared
                // with the UI or another executor; a fresh context sees later purchases/removals.
                let context = ModelContext(container)
                context.autosaveEnabled = false
                do {
                    try ShoppingCheckPersistence.update(context, id: id, checked: checked)
                    if failBeforeSave { throw CocoaError(.fileWriteUnknown) }
                    try context.save()
                    let elapsed = started.duration(to: .now).components
                    continuation.resume(returning: ShoppingCheckSaveResult(
                        milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                        ranOnMainThread: Thread.isMainThread))
                } catch { context.rollback(); continuation.resume(throwing: error) }
            }
        }
    }
}

/// Main-actor presentation, serial async writes, and a last-intent-wins queue.
@MainActor
final class ShoppingChecks: ObservableObject {
    typealias Save = @MainActor (UUID, Bool) async throws -> ShoppingCheckSaveResult
    private struct Change {
        var desired: Bool
        var confirmed: Bool
        var revision: Int
    }
    @Published private(set) var overrides: [UUID: Bool] = [:]
    @Published private(set) var savingIDs: Set<UUID> = []
    @Published var errorMessage: String?
    private var changes: [UUID: Change] = [:]
    private var observed: [UUID: Bool] = [:]
    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var save: Save?
    private var revision = 0
    private var failures = 0
    private(set) var lastSave: ShoppingCheckSaveResult?

    init(save: Save? = nil) { self.save = save }
    func configure(container: ModelContainer) {
        guard save == nil else { return }
        // Only IDs and booleans cross actors; the writer creates its context on its private queue.
        let writer = Task { await ShoppingCheckWriter.background(container: container) }
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let delayed = testing && ProcessInfo.processInfo.arguments.contains("--ui-check-delay")
        let fail = testing && ProcessInfo.processInfo.arguments.contains("--ui-check-failure")
        save = { id, checked in
            let undo = InventoryUndoCenter.attached(to: container)
            let token = undo?.offer?.id
            if delayed { try await Task.sleep(for: .milliseconds(5000)) }
            let result = try await writer.value.save(id: id, checked: checked, failBeforeSave: fail)
            // A check still invalidates the preceding undo, but never a newer stock operation.
            if undo?.offer?.id == token { undo?.clear() }
            return result
        }
    }
    func isChecked(id: UUID, stored: Bool) -> Bool { overrides[id] ?? stored }
    func toggle(id: UUID, stored: Bool) {
        guard save != nil else { return }
        revision += 1
        if observed[id] == nil { observed[id] = stored }
        var change = changes[id] ?? Change(desired: stored, confirmed: stored, revision: revision)
        change.desired.toggle(); change.revision = revision
        changes[id] = change
        overrides[id] = change.desired
        if !savingIDs.contains(id) { savingIDs.insert(id) }
        if !queue.contains(id) { queue.append(id) }
        if worker == nil { worker = Task { await drain() } }
    }
    func synchronize(_ values: [UUID: Bool]) {
        observed = values
        let settled = changes.keys.filter { !savingIDs.contains($0)
            && (values[$0] == nil || values[$0] == changes[$0]?.desired) }
        guard !settled.isEmpty else { return }
        var next = overrides
        for id in settled { changes.removeValue(forKey: id); next.removeValue(forKey: id) }
        if next != overrides { overrides = next }
    }
    /// Purchase confirmation takes a stable snapshot only after every check has settled.
    func flush() async -> Bool {
        let previousFailures = failures
        while let task = worker { await task.value }
        return failures == previousFailures
    }
    private func drain() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let request = changes[id], let save else { savingIDs.remove(id); continue }
            if request.desired != request.confirmed {
                do {
                    lastSave = try await save(id, request.desired)
                    changes[id]?.confirmed = request.desired
                } catch {
                    failures += 1; errorMessage = error.localizedDescription
                    // Roll back this intent only. A later tap remains queued and authoritative.
                    if changes[id]?.revision == request.revision {
                        let confirmed = changes[id]?.confirmed ?? request.confirmed
                        changes[id]?.desired = confirmed
                    }
                }
            }
            if let current = changes[id], overrides[id] != current.desired { overrides[id] = current.desired }
            if !queue.contains(id) { savingIDs.remove(id) }
            synchronize(observed)
        }
        worker = nil
    }
}
