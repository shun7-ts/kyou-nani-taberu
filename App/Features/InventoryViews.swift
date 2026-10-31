import SwiftUI
import SwiftData
import UIKit

struct RefrigeratorView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @Query private var custom: [CustomIngredient]
    @Query private var allItems: [InventoryItem]
    @State private var search = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var storage: StorageMethod?
    @State private var category: IngredientCategory?
    @State private var group = "すべて"
    @State private var sort = "期限順"
    @State private var showReceipt = false
    @State private var showVoice = false
    @State private var showAdd = false
    @State private var showBulk = false
    @State private var editing: InventoryItem?
    @State private var removalError: String?
    private func master(_ item: InventoryItem) -> IngredientMaster? {
        masters.first { $0.id == item.ingredientMasterID }
    }
    private func name(_ item: InventoryItem) -> String {
        master(item)?.canonicalName ?? custom.first { $0.id == item.customIngredientID }?.name ?? "未対応の食材"
    }
    private func ingredientCategory(_ item: InventoryItem) -> IngredientCategory {
        master(item)?.category ?? custom.first { $0.id == item.customIngredientID }?.category ?? .other
    }
    private var items: [InventoryItem] {
        allItems.filter {
            !$0.isDeleted && (group == "すべて" || (group == "調味料" ? ingredientCategory($0) == .seasoning : ingredientCategory($0) != .seasoning)) && (storage == nil || $0.storage == storage)
            && (category == nil || ingredientCategory($0) == category)
            && IngredientSearch.matches(search, names: [name($0)] + (master($0)?.aliases ?? []))
        }.sorted {
            switch sort {
            case "名前順": return name($0).localizedStandardCompare(name($1)) == .orderedAscending
            case "種類順": return ingredientCategory($0).rawValue < ingredientCategory($1).rawValue
            case "登録順": return $0.createdAt > $1.createdAt
            default: return ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            }
        }
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: geometry.size.height < 230 ? 4 : 8) {
                    if showSearch { searchField }
                    if geometry.size.height >= 230 {
                        registrationArea(compact: typeSize.isAccessibilitySize && geometry.size.height < 350)
                    }
                    refrigeratorFrame(compact: geometry.size.height < 300)
                }.padding(.horizontal, 16).padding(.vertical, geometry.size.height < 230 ? 4 : 8)
            }.background(AppTheme.background)
            .modifier(PageHeading(title: "マイ冷蔵庫", icon: "refrigerator"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { FlatToolbarIcon(systemName: "plus") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("食材を追加").accessibilityIdentifier("inventory-add")
                    Button {
                        showSearch.toggle()
                        if !showSearch { search = ""; searchFocused = false }
                    } label: { FlatToolbarIcon(systemName: showSearch ? "xmark" : "magnifyingglass") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showSearch ? "検索を閉じる" : "食材を検索")
                        .accessibilityIdentifier("inventory-search-toggle")
                    sortMenu
                }.flatToolbarBackground()
            }
            .onChange(of: group) { category = nil }
            .sheet(isPresented: $showVoice) { VoiceInputView() }
            .sheet(isPresented: $showReceipt) { ReceiptImportView() }
            .sheet(isPresented: $showAdd) { InventoryEditorView() }
            .sheet(isPresented: $showBulk) { BulkInventoryView() }
            .sheet(item: $editing) { InventoryEditorView(item: $0) }
            .alert("取り除けませんでした", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(removalError ?? "") }
        }
    }
    private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(AppTheme.secondary).accessibilityHidden(true)
                TextField(typeSize.isAccessibilitySize ? "検索" : "食材を探す", text: $search)
                    .font(AppFont.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityLabel("食材を探す").accessibilityIdentifier("inventory-search")
                    .frame(minWidth: 60, minHeight: 44)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle").font(.system(size: 18)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("検索をクリア").accessibilityIdentifier("inventory-list-search-clear")
                }
            }.padding(.leading, 12).padding(.trailing, search.isEmpty ? 12 : 0)
                .frame(minHeight: 44).foregroundStyle(AppTheme.text)
                .contentShape(Rectangle()).onTapGesture { searchFocused = true }
                .accessibilityElement(children: .contain).accessibilityIdentifier("inventory-search-container")
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 1).allowsHitTesting(false) }
                .onAppear { searchFocused = true }
                .fixedSize(horizontal: false, vertical: true)
    }
    private var sortMenu: some View {
        Menu {
            Picker("並び順", selection: $sort) {
                ForEach(["期限順", "種類順", "名前順", "登録順"], id: \.self) { Text($0).tag($0) }
            }
        } label: {
            FlatToolbarIcon(systemName: "line.3.horizontal.decrease")
        }.buttonStyle(.plain).accessibilityLabel("並べ替え").accessibilityValue(sort).accessibilityIdentifier("inventory-sort")
    }

    private func refrigeratorFrame(compact: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                stockListHeader(compact: compact)
                if !compact && group != "調味料" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            categoryButton("すべて", selected: category == nil) { category = nil }
                                .accessibilityIdentifier("inventory-tag-all")
                            ForEach([IngredientCategory.vegetable, .eggDairy, .meat, .fish, .soyProduct, .staple, .mushroom, .processed, .other], id: \.self) { tag in
                                categoryButton(tag.label, selected: category == tag) { category = category == tag ? nil : tag }
                                    .accessibilityIdentifier("inventory-tag-" + tag.rawValue)
                            }
                        }
                    }
                }
            }.padding(.leading, 30).padding(.trailing, 12).padding(.vertical, compact ? 4 : 8)
                .overlay(alignment: .leading) { doorHandle.padding(.leading, 10) }
            Rectangle().fill(AppTheme.illustration).frame(height: 1.3).accessibilityHidden(true)
            stockList
                .overlay(alignment: .topLeading) { doorHandle.padding(.leading, 10).padding(.top, 18) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(AppTheme.illustration, lineWidth: 1.4).allowsHitTesting(false).accessibilityHidden(true) }
            .background { AppCardSurface(cornerRadius: 24, shadow: .refrigerator) }
    }
    private var doorHandle: some View {
        RoundedRectangle(cornerRadius: 4).strokeBorder(AppTheme.illustration, lineWidth: 1.3)
            .frame(width: 8, height: 42).allowsHitTesting(false).accessibilityHidden(true)
    }
    private var stockList: some View {
        List {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(search.isEmpty ? "食材を追加しましょう" : "一致する食材がありません")
                        .font(AppFont.headline).foregroundStyle(AppTheme.text).fixedSize(horizontal: false, vertical: true)
                    Button("まとめて登録") { showBulk = true }.frame(minHeight: 44)
                    Button("手入力で登録") { showAdd = true }.frame(minHeight: 44)
                }.listRowSeparator(.hidden).listRowBackground(AppTheme.surface)
                    .listRowInsets(EdgeInsets(top: 6, leading: 30, bottom: 6, trailing: 12))
            } else {
                ForEach([false, true], id: \.self) { seasonings in
                    let rows = items.filter { (ingredientCategory($0) == .seasoning) == seasonings }
                    if !rows.isEmpty {
                        if group == "すべて" {
                            Text((seasonings ? "調味料" : "食材") + "・\(rows.count)")
                                .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppTheme.secondary)
                                .listRowSeparator(.hidden).listRowBackground(AppTheme.surface)
                                .listRowInsets(EdgeInsets(top: 4, leading: 30, bottom: 4, trailing: 12))
                        }
                        ForEach(rows) { item in
                            Button { editing = item } label: {
                                HStack(spacing: 8) {
                                    if typeSize.isAccessibilitySize {
                                        VStack(alignment: .leading, spacing: 6) {
                                            stockIdentity(item)
                                            stockAmount(item, alignment: .leading)
                                        }
                                    } else {
                                        stockIdentity(item)
                                        Spacer(minLength: 8)
                                        stockAmount(item, alignment: .trailing)
                                    }
                                    Image(systemName: "chevron.right").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                                        .accessibilityHidden(true)
                                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("inventory-row-\(master(item)?.key ?? "custom")")
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        do { try InventoryService(container: context.container).discard(id: item.id) }
                                        catch { removalError = error.localizedDescription }
                                    } label: { Label("取り除く", systemImage: "trash") }
                                        .accessibilityIdentifier("inventory-remove-" + item.id.uuidString)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 30, bottom: 6, trailing: 12))
                                .listRowBackground(AppTheme.surface)
                        }
                    }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(AppTheme.surface)
            .listRowBackground(AppTheme.surface)
            .listRowInsets(EdgeInsets(top: 6, leading: 30, bottom: 6, trailing: 12))
            .listRowSeparatorTint(AppTheme.border)
            .accessibilityIdentifier("inventory-scroll-list")
    }
    private func stockListHeader(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text(group == "調味料" ? "調味料" : "食材").font(compact ? AppFont.caption : AppFont.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(items.count)").font((compact ? AppFont.caption : AppFont.headline).weight(.semibold))
                .accessibilityIdentifier("inventory-visible-count")
            Spacer(minLength: 4)
            Menu {
                Picker("表示", selection: $group) {
                    ForEach(["すべて", "食材", "調味料"], id: \.self) { Text($0).tag($0) }
                }
                if compact {
                    Picker("種類", selection: $category) {
                        Text("すべての種類").tag(IngredientCategory?.none)
                        ForEach(IngredientCategory.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                }
            } label: { compactFilterLabel(group, symbol: "line.3.horizontal.decrease") }
                .accessibilityLabel("表示").accessibilityValue(group).accessibilityIdentifier("inventory-group")
            Menu {
                Picker("保存方法", selection: $storage) {
                    Text("すべて").tag(StorageMethod?.none)
                    ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            } label: { compactFilterLabel(storage?.label ?? "保存方法", symbol: "refrigerator") }
                .accessibilityLabel("保存方法").accessibilityValue(storage?.label ?? "すべて").accessibilityIdentifier("inventory-storage")
        }.foregroundStyle(AppTheme.text).buttonStyle(.plain)
    }
    private func compactFilterLabel(_ title: String, symbol: String) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
            } else {
                HStack(spacing: 4) {
                    Text(title).font(AppFont.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down").font(AppFont.caption2).accessibilityHidden(true)
                }.padding(.horizontal, 8).frame(minHeight: 44)
            }
        }.foregroundStyle(AppTheme.accent).background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }
    private func categoryButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(AppFont.caption.weight(selected ? .semibold : .medium)).fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 44)
                .foregroundStyle(selected ? AppTheme.accent : AppTheme.text)
                .background(selected ? AppTheme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private func registrationArea(compact: Bool) -> some View {
        if compact {
            Menu {
                Button("音声", systemImage: "mic") { showVoice = true }.accessibilityIdentifier("inventory-voice")
                Button("レシート", systemImage: "receipt") { showReceipt = true }.accessibilityIdentifier("inventory-receipt")
                Button("まとめて", systemImage: "checklist") { showBulk = true }.accessibilityIdentifier("inventory-bulk")
            } label: {
                Label("食材の追加", systemImage: "plus.circle").font(AppFont.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityIdentifier("inventory-registration-menu").buttonStyle(.plain).foregroundStyle(AppTheme.accent)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if !typeSize.isAccessibilitySize { Text("食材の追加").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
                HStack(spacing: 4) {
                    registrationButton("音声", icon: "mic", id: "inventory-voice") { showVoice = true }
                    Divider().frame(height: 24).accessibilityHidden(true)
                    registrationButton("レシート", icon: "receipt", id: "inventory-receipt") { showReceipt = true }
                    Divider().frame(height: 24).accessibilityHidden(true)
                    registrationButton("まとめて", icon: "checklist", id: "inventory-bulk") { showBulk = true }
                }.padding(.horizontal, 8).padding(.vertical, 2)
                    .background { AppCardSurface(cornerRadius: 14, shadow: .registration) }
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.border, lineWidth: 1).allowsHitTesting(false) }
            }
        }
    }
    private func registrationButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: typeSize.isAccessibilitySize ? 24 : 20))
                    .foregroundStyle(AppTheme.illustration).accessibilityHidden(true)
                if !typeSize.isAccessibilitySize {
                    Text(title).font(AppFont.caption.weight(.medium)).foregroundStyle(AppTheme.text)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityHint("食材を追加します").accessibilityIdentifier(id)
    }
    private func stockIdentity(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                IngredientCategoryIcon(category: ingredientCategory(item))
                Text(name(item)).font(AppFont.headline).foregroundStyle(AppTheme.text)
            }
            Text(item.storage.label + "・" + ingredientCategory(item).label).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func stockAmount(_ item: InventoryItem, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(amountLabel(item)).foregroundStyle(AppTheme.text)
            Text(expiryLabel(item)).font(AppFont.caption)
                .foregroundStyle(item.expiresAt == nil ? AppTheme.secondary : (InventoryService.usable(item, on: .now) ? AppTheme.warning : AppTheme.danger))
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct BulkInventoryView: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @State private var presets: InventoryPresets?
    @State private var mode = "seasonings"
    @State private var search = ""
    @State private var selected = Set<String>()
    @State private var expanded = false
    @State private var error: String?
    @State private var completion: String?
    @State private var showCustom = false
    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("家にあるものを選ぶだけ。数量や期限は後から直せます。")
                        .font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                    Picker("食材の種類", selection: $mode) {
                        Text("調味料").tag("seasonings"); Text("よくある食材").tag("foods")
                    }.pickerStyle(.segmented)
                }
                if search.isEmpty {
                    if let presets {
                        ForEach(presets.sections.filter { $0.mode == mode }) { section in
                            Section {
                                if section.collapsedByDefault {
                                    DisclosureGroup(section.title, isExpanded: $expanded) {
                                        ForEach(section.items) { selectionRow(key: $0.ingredientKey, label: $0.label) }
                                    }
                                } else {
                                    if section.groupSelectionEnabled {
                                        let keys = Set(section.items.map(\.ingredientKey))
                                        Button(selected.isSuperset(of: keys) ? "まとめて解除" : "基本の調味料をまとめて選択") {
                                            if selected.isSuperset(of: keys) { selected.subtract(keys) }
                                            else { selected.formUnion(keys) }
                                        }.frame(minHeight: 44)
                                    }
                                    ForEach(section.items) { selectionRow(key: $0.ingredientKey, label: $0.label) }
                                }
                            } header: { if !section.collapsedByDefault { Text(section.title) } }
                        }
                    }
                } else {
                    Section("検索結果") {
                        ForEach(masters.filter { $0.trackInventory && $0.status == .active &&
                            IngredientSearch.matches(search, names: [$0.canonicalName] + $0.aliases) }.sorted { $0.canonicalName < $1.canonicalName }) {
                            selectionRow(key: $0.key, label: $0.canonicalName)
                        }
                    }
                }
                Section { Button("カスタム食材を追加") { showCustom = true } }
                if let completion { Section { Text(completion).foregroundStyle(AppTheme.accent) } }
            }
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .navigationTitle("家にあるもの")
            .searchable(text: $search, prompt: "食材・調味料を探す")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("あとで") { onComplete?(); dismiss() }.accessibilityIdentifier("bulk-skip")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    do {
                        let count = try InventoryService(container: context.container, mergeDuplicates: mergeInventory).bulkRegister(keys: selected)
                        completion = "\(count)品を登録しました。登録済みの在庫はそのまま保持しました。"
                        selected.removeAll()
                        onComplete?()
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                } label: {
                    Text("選んだ\(selected.count)品を冷蔵庫へ追加").frame(maxWidth: .infinity)
                }.buttonStyle(CoralPrimaryButtonStyle()).disabled(selected.isEmpty)
                    .accessibilityIdentifier("bulk-save").padding().background(AppTheme.background)
            }
            .task {
                do { presets = try InventoryPresets.load() }
                catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: $showCustom) { InventoryEditorView(customOnly: true) }
            .alert("登録できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func selectionRow(key: String, label: String) -> some View {
        Button {
            if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
        } label: {
            HStack {
                Text(label).foregroundStyle(AppTheme.text)
                Spacer()
                Image(systemName: selected.contains(key) ? "checkmark.circle.fill" : "circle")
            }.frame(minHeight: 44)
        }.accessibilityLabel(label).accessibilityValue(selected.contains(key) ? "選択済み" : "未選択")
            .accessibilityIdentifier("bulk-item-\(key)")
    }
}

struct InventoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @Query private var customs: [CustomIngredient]
    @Query private var inventory: [InventoryItem]
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    var item: InventoryItem?
    var customOnly = false
    @State private var masterID: UUID?
    @State private var customMode = false
    @State private var ingredientSearch = ""
    @State private var showMasterPicker = false
    @State private var customName = ""
    @State private var mappedMasterID: UUID?
    @State private var showMapping = false
    @State private var exact = false
    @State private var quantity = "1"
    @State private var unit: IngredientUnit = .piece
    @State private var rough: RoughStockState = .available
    @State private var storage: StorageMethod = .refrigerated
    @State private var purchasedAt = Date.now
    @State private var hasExpiry = false
    @State private var expiresAt = Date.now
    @State private var expiryKind: ExpiryKind = .unspecified
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var loaded = false
    @Environment(\.dynamicTypeSize) private var textSize
    private enum InputField: Hashable { case name, quantity, search }
    @FocusState private var inputFocus: InputField?
    @ScaledMetric(relativeTo: .body) private var editingMargin: CGFloat = 180
    private var searchableFoods: [IngredientMaster] {
        masters.filter { $0.trackInventory && $0.status == .active
            && IngredientSearch.matches(ingredientSearch, names: [$0.canonicalName] + $0.aliases) }
            .sorted { $0.canonicalName.localizedStandardCompare($1.canonicalName) == .orderedAscending }
    }
    private var selected: IngredientMaster? { masters.first { $0.id == masterID } }
    private var allowedUnits: [IngredientUnit] { customMode ? IngredientUnit.allCases : selected?.allowedUnits ?? IngredientUnit.allCases }
    private var title: String {
        if let item {
            return masters.first { $0.id == item.ingredientMasterID }?.canonicalName
                ?? customs.first { $0.id == item.customIngredientID }?.name ?? "食材の編集"
        }
        return "食材を追加"
    }
    private var valid: Bool {
        let identityOK = item != nil || (customMode ? !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selected != nil)
        let value = Double(quantity)
        return identityOK && (!exact || (value != nil && value!.isFinite && value! >= 0))
    }
    private var mergePreview: String? {
        guard item == nil, mergeInventory, !customMode, let masterID else { return nil }
        let amount: StockAmount = exact ? .exact(Double(quantity) ?? -.infinity, unit) : .rough(rough)
        guard let target = inventory.filter({
            InventoryAddition.canMerge(reference: .master(masterID), amount: amount, storage: storage,
                expiresAt: hasExpiry ? expiresAt : nil, expiryKind: hasExpiry ? expiryKind : .unspecified, item: $0)
        }).min(by: InventoryAddition.precedes) else { return nil }
        if exact, let oldUnit = target.unit, let added = Units.convert(Double(quantity) ?? 0, from: unit, to: oldUnit) {
            return "現在 \((target.quantity ?? 0).formatted())\(oldUnit.label) ＋ 追加 \(added.formatted())\(oldUnit.label) → \(((target.quantity ?? 0) + added).formatted())\(oldUnit.label)"
        }
        return "同じ条件の在庫にまとめます"
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    if item == nil { identitySection }
                    if customMode { mappingSection }
                    amountSection
                    Section("保存・日付") {
                        Picker("保存方法", selection: $storage) {
                            ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        DatePicker("購入日", selection: $purchasedAt, displayedComponents: .date)
                        Toggle("期限を登録する", isOn: $hasExpiry)
                        if hasExpiry {
                            DatePicker("期限", selection: $expiresAt, displayedComponents: .date)
                            Picker("期限の種類", selection: $expiryKind) {
                                ForEach([ExpiryKind.unspecified, .bestBefore, .useBy], id: \.self) { Text($0.label).tag($0) }
                            }
                        }
                    }
                    if item != nil {
                        Section("在庫の操作") {
                            Button("廃棄・一覧から取り除く", role: .destructive) { confirmDiscard = true }
                        }
                    }
                }.scrollContentBackground(.hidden).background(AppTheme.background)
                    .contentMargins(.bottom, inputFocus == nil ? 0 : editingMargin, for: .scrollContent)
                    .onChange(of: inputFocus) { revealInput(using: scroll) }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in revealInput(using: scroll) }
            }
            .safeAreaInset(edge: .bottom) {
                if inputFocus != nil {
                    HStack {
                        Spacer()
                        Button("入力を完了") { inputFocus = nil }.frame(minHeight: 44)
                            .accessibilityIdentifier("inventory-keyboard-done")
                    }.padding(.horizontal).background(AppTheme.background)
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!valid).accessibilityIdentifier("inventory-save")
                }
            }
            .onAppear { populate() }
            .sheet(isPresented: $showMasterPicker) {
                IngredientMappingPicker(title: "食材を選ぶ", isMapping: false) { master in
                    masterID = master.id; inputFocus = nil
                }
            }
            .sheet(isPresented: $showMapping) {
                IngredientMappingPicker { master in mappedMasterID = master.id }
            }
            .onChange(of: masterID) { _, _ in
                if item == nil, let selected {
                    unit = selected.defaultUnit; storage = selected.defaultStorage; exact = selected.stockMode == .exact
                }
            }
            .onChange(of: customMode) { _, value in
                if !value, let selected, !selected.allowedUnits.contains(unit) { unit = selected.defaultUnit }
            }
            .confirmationDialog("この在庫を取り除きますか？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("取り除く", role: .destructive) {
                    do {
                        if let item { try InventoryService(container: context.container).discard(id: item.id) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private var identitySection: some View {
        Section(customMode ? "カスタム食材" : "食材") {
            if customMode {
                TextField("食材名", text: $customName).id(InputField.name).focused($inputFocus, equals: .name)
                    .accessibilityLabel("食材名").accessibilityIdentifier("inventory-custom-name")
            } else if let selected {
                HStack {
                    Label { Text(selected.canonicalName) } icon: { IngredientCategoryIcon(category: selected.category) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("inventory-selected-ingredient")
                    Spacer()
                    Button("変更") { masterID = nil; inputFocus = .search }
                        .font(AppFont.caption).frame(minHeight: 44).buttonStyle(.borderless)
                        .accessibilityIdentifier("inventory-change-ingredient")
                }
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondary)
                    TextField("食材を検索", text: $ingredientSearch)
                        .id(InputField.search).focused($inputFocus, equals: .search)
                        .submitLabel(.search).onSubmit { inputFocus = nil }
                        .accessibilityLabel("食材を検索").accessibilityIdentifier("inventory-ingredient-search")
                    if !ingredientSearch.isEmpty {
                        Button { ingredientSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(AppTheme.secondary).frame(minWidth: 44, minHeight: 44)
                            .buttonStyle(.borderless).accessibilityLabel("検索を消す").accessibilityIdentifier("inventory-search-clear")
                    }
                }.frame(minHeight: 44)
                if !ingredientSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if searchableFoods.isEmpty {
                        Text("見つかりませんでした").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    }
                    ForEach(searchableFoods) { food in
                        Button { masterID = food.id; inputFocus = nil } label: {
                            let layout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout(spacing: 8))
                            layout {
                                Label { Text(food.canonicalName) } icon: { IngredientCategoryIcon(category: food.category) }
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(food.category.label).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.accessibilityIdentifier("inventory-search-food-" + food.key)
                    }
                } else {
                    Button("一覧から選ぶ") { inputFocus = nil; showMasterPicker = true }
                        .font(AppFont.caption).frame(minHeight: 44).accessibilityIdentifier("inventory-master-picker")
                }
            }
            if !customOnly {
                Button {
                    inputFocus = nil
                    if !customMode && customName.isEmpty { customName = ingredientSearch.trimmingCharacters(in: .whitespacesAndNewlines) }
                    customMode.toggle()
                } label: {
                    Label(customMode ? "食材検索に戻る" : "カスタム食材", systemImage: customMode ? "magnifyingglass" : "plus")
                        .font(AppFont.caption).foregroundStyle(AppTheme.secondary).frame(minHeight: 44)
                }.accessibilityIdentifier("inventory-custom-mode")
            }
        }
    }
    private var mappingSection: some View {
        Section("献立に使う食材") {
            Button { showMapping = true } label: {
                Label(masters.first { $0.id == mappedMasterID }?.canonicalName ?? "対応する食材を選ぶ", systemImage: "link")
                    .frame(minHeight: 44)
            }.accessibilityIdentifier("custom-mapping-picker")
            if mappedMasterID != nil {
                Button("対応付けを解除") { mappedMasterID = nil }.font(AppFont.caption).frame(minHeight: 44)
            }
            Text("同じ食材を選ぶと献立に使えます。名前はそのままです。")
                .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
        }
    }
    private var amountSection: some View {
        Section(item == nil ? "追加する量" : "在庫量") {
            Toggle("数量で管理する", isOn: $exact).accessibilityIdentifier("inventory-exact-toggle")
            if exact {
                TextField("数量", text: $quantity).id(InputField.quantity).focused($inputFocus, equals: .quantity)
                    .keyboardType(.decimalPad).accessibilityLabel("数量")
                    .accessibilityIdentifier("inventory-quantity")
                if textSize.isAccessibilitySize {
                    LabeledFilterMenu(title: "単位", selection: $unit, options: allowedUnits, label: { $0.label })
                        .accessibilityIdentifier("inventory-unit")
                } else {
                    Picker("単位", selection: $unit) {
                        ForEach(allowedUnits, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("inventory-unit")
                }
            } else {
                if textSize.isAccessibilitySize {
                    LabeledFilterMenu(title: "状態", selection: $rough,
                        options: [.available, .low, .unavailable], label: { $0.label })
                } else {
                    Picker("状態", selection: $rough) {
                        ForEach([RoughStockState.available, .low, .unavailable], id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if let selected, [.piece, .can, .block, .portion].contains(selected.defaultUnit) {
                    HStack {
                        Text("数量も記録").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                        ForEach([1, 2], id: \.self) { count in
                            Button("\(count)\(selected.defaultUnit.label)") {
                                quantity = String(count); unit = selected.defaultUnit; exact = true
                            }.buttonStyle(.bordered).frame(minHeight: 44)
                        }
                    }
                }
            }
            if let mergePreview {
                Text(mergePreview).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    .accessibilityIdentifier("inventory-merge-preview")
            }
        }
    }
    private func revealInput(using scroll: ScrollViewProxy) {
        guard let inputFocus else { return }
        withAnimation { scroll.scrollTo(inputFocus, anchor: .top) }
    }
    private func populate() {
        guard !loaded else { return }; loaded = true
        customMode = customOnly
        guard let item else { return }
        masterID = item.ingredientMasterID
        customMode = item.customIngredientID != nil
        mappedMasterID = customs.first { $0.id == item.customIngredientID }?.mappedIngredientMasterID
        exact = item.stockMode == .exact
        quantity = String(item.quantity ?? 1)
        unit = item.unit ?? selected?.defaultUnit ?? .piece
        rough = item.roughState ?? .available
        storage = item.storage; purchasedAt = item.purchasedAt
        hasExpiry = item.expiresAt != nil; expiresAt = item.expiresAt ?? .now; expiryKind = item.expiryKind
    }
    private func save() {
        do {
            let amount: StockAmount = exact ? .exact(Double(quantity) ?? -.infinity, unit) : .rough(rough)
            let draft = InventoryDraft(masterID: customMode ? nil : masterID, customName: customName, mappedMasterID: mappedMasterID, updatesMapping: customMode,
                amount: amount, storage: storage, purchasedAt: purchasedAt,
                expiresAt: hasExpiry ? expiresAt : nil, expiryKind: hasExpiry ? expiryKind : .unspecified)
            try InventoryService(container: context.container, mergeDuplicates: mergeInventory).save(draft, editingID: item?.id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

}


struct IngredientMappingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var masters: [IngredientMaster]
    @State private var search = ""
    var title = "献立に使う食材"
    var isMapping = true
    let onSelect: (IngredientMaster) -> Void
    private var foods: [IngredientMaster] {
        masters.filter { $0.trackInventory && $0.status == .active
            && IngredientSearch.matches(search, names: [$0.canonicalName] + $0.aliases) }
            .sorted { $0.canonicalName < $1.canonicalName }
    }
    var body: some View {
        NavigationStack {
            List {
                if isMapping {
                    Section {
                        Text("同じ食材を選んでください。加工済みの料理は、原材料に対応付けずそのまま登録できます。")
                            .font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                    }
                }
                ForEach(foods) { food in
                    Button { onSelect(food); dismiss() } label: {
                        Label { Text(food.canonicalName) } icon: { IngredientCategoryIcon(category: food.category) }.frame(minHeight: 44)
                    }.accessibilityIdentifier("mapping-food-" + food.key)
                }
            }.searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "食材名・別名を探す")
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        }
    }
}
