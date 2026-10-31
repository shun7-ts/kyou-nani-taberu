import SwiftUI
import SwiftData

struct RootView: View {
    let recipes: [Recipe]
    @EnvironmentObject private var notices: ExpiryNotifications
    @EnvironmentObject private var session: AppSession
    @State private var selectedTab = 0
    @State private var todayPlanRequest = 0
    @AppStorage("privacyPolicyConsentVersion") private var policyVersion = 0
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var inventory: [InventoryItem]
    @State private var showNotificationIntroduction = false
    private var stockSignature: String {
        inventory.map { "\($0.id)-\($0.syncVersion)-\($0.updatedAt)-\($0.expiresAt?.description ?? "")-\($0.isDeleted)" }.sorted().joined()
    }
    private func refreshNotices() {
        notices.requestRefresh(container: context.container)
    }
    private func introduceNotifications() {
        guard !session.isResetting, policyVersion == PrivacyPolicy.version, notices.isReady, !showSetup, setupCompleted, !notices.introductionShown,
              notices.authorization == .notDetermined,
              inventory.contains(where: { InventoryService.usable($0, on: .now) && $0.expiresAt != nil }) else { return }
        notices.introductionShown = true
        showNotificationIntroduction = true
    }
    @AppStorage("initialInventorySetupCompleted") private var setupCompleted = false
    @State private var showSetup = false
    private func presentInitialFlow() {
        guard !session.isResetting else { return }
        guard policyVersion == PrivacyPolicy.version else { return }
        if !setupCompleted { showSetup = true }
        else { introduceNotifications() }
    }
    var body: some View {
        Group {
            if policyVersion != PrivacyPolicy.version {
                PrivacyIntroductionView(onComplete: { showSetup = !setupCompleted })
            } else { tabContents }
        }
    }
    private var tabContents: some View {
        TabView(selection: $selectedTab) {
            HomeView(recipes: recipes, openPlan: { todayPlanRequest += 1; selectedTab = 1 }).tint(AppTheme.accent).tag(0).tabItem { Label("ホーム", systemImage: "house").environment(\.symbolVariants, .none) }
            MealPlanView(recipes: recipes).id(todayPlanRequest).tint(AppTheme.accent).tag(1).tabItem { Label("献立", systemImage: "calendar").environment(\.symbolVariants, .none) }
            RefrigeratorView().tint(AppTheme.accent).tag(2).tabItem { Label("マイ冷蔵庫", systemImage: "refrigerator").environment(\.symbolVariants, .none) }
            ShoppingView().tint(AppTheme.accent).tag(3).tabItem { Label("買い物", systemImage: "basket").environment(\.symbolVariants, .none) }
        }.tint(AppTheme.tabAccent)
            .onAppear { presentInitialFlow() }
            .task { refreshNotices() }
            .onChange(of: stockSignature) { introduceNotifications(); refreshNotices() }
            .onChange(of: notices.settingsSignature) { refreshNotices() }
            .onChange(of: notices.isReady) { introduceNotifications() }
            .onChange(of: notices.authorization) { introduceNotifications() }
            .onChange(of: showSetup) { introduceNotifications() }
            .onChange(of: scenePhase) { if scenePhase == .active { refreshNotices() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshNotices() }
            .onReceive(NotificationCenter.default.publisher(for: ExpiryNotifications.inventoryChanged)) { _ in refreshNotices() }
            .safeAreaInset(edge: .top) {
                if showNotificationIntroduction {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("期限が近い食材をお知らせできます").font(AppFont.headline)
                        Text("通知する日と時刻はマイページで変更できます。許可しなくても在庫管理は使えます。")
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                        HStack {
                            Button("通知を許可する") {
                                showNotificationIntroduction = false
                                Task { await notices.allow(container: context.container) }
                            }.accessibilityIdentifier("expiry-introduction-allow")
                            Spacer()
                            Button("あとで") { showNotificationIntroduction = false }
                                .accessibilityIdentifier("expiry-introduction-later")
                        }.frame(minHeight: 44)
                    }.padding().background(AppTheme.background)
                }
            }
            .sheet(isPresented: Binding(get: { notices.openedInventoryID != nil && policyVersion == PrivacyPolicy.version && !showSetup }, set: { if !$0 { notices.openedInventoryID = nil } })) {
                if let item = inventory.first(where: { $0.id == notices.openedInventoryID && !$0.isDeleted }) {
                    InventoryEditorView(item: item)
                } else { ContentUnavailableView("この食材は取り除かれています", systemImage: "carrot") }
            }
            .sheet(isPresented: $showSetup) {
                BulkInventoryView(onComplete: { setupCompleted = true })
                    .interactiveDismissDisabled()
            }
    }
}
struct MyPageView: View {
    var embedded = false
    @AppStorage(AppPreferences.defaultServings) private var preferredServings = 1
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    @State private var showBulk = false
    var body: some View {
        if embedded { contents } else { NavigationStack { contents } }
    }
    private var contents: some View {
            List {
                Section("レシピ") {
                    LabeledFilterMenu(title: "いつもの人数", selection: $preferredServings,
                        options: Array(1...4), label: { "\($0)人分" })
                        .accessibilityIdentifier("settings-default-servings")
                    NavigationLink("おすすめの見方") { SuggestionExplanationView() }
                        .accessibilityIdentifier("settings-suggestion-explanation")
                }
                Section {
                    Toggle("同じ条件の在庫へ自動合算", isOn: $mergeInventory)
                        .accessibilityIdentifier("settings-merge-inventory")
                    Button("家にあるものをまとめて登録") { showBulk = true }
                } header: { Text("食材の登録") } footer: {
                    Text("保存方法・期限が同じ在庫に追加。量が不明な組み合わせは分けます。")
                }
                Section("写真・音声の利用と同意") {
                    NavigationLink("レシート写真の扱い") { ReceiptPrivacyView() }
                    NavigationLink("音声の扱い") { VoicePrivacyView() }
                }
                Section("通知") { NavigationLink("期限通知") { NotificationSettingsView() } }
                Section("在庫の管理") { NavigationLink("取り除いた食材を戻す") { RemovedInventoryView() } }
                Section("プライバシー・データ管理") {
                    NavigationLink("プライバシーポリシー") { PrivacyPolicyView() }.accessibilityIdentifier("settings-privacy-policy")
                    NavigationLink("端末内データを全削除") { DeleteDataView() }.accessibilityIdentifier("settings-delete-data")
                }
                Section("データについて") {
                    NavigationLink("画像の出典") { MealPhotoCreditsView() }.accessibilityIdentifier("settings-photo-credits")
                    NavigationLink("フォントのライセンス") { FontLicenseView() }.accessibilityIdentifier("settings-font-license")
                    Text("在庫と買い物リストはこの端末に保存されます。アカウント登録は必要ありません。")
                }
            }.scrollContentBackground(.hidden).background(AppTheme.background)
                .modifier(PageHeading(title: "マイページ", icon: "person.crop.circle"))
                .sheet(isPresented: $showBulk) { BulkInventoryView() }
    }
}

struct RemovedInventoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var stock: [InventoryItem]
    @Query private var masters: [IngredientMaster]
    @Query private var customs: [CustomIngredient]
    @State private var error: String?
    var body: some View {
        List {
            let removed = stock.filter(\.isDeleted)
            if removed.isEmpty { Text("取り除いた食材はありません。") }
            ForEach(removed) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(masters.first { $0.id == item.ingredientMasterID }?.canonicalName
                            ?? customs.first { $0.id == item.customIngredientID }?.name ?? "食材")
                        Text(amountLabel(item) + " · " + expiryLabel(item)).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer()
                    Button("戻す") {
                        do { try InventoryService(container: context.container).restore(id: item.id) }
                        catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 44)
                }
            }
        }.navigationTitle("取り除いた食材")
            .alert("戻せませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
}
