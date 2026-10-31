import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var notices: ExpiryNotifications
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: notices.hour, minute: notices.minute, second: 0, of: .now)! },
                set: { notices.hour = Calendar.current.component(.hour, from: $0); notices.minute = Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        Form {
            Section {
                Toggle("期限通知", isOn: $notices.enabled).accessibilityIdentifier("expiry-notifications-enabled")
                Picker("通知する日", selection: $notices.days) {
                    Text("期限当日").tag(0)
                    ForEach(1...7, id: \.self) { Text("期限の\($0)日前").tag($0) }
                }.accessibilityIdentifier("expiry-notification-days")
                DatePicker("通知時刻", selection: time, displayedComponents: .hourAndMinute)
            }
            Section("この端末の通知許可") {
                switch notices.authorization {
                case .notDetermined:
                    Text("期限が近い食材を、この端末の通知でお知らせします。許可しなくても在庫管理は使えます。")
                    Button("通知を許可する") { Task { await notices.allow(container: context.container) } }
                        .accessibilityIdentifier("expiry-notification-authorize")
                case .denied:
                    Text("通知は許可されていません。アプリ内の期限表示は引き続き使えます。")
                    Button("iPhoneの設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                default: Text("通知は許可されています").accessibilityIdentifier("expiry-notification-authorized")
                }
            }
            Section("予約状況") {
                Text("\(notices.scheduledCount)件の期限通知を予約中").accessibilityIdentifier("expiry-notification-count")
                if notices.omittedCount > 0 { Text("件数が多いため、期限が近い60件を優先しています。次にアプリを開くと予約を更新します。") }
                if let error = notices.error { Text(error).foregroundStyle(.red) }
                Button("予約を更新する") { notices.requestRefresh(container: context.container) }
                    .accessibilityIdentifier("expiry-notification-refresh")
            }
        }.navigationTitle("期限通知").scrollContentBackground(.hidden).background(AppTheme.background)
            .task { notices.requestRefresh(container: context.container) }
    }
}

struct NoticeInboxView: View {
    let recipes: [Recipe]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var notifications: ExpiryNotifications
    @Query private var stock: [InventoryItem]
    @Query private var masters: [IngredientMaster]
    @Query private var customs: [CustomIngredient]
    @AppStorage(AppPreferences.readNoticeIDs) private var readJSON = ""
    @State private var now = Date.now
    private var expiry: [InAppNotice] {
        AppNoticeFeed.expiry(AppNoticeFeed.stock(stock, masters: masters, customs: customs), days: notifications.days, now: now)
    }
    private var items: [InAppNotice] { expiry + AppNoticeFeed.updates() }
    private var unread: Int { items.filter { !NoticeReadState.ids(readJSON).contains($0.id) }.count }
    private func mark(_ id: String) { readJSON = NoticeReadState.marking([id], in: readJSON, current: items) }
    var body: some View {
        List {
            Section("食材の期限") {
                if expiry.isEmpty {
                    Label("期限が近い食材はありません", systemImage: "checkmark.circle")
                        .foregroundStyle(AppTheme.secondary).accessibilityIdentifier("notice-expiry-empty")
                }
                ForEach(expiry) { notice in
                    NavigationLink {
                        if let item = stock.first(where: { $0.id == notice.inventoryID && !$0.isDeleted }) {
                            InventoryEditorView(item: item).onAppear { mark(notice.id) }
                        } else { ContentUnavailableView("食材が見つかりません", systemImage: "refrigerator") }
                    } label: { noticeRow(notice) }
                        .accessibilityIdentifier("notice-" + (notice.inventoryID?.uuidString ?? notice.id))
                }
            }
            Section("アプリから") {
                ForEach(AppNoticeFeed.updates()) { notice in
                    NavigationLink {
                        NoticeUpdateDetail(notice: notice, recipes: recipes).onAppear { mark(notice.id) }
                    } label: { noticeRow(notice) }.accessibilityIdentifier("notice-" + notice.id)
                }
            }
            Section {
                NavigationLink { NotificationSettingsView() } label: {
                    Label("期限通知の設定", systemImage: "bell.badge")
                }
            }
        }.navigationTitle("お知らせ").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("すべて既読") {
                        readJSON = NoticeReadState.marking(items.map(\.id), in: readJSON, current: items)
                    }.disabled(unread == 0).accessibilityIdentifier("notice-read-all")
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = .now }
    }
    private func noticeRow(_ notice: InAppNotice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.kind == .expiry ? "calendar.badge.exclamationmark" : "sparkles")
                .foregroundStyle(notice.kind == .update ? AppTheme.accent : notice.overdue ? AppTheme.danger : AppTheme.warning)
                .frame(width: 24).padding(.top, 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(notice.title).font(AppFont.headline).foregroundStyle(AppTheme.text)
                Text(notice.body).font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if notice.kind == .update { Text(notice.date.formatted(.dateTime.month().day())).font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
            }
            if !NoticeReadState.ids(readJSON).contains(notice.id) {
                Circle().fill(AppTheme.accent).frame(width: 7, height: 7).padding(.top, 7).accessibilityHidden(true)
            }
        }.padding(.vertical, 6).frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityValue(NoticeReadState.ids(readJSON).contains(notice.id) ? "既読" : "未読")
    }
}

private struct NoticeUpdateDetail: View {
    let notice: InAppNotice
    let recipes: [Recipe]
    var body: some View {
        List {
            Section {
                Text(notice.title).font(AppFont.title2.bold())
                Text(notice.date.formatted(.dateTime.year().month().day())).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                Text(notice.body).fixedSize(horizontal: false, vertical: true)
            }
            Section("レシピを見る") {
                ForEach(notice.recipeKeys.compactMap { key in recipes.first { $0.key == key } }) { recipe in
                    NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                        HStack(spacing: 12) {
                            RecipeMealImage(height: 56, recipeKey: recipe.key).frame(width: 56).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title).foregroundStyle(AppTheme.text)
                                Label("\(recipe.minutes)分", systemImage: "clock").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                            }.fixedSize(horizontal: false, vertical: true)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("notice-recipe-" + recipe.key)
                }
            }
        }.navigationTitle("更新情報").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(AppTheme.background)
    }
}
