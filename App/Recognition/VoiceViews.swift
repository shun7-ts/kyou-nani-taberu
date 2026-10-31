import SwiftUI
import SwiftData

struct VoicePrivacyView: View {
    @AppStorage("voiceConsentVersion") private var version = 0
    @AppStorage("voiceConsentDate") private var acceptedAt = 0.0
    static let currentVersion = 1
    var body: some View {
        Form {
            VoicePrivacyText()
            Section("利用への同意") {
                if version == Self.currentVersion {
                    Text("同意済み（説明 v1）")
                    if acceptedAt > 0 { Text(Date(timeIntervalSince1970: acceptedAt), style: .date) }
                    Button("音声入力への同意を取り消す", role: .destructive) { version = 0; acceptedAt = 0 }
                } else {
                    Text("同意していません。手入力と在庫管理は引き続き利用できます。")
                    Button("説明に同意する") { acceptedAt = Date.now.timeIntervalSince1970; version = Self.currentVersion }
                }
            }
        }.navigationTitle("音声の扱い")
    }
}
private struct VoicePrivacyText: View {
    var body: some View {
        Section("音声の利用目的") {
            Text("冷蔵庫の食材をまとめて話して登録できます。購入・使用・残量の修正にも使えます。一覧を確認してから反映します。")
        }
        Section("音声とデータの扱い") {
            Text("日本語の端末内音声認識だけを使います。端末内認識が使えない場合は手入力で続けられます。アプリから外部の認識サービスへ音声を送信しません。")
            Text("マイクと音声認識のOS許可は、録音を開始するときに求めます。1回30秒まで。音声はメモリで扱い、録音ファイルを作りません。終了・中止・画面を閉じる・アプリを離れるとマイクを停止し、処理終了時に音声を解放します。")
            Text("認識した食材と量は保存前に確認・修正できます。閉じると未保存の文章と候補を破棄します。保存するのは確認した在庫情報と変更履歴だけで、発話全文は保存しません。")
            Text("同意しなくても文章の手入力が使えます。同意は設定から取り消せます。OSの許可はiPhoneの設定で変更できます。")
        }
    }
}

struct VoiceInputView: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var editingMargin: CGFloat = 120
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var masters: [IngredientMaster]
    @Query private var custom: [CustomIngredient]
    @Query private var inventory: [InventoryItem]
    @AppStorage("voiceConsentVersion") private var consent = 0
    @AppStorage("voiceConsentDate") private var acceptedAt = 0.0
    @StateObject private var recorder = VoiceRecorder()
    @State private var manualMode = false
    @State private var capturePrefix = ""
    @State private var captureActive = false
    @State private var appendedText = ""
    @State private var captureAfterReview = false
    @State private var foodRowID: UUID?
    @FocusState private var inputFocus: VoiceInputField?
    @State private var text = ""
    @State private var rows: [VoiceRow] = []
    @State private var sessionID = UUID()
    @State private var discard = false
    @State private var error: String?
    @State private var saving = false
    private var available: [IngredientMaster] { masters.filter { $0.trackInventory && $0.status == .active }.sorted { $0.canonicalName < $1.canonicalName } }
    private var dirty: Bool { !text.isEmpty || !rows.isEmpty || recorder.busy }
    private var canSave: Bool {
        let selected = rows.filter { $0.draft.included }
        let snapshotIDs = selected.filter { $0.action == .snapshot }.compactMap { $0.draft.masterID }
        guard Set(snapshotIDs).count == snapshotIDs.count,
              !selected.contains(where: { $0.action != .snapshot && $0.draft.masterID.map(snapshotIDs.contains) == true }) else { return false }
        return !selected.isEmpty && appendedText.isEmpty && !recorder.busy && !saving && selected.allSatisfy { row in
            if row.action == .snapshot { return VoiceSnapshotParser.ready(row, inventory: inventory) }
            guard row.draft.confirmed, row.action != .choose else { return false }
            if row.action != .add {
                guard let target = inventory.first(where: { $0.id == row.targetID && !$0.isDeleted }), target.syncVersion == row.targetVersion else { return false }
            } else if row.draft.masterID == nil && row.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if row.action == .move { return true }
            if row.action == .consume && !row.draft.exact { return row.postUseState != nil }
            return !row.draft.exact || (Double(row.draft.quantity).map { $0.isFinite && (row.action == .add ? $0 > 0 : $0 >= 0) } ?? false)
        }
    }
    var body: some View {
        NavigationStack {
            Group {
                if consent != VoicePrivacyView.currentVersion && !manualMode {
                    Form {
                        VoicePrivacyText()
                        Button("同意して音声入力へ進む") { acceptedAt = Date.now.timeIntervalSince1970; consent = VoicePrivacyView.currentVersion }
                            .accessibilityIdentifier("voice-consent")
                        Button("同意せず文章を入力する") { manualMode = true }
                            .accessibilityIdentifier("voice-manual-without-consent")
                    }
                } else { reviewForm }
            }.navigationTitle(rows.isEmpty ? "音声でまとめて登録" : "内容を確認")
                .scrollContentBackground(.hidden).background(AppTheme.background)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { if dirty { discard = true } else { clear(); dismiss() } }
                    }
                }
                .confirmationDialog("未保存の文章と候補を破棄しますか？", isPresented: $discard, titleVisibility: .visible) {
                    Button("破棄して閉じる", role: .destructive) { clear(); dismiss() }
                }
                .interactiveDismissDisabled(dirty)
                .onChange(of: recorder.transcript) {
                    guard captureActive else { return }
                    text = [capturePrefix, recorder.transcript].filter { !$0.isEmpty }.joined(separator: "\n")
                    if captureAfterReview { appendedText = recorder.transcript }
                }
                .onChange(of: consent) { if consent != VoicePrivacyView.currentVersion { clear(); manualMode = false } }
                .onChange(of: scenePhase, initial: true) { updateVoiceActivity() }
                .onDisappear { if foodRowID == nil { clear() } }
        }.sheet(isPresented: Binding(get: { foodRowID != nil }, set: { if !$0 { foodRowID = nil } })) {
            IngredientMappingPicker(title: "食材を選ぶ", isMapping: false) { food in
                guard let id = foodRowID, let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index] = VoiceSnapshotParser.selecting(ReceiptIngredient(id: food.id,
                    name: food.canonicalName, aliases: food.aliases, unit: food.defaultUnit,
                    allowedUnits: food.allowedUnits, storage: food.defaultStorage, category: food.category),
                    for: rows[index], inventory: inventory)
            }
        }
    }
    private var reviewForm: some View {
        ScrollViewReader { scroll in
            Form {
                Section {
                    Text("例：卵6個、玉ねぎ半分、牛乳。買った・使った内容も話せます")
                        .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    if consent == VoicePrivacyView.currentVersion {
                        Button {
                            endEditing()
                            if recorder.busy { recorder.stop() } else { beginRecording() }
                        } label: { Label(recorder.busy ? recorder.buttonText : (text.isEmpty ? "話して追加" : "追加で話す"), systemImage: recorder.recording ? "stop.circle" : "mic") }
                            .accessibilityIdentifier("voice-record")
                        if recorder.busy { ProgressView(recorder.progressText) }
                    }
                    if let message = recorder.message { Text(message).font(AppFont.caption).foregroundStyle(AppTheme.warning) }
                    if recorder.settingsNeeded, let url = URL(string: UIApplication.openSettingsURLString) { Link("iPhoneの設定を開く", destination: url) }
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-voice-fixture") {
                        Button("文章入力の例を使う") { text = "卵を6個買った" }.accessibilityIdentifier("voice-fixture")
                        Button("冷蔵庫の例を使う") { text = "卵が6個、玉ねぎが半分、鶏むねが300グラム。牛乳とキャベツもある。しょうゆは少なめ" }.accessibilityIdentifier("voice-stock-fixture")
                        Button("追加入力の例を使う") { appendedText = "にんじん2本、豆腐"; text += "\n" + appendedText }.accessibilityIdentifier("voice-append-fixture")
                        Button("曖昧な例を使う") { text = "牛乳半分、スポンジ、卵6個" }.accessibilityIdentifier("voice-uncertain-fixture")
                        Button("使用した文章の例を使う") { text = "卵を2個使った" }.accessibilityIdentifier("voice-use-fixture")
                    }
                    if rows.isEmpty {
                        TextEditor(text: $text).id(VoiceInputField.text).focused($inputFocus, equals: .text)
                            .frame(minHeight: 90).disabled(recorder.busy).accessibilityIdentifier("voice-text")
                        Button("一覧にする") { endEditing(); parse() }
                            .disabled(recorder.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("voice-parse")
                    } else if !appendedText.isEmpty {
                        Text(appendedText).font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                        Button("追加分を一覧にする") { endEditing(); appendCandidates() }
                            .disabled(recorder.busy).accessibilityIdentifier("voice-parse")
                    }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("voice-error") }
                }
                ForEach(rows) { snapshot in
                    if snapshot.action == .snapshot {
                        VoiceSnapshotRowView(row: Binding(get: { rows.first { $0.id == snapshot.id } ?? snapshot }, set: { updated in
                            if let index = rows.firstIndex(where: { $0.id == snapshot.id }) { rows[index] = updated }
                         }), masters: available, inventory: inventory, inputFocus: $inputFocus,
                             onChooseFood: { foodRowID = $0 }, onDelete: deleteRow)
                    } else {
                    VoiceRowView(row: Binding(get: { rows.first { $0.id == snapshot.id } ?? snapshot }, set: { updated in
                        if let index = rows.firstIndex(where: { $0.id == snapshot.id }) { rows[index] = updated }
                    }), masters: available, custom: custom, inventory: inventory, inputFocus: $inputFocus, onDelete: deleteRow)
                    }
                }
            }
            .contentMargins(.bottom, inputFocus == nil ? 0 : editingMargin, for: .scrollContent)
            .onChange(of: inputFocus) { revealInput(using: scroll) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in revealInput(using: scroll) }
        }.safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if inputFocus != nil {
                    HStack {
                        Spacer()
                        Button("入力を完了") { endEditing() }.frame(minHeight: 44)
                            .accessibilityIdentifier("voice-keyboard-done")
                    }.padding(.horizontal)
                }
                if inputFocus == nil {
                    Button { save() } label: { Text("\(rows.filter { $0.draft.included }.count)件を登録").frame(maxWidth: .infinity) }
                        .buttonStyle(CoralPrimaryButtonStyle()).disabled(!canSave).padding()
                        .accessibilityLabel("確認した\(rows.filter { $0.draft.included }.count)件を登録").accessibilityIdentifier("voice-save")
                }
            }.background(AppTheme.background)
        }
    }
    private func revealInput(using scroll: ScrollViewProxy) {
        guard let inputFocus else { return }
        withAnimation { scroll.scrollTo(inputFocus, anchor: .top) }
    }
    private func updateVoiceActivity() {
        switch scenePhase {
        case .active: recorder.activityChanged(.active)
        case .background: recorder.activityChanged(.background)
        default: recorder.activityChanged(.inactive)
        }
    }
    private func endEditing() { inputFocus = nil; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func parse() {
        do {
            let ingredients = available.map { ReceiptIngredient(id: $0.id, name: $0.canonicalName, aliases: $0.aliases, unit: $0.defaultUnit, allowedUnits: $0.allowedUnits, storage: $0.defaultStorage, category: $0.category) }
            let candidates = try VoiceSnapshotParser.parse(text, ingredients: ingredients)
            rows = VoiceSnapshotParser.prepare(candidates, inventory: inventory); sessionID = UUID(); error = nil
            appendedText = ""; captureActive = false
        } catch { self.error = error.localizedDescription }
    }
    private var recognitionIngredients: [ReceiptIngredient] {
        available.map { ReceiptIngredient(id: $0.id, name: $0.canonicalName, aliases: $0.aliases, unit: $0.defaultUnit, allowedUnits: $0.allowedUnits, storage: $0.defaultStorage, category: $0.category) }
    }
    private func beginRecording() {
        guard appendedText.isEmpty else { error = "追加入力を一覧にしてから続けてください。"; return }
        capturePrefix = text; captureAfterReview = !rows.isEmpty; captureActive = true
        let hints = VoiceRecognitionHints.make(ingredients: recognitionIngredients, stockedIDs: Set(inventory.filter { !$0.isDeleted }.compactMap(\.ingredientMasterID)))
        Task { await recorder.start(hints: hints) }
    }
    private func appendCandidates() {
        do {
            let next = try VoiceSnapshotParser.parse(appendedText, ingredients: recognitionIngredients)
            let prepared = VoiceSnapshotParser.prepare(next, inventory: inventory)
            guard rows.count + prepared.count <= 20 else { throw VoiceError.tooMany }
            for candidate in prepared {
                if candidate.action == .snapshot, let id = candidate.draft.masterID,
                   let index = rows.firstIndex(where: { $0.action == .snapshot && $0.draft.masterID == id }) {
                    rows[index].repeated = true
                    // Preserve edits; repeated conflicting amounts need one explicit resolution.
                    if rows[index].draft.exact != candidate.draft.exact || rows[index].draft.quantity != candidate.draft.quantity || rows[index].draft.rough != candidate.draft.rough || rows[index].draft.unit != candidate.draft.unit || rows[index].draft.storage != candidate.draft.storage {
                        rows[index].issue = "同じ食材の量が複数あります。残量を選んでください"
                        rows[index].draft.source += " / " + candidate.draft.source
                    }
                } else { rows.append(candidate) }
            }
            appendedText = ""; captureActive = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func deleteRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
        if foodRowID == id { foodRowID = nil }
        if rows.isEmpty { text = ""; appendedText = "" }
        error = nil
    }
    private func clear() {
        endEditing(); captureActive = false; recorder.cancel(erase: true); rows.removeAll(); text = ""; appendedText = ""; error = nil
    }
    private func save() {
        guard canSave else { return }; saving = true
        do {
            let confirmed = rows.map { original in
                var row = original
                if row.action == .snapshot && row.draft.included { row.draft.confirmed = true }
                return row
            }
            try VoiceImportService(container: context.container, mergeDuplicates: mergeInventory).save(rows: confirmed, sessionID: sessionID); clear(); dismiss()
        }
        catch { self.error = error.localizedDescription; saving = false }
    }
}

private enum VoiceInputField: Hashable {
    case text
    case name(UUID)
    case quantity(UUID)
}

private struct VoiceRowView: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    @Binding var row: VoiceRow
    let masters: [IngredientMaster]
    let custom: [CustomIngredient]
    let inventory: [InventoryItem]
    let inputFocus: FocusState<VoiceInputField?>.Binding
    var onDelete: (UUID) -> Void
    private var master: IngredientMaster? { masters.first { $0.id == row.draft.masterID } }
    private var units: [IngredientUnit] { master?.allowedUnits ?? IngredientUnit.allCases }
    private var targets: [InventoryItem] { inventory.filter { !$0.isDeleted && $0.ingredientMasterID == row.draft.masterID }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) } }
    private var target: InventoryItem? { inventory.first { $0.id == row.targetID && !$0.isDeleted } }
    private var mergeTarget: InventoryItem? {
        inventory.filter { ReceiptImportService.canMerge(row.draft, into: $0) }
            .min(by: InventoryAddition.precedes)
    }
    private var signature: String {
        "\(row.action)|\(String(describing: row.targetID))|\(String(describing: row.targetVersion))|\(String(describing: row.postUseState))|\(String(describing: row.draft.masterID))|\(row.draft.name)|\(row.draft.category)|\(row.draft.included)|\(row.draft.exact)|\(row.draft.quantity)|\(row.draft.unit)|\(row.draft.rough)|\(row.draft.storage)|\(row.draft.purchasedAt)|\(String(describing: row.draft.expiresAt))|\(row.draft.expiryKind)|\(row.draft.merge)"
    }
    var body: some View {
        Section {
            Text(row.draft.source).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
            Toggle("この項目を反映する", isOn: $row.draft.included)
            if row.draft.included {
                Picker("操作", selection: $row.action) { ForEach(VoiceAction.allCases.filter { $0 != .snapshot }, id: \.self) { Text($0.label).tag($0) } }
                    .accessibilityIdentifier("voice-action")
                Picker("食材", selection: $row.draft.masterID) {
                    Text("カスタム食材").tag(UUID?.none)
                    ForEach(masters) { Text($0.canonicalName).tag(Optional($0.id)) }
                }.onChange(of: row.draft.masterID) {
                    row.targetID = nil; row.targetVersion = nil
                    if let master {
                        row.draft.name = master.canonicalName; row.draft.category = master.category
                        if !master.allowedUnits.contains(row.draft.unit) { row.draft.unit = master.defaultUnit; row.draft.exact = false }
                    }
                }
                if row.action == .add {
                    if row.draft.masterID == nil {
                        TextField("食材名", text: $row.draft.name).id(VoiceInputField.name(row.id)).focused(inputFocus, equals: .name(row.id)).accessibilityIdentifier("voice-custom-name")
                        Picker("食材の種類", selection: $row.draft.category) { ForEach(IngredientCategory.allCases, id: \.self) { Text($0.label).tag($0) } }
                    }
                } else if row.action != .choose { targetPicker }
                if row.action != .move && row.action != .choose { amountFields }
                if row.action == .add || row.action == .move {
                    Picker("保存方法", selection: $row.draft.storage) { ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) } }
                }
                if row.action == .add { additionFields }
                if row.action == .consume, let target { consumptionPreview(target) }
                if row.action == .setAmount {
                    Text("修正後：\(row.draft.exact ? row.draft.quantity + row.draft.unit.label : row.draft.rough.label)")
                }
                if row.action == .move { Text("変更後：\(row.draft.storage.label)（量・購入日・期限は維持）") }
                Text(row.draft.reason).font(AppFont.caption).foregroundStyle(AppTheme.warning)
                Toggle("操作・対象・量を確認しました", isOn: $row.draft.confirmed).accessibilityIdentifier("voice-confirm")
            }
        } header: {
            HStack {
                Button { onDelete(row.id) } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("\(row.draft.name.isEmpty ? "要確認" : row.draft.name)を削除")
                    .accessibilityIdentifier("voice-delete-" + (master?.key ?? row.id.uuidString))
                Text(row.draft.name.isEmpty ? "要確認" : row.draft.name)
            }
        }.onChange(of: signature) { row.draft.confirmed = false }
    }
    private var targetPicker: some View {
        Group {
            Picker("修正する在庫", selection: $row.targetID) {
                Text("在庫を選ぶ").tag(UUID?.none)
                ForEach(targets) { item in Text(targetLabel(item)).tag(Optional(item.id)) }
            }.accessibilityIdentifier("voice-target")
                .onChange(of: row.targetID) { captureTarget() }
            if let target {
                Text("現在：\(targetLabel(target))").font(AppFont.caption)
                if row.targetVersion != target.syncVersion {
                    Text("在庫が更新されています。現在の内容を確認し直してください。").foregroundStyle(AppTheme.warning)
                    Button("現在の在庫を確認し直す") { captureTarget(); row.draft.confirmed = false }
                }
            } else { Text("複数ロットでも推測せず、修正する在庫を選びます。").font(AppFont.caption) }
        }
    }
    private var amountFields: some View {
        Group {
            Toggle(row.action == .consume ? "使用量を数量で指定" : "数量を指定", isOn: $row.draft.exact)
            if row.draft.exact {
                TextField(row.action == .consume ? "使用量" : "数量", text: $row.draft.quantity).id(VoiceInputField.quantity(row.id)).focused(inputFocus, equals: .quantity(row.id)).keyboardType(.decimalPad).accessibilityIdentifier("voice-quantity")
                Picker("単位", selection: $row.draft.unit) { ForEach(units, id: \.self) { Text($0.label).tag($0) } }
            } else if row.action == .consume {
                Picker("使用後の状態（選択必須）", selection: $row.postUseState) {
                    Text("状態を選ぶ").tag(RoughStockState?.none)
                    ForEach([RoughStockState.available, .low, .unavailable], id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                Text("数量を差し引かず、選んだ使用後の状態へ変更します。").font(AppFont.caption)
            } else {
                Picker("在庫の状態", selection: $row.draft.rough) { ForEach([RoughStockState.available, .low, .unavailable], id: \.self) { Text($0.label).tag($0) } }
            }
        }
    }
    private var additionFields: some View {
        Group {
            DatePicker("購入日", selection: $row.draft.purchasedAt, displayedComponents: .date)
            Toggle("期限を入力する", isOn: Binding(get: { row.draft.expiresAt != nil }, set: { row.draft.expiresAt = $0 ? .now : nil; row.draft.confirmed = false }))
            if row.draft.expiresAt != nil {
                DatePicker("期限", selection: Binding(get: { row.draft.expiresAt ?? .now }, set: { row.draft.expiresAt = $0 }), displayedComponents: .date)
                Picker("期限の種類", selection: $row.draft.expiryKind) { ForEach([ExpiryKind.unspecified, .bestBefore, .useBy], id: \.self) { Text($0.label).tag($0) } }
            }
            if mergeInventory && row.draft.merge, let item = mergeTarget {
                if let unit = item.unit, let quantity = Double(row.draft.quantity), let added = Units.convert(quantity, from: row.draft.unit, to: unit) {
                    Text("現在 \(amountLabel(item)) ＋ 追加 \(added.formatted())\(unit.label) → \(((item.quantity ?? 0) + added).formatted())\(unit.label)").font(AppFont.caption)
                } else { Text("同じ条件の在庫にまとめます").font(AppFont.caption) }
            }
        }
    }
    @ViewBuilder private func consumptionPreview(_ item: InventoryItem) -> some View {
        if row.draft.exact, let unit = item.unit, item.stockMode == .exact, let quantity = Double(row.draft.quantity), let used = Units.convert(quantity, from: row.draft.unit, to: unit) {
            let remaining = (item.quantity ?? 0) - used
            Text(remaining >= 0 ? "使用後：\(remaining.formatted())\(unit.label)" : "要確認：使用量が在庫を超えています")
                .foregroundStyle(remaining >= 0 ? AppTheme.text : AppTheme.danger)
        } else if row.draft.exact {
            Text("要確認：この在庫から数量を差し引けません。残りを修正する操作を選んでください。").foregroundStyle(AppTheme.warning)
        } else { Text("使用後：\(row.postUseState?.label ?? "状態を選んでください")") }
    }
    private func targetLabel(_ item: InventoryItem) -> String {
        let name = masters.first { $0.id == item.ingredientMasterID }?.canonicalName ?? custom.first { $0.id == item.customIngredientID }?.name ?? "未対応の食材"
        return "\(name) · \(amountLabel(item)) · \(item.storage.label) · \(expiryLabel(item)) · 購入\(item.purchasedAt.formatted(.dateTime.month().day()))"
    }
    private func captureTarget() {
        guard let target else { row.targetVersion = nil; return }
        row.targetVersion = target.syncVersion
        if row.draft.masterID == nil, let ingredient = custom.first(where: { $0.id == target.customIngredientID }) { row.draft.name = ingredient.name; row.draft.category = ingredient.category }
        if !row.draft.exact, let unit = target.unit { row.draft.unit = unit }
    }
}


/// Compact stocktaking rows. Only uncertain or intentionally edited rows expand.
private struct VoiceSnapshotRowView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var row: VoiceRow
    let masters: [IngredientMaster]
    let inventory: [InventoryItem]
    let inputFocus: FocusState<VoiceInputField?>.Binding
    @State private var expanded = false
    var onChooseFood: (UUID) -> Void
    var onDelete: (UUID) -> Void
    private var master: IngredientMaster? { masters.first { $0.id == row.draft.masterID } }
    private var lots: [InventoryItem] {
        inventory.filter { row.draft.masterID != nil && !$0.isDeleted && $0.ingredientMasterID == row.draft.masterID }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private var target: InventoryItem? { lots.first { $0.id == row.targetID } }
    private var unresolved: Bool { !VoiceSnapshotParser.ready(row, inventory: inventory) }
    private var summary: String {
        if row.draft.exact, let value = Double(row.draft.quantity) { return value.formatted() + row.draft.unit.label }
        if row.draft.rough == .available, let target, target.stockMode == .exact, (target.quantity ?? 0) > 0 { return amountLabel(target) + "（維持）" }
        return row.draft.rough == .available ? "あり" : row.draft.rough.label
    }
    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Button { onDelete(row.id) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderless)
                    .accessibilityLabel("\(row.draft.name.isEmpty ? row.draft.source : row.draft.name)を削除")
                    .accessibilityIdentifier("voice-delete-" + (master?.key ?? row.id.uuidString))
                Button { row.draft.included.toggle() } label: {
                    Image(systemName: row.draft.included ? "checkmark.circle.fill" : "circle")
                        .font(AppFont.title3).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(row.draft.included ? "登録から外す" : "登録に含める")
                    .accessibilityIdentifier("voice-include-" + (master?.key ?? row.id.uuidString))
                Button { expanded.toggle() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.draft.name.isEmpty ? row.draft.source : row.draft.name).foregroundStyle(AppTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if textSize.isAccessibilitySize {
                                Text(summary).font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if unresolved { Label("要確認", systemImage: "exclamationmark.circle").font(AppFont.caption).foregroundStyle(AppTheme.warning) }
                            else if row.repeated { Text("重複をまとめました").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
                        }
                        Spacer(minLength: 8)
                        if !textSize.isAccessibilitySize { Text(summary).foregroundStyle(AppTheme.secondary) }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(AppFont.caption)
                    }.frame(minHeight: 44)
                }.buttonStyle(.borderless).accessibilityIdentifier("voice-edit-" + (master?.key ?? row.id.uuidString))
            }
            if expanded { editor }
        }
        .onChange(of: row.draft.quantity) { VoiceSnapshotParser.resolveEditedAmount(&row) }
        .onChange(of: row.draft.exact) { VoiceSnapshotParser.resolveEditedAmount(&row) }
        .onChange(of: row.draft.rough) { VoiceSnapshotParser.resolveEditedAmount(&row) }
    }
    @ViewBuilder private var editor: some View {
        Text(row.draft.source).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
        Button(row.draft.name.isEmpty ? "食材を選ぶ" : "食材を選び直す") { onChooseFood(row.id) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("voice-select-food")
        if lots.count > 1 {
            Text("更新する在庫を選んでください。他の在庫の量は変わりません。").font(AppFont.caption)
            Picker("更新する在庫", selection: $row.targetID) {
                Text("在庫を選ぶ").tag(UUID?.none)
                ForEach(lots) { item in Text(amountLabel(item) + " · " + item.storage.label + " · " + expiryLabel(item) + " · 購入" + item.purchasedAt.formatted(.dateTime.month().day())).tag(Optional(item.id)) }
            }.accessibilityIdentifier("voice-snapshot-target")
                .onChange(of: row.targetID) { row.targetVersion = target?.syncVersion }
        }
        if master?.category != .seasoning {
            Toggle("数量を指定", isOn: $row.draft.exact).accessibilityIdentifier("voice-exact")
            if row.draft.exact {
                TextField("残っている量", text: $row.draft.quantity)
                    .id(VoiceInputField.quantity(row.id)).focused(inputFocus, equals: .quantity(row.id)).keyboardType(.decimalPad)
                    .accessibilityIdentifier("voice-snapshot-quantity")
                Picker("単位", selection: $row.draft.unit) {
                    ForEach(master?.allowedUnits ?? IngredientUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
        }
        if !row.draft.exact {
            Picker("状態", selection: $row.draft.rough) {
                Text("あり").tag(RoughStockState.available)
                Text("少ない").tag(RoughStockState.low)
                Text("ない").tag(RoughStockState.unavailable)
            }.accessibilityIdentifier("voice-snapshot-state")
        }
        Picker("保存方法", selection: $row.draft.storage) {
            ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
        }.onChange(of: row.draft.storage) { row.storageSpoken = true }
        if target == nil && lots.isEmpty {
            DatePicker("購入日", selection: $row.draft.purchasedAt, displayedComponents: .date)
            Toggle("期限を入力", isOn: Binding(get: { row.draft.expiresAt != nil }, set: { row.draft.expiresAt = $0 ? .now : nil }))
            if let date = row.draft.expiresAt {
                DatePicker("期限", selection: Binding(get: { row.draft.expiresAt ?? date }, set: { row.draft.expiresAt = $0 }), displayedComponents: .date)
                Picker("期限の種類", selection: $row.draft.expiryKind) {
                    ForEach([ExpiryKind.unspecified, .bestBefore, .useBy], id: \.self) { Text($0.label).tag($0) }
                }
            }
        }
        if let issue = row.issue { Text(issue).font(AppFont.caption).foregroundStyle(AppTheme.warning) }
        if let target { Text("現在：" + amountLabel(target)).font(AppFont.caption).foregroundStyle(AppTheme.secondary) }

    }
}
