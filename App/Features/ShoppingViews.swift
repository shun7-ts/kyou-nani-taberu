import SwiftUI
import SwiftData
import UIKit

struct ShoppingView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ShoppingListItem> { !$0.isAddedToInventory }, sort: \ShoppingListItem.createdAt)
    private var open: [ShoppingListItem]
    @State private var filter = "すべて"
    @State private var showAdd = false
    @State private var showPurchase = false
    @State private var purchaseOpening = false
    @State private var purchaseRows: [ShoppingListItem] = []
    @StateObject private var checks = ShoppingChecks()
    @State private var editing: ShoppingListItem?
    @State private var error: String?
    private func checked(_ row: ShoppingListItem) -> Bool { checks.isChecked(id: row.id, stored: row.isChecked) }
    private var checkValues: [UUID: Bool] { Dictionary(uniqueKeysWithValues: open.map { ($0.id, $0.isChecked) }) }
    var body: some View {
        let presentation = ShoppingPresentation(rows: open, filter: filter, checks: checks)
        NavigationStack {
            List {
                if typeSize.isAccessibilitySize {
                    LabeledFilterMenu(title: "表示", selection: $filter,
                        options: ["すべて", "未購入", "購入済み"], label: { $0 })
                        .accessibilityIdentifier("shopping-filter").disabled(purchaseOpening)
                } else {
                    Picker("表示", selection: $filter) {
                        ForEach(["すべて", "未購入", "購入済み"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("shopping-filter").disabled(purchaseOpening)
                }
                if open.isEmpty {
                    ContentUnavailableView("買うものはまだありません", systemImage: "basket",
                        description: Text("献立の不足分を追加できます。"))
                    Button("買うものを追加") { showAdd = true }
                }
                ForEach([true, false], id: \.self) { derived in
                    let rows = derived ? presentation.mealRows : presentation.manualRows
                    if !rows.isEmpty {
                        Section(derived ? "献立から" : "追加したもの") {
                            ForEach(rows) { row in
                                ShoppingRowView(row: row, locked: purchaseOpening,
                                    toggle: { checks.toggle(id: row.id, stored: row.isChecked) },
                                    edit: { editing = open.first { $0.id == row.id } },
                                    remove: {
                                        do { try MealService(container: context.container).removeShopping(id: row.id) }
                                        catch { self.error = error.localizedDescription }
                                    }).equatable()
                            }
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(AppTheme.background)
                .modifier(PageHeading(title: "買い物", icon: "basket"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Label("買うものを追加", systemImage: "plus") }
                            .disabled(purchaseOpening)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    let count = presentation.checkedCount
                    if count > 0 {
                        VStack(spacing: 0) {
                        Button {
                            guard !purchaseOpening else { return }
                            purchaseOpening = true
                            Task { @MainActor in
                                defer { purchaseOpening = false }
                                guard await checks.flush() else { return }
                                purchaseRows = open.filter { checked($0) }
                                if !purchaseRows.isEmpty { showPurchase = true }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if purchaseOpening { ProgressView().tint(AppTheme.secondary).accessibilityHidden(true) }
                                Text(purchaseOpening ? "保存中…" : typeSize.isAccessibilitySize ? "\(count)品を確認" : "購入した\(count)品を確認")
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(CoralPrimaryButtonStyle()).disabled(purchaseOpening)
                            .accessibilityLabel("購入した\(count)品を確認")
                            .accessibilityValue(purchaseOpening ? "保存中" : "")
                            .accessibilityIdentifier("shopping-complete")
                        Button {
                            guard !purchaseOpening else { return }
                            purchaseOpening = true
                            Task { @MainActor in
                                defer { purchaseOpening = false }
                                guard await checks.flush() else { return }
                                do {
                                    let ids = Set(open.filter { checked($0) }.map(\.id))
                                    try MealService(container: context.container).removeCheckedShopping(ids: ids)
                                } catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            Label("かごから取り除く", systemImage: "minus.circle")
                                .font(AppFont.caption).frame(minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(AppTheme.secondary).disabled(purchaseOpening)
                            .accessibilityLabel("購入済みの\(count)品を買い物かごから取り除く")
                            .accessibilityIdentifier("shopping-remove-checked")
                        }.padding(.horizontal).padding(.top, 8).background(AppTheme.background)
                    }
                }
                .sheet(isPresented: $showAdd) { ManualShoppingView() }
                .sheet(item: $editing) { ManualShoppingView(item: $0) }
                .sheet(isPresented: $showPurchase) { PurchaseView(rows: purchaseRows) }
                .onAppear { checks.configure(container: context.container); checks.synchronize(checkValues) }
                .onChange(of: checkValues) { _, values in checks.synchronize(values) }
                .alert("変更できませんでした", isPresented: Binding(get: { error != nil || checks.errorMessage != nil }, set: { if !$0 {
                    error = nil
                    // SwiftUI may dismiss the alert during a view update; publish afterward.
                    Task { @MainActor in checks.errorMessage = nil }
                } })) {
                    Button("閉じる", role: .cancel) {}
                } message: { Text(error ?? checks.errorMessage ?? "") }
        }
    }
}
/// Plain display values make unchanged rows skip body evaluation after another row changes.
struct ShoppingRowPresentation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let quantity: Double
    let unit: IngredientUnit
    let sourceMealID: UUID?
    let sourceRecipeTitle: String?
    let needsConfirmation: Bool
    let isChecked: Bool
    let isSaving: Bool
    init(row: ShoppingListItem, checked: Bool, saving: Bool) {
        id = row.id; name = row.name; quantity = row.quantity; unit = row.unit
        sourceMealID = row.sourceMealID; sourceRecipeTitle = row.sourceRecipeTitle
        needsConfirmation = row.needsConfirmation; isChecked = checked; isSaving = saving
    }
}
struct ShoppingPresentation {
    var mealRows: [ShoppingRowPresentation] = []
    var manualRows: [ShoppingRowPresentation] = []
    var checkedCount = 0
    @MainActor init(rows: [ShoppingListItem], filter: String, checks: ShoppingChecks) {
        for row in rows where !row.isAddedToInventory {
            let checked = checks.isChecked(id: row.id, stored: row.isChecked)
            if checked { checkedCount += 1 }
            guard filter == "すべて" || (filter == "購入済み" ? checked : !checked) else { continue }
            let value = ShoppingRowPresentation(row: row, checked: checked, saving: checks.savingIDs.contains(row.id))
            if row.sourceMealID != nil { mealRows.append(value) } else { manualRows.append(value) }
        }
    }
}
private struct ShoppingRowView: View, Equatable {
    let row: ShoppingRowPresentation
    let locked: Bool
    let toggle: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.row == rhs.row && lhs.locked == rhs.locked }
    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top) {
                Image(systemName: row.isChecked ? "checkmark.circle.fill" : "circle").font(AppFont.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).strikethrough(row.isChecked).foregroundStyle(AppTheme.productName).font(AppFont.body.weight(.medium))
                    Text("\(row.quantity.formatted())\(row.unit.label)").foregroundStyle(AppTheme.secondary)
                    if let title = row.sourceRecipeTitle { Text(title).font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
                    if row.needsConfirmation {
                        Label("量・単位を確認", systemImage: "exclamationmark.circle")
                            .font(AppFont.caption).foregroundStyle(AppTheme.warning)
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(locked)
            .accessibilityIdentifier("shopping-row-\(row.name)")
            .accessibilityValue(row.isChecked ? "購入済み" : "未購入")
            .swipeActions {
                Button("数量を編集", action: edit).tint(AppTheme.accent).disabled(locked || row.isSaving)
                Button("削除", role: .destructive, action: remove).disabled(locked || row.isSaving)
            }
    }
}

struct ManualShoppingView: View {
    var item: ShoppingListItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @State private var showMasterPicker = false
    @State private var selectedMasterID: UUID?
    private var candidates: [IngredientMaster] { IngredientNameResolver.candidates(name, masters: masters) }
    private var effectiveMaster: IngredientMaster? {
        candidates.count == 1 ? candidates.first : candidates.first { $0.id == selectedMasterID }
    }
    @State private var name = ""
    @State private var quantity = 1.0
    @State private var unit: IngredientUnit = .piece
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if item == nil {
                    Section("食材") {
                        Button { showMasterPicker = true } label: {
                            HStack {
                                Label(effectiveMaster?.canonicalName ?? "食材を選ぶ", systemImage: "magnifyingglass")
                                Spacer()
                                if effectiveMaster != nil { Text("変更").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("shopping-master-picker")
                    }
                }
                Section("自由入力") {
                    TextField("品名", text: $name).disabled(item != nil).accessibilityIdentifier("shopping-name")
                }
                if item == nil && candidates.count > 1 {
                    Section("どの食材ですか？") {
                        ForEach(candidates) { food in
                            Button { selectedMasterID = food.id; unit = food.defaultUnit } label: {
                                Label(food.canonicalName, systemImage: selectedMasterID == food.id ? "checkmark.circle.fill" : "circle")
                                    .frame(minHeight: 44)
                            }.accessibilityIdentifier("shopping-candidate-" + food.key)
                        }
                    }
                }
                TextField("数量", value: $quantity, format: .number).keyboardType(.decimalPad).accessibilityIdentifier("shopping-quantity")
                Picker("単位", selection: $unit) {
                    ForEach(effectiveMaster?.allowedUnits ?? IngredientUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }.navigationTitle("買うものを追加")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("追加") {
                            do {
                                let service = MealService(container: context.container)
                                if let item { try service.updateShopping(id: item.id, quantity: quantity, unit: unit) }
                                else { try service.saveManual(name: name, quantity: quantity, unit: unit, masterID: effectiveMaster?.id) }
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !quantity.isFinite || quantity <= 0
                            || (item == nil && candidates.count > 1 && effectiveMaster == nil))
                            .accessibilityIdentifier("shopping-manual-save")
                    }
                }
                .sheet(isPresented: $showMasterPicker) {
                    IngredientMappingPicker(title: "食材を選ぶ", isMapping: false) { master in
                        selectedMasterID = master.id; name = master.canonicalName; unit = master.defaultUnit
                    }
                }
                .onChange(of: name) { _, value in
                    if masters.first(where: { $0.id == selectedMasterID })?.canonicalName != value { selectedMasterID = nil }
                    if let master = effectiveMaster, !master.allowedUnits.contains(unit) { unit = master.defaultUnit }
                }
                .onAppear { if let item { name = item.name; quantity = item.quantity; unit = item.unit } }
                .alert("追加できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("閉じる", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }
}
struct PurchaseView: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    let rows: [ShoppingListItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @State private var drafts: [PurchaseDraft] = []
    @State private var commonDate = Date.now
    @State private var commonStorage: StorageMethod = .refrigerated
    @State private var dateOverrides = Set<UUID>()
    @State private var storageOverrides = Set<UUID>()
    @State private var expandedDetails = Set<UUID>()
    @State private var error: String?
    @State private var loaded = false
    @Environment(\.dynamicTypeSize) private var textSize
    @FocusState private var inputFocus: UUID?
    @ScaledMetric(relativeTo: .body) private var editingMargin: CGFloat = 180
    var body: some View {
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let mastersByID = Dictionary(uniqueKeysWithValues: masters.map { ($0.id, $0) })
        let seasoningIDs = Set(rows.filter { row in
            row.ingredientMasterID.flatMap { mastersByID[$0] }?.category == .seasoning
        }.map(\.id))
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    Section("共通設定") {
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(spacing: 8))
                        layout {
                            DatePicker("購入日", selection: $commonDate, displayedComponents: .date).labelsHidden()
                                .accessibilityLabel("共通の購入日").accessibilityIdentifier("purchase-common-date")
                            if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                            Picker("保存方法", selection: $commonStorage) {
                                ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.menu).labelsHidden().accessibilityLabel("共通の保存方法")
                                .accessibilityIdentifier("purchase-common-storage")
                        }
                        .font(AppFont.subheadline)
                    }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    ForEach(drafts.indices, id: \.self) { index in
                        if let row = rowsByID[drafts[index].id] {
                            purchaseSection(index, row: row, master: row.ingredientMasterID.flatMap { mastersByID[$0] })
                        }
                    }
                }.listSectionSpacing(.compact).scrollContentBackground(.hidden).background(AppTheme.background)
                    .contentMargins(.bottom, inputFocus == nil ? 0 : editingMargin, for: .scrollContent)
                    .onChange(of: inputFocus) { revealInput(using: scroll) }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in revealInput(using: scroll) }
            }
                .navigationTitle("購入品を確認").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        if inputFocus != nil {
                            HStack {
                                Spacer()
                                Button("入力を完了") { inputFocus = nil }.frame(minHeight: 44)
                                    .accessibilityIdentifier("purchase-keyboard-done")
                            }.padding(.horizontal)
                        } else {
                            Button {
                                do { try MealService(container: context.container, mergeDuplicates: mergeInventory).purchase(drafts); dismiss() }
                                catch { self.error = error.localizedDescription }
                            } label: { Text("\(drafts.count)品を登録").frame(maxWidth: .infinity) }
                                .buttonStyle(CoralPrimaryButtonStyle())
                                .disabled(drafts.isEmpty || drafts.contains { draft in
                                    !seasoningIDs.contains(draft.id)
                                        && (!draft.quantity.isFinite || draft.quantity <= 0)
                                })
                                .padding().background(AppTheme.background)
                                .accessibilityLabel("購入した\(drafts.count)品を登録").accessibilityIdentifier("purchase-save")
                        }
                    }.background(AppTheme.background)
                }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    drafts = rows.map { row in
                        PurchaseDraft(id: row.id, quantity: row.quantity, unit: row.unit,
                            storage: row.ingredientMasterID.flatMap { mastersByID[$0] }?.defaultStorage ?? .refrigerated,
                            purchasedAt: commonDate, addToInventory: row.ingredientMasterID != nil)
                    }
                }
                .onChange(of: commonDate) { _, value in
                    for index in drafts.indices where !dateOverrides.contains(drafts[index].id) { drafts[index].purchasedAt = value }
                }
                .onChange(of: commonStorage) { _, value in
                    for index in drafts.indices where !storageOverrides.contains(drafts[index].id) { drafts[index].storage = value }
                }
                .alert("登録できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("閉じる", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }
    private func purchaseSection(_ index: Int, row: ShoppingListItem, master: IngredientMaster?) -> some View {
        let draft = drafts[index]
        let units = master?.allowedUnits ?? IngredientUnit.allCases
        return Section {
            if master?.category == .seasoning {
                Picker("購入後の在庫", selection: $drafts[index].seasoningState) {
                    Text("あり").tag(RoughStockState.available)
                    Text("少なめ").tag(RoughStockState.low)
                    Text("なし").tag(RoughStockState.unavailable)
                }.modifier(PurchaseStatePickerStyle(large: textSize.isAccessibilitySize))
                    .accessibilityIdentifier("purchase-state-" + row.name)
            } else {
                HStack(spacing: 10) {
                    TextField("購入量", value: $drafts[index].quantity, format: .number).id(draft.id).focused($inputFocus, equals: draft.id)
                        .keyboardType(.decimalPad).accessibilityLabel("購入量")
                        .accessibilityIdentifier("purchase-quantity-" + row.name)
                        .textFieldStyle(.roundedBorder).frame(minWidth: 64, maxWidth: .infinity, minHeight: 44)
                    Picker("単位", selection: $drafts[index].unit) {
                        ForEach(units, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(row.name + "の単位").accessibilityIdentifier("purchase-unit-" + row.name)
                }
                if row.needsConfirmation { Label("量を確認", systemImage: "exclamationmark.circle").font(AppFont.caption).foregroundStyle(AppTheme.warning) }
            }
            Button {
                if expandedDetails.contains(draft.id) { expandedDetails.remove(draft.id) }
                else { expandedDetails.insert(draft.id) }
            } label: {
                HStack {
                    Text("保存・期限")
                    Spacer()
                    Image(systemName: expandedDetails.contains(draft.id) ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).font(AppFont.subheadline).accessibilityIdentifier("purchase-details-" + row.name)
                .accessibilityValue(expandedDetails.contains(draft.id) ? "開いています" : "閉じています")
            if expandedDetails.contains(draft.id) {
                Group {
                    Picker("保存方法", selection: Binding(get: { drafts[index].storage }, set: {
                        storageOverrides.insert(draft.id); drafts[index].storage = $0
                    })) {
                        ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("purchase-storage-" + row.name)
                    DatePicker("購入日", selection: Binding(get: { drafts[index].purchasedAt }, set: {
                        dateOverrides.insert(draft.id); drafts[index].purchasedAt = $0
                    }), displayedComponents: .date).accessibilityIdentifier("purchase-date-" + row.name)
                    let expiryLayout = textSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 8))
                    expiryLayout {
                        Text("期限")
                        if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                        HStack(spacing: 4) {
                            PurchaseCompactExpiry(date: $drafts[index].expiresAt)
                                .accessibilityLabel(row.name + "の期限")
                                .accessibilityValue(drafts[index].expiresAt?.formatted(date: .numeric, time: .omitted) ?? "指定なし")
                                .accessibilityIdentifier("purchase-expiry-" + row.name)
                            Button {
                                drafts[index].expiresAt = nil; drafts[index].expiryKind = .unspecified
                            } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                                .buttonStyle(.plain).foregroundStyle(AppTheme.secondary)
                                .accessibilityLabel(row.name + "の期限を解除")
                                .accessibilityIdentifier("purchase-expiry-clear-" + row.name)
                                .opacity(drafts[index].expiresAt == nil ? 0 : 1)
                                .disabled(drafts[index].expiresAt == nil)
                                .accessibilityHidden(drafts[index].expiresAt == nil)
                        }
                    }
                    if drafts[index].expiresAt != nil {
                        Picker("期限の種類", selection: $drafts[index].expiryKind) {
                            ForEach([ExpiryKind.unspecified, .bestBefore, .useBy], id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                }.font(AppFont.subheadline)
            }
        } header: {
            HStack(spacing: 8) {
                Text(row.name).font(AppFont.headline).foregroundStyle(AppTheme.productName)
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                    .accessibilityIdentifier("purchase-name-" + row.name)
                Button { drafts[index].addToInventory.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: drafts[index].addToInventory ? "checkmark.square.fill" : "square")
                        if !textSize.isAccessibilitySize { Text("冷蔵庫に追加").font(AppFont.caption) }
                    }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(row.name + "を冷蔵庫に追加")
                    .accessibilityValue(drafts[index].addToInventory ? "オン" : "オフ")
                    .accessibilityIdentifier("purchase-inventory-" + row.name)
                Spacer(minLength: 0)
            }.textCase(nil)
        }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
    private func revealInput(using scroll: ScrollViewProxy) {
        guard let inputFocus else { return }
        withAnimation { scroll.scrollTo(inputFocus, anchor: .top) }
    }
}
private struct PurchaseStatePickerStyle: ViewModifier {
    let large: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if large { content.pickerStyle(.menu).frame(minHeight: 44) }
        else { content.pickerStyle(.segmented).frame(minHeight: 44) }
    }
}
/// An optional date uses the same compact field and calendar interaction as purchase dates.
private struct PurchaseCompactExpiry: View {
    @Binding var date: Date?
    @State private var showsCalendar = false
    var body: some View {
        Button {
            if date == nil { date = Calendar.current.startOfDay(for: .now) }
            showsCalendar = true
        } label: {
            Text(date?.formatted(date: .numeric, time: .omitted) ?? "指定なし")
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(.primary)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .popover(isPresented: $showsCalendar) {
                DatePicker("期限", selection: Binding(get: { date ?? .now }, set: {
                    date = Calendar.current.startOfDay(for: $0)
                }), displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden().padding(8).frame(width: 320)
                    .presentationCompactAdaptation(.popover)
            }
    }
}

struct CookingView: View {
    let meal: MealSelection
    let recipe: Recipe
    var onCompleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @State private var drafts: [CookingDraft] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var expandedKeys = Set<String>()
    @Environment(\.dynamicTypeSize) private var textSize
    @FocusState private var inputFocus: String?
    @ScaledMetric(relativeTo: .body) private var editingMargin: CGFloat = 180
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    Section {
                        Text(recipe.title).font(AppFont.headline)
                        Text(meal.isPrepared ? "作り置きなので、材料の在庫は変えません" : "変更する食材だけ編集")
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    }
                    if !meal.isPrepared {
                        Section("食材・調味料") { ForEach(drafts.indices, id: \.self) { index in cookingSection(index) } }
                    }
                }.scrollContentBackground(.hidden).background(AppTheme.background)
                    .contentMargins(.bottom, inputFocus == nil ? 0 : editingMargin, for: .scrollContent)
                    .onChange(of: inputFocus) { revealInput(using: scroll) }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in revealInput(using: scroll) }
            }
                .navigationTitle(meal.isPrepared ? "作り置きの完了" : "調理後の在庫").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        if inputFocus != nil {
                            HStack {
                                Spacer()
                                Button("入力を完了") { inputFocus = nil }.frame(minHeight: 44)
                                    .accessibilityIdentifier("cooking-keyboard-done")
                            }.padding(.horizontal)
                        } else {
                            Button {
                                do { try MealService(container: context.container).cook(mealID: meal.id, recipe: recipe, drafts: drafts); onCompleted(); dismiss() }
                                catch { self.error = error.localizedDescription }
                            } label: { Text(meal.isPrepared ? "完了" : "記録して完了").frame(maxWidth: .infinity) }
                                .buttonStyle(CoralPrimaryButtonStyle()).padding().background(AppTheme.background)
                                .disabled((!meal.isPrepared && drafts.isEmpty) || drafts.contains { !$0.quantity.isFinite || $0.quantity < 0 || $0.remainingAmounts.values.contains { !$0.quantity.isFinite || $0.quantity < 0 } })
                                .accessibilityLabel(meal.isPrepared ? "作り置きを完了・材料の在庫は変更なし" : "使用量を確定して在庫を更新").accessibilityIdentifier("cooking-save")
                            if !meal.isPrepared {
                                Button("在庫を変えずに完了") {
                                    do {
                                        try MealService(container: context.container).cook(mealID: meal.id, recipe: recipe,
                                            drafts: [], updateInventory: false); onCompleted(); dismiss()
                                    } catch { self.error = error.localizedDescription }
                                }.font(AppFont.subheadline).frame(minHeight: 44)
                                    .buttonStyle(.borderless).accessibilityIdentifier("cooking-skip-stock")
                            }
                        }
                    }.background(AppTheme.background)
                }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    guard !meal.isPrepared else { return }
                    drafts = recipe.ingredients.filter { $0.inventoryMode != "ignored" }.map { ingredient in
                        let lots = relevantLots(ingredient.ingredientKey)
                        if isSeasoning(ingredient) {
                            return CookingDraft(ingredientKey: ingredient.ingredientKey, quantity: 0,
                                seasoningStates: [:])
                        }
                        let rough = lots.filter { $0.stockMode == .rough }
                        let hasExact = lots.contains { ($0.quantity ?? 0) > 0 }
                        return CookingDraft(ingredientKey: ingredient.ingredientKey,
                            quantity: !rough.isEmpty && !hasExact ? 0 : ingredient.requirement == "optional" && lots.isEmpty ? 0
                                : ingredient.amount(servings: meal.servings, base: recipe.baseServings),
                            roughStates: [:])
                    }
                    for draft in drafts {
                        guard let ingredient = recipe.ingredients.first(where: { $0.ingredientKey == draft.ingredientKey }), !isSeasoning(ingredient) else { continue }
                        let lots = relevantLots(draft.ingredientKey)
                        if lots.allSatisfy({ $0.stockMode == .exact }),
                           CookingAmounts.available(lots: lots.map(StockLot.init), unit: ingredient.unit).map({ $0 < draft.quantity }) ?? true {
                            expandedKeys.insert(draft.ingredientKey)
                        }
                    }
                }
                .alert("使用量の確認が必要です", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("入力に戻る", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }
    private func revealInput(using scroll: ScrollViewProxy) {
        guard let inputFocus else { return }
        withAnimation { scroll.scrollTo(inputFocus, anchor: .top) }
    }
    private func relevantLots(_ key: String) -> [InventoryItem] {
        guard let id = masters.first(where: { $0.key == key })?.id else { return [] }
        return stock.filter { IngredientIdentity.masterID(for: $0, customs: customs, masters: masters) == id && InventoryService.usable($0, on: .now) }
    }
    private func isSeasoning(_ ingredient: RecipeIngredient) -> Bool {
        masters.first { $0.key == ingredient.ingredientKey }?.category == .seasoning || ingredient.inventoryMode == "presence"
    }
    private func state(of lot: InventoryItem) -> RoughStockState {
        lot.roughState ?? ((lot.quantity ?? 0) > 0 ? .available : .unavailable)
    }
    private func cookingSection(_ index: Int) -> some View {
        let draft = drafts[index]
        let ingredient = recipe.ingredients.first { $0.ingredientKey == draft.ingredientKey }!
        let lots = relevantLots(draft.ingredientKey)
        let available = CookingAmounts.available(lots: lots.map(StockLot.init), unit: ingredient.unit)
        let rough = lots.filter { $0.stockMode == .rough }
        let hasExact = lots.contains { $0.stockMode == .exact && ($0.quantity ?? 0) > 0 }
        let stateOnly = isSeasoning(ingredient)
        let usage = draft.inputMode == .used ? draft.quantity : (available ?? 0) - draft.quantity
        return DisclosureGroup(isExpanded: Binding(get: { expandedKeys.contains(draft.ingredientKey) }, set: { value in
            if value { expandedKeys.insert(draft.ingredientKey) } else { expandedKeys.remove(draft.ingredientKey); inputFocus = nil }
        })) {
            if stateOnly {
                if lots.isEmpty {
                    Label("在庫なし", systemImage: "refrigerator").foregroundStyle(AppTheme.secondary)
                } else {
                    ForEach(lots) { lot in
                        statePicker(title: lots.count == 1 ? "調理後" : lot.storage.label + "・" + amountLabel(lot),
                            selection: Binding(get: { drafts[index].seasoningStates[lot.id] ?? state(of: lot) },
                                set: { drafts[index].seasoningStates[lot.id] = $0 }),
                            identifier: "cooking-seasoning-" + draft.ingredientKey + "-" + lot.id.uuidString)
                    }
                }
            } else {
                if hasExact || rough.isEmpty {
                    let modeBinding = Binding(get: { drafts[index].inputMode }, set: { mode in
                        guard mode != drafts[index].inputMode else { return }
                        inputFocus = nil
                        if let available, drafts[index].quantity <= available {
                            drafts[index].quantity = max(0, available - drafts[index].quantity)
                        } else if mode == .remaining { drafts[index].quantity = available ?? 0 }
                        drafts[index].inputMode = mode
                    })
                    Group {
                        if textSize.isAccessibilitySize {
                            LabeledFilterMenu(title: "入力方法", selection: modeBinding, options: [.used, .remaining],
                                label: { $0 == .used ? "使った量" : "残りの量" })
                        } else {
                            Picker("入力方法", selection: modeBinding) {
                                Text("使った量").tag(CookingAmountMode.used)
                                Text("残りの量").tag(CookingAmountMode.remaining)
                            }.pickerStyle(.segmented)
                        }
                    }.accessibilityIdentifier("cooking-mode-" + draft.ingredientKey).disabled(available == nil)
                    HStack(spacing: 8) {
                        Text(draft.inputMode == .used ? "使った量" : "残りの量").font(AppFont.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("量", value: $drafts[index].quantity, format: .number)
                            .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                            .frame(minWidth: 56, maxWidth: 110, minHeight: 44)
                            .id(draft.ingredientKey).focused($inputFocus, equals: draft.ingredientKey)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel((draft.inputMode == .used ? "使った量" : "残りの量") + "（" + ingredient.unit.label + "）")
                            .accessibilityIdentifier("cooking-quantity-" + draft.ingredientKey)
                        Text(ingredient.unit.label).foregroundStyle(AppTheme.secondary)
                        Spacer(minLength: 0)
                    }
                    if let available {
                        Label("在庫 \(available.formatted())\(ingredient.unit.label) → 残り \(max(0, available - usage).formatted())\(ingredient.unit.label)", systemImage: "refrigerator")
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cooking-preview-" + draft.ingredientKey)
                        if usage < 0 || usage > available {
                            Label("在庫量を超えています", systemImage: "exclamationmark.circle")
                                .font(AppFont.caption).foregroundStyle(AppTheme.warning)
                        }
                    } else {
                        Text("量・単位を確認してください。").font(AppFont.caption).foregroundStyle(AppTheme.warning)
                    }
                }
                ForEach(rough) { lot in roughLotEditor(lot, index: index, ingredient: ingredient) }
            }
        } label: {
            Text(masters.first { $0.key == draft.ingredientKey }?.canonicalName ?? draft.ingredientKey)
                .font(AppFont.headline).foregroundStyle(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                .accessibilityIdentifier("cooking-expand-" + draft.ingredientKey)
        }
    }
    private func roughLotEditor(_ lot: InventoryItem, index: Int, ingredient: RecipeIngredient) -> some View {
        let key = ingredient.ingredientKey
        let units = masters.first { $0.key == key }?.allowedUnits ?? [ingredient.unit]
        return VStack(alignment: .leading, spacing: 8) {
            Text(lot.storage.label + "・" + lot.purchasedAt.formatted(.dateTime.month().day()))
                .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
            Toggle("残った量を記録", isOn: Binding(get: { drafts[index].remainingAmounts[lot.id] != nil }, set: { enabled in
                inputFocus = nil
                if enabled {
                    drafts[index].roughStates.removeValue(forKey: lot.id)
                    drafts[index].remainingAmounts[lot.id] = RemainingStockAmount(quantity: .nan,
                        unit: masters.first { $0.key == key }?.defaultUnit ?? ingredient.unit)
                } else { drafts[index].remainingAmounts.removeValue(forKey: lot.id) }
            })).accessibilityIdentifier("cooking-record-remaining-" + key)
            if let amount = drafts[index].remainingAmounts[lot.id] {
                HStack {
                    TextField("残りの量", text: Binding(get: {
                        let value = drafts[index].remainingAmounts[lot.id]?.quantity ?? .nan
                        return value.isFinite ? value.formatted(.number.grouping(.never)) : ""
                    }, set: { drafts[index].remainingAmounts[lot.id]?.quantity = Double($0) ?? .nan }))
                        .keyboardType(.decimalPad).focused($inputFocus, equals: "remaining-" + lot.id.uuidString)
                        .id("remaining-" + lot.id.uuidString).accessibilityIdentifier("cooking-observed-" + key)
                    Picker("単位", selection: Binding(get: { drafts[index].remainingAmounts[lot.id]?.unit ?? ingredient.unit },
                        set: { drafts[index].remainingAmounts[lot.id]?.unit = $0 })) {
                        ForEach(units, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("cooking-observed-unit-" + key)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { remainingShortcuts(index: index, lot: lot, unit: amount.unit) }
                    VStack(alignment: .leading) { remainingShortcuts(index: index, lot: lot, unit: amount.unit) }
                }
            } else {
                statePicker(title: "調理後", selection: Binding(get: { drafts[index].roughStates[lot.id] ?? state(of: lot) },
                    set: { drafts[index].roughStates[lot.id] = $0 }), identifier: "cooking-state-" + key + "-" + lot.id.uuidString)
            }
        }
    }
    @ViewBuilder private func remainingShortcuts(index: Int, lot: InventoryItem, unit: IngredientUnit) -> some View {
        Button("使い切った") { drafts[index].remainingAmounts[lot.id]?.quantity = 0 }
            .buttonStyle(.bordered).frame(minHeight: 44)
        if [.piece, .can, .block, .portion].contains(unit) {
            ForEach([0.5, 1.0], id: \.self) { value in
                Button((value == 0.5 ? "½" : "1") + unit.label) { drafts[index].remainingAmounts[lot.id]?.quantity = value }
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
    }
    private func statePicker(title: String, selection: Binding<RoughStockState>, identifier: String) -> some View {
        Group {
            if textSize.isAccessibilitySize {
                LabeledFilterMenu(title: title, selection: selection, options: [.available, .low, .unavailable], label: { $0.label })
            } else {
                Picker(title, selection: selection) {
                    ForEach([RoughStockState.available, .low, .unavailable], id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            }
        }.accessibilityIdentifier(identifier)
    }
}
