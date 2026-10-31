import SwiftUI
import SwiftData
import PhotosUI

struct ReceiptPrivacyView: View {
    @AppStorage("receiptConsentVersion") private var version = 0
    @AppStorage("receiptConsentDate") private var acceptedAt = 0.0
    static let currentVersion = 2
    var body: some View {
        Form {
            ReceiptPrivacyText()
            Section("利用への同意") {
                if version == Self.currentVersion {
                    Text("同意済み（説明 v\(Self.currentVersion)）")
                    if acceptedAt > 0 { Text(Date(timeIntervalSince1970: acceptedAt), style: .date) }
                    Button("レシート読み取りへの同意を取り消す", role: .destructive) { version = 0; acceptedAt = 0 }
                } else {
                    Text("同意していません。手入力と在庫管理は引き続き利用できます。")
                    Button("説明に同意する") { acceptedAt = Date.now.timeIntervalSince1970; version = Self.currentVersion }
                }
            }
        }.navigationTitle("レシート写真の扱い")
    }
}

private struct ReceiptPrivacyText: View {
    var body: some View {
        Section("写真の利用目的") {
            Text("説明 v2：選んだ写真またはアプリ内で撮影したレシートから商品名や数量を読み取り、在庫の入力を補助します。結果は保存前に修正できます。")
        }
        Section("写真とデータの扱い") {
            Text("文字の読み取りは端末内で行います。アプリから写真や認識結果を外部の認識サービスへ送信しません。")
            Text("読み取り用の画像はメモリ上で扱い、処理終了後に解放します。アプリのファイルやデータベースには画像を保存しません。確認画面を閉じると未保存の読み取り結果も破棄します。")
            Text("撮影は静止画1枚です。カメラの許可は撮影ボタンを押したときに求め、動画やマイクは使いません。撮影した画像を写真ライブラリへ追加しません。撮影の中止やアプリを離れた場合は未処理の画像を破棄します。")
            Text("写真ライブラリにある元の写真は削除しません。iCloudにしかない写真の取得には通信が必要な場合があります。")
            Text("保存するのは確認した食材・数量・保存方法・日付などの在庫情報と登録履歴です。レシート全文や金額は保存しません。")
        }
        Section("選択できます") {
            Text("同意しなくても手入力を使えます。同意は設定から取り消せます。カメラを拒否しても写真選択・手入力で続けられます。OSの許可はiPhoneの設定から変更できます。")
        }
    }
}

struct ReceiptImportView: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var editingMargin: CGFloat = 120
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = ReceiptCameraTesting.controller()
    @Query private var masters: [IngredientMaster]
    @Query private var inventory: [InventoryItem]
    @AppStorage("receiptConsentVersion") private var consent = 0
    @AppStorage("receiptConsentDate") private var acceptedAt = 0.0
    @State private var manualMode = false
    @FocusState private var inputFocus: ReceiptInputField?
    @State private var rows: [ReceiptRow] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var sessionID = UUID()
    @State private var processing = false
    @State private var saving = false
    @State private var error: String?
    @State private var purchaseDate = Date.now
    @State private var storage: StorageMethod = .refrigerated
    @State private var discardConfirmation = false
    @State private var foodTarget: ReceiptFoodTarget?
    private var available: [IngredientMaster] { masters.filter { $0.trackInventory && $0.status == .active }.sorted { $0.canonicalName < $1.canonicalName } }
    private var canSave: Bool {
        let selected = rows.filter(\.included)
        return !selected.isEmpty && !processing && !camera.preparing && !saving && selected.allSatisfy {
            ($0.masterID != nil || !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (!$0.exact || (Double($0.quantity).map { $0.isFinite && $0 > 0 } ?? false))
        }
    }
    var body: some View {
        NavigationStack {
            Group {
                if consent != ReceiptPrivacyView.currentVersion && !manualMode {
                    Form {
                        ReceiptPrivacyText()
                        Button("同意して読み取りへ進む") {
                            acceptedAt = Date.now.timeIntervalSince1970; consent = ReceiptPrivacyView.currentVersion
                        }.accessibilityIdentifier("receipt-consent")
                        Button("同意せず手入力する") { manualMode = true; addRow() }
                            .accessibilityIdentifier("receipt-manual-without-consent")
                    }
                } else { reviewForm }
            }.navigationTitle(rows.isEmpty ? "レシートから登録" : "読み取り結果")
                .navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden).background(AppTheme.background)
                .toolbar {
                    if !rows.isEmpty {
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 5) {
                                Image(systemName: "receipt")
                                Text("読み取り結果").lineLimit(1).minimumScaleFactor(0.75)
                            }.font(AppFont.subheadline).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundStyle(AppTheme.accent).accessibilityElement(children: .combine)
                                .accessibilityLabel("読み取り結果").accessibilityIdentifier("receipt-result-title")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                receiptPhotoActions
                                Button("食材を追加", systemImage: "plus") { addRow() }.accessibilityIdentifier("receipt-add-row")
                            } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("食材や写真を追加").accessibilityIdentifier("receipt-add-menu")
                                .disabled(processing || camera.preparing)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { if rows.isEmpty { clear(); dismiss() } else { discardConfirmation = true } }
                    }
                }
                .confirmationDialog("未保存の読み取り結果を破棄しますか？", isPresented: $discardConfirmation, titleVisibility: .visible) {
                    Button("破棄して閉じる", role: .destructive) { clear(); dismiss() }
                }
                .interactiveDismissDisabled(!rows.isEmpty || processing || camera.preparing)
                .onChange(of: selectedPhoto) { if let selectedPhoto { load(selectedPhoto) } }
                .onChange(of: consent) { if consent != ReceiptPrivacyView.currentVersion { clear(); manualMode = false } }
                .onChange(of: scenePhase, initial: true) { updateCameraActivity() }
                .fullScreenCover(item: Binding(get: { camera.session }, set: { if $0 == nil, camera.session != nil { camera.cancel() } }), onDismiss: {
                    let data = camera.presentationDidDismiss()
                    if consent == ReceiptPrivacyView.currentVersion, let data { read { data } }
                }) { session in
                    Group {
                        if ReceiptCameraTesting.fixture {
                            ReceiptCameraFixtureView(sessionID: session.id, completed: camera.complete, cancelled: camera.cancel(sessionID:))
                        } else {
                            ReceiptCameraPicker(sessionID: session.id, completed: camera.complete, cancelled: camera.cancel(sessionID:))
                        }
                    }.ignoresSafeArea().interactiveDismissDisabled()
                }
                .sheet(item: $foodTarget) { target in
                    ReceiptFoodSearch(masters: available, suggestedIDs: rows.first { $0.id == target.id }?.suggestedMasterIDs ?? [], onSelect: { food in
                        guard let index = rows.firstIndex(where: { $0.id == target.id }) else { return }
                        let ingredient = ReceiptIngredient(id: food.id, name: food.canonicalName, aliases: food.aliases,
                            unit: food.defaultUnit, allowedUnits: food.allowedUnits, storage: food.defaultStorage, category: food.category)
                        rows[index] = ReceiptParser.resolving(rows[index], as: ingredient)
                    }, onCustom: { name in
                        guard let index = rows.firstIndex(where: { $0.id == target.id }) else { return }
                        rows[index].masterID = nil; rows[index].name = name; rows[index].category = .other
                        rows[index].included = true; rows[index].suggestedMasterIDs = []
                    })
                }
                .onDisappear { if !camera.presentationActive && foodTarget == nil { clear() } }
        }
    }
    private var reviewForm: some View {
        ScrollViewReader { scroll in
            Form {
                if rows.isEmpty {
                    Section {
                        receiptPhotoActions
                        Button("食材を手入力で追加") { addRow() }.disabled(processing || camera.preparing)
                            .accessibilityIdentifier("receipt-add-row")
                        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-receipt-fixture") && consent == ReceiptPrivacyView.currentVersion {
                            Button("読み取り例を使う") { apply(lines: ["牛乳 1000ml ¥198", "台所スポンジ ¥100", "レジ袋（大） ¥5", "有料袋 ¥3", "フロッコリー 200g ¥158", "小計 ¥461", "支払い レモン", "卵 ¥298"]) }
                                .accessibilityIdentifier("receipt-fixture")
                        }
                    }
                }
                if !rows.isEmpty {
                    Section("共通設定") {
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(spacing: 8))
                        layout {
                            DatePicker("購入日", selection: $purchaseDate, displayedComponents: .date).labelsHidden()
                                .accessibilityLabel("共通の購入日").accessibilityIdentifier("receipt-common-date")
                            if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                            Picker("保存方法", selection: $storage) {
                                ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.menu).labelsHidden().accessibilityLabel("共通の保存方法")
                                .accessibilityIdentifier("receipt-common-storage")
                        }.font(AppFont.subheadline)
                    }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .onChange(of: purchaseDate) { for index in rows.indices where !rows[index].purchaseDateOverridden { rows[index].purchasedAt = purchaseDate } }
                        .onChange(of: storage) { for index in rows.indices where !rows[index].storageOverridden { rows[index].storage = storage } }
                    ForEach(rows) { snapshot in
                        // SwiftUI may read a row binding during its dismissal animation after cleanup.
                        // Resolve by stable identity, and ignore writes once the draft has been removed.
                        ReceiptRowView(row: Binding(get: {
                            rows.first { $0.id == snapshot.id } ?? snapshot
                        }, set: { updated in
                            if let index = rows.firstIndex(where: { $0.id == snapshot.id }) { rows[index] = updated }
                        }), masters: available, inventory: inventory, inputFocus: $inputFocus) {
                            endEditing(); foodTarget = ReceiptFoodTarget(id: snapshot.id)
                        }
                    }
                }
                if processing || camera.preparing || error != nil || camera.message != nil {
                    Section {
                        if processing {
                            ProgressView("読み取り中…")
                            Button("読み取りを中止") { cancelReading() }
                        }
                        if camera.preparing {
                            ProgressView("撮影の準備中…")
                            Button("撮影の準備を中止") { camera.cancel() }.accessibilityIdentifier("receipt-camera-cancel-preparation")
                        }
                        if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("receipt-error") }
                        if let message = camera.message {
                            Text(message).foregroundStyle(AppTheme.warning).accessibilityIdentifier("receipt-camera-message")
                        }
                        if camera.settingsNeeded, let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("iPhoneの設定を開く", destination: url).accessibilityIdentifier("receipt-camera-settings")
                        }
                    }
                }
            }.listSectionSpacing(.compact).id(rows.isEmpty)
            .contentMargins(.bottom, inputFocus == nil ? 0 : editingMargin, for: .scrollContent)
            .onChange(of: inputFocus) { revealInput(using: scroll) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in revealInput(using: scroll) }
        }.safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if inputFocus != nil {
                    HStack {
                        Spacer()
                        Button("入力を完了") { endEditing() }.frame(minHeight: 44)
                            .accessibilityIdentifier("receipt-keyboard-done")
                    }.padding(.horizontal)
                }
                if inputFocus == nil {
                    Button { save() } label: {
                        Text("\(rows.filter(\.included).count)品を登録").frame(maxWidth: .infinity)
                    }.buttonStyle(CoralPrimaryButtonStyle()).disabled(!canSave).padding()
                        .accessibilityLabel("\(rows.filter(\.included).count)品を冷蔵庫へ登録").accessibilityIdentifier("receipt-save")
                }
            }.background(AppTheme.background)
        }
    }
    @ViewBuilder private var receiptPhotoActions: some View {
        if consent == ReceiptPrivacyView.currentVersion {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("レシート写真を選ぶ", systemImage: "photo")
            }.disabled(processing || camera.preparing).accessibilityIdentifier("receipt-photo-picker")
            Button { Task { await camera.open() } } label: {
                Label("レシートを撮影する", systemImage: "camera")
            }.disabled(processing || camera.preparing).accessibilityIdentifier("receipt-camera")
        }
    }
    private func revealInput(using scroll: ScrollViewProxy) {
        guard let inputFocus else { return }
        withAnimation { scroll.scrollTo(inputFocus, anchor: .top) }
    }
    private func addRow() {
        var row = ReceiptRow(); row.purchasedAt = purchaseDate; row.storage = storage; rows.append(row)
    }
    private func apply(lines: [String]) {
        do {
            let ingredients = available.map { ReceiptIngredient(id: $0.id, name: $0.canonicalName, aliases: $0.aliases,
                unit: $0.defaultUnit, allowedUnits: $0.allowedUnits, storage: $0.defaultStorage, category: $0.category) }
            var candidates = try ReceiptParser.parse(lines, ingredients: ingredients)
            guard !candidates.isEmpty else { throw ReceiptError.noProducts }
            guard rows.count + candidates.count <= 120 else { throw ReceiptError.tooManyRows }
            for index in candidates.indices { candidates[index].purchasedAt = purchaseDate; candidates[index].storage = storage }
            rows.append(contentsOf: candidates); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func updateCameraActivity() {
        switch scenePhase {
        case .active: camera.activityChanged(.active)
        case .background: camera.activityChanged(.background); cancelReading()
        default: camera.activityChanged(.inactive)
        }
    }
    private func load(_ photo: PhotosPickerItem) {
        read {
            guard let data = try await photo.loadTransferable(type: Data.self) else { throw ReceiptError.invalidImage }
            return data
        }
    }
    private func read(_ loadData: @escaping () async throws -> Data) {
        guard consent == ReceiptPrivacyView.currentVersion else { return }
        cancelReading(); processing = true; error = nil
        let token = generation
        task = Task { @MainActor in
            do {
                let data = try await loadData()
                guard !Task.isCancelled, token == generation, consent == ReceiptPrivacyView.currentVersion else { return }
                let lines = try await ReceiptOCR.recognize(data: data)
                guard !Task.isCancelled, token == generation, consent == ReceiptPrivacyView.currentVersion else { return }
                apply(lines: lines)
            } catch {
                if !Task.isCancelled && token == generation { self.error = error.localizedDescription }
            }
            if token == generation { selectedPhoto = nil; processing = false; task = nil }
        }
    }
    private func cancelReading() { generation = UUID(); task?.cancel(); task = nil; selectedPhoto = nil; processing = false }
    private func endEditing() { inputFocus = nil; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func clear() { endEditing(); foodTarget = nil; camera.cancel(); cancelReading(); rows.removeAll(); error = nil }
    private func save() {
        guard canSave else { return }
        saving = true
        do {
            // The final registration action confirms the selected, edited rows together.
            let reviewed = rows.map { row in var copy = row; copy.confirmed = row.included; return copy }
            try ReceiptImportService(container: context.container, mergeDuplicates: mergeInventory).save(rows: reviewed, sessionID: sessionID)
            clear(); dismiss()
        }
        catch { self.error = error.localizedDescription; saving = false }
    }
}

private struct ReceiptFoodTarget: Identifiable { let id: UUID }

private enum ReceiptInputField: Hashable {
    case name(UUID)
    case quantity(UUID)
}

private struct ReceiptRowView: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var row: ReceiptRow
    let masters: [IngredientMaster]
    let inventory: [InventoryItem]
    let inputFocus: FocusState<ReceiptInputField?>.Binding
    let chooseFood: () -> Void
    @State private var expanded = false
    @State private var showsCalendar = false
    private var master: IngredientMaster? { masters.first { $0.id == row.masterID } }
    private var units: [IngredientUnit] { master?.allowedUnits ?? IngredientUnit.allCases }
    private var unresolved: Bool { row.masterID == nil && row.name.isEmpty && row.source != "手入力" }
    private var suggestions: [IngredientMaster] { masters.filter { row.suggestedMasterIDs.contains($0.id) } }
    private var mergeTarget: InventoryItem? { inventory.first { ReceiptImportService.canMerge(row, into: $0) } }
    private var quantityField: some View {
        TextField("数量", text: $row.quantity).id(ReceiptInputField.quantity(row.id)).focused(inputFocus, equals: .quantity(row.id))
            .keyboardType(.decimalPad).accessibilityLabel(row.name.isEmpty ? "数量" : row.name + "の数量").accessibilityIdentifier("receipt-quantity")
    }
    private var unitPicker: some View {
        Picker("単位", selection: $row.unit) { ForEach(units, id: \.self) { Text($0.label).tag($0) } }
            .pickerStyle(.menu).accessibilityIdentifier("receipt-unit")
    }
    var body: some View {
        Section {
            HStack(spacing: 8) {
                Button(action: chooseFood) {
                    HStack(spacing: 6) {
                        Text(row.masterID == nil ? "食材を選ぶ" : row.name).font(AppFont.headline)
                            .foregroundStyle(row.name.isEmpty ? AppTheme.accent : AppTheme.productName)
                        Image(systemName: "magnifyingglass").font(AppFont.caption).foregroundStyle(AppTheme.accent)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("receipt-food-" + (master?.key ?? "unresolved"))
                Spacer(minLength: 0)
                Button { row.included.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: row.included ? "checkmark.square.fill" : "square")
                        if !textSize.isAccessibilitySize { Text("登録") }
                    }.font(AppFont.caption).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                    .accessibilityLabel((row.name.isEmpty ? row.source : row.name) + "を登録")
                    .accessibilityValue(row.included ? "オン" : "オフ").accessibilityIdentifier("receipt-include")
            }.listRowSeparator(.hidden)
            if row.source != "手入力" {
                Text(row.source).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if unresolved {
                Label("確認できませんでした", systemImage: "exclamationmark.circle")
                    .font(AppFont.subheadline).foregroundStyle(AppTheme.warning).accessibilityIdentifier("receipt-unresolved")
                ForEach(suggestions.prefix(3)) { food in
                    Button { select(food) } label: {
                        Label("候補：" + food.canonicalName, systemImage: "magnifyingglass").frame(minHeight: 44)
                    }.accessibilityIdentifier("receipt-suggestion-" + food.key)
                }
            }
            if row.included {
                if row.masterID == nil {
                    TextField("食材名", text: $row.name).id(ReceiptInputField.name(row.id))
                        .focused(inputFocus, equals: .name(row.id)).accessibilityIdentifier("receipt-custom-name")
                }
                Toggle("数量を入力", isOn: $row.exact).accessibilityIdentifier("receipt-exact")
                if row.exact {
                    let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 10))
                    layout { quantityField; unitPicker }
                }
                Button { expanded.toggle() } label: {
                    HStack {
                        Text("保存・期限")
                        Spacer(minLength: 0)
                        if !textSize.isAccessibilitySize {
                            Text(row.storage.label + (row.exact ? "" : "・" + row.rough.label))
                                .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(AppFont.caption).foregroundStyle(AppTheme.accent)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("receipt-details-" + (master?.key ?? "custom"))
                    .accessibilityValue(expanded ? "展開中" : "折りたたみ")
                if expanded {
                    if !row.exact {
                        Picker("在庫の状態", selection: $row.rough) {
                            Text("あり").tag(RoughStockState.available)
                            Text("少なめ").tag(RoughStockState.low)
                            Text("なし").tag(RoughStockState.unavailable)
                        }.pickerStyle(.menu)
                    }
                    Picker("保存方法", selection: Binding(get: { row.storage }, set: { row.storage = $0; row.storageOverridden = true })) {
                        ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("receipt-storage")
                    DatePicker("購入日", selection: Binding(get: { row.purchasedAt }, set: { row.purchasedAt = $0; row.purchaseDateOverridden = true }), displayedComponents: .date)
                        .accessibilityIdentifier("receipt-date")
                    let expiryLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 8))
                    expiryLayout {
                        Text("期限")
                        if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                        HStack(spacing: 4) {
                            Button {
                                if row.expiresAt == nil { row.expiresAt = Calendar.current.startOfDay(for: .now) }
                                showsCalendar = true
                            } label: {
                                Text(row.expiresAt?.formatted(date: .numeric, time: .omitted) ?? "指定なし")
                                    .font(AppFont.subheadline).lineLimit(1).minimumScaleFactor(0.6)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                    .frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel("期限").accessibilityIdentifier("receipt-expiry")
                                .popover(isPresented: $showsCalendar) {
                                    DatePicker("期限", selection: Binding(get: { row.expiresAt ?? .now }, set: { row.expiresAt = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date)
                                        .datePickerStyle(.graphical).labelsHidden().padding(8).frame(width: 320)
                                        .presentationCompactAdaptation(.popover)
                                }
                            if row.expiresAt != nil {
                                Button { row.expiresAt = nil; row.expiryKind = .unspecified } label: {
                                    Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                                }.buttonStyle(.plain).foregroundStyle(AppTheme.secondary)
                                    .accessibilityLabel("期限を解除").accessibilityIdentifier("receipt-expiry-clear")
                            }
                        }
                    }
                    if row.expiresAt != nil {
                        Picker("期限の種類", selection: $row.expiryKind) {
                            ForEach([ExpiryKind.unspecified, .bestBefore, .useBy], id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.menu)
                    }
                    if mergeInventory && row.merge && mergeTarget != nil {
                        Label("同じ条件の在庫にまとめます", systemImage: "plus.circle")
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    }
                }
            }
        }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
    private func select(_ food: IngredientMaster) {
        let ingredient = ReceiptIngredient(id: food.id, name: food.canonicalName, aliases: food.aliases,
            unit: food.defaultUnit, allowedUnits: food.allowedUnits, storage: food.defaultStorage, category: food.category)
        row = ReceiptParser.resolving(row, as: ingredient)
    }
}

private struct ReceiptFoodSearch: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let masters: [IngredientMaster]
    let suggestedIDs: [UUID]
    let onSelect: (IngredientMaster) -> Void
    let onCustom: (String) -> Void
    private var foods: [IngredientMaster] {
        masters.filter { ReceiptParser.searchMatches(search, names: [$0.canonicalName] + $0.aliases) }
    }
    var body: some View {
        NavigationStack {
            List {
                if foods.isEmpty { Text("食材が見つかりませんでした").foregroundStyle(AppTheme.secondary) }
                if search.isEmpty && !suggestedIDs.isEmpty {
                    Section("候補") { ForEach(foods.filter { suggestedIDs.contains($0.id) }) { food in foodButton(food) } }
                }
                Section {
                    ForEach(foods.filter { !search.isEmpty || !suggestedIDs.contains($0.id) }) { food in foodButton(food) }
                }
                Section {
                    Button {
                        onCustom(search.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
                    } label: { Label("カスタム食材として入力", systemImage: "square.and.pencil").frame(minHeight: 44) }
                        .accessibilityIdentifier("receipt-custom-food")
                }
            }.searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "食材名・別名で検索")
                .navigationTitle("食材を選ぶ").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }
    private func foodButton(_ food: IngredientMaster) -> some View {
        Button { onSelect(food); dismiss() } label: {
            Label { Text(food.canonicalName) } icon: { IngredientCategoryIcon(category: food.category) }.frame(minHeight: 44)
        }.accessibilityIdentifier("receipt-search-food-" + food.key)
    }
}
