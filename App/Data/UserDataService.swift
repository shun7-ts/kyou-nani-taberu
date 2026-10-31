import Foundation
import SwiftData
import Combine

struct UserDataSummary: Equatable {
    var inventory = 0
    var customs = 0
    var events = 0
    var meals = 0
    var shopping = 0
}

@MainActor
struct UserDataService {
    let container: ModelContainer
    var saveContext: (ModelContext) throws -> Void = { try $0.save() }
    func summary() throws -> UserDataSummary {
        let context = ModelContext(container)
        return try UserDataSummary(inventory: context.fetchCount(FetchDescriptor<InventoryItem>()),
            customs: context.fetchCount(FetchDescriptor<CustomIngredient>()),
            events: context.fetchCount(FetchDescriptor<InventoryEvent>()),
            meals: context.fetchCount(FetchDescriptor<MealSelection>()),
            shopping: context.fetchCount(FetchDescriptor<ShoppingListItem>()))
    }
    func deleteAll() throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        do {
            // Fetch and delete in the same transaction, including soft-deleted/consumed history.
            for value in try context.fetch(FetchDescriptor<InventoryEvent>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<ShoppingListItem>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<MealSelection>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<InventoryItem>()) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<CustomIngredient>()) { context.delete(value) }
            // Bundled masters/recipes are app content, not user records; preserve fixed UUIDs.
            try saveContext(context)
            InventoryUndoCenter.attached(to: container)?.clear()
        } catch { context.rollback(); throw error }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var generation = UUID()
    @Published private(set) var isResetting = false
    let preferences: UserDefaults
    init(preferences: UserDefaults) { self.preferences = preferences }

    func reset(service: UserDataService, notices: ExpiryNotifications) async throws {
        guard !isResetting else { return }
        isResetting = true
        await notices.pauseForDataReset()
        do {
            try service.deleteAll()
            // Infallible app/OS reset operations run only after database commit succeeds.
            notices.clearForDataReset()
            AppPreferences.reset(preferences)
            generation = UUID() // Release all navigation, editor, recognition and recipe-step state.
            isResetting = false
            notices.resumeAfterDataReset(container: service.container)
        } catch {
            isResetting = false
            notices.resumeAfterDataReset(container: service.container)
            throw error
        }
    }
}
