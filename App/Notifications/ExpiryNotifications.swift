import Foundation
import SwiftData
import UserNotifications
import Combine

struct ExpiryNotice: Equatable {
    let identifier: String
    let inventoryID: UUID
    let name: String
    let fireAt: Date
    let expiresAt: Date
    let kind: ExpiryKind
}

struct ExpiryStock {
    let id: UUID
    let name: String
    let expiresAt: Date?
    let kind: ExpiryKind
    let hasStock: Bool
}

/// Dates are calendar days in the user's current time zone, never fixed 24-hour offsets.
enum ExpiryNoticePlanner {
    static let prefix = "inventory-expiry."
    static func plan(_ stock: [ExpiryStock], days: Int, hour: Int, minute: Int,
                     now: Date = .now, calendar: Calendar = .current) -> [ExpiryNotice] {
        stock.compactMap { item -> ExpiryNotice? in
            guard item.hasStock, let expiry = item.expiresAt,
                  calendar.startOfDay(for: expiry) >= calendar.startOfDay(for: now),
                  let day = calendar.date(byAdding: .day, value: -max(0, min(days, 7)), to: calendar.startOfDay(for: expiry)),
                  let fire = calendar.date(bySettingHour: max(0, min(hour, 23)), minute: max(0, min(minute, 59)), second: 0, of: day),
                  fire > now else { return nil }
            return ExpiryNotice(identifier: prefix + item.id.uuidString, inventoryID: item.id,
                                name: item.name, fireAt: fire, expiresAt: expiry, kind: item.kind)
        }.sorted { $0.fireAt == $1.fireAt ? $0.identifier < $1.identifier : $0.fireAt < $1.fireAt }
    }
}

@MainActor
protocol ExpiryNotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pending() async -> [UNNotificationRequest]
    func remove(_ ids: [String])
    func add(_ notice: ExpiryNotice) async throws
    func removeDelivered(_ ids: [String])
    func clearAll()
}

@MainActor
final class SystemExpiryNotificationClient: ExpiryNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pending() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func remove(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
    func clearAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    static func request(for notice: ExpiryNotice) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(notice.name)の期限が近づいています"
        let label = notice.kind == .useBy ? "消費期限" : notice.kind == .bestBefore ? "賞味期限" : "期限"
        content.body = "\(label)は\(notice.expiresAt.formatted(date: .abbreviated, time: .omitted))です。冷蔵庫で確認しましょう。"
        content.sound = .default
        content.userInfo = ["inventoryID": notice.inventoryID.uuidString]
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notice.fireAt)
        components.calendar = .current
        components.timeZone = .current
        return UNNotificationRequest(identifier: notice.identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
    func add(_ notice: ExpiryNotice) async throws {
        try await center.add(Self.request(for: notice))
    }
}

/// A test-only backend keeps XCTest away from the user's real permission and notification queue.
@MainActor
final class TestExpiryNotificationClient: ExpiryNotificationClient {
    var status: UNAuthorizationStatus = .notDetermined
    var notices: [String: ExpiryNotice] = [:]
    func authorization() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { status = .authorized; return true }
    func pending() async -> [UNNotificationRequest] {
        notices.values.map { notice in
            let content = UNMutableNotificationContent(); content.userInfo = ["inventoryID": notice.inventoryID.uuidString]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notice.fireAt)
            return UNNotificationRequest(identifier: notice.identifier, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }
    func remove(_ ids: [String]) { for id in ids { notices[id] = nil } }
    func removeDelivered(_ ids: [String]) {}
    func clearAll() { notices.removeAll() }
    func add(_ notice: ExpiryNotice) async throws { notices[notice.identifier] = notice }
}

final class ExpiryNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var openInventory: ((UUID) -> Void)?
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let value = response.notification.request.content.userInfo["inventoryID"] as? String,
           let id = UUID(uuidString: value) {
            DispatchQueue.main.async { self.openInventory?(id) }
        }
        completionHandler()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
final class ExpiryNotifications: ObservableObject {
    static let inventoryChanged = Notification.Name("inventoryChangedForExpiryNotifications")
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isReady = false
    @Published private(set) var scheduledCount = 0
    @Published private(set) var omittedCount = 0
    @Published private(set) var error: String?
    @Published var openedInventoryID: UUID?
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "expiryNotificationsEnabled") } }
    @Published var days: Int { didSet { defaults.set(days, forKey: "expiryNotificationDays") } }
    @Published var hour: Int { didSet { defaults.set(hour, forKey: "expiryNotificationHour") } }
    @Published var minute: Int { didSet { defaults.set(minute, forKey: "expiryNotificationMinute") } }
    private let defaults: UserDefaults
    private let client: ExpiryNotificationClient
    private let delegate = ExpiryNotificationDelegate()
    private var refreshing = false
    private var refreshAgain = false
    private var refreshTask: Task<Void, Never>?
    private var resetPaused = false
    private var generation = UUID()

    init(defaults: UserDefaults, client: ExpiryNotificationClient? = nil, testing: Bool = false) {
        self.defaults = defaults
        self.client = client ?? (testing ? TestExpiryNotificationClient() : SystemExpiryNotificationClient())
        enabled = defaults.object(forKey: "expiryNotificationsEnabled") as? Bool ?? true
        days = max(0, min(defaults.object(forKey: "expiryNotificationDays") as? Int ?? 2, 7))
        hour = max(0, min(defaults.object(forKey: "expiryNotificationHour") as? Int ?? 9, 23))
        minute = max(0, min(defaults.integer(forKey: "expiryNotificationMinute"), 59))
        if !testing {
            delegate.openInventory = { [weak self] id in self?.openedInventoryID = id }
            UNUserNotificationCenter.current().delegate = delegate
        }
    }
    var settingsSignature: String { "\(enabled)-\(days)-\(hour)-\(minute)" }
    var introductionShown: Bool {
        get { defaults.bool(forKey: "expiryNotificationIntroductionShown") }
        set { defaults.set(newValue, forKey: "expiryNotificationIntroductionShown") }
    }
    func allow(container: ModelContainer) async {
        guard !resetPaused else { return }
        let token = generation
        do {
            let allowed = try await client.requestAuthorization()
            guard token == generation, !resetPaused else { return }
            enabled = allowed; error = nil
        }
        catch { guard token == generation, !resetPaused else { return }; self.error = "通知を許可できませんでした。もう一度お試しください。\n\(error.localizedDescription)"; return }
        requestRefresh(container: container)
    }
    /// Coalesce overlapping stock/settings/foreground changes. Never let an older async refresh win.
    func requestRefresh(container: ModelContainer) {
        guard !resetPaused else { return }
        refreshAgain = true
        guard !refreshing else { return }
        refreshing = true
        refreshTask = Task {
            while refreshAgain && !Task.isCancelled && !resetPaused {
                refreshAgain = false
                await reconcile(container: container)
            }
            refreshing = false
            refreshTask = nil
        }
    }
    func reconcile(container: ModelContainer, now: Date = .now) async {
        guard !resetPaused else { return }
        let token = generation
        do {
            let status = await client.authorization()
            guard token == generation, !resetPaused, !Task.isCancelled else { return }
            authorization = status
            isReady = true
            let context = ModelContext(container)
            let items = try context.fetch(FetchDescriptor<InventoryItem>())
            let masters = try context.fetch(FetchDescriptor<IngredientMaster>())
            let customs = try context.fetch(FetchDescriptor<CustomIngredient>())
            let stock = items.map { item in
                ExpiryStock(id: item.id, name: masters.first { $0.id == item.ingredientMasterID }?.canonicalName
                    ?? customs.first { $0.id == item.customIngredientID }?.name ?? "食材",
                    expiresAt: item.expiresAt, kind: item.expiryKind,
                    hasStock: !item.isDeleted && (item.stockMode == .exact ? (item.quantity ?? 0) > 0 : item.roughState != .unavailable))
            }
            let allowed = enabled && [.authorized, .provisional, .ephemeral].contains(authorization)
            let all = allowed ? ExpiryNoticePlanner.plan(stock, days: days, hour: hour, minute: minute, now: now) : []
            // Reserve headroom below the OS queue limit; earliest inventory reminders take priority.
            let plan = Array(all.prefix(60))
            let expected = Set(plan.map(\.identifier))
            let pending = await client.pending().filter { $0.identifier.hasPrefix(ExpiryNoticePlanner.prefix) }
            guard token == generation, !resetPaused, !Task.isCancelled else { return }
            client.remove(pending.map(\.identifier).filter { !expected.contains($0) })
            client.removeDelivered(items.filter { $0.isDeleted || ($0.stockMode == .exact ? ($0.quantity ?? 0) == 0 : $0.roughState == .unavailable) }
                .map { ExpiryNoticePlanner.prefix + $0.id.uuidString })
            for notice in plan {
                // Stable identifiers replace edited reminders instead of adding duplicates.
                guard token == generation, !resetPaused, !Task.isCancelled else { return }
                try await client.add(notice)
                guard token == generation, !resetPaused, !Task.isCancelled else { client.remove([notice.identifier]); return }
            }
            scheduledCount = plan.count
            omittedCount = all.count - plan.count
            error = nil
        } catch {
            guard token == generation, !resetPaused, !Task.isCancelled else { return }
            self.error = "通知の予約を更新できませんでした。設定から再試行してください。\n\(error.localizedDescription)" }
    }
    /// Stop coalesced refreshes before deleting data; wait for an in-flight OS add to finish.
    func pauseForDataReset() async {
        resetPaused = true; generation = UUID(); refreshAgain = false
        let task = refreshTask; task?.cancel(); await task?.value
        refreshTask = nil; refreshing = false
    }
    func clearForDataReset() {
        client.clearAll()
        openedInventoryID = nil; scheduledCount = 0; omittedCount = 0; error = nil
        enabled = true; days = 2; hour = 9; minute = 0
        introductionShown = false
    }
    func resumeAfterDataReset(container: ModelContainer) {
        resetPaused = false; requestRefresh(container: container)
    }

}

/// An in-app inbox is independent of OS permission and reflects current stock.
struct InAppNotice: Identifiable, Equatable {
    enum Kind { case expiry, update }
    let id: String
    let title: String
    let body: String
    let date: Date
    let kind: Kind
    var inventoryID: UUID? = nil
    var recipeKeys: [String] = []
    var overdue = false
}

enum AppNoticeFeed {
    static let newRecipeKeys = ["milk_carbonara", "pork_daikon_simmer", "chicken_nanban",
        "salmon_chanchan", "atsuage_komatsuna_simmer", "pumpkin_potage"]
    static func updates(calendar: Calendar = .current) -> [InAppNotice] {
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)) ?? .distantPast
        return [InAppNotice(id: "recipe-update-2026-10-07-1", title: "レシピを6品追加しました",
            body: "カルボナーラ、豚バラ大根、チキン南蛮、鮭のちゃんちゃん焼き、厚揚げと小松菜の煮浸し、かぼちゃのポタージュ。分量と工程ごとの時間も確認できます。",
            date: date, kind: .update, recipeKeys: newRecipeKeys),
            InAppNotice(id: "photo-update-2026-10-07-1", title: "料理の画像を3枚追加しました",
                body: "カルボナーラ、かぼちゃのポタージュ、手羽元のさっぱり煮に料理のイメージ画像を追加しました。",
                date: date, kind: .update, recipeKeys: ["milk_carbonara", "pumpkin_potage", "drumette_vinegar_simmer"])]
    }
    static func expiry(_ stock: [ExpiryStock], days: Int = 2, now: Date = .now,
                       calendar: Calendar = .current) -> [InAppNotice] {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: max(0, min(days, 7)), to: today) else { return [] }
        return stock.compactMap { item in
            guard item.hasStock, let date = item.expiresAt, calendar.startOfDay(for: date) <= end else { return nil }
            let day = calendar.startOfDay(for: date)
            let remaining = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            let timing = remaining < 0 ? "期限を過ぎています" : remaining == 0 ? "今日が期限です" : remaining == 1 ? "明日が期限です" : "あと\(remaining)日"
            let label = item.kind == .useBy ? "消費期限" : item.kind == .bestBefore ? "賞味期限" : "期限"
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let id = "stock.\(item.id).\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0).\(item.kind.rawValue)"
            return InAppNotice(id: id, title: item.name,
                body: "\(timing) · \(label) \(date.formatted(.dateTime.month().day()))",
                date: date, kind: .expiry, inventoryID: item.id, overdue: remaining < 0)
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    static func stock(_ items: [InventoryItem], masters: [IngredientMaster], customs: [CustomIngredient]) -> [ExpiryStock] {
        let names = Dictionary(uniqueKeysWithValues: masters.map { ($0.id, $0.canonicalName) })
        let customNames = Dictionary(uniqueKeysWithValues: customs.map { ($0.id, $0.name) })
        return items.map { item in
            ExpiryStock(id: item.id, name: item.ingredientMasterID.flatMap { names[$0] }
                ?? item.customIngredientID.flatMap { customNames[$0] } ?? "食材",
                expiresAt: item.expiresAt, kind: item.expiryKind,
                hasStock: !item.isDeleted && StockExpiry.hasStock(StockLot(item)))
        }
    }
}

enum NoticeReadState {
    static func ids(_ raw: String) -> Set<String> {
        guard let data = raw.data(using: .utf8), let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }
    static func marking(_ ids: [String], in raw: String, current: [InAppNotice]) -> String {
        let visible = Set(current.map(\.id))
        let read = (Self.ids(raw).union(ids)).intersection(visible)
        guard let data = try? JSONEncoder().encode(read.sorted()) else { return raw }
        return String(decoding: data, as: UTF8.self)
    }
}
