import Foundation

enum VoiceAction: String, CaseIterable {
    case choose, snapshot, add, consume, setAmount, move
    var label: String {
        switch self { case .snapshot: "冷蔵庫の中身"; case .choose: "操作を選ぶ"; case .add: "買った・追加する"; case .consume: "使った"; case .setAmount: "残りを修正"; case .move: "保存方法を変更" }
    }
}
struct VoiceRow: Identifiable {
    var draft: ReceiptRow
    var action: VoiceAction = .choose
    var targetID: UUID?
    var targetVersion: Int?
    var postUseState: RoughStockState?
    // Transient review metadata, never persisted as recognition text.
    var snapshotLots: [UUID: Int] = [:]
    var issue: String?
    var storageSpoken = false
    var repeated = false
    var id: UUID { draft.id }
}
enum VoiceError: LocalizedError {
    case empty, tooMany, invalid, target, incompatible, exceeds, duplicate, stockChanged
    var errorDescription: String? {
        switch self {
        case .stockChanged: "在庫が変わっています。候補を作り直して確認してください。"
        case .empty: "食材を入力してください。例：卵6個、牛乳"
        case .tooMany: "項目が多いため、20項目ずつに分けてください。"
        case .invalid: "すべての対象項目で操作・食材・数量を確認してください。"
        case .target: "修正する在庫を選び直してください。取り除いた在庫は変更できません。"
        case .incompatible: "単位が合わないか、数量が曖昧です。残りを修正する操作で確認後の量を入力してください。"
        case .exceeds: "使用量が現在の在庫を超えています。量や対象の在庫を確認してください。"
        case .duplicate: "この確認結果は反映済みです。"
        }
    }
}

/// A conservative grammar produces editable candidates, never an inventory mutation.
enum VoiceParser {
    static func parse(_ text: String, ingredients: [ReceiptIngredient]) throws -> [VoiceRow] {
        let lines = text.components(separatedBy: CharacterSet(charactersIn: "\n。；;、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw VoiceError.empty }
        guard lines.count <= 20, text.count <= 4000 else { throw VoiceError.tooMany }
        return lines.map { source in
            let normalized = ReceiptParser.normalized(source)
            let matches = ingredients.filter { ingredient in
                ([ingredient.name] + ingredient.aliases).contains { alias in
                    let key = ReceiptParser.normalized(alias)
                    if key.count >= 2 { return normalized.contains(key) }
                    guard let range = normalized.range(of: key), key.count == 1 else { return false }
                    let prefix = normalized[..<range.lowerBound], suffix = normalized[range.upperBound...]
                    return (prefix.isEmpty || prefix.last.map { "ノトヲハガ".contains($0) } == true)
                        && (suffix.isEmpty || suffix.first.map { $0.isNumber || "ヲハガノト残少冷常零一二三四五六七八九十".contains($0) } == true)
                }
            }
            let ingredient = matches.count == 1 ? matches[0] : nil
            var draft = ReceiptRow(source: source, masterID: ingredient?.id, name: ingredient?.name ?? "",
                included: ingredient != nil, reason: "要確認：操作・食材・数量を確認してください。期限は実物を見て入力してください。")
            if let ingredient { draft.unit = ingredient.unit; draft.storage = ingredient.storage; draft.category = ingredient.category }
            var actions: [VoiceAction] = []
            if ["買った", "買いました", "購入", "追加", "補充"].contains(where: source.contains) { actions.append(.add) }
            if ["使った", "使いました", "使用", "食べた", "飲んだ", "消費"].contains(where: source.contains) { actions.append(.consume) }
            if ["残り", "残って", "少ない", "なくなった", "在庫は", "ある", "ない"].contains(where: source.contains) { actions.append(.setAmount) }
            if ["移す", "移した", "移動", "冷凍した", "冷蔵した"].contains(where: source.contains) { actions.append(.move) }
            let ambiguous = source.range(of: #"使ってない|使わな|買わな|買ってない|してない|しなかった|取消|取り消|[−-]\s*\d"#, options: .regularExpression) != nil
            var row = VoiceRow(draft: draft, action: actions.count == 1 && !ambiguous ? actions[0] : .choose)
            if ambiguous { row.draft.included = false; row.draft.reason = "否定・取消の可能性があります。操作を選んで内容を確認してください。" }
            if source.contains("冷凍") { row.draft.storage = .frozen }
            else if source.contains("常温") { row.draft.storage = .roomTemperature }
            else if source.contains("冷蔵") { row.draft.storage = .refrigerated }
            if let amount = quantity(source), ingredient?.allowedUnits.contains(amount.1) == true {
                row.draft.exact = true; row.draft.quantity = String(amount.0); row.draft.unit = amount.1
            } else { row.draft.reason += " 数量を確定できないため手入力してください。" }
            if source.contains("少ない") { row.draft.rough = .low }
            else if source.contains("ない") || source.contains("なくなった") { row.draft.rough = .unavailable }
            if matches.count != 1 { row.draft.reason = "食材が未確定です。食材を選んでください。" }
            return row
        }
    }
    static func quantity(_ source: String) -> (Double, IngredientUnit)? {
        var text = source.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
        // Spoken metric names and fractions are explicit quantities. Bare 'half' is not.
        for (word, unit) in [("キログラム", "kg"), ("ミリリットル", "ml"), ("リットル", "l"), ("グラム", "g")] { text = text.replacingOccurrences(of: word, with: unit) }
        text = text.replacingOccurrences(of: "二分の一", with: "0.5")
        let numbers = try! NSRegularExpression(pattern: #"[〇零一二三四五六七八九十百千]+(?=\s*(kg|ml|g|l|個|枚|袋|缶|パック|丁|束|本|片|膳|玉))"#)
        for match in numbers.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if let range = Range(match.range, in: text), let value = japaneseNumber(String(text[range])) { text.replaceSubrange(range, with: String(value)) }
        }
        let regex = try! NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?(?:/[0-9]+(?:\.[0-9]+)?)?)\s*(kg|ml|g|l|個|枚|袋|缶|パック|丁|束|本|片|膳|玉)"#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, text.range(of: #"[−-]\s*\d|×|[x*]\s*\d|半分|セット|組"#, options: .regularExpression) == nil,
              let values = Range(matches[0].range(at: 1), in: text), let units = Range(matches[0].range(at: 2), in: text) else { return nil }
        let parts = text[values].split(separator: "/").compactMap { Double($0) }
        guard let first = parts.first, parts.count <= 2, parts.count != 2 || parts[1] > 0 else { return nil }
        let value = parts.count == 2 ? first / parts[1] : first
        let mapping: [String: IngredientUnit] = ["kg": .kilogram, "g": .gram, "ml": .milliliter, "l": .liter, "個": .piece, "枚": .slice, "袋": .bag, "缶": .can, "パック": .pack, "丁": .block, "束": .bunch, "本": .stalk, "片": .clove, "膳": .serving, "玉": .portion]
        guard value.isFinite, value >= 0, let unit = mapping[String(text[units])] else { return nil }
        return (value, unit)
    }
    private static func japaneseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["〇":0, "零":0, "一":1, "二":2, "三":3, "四":4, "五":5, "六":6, "七":7, "八":8, "九":9]
        let scales: [Character: Int] = ["十":10, "百":100, "千":1000]
        if !text.contains(where: { scales[$0] != nil }) { return Int(text.compactMap { digits[$0].map(String.init) }.joined()) }
        var total = 0, pending = 0, previousScale = 10000
        for character in text {
            if let digit = digits[character] { guard pending == 0 else { return nil }; pending = digit }
            else if let scale = scales[character] { guard scale < previousScale else { return nil }; total += max(1, pending) * scale; pending = 0; previousScale = scale }
            else { return nil }
        }
        return total + pending
    }
}


/// Natural enumeration for stocktaking. Longest non-overlapping master aliases win;
/// unknown words and uncertain amounts stay visible for review, never fuzzy auto-matched.
enum VoiceSnapshotParser {
    private struct Mention {
        let range: NSRange
        let ingredient: ReceiptIngredient
        var ambiguous = false
    }
    static func parse(_ text: String, ingredients: [ReceiptIngredient]) throws -> [VoiceRow] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceError.empty }
        guard text.count <= 4000 else { throw VoiceError.tooMany }
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: "\n。；;、,，"))
        var rows: [VoiceRow] = []
        for clause in clauses {
            let text = ReceiptParser.normalized(clause)
            guard !text.isEmpty else { continue }
            // Destructive/relative operations retain the existing explicit-confirmation workflow.
            if clause.range(of: "買った|買いました|購入|追加|補充|使った|使いました|使用|食べた|飲んだ|消費|移す|移した|移動|冷凍した|冷蔵した|買わな|買ってない|使わな|使ってない", options: .regularExpression) != nil {
                rows += try VoiceParser.parse(clause, ingredients: ingredients)
                continue
            }
            let string = text as NSString
            let masked = NSMutableString(string: text)
            let fillerPattern = try! NSRegularExpression(pattern: "ダイタイ|クライ|エット|エート|ジャナクテ|ジャナイ")
            for match in fillerPattern.matches(in: text, range: NSRange(location: 0, length: string.length)).reversed() {
                masked.replaceCharacters(in: match.range, with: String(repeating: "□", count: match.range.length))
            }
            let matching = masked as NSString
            var hits: [Mention] = []
            for ingredient in ingredients {
                for alias in Set(VoiceRecognitionHints.aliases(for: ingredient).map(ReceiptParser.normalized)) where !alias.isEmpty {
                    var start = 0
                    while start < string.length {
                        let range = matching.range(of: alias, range: NSRange(location: start, length: string.length - start))
                        guard range.location != NSNotFound else { break }
                        start = NSMaxRange(range)
                        if alias.count == 1 {
                            let before = string.substring(to: range.location).last
                            let after = string.substring(from: NSMaxRange(range)).first
                            guard before == nil || "トヲハガノ、".contains(before!),
                                  after == nil || after!.isNumber || "ヲハガノト残少冷常零一二三四五六七八九十アナ".contains(after!) else { continue }
                        }
                        hits.append(Mention(range: range, ingredient: ingredient))
                    }
                }
            }
            hits.sort { $0.range.length != $1.range.length ? $0.range.length > $1.range.length : $0.range.location < $1.range.location }
            var mentions: [Mention] = []
            for hit in hits {
                if let index = mentions.firstIndex(where: { NSIntersectionRange($0.range, hit.range).length > 0 }) {
                    if mentions[index].range == hit.range && mentions[index].ingredient.id != hit.ingredient.id { mentions[index].ambiguous = true }
                } else { mentions.append(hit) }
            }
            mentions.sort { $0.range.location < $1.range.location }
            guard !mentions.isEmpty else {
                if text.range(of: "ジャナクテ|訂正|違ウ|取リ消", options: .regularExpression) != nil,
                   let index = rows.indices.last {
                    rows[index].issue = "言い直した内容を確認してください"
                    rows[index].draft.source += " / " + clause
                }
                if !filler(text) { rows.append(unknown(clause)) }
                continue
            }
            let clauseStart = rows.count
            var prefix = string.substring(to: mentions[0].range.location)
            if !filler(prefix) { rows.append(unknown(prefix)); prefix = "" }
            for (index, mention) in mentions.enumerated() {
                let end = index + 1 < mentions.count ? mentions[index + 1].range.location : string.length
                let suffix = string.substring(with: NSRange(location: NSMaxRange(mention.range), length: end - NSMaxRange(mention.range)))
                // Connectors occur outside the matched food name, so トマト/とうもろこし survive.
                let pieces = suffix.replacingOccurrences(of: "ト(?!ル|ツ)", with: "|", options: .regularExpression).components(separatedBy: "|")
                let body = prefix + string.substring(with: mention.range) + (pieces.first ?? "")
                var row = candidate(body, ingredient: mention.ingredient)
                if mention.ambiguous { row.draft.masterID = nil; row.draft.name = ""; row.draft.included = false; row.issue = "食材を選んでください" }
                rows.append(row)
                prefix = ""
                for tail in pieces.dropFirst() where !tail.isEmpty {
                    if filler(tail) {
                        if tail.contains("冷凍") || tail.contains("冷蔵") || tail.contains("常温") { prefix = tail }
                    } else { rows.append(unknown(tail)) }
                }
            }
            // A shared state in "卵と牛乳はない" applies to the coordinated bare names.
            if let last = rows.last, last.action == .snapshot, !last.draft.exact, last.draft.rough != .available {
                for index in clauseStart..<max(clauseStart, rows.count - 1) where rows[index].action == .snapshot && rows[index].draft.masterID != nil && !rows[index].draft.exact {
                    if rows[index].draft.source.range(of: "アル|アリ|少ナ|少シ|少量|ナイ|無イ|切レテ", options: .regularExpression) == nil {
                        rows[index].draft.rough = last.draft.rough
                    }
                }
            }
        }
        guard !rows.isEmpty else { throw VoiceError.empty }
        guard rows.count <= 20 else { throw VoiceError.tooMany }
        // Repeated foods must not create multiple lots or sum stocktaking amounts.
        var result: [VoiceRow] = []
        for row in rows {
            if row.action == .snapshot, let id = row.draft.masterID,
               let index = result.firstIndex(where: { $0.action == .snapshot && $0.draft.masterID == id }) {
                var prior = result[index]
                if prior.draft.exact == row.draft.exact && prior.draft.quantity == row.draft.quantity && prior.draft.unit == row.draft.unit && prior.draft.rough == row.draft.rough && prior.draft.storage == row.draft.storage {
                    prior.repeated = true
                } else {
                    prior.issue = "同じ食材の量が複数あります。残量を選んでください"
                    prior.draft.source += " / " + row.draft.source
                    prior.repeated = true
                }
                result[index] = prior
            } else { result.append(row) }
        }
        return result
    }
    private static func filler(_ text: String) -> Bool {
        var remainder = text
        for word in ["冷蔵庫ニハ", "冷蔵庫ニ", "冷蔵庫", "冷凍庫", "ソレカラ", "ソレト", "エット", "エート", "アト", "コレト", "冷凍ノ", "冷蔵ノ", "常温ノ", "冷凍", "冷蔵", "常温", "デス", "アリマス", "ガアル", "ガアリ", "アル", "モアル", "ハ", "ガ", "モ", "ノ", "ト"] {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.isEmpty
    }
    private static func unknown(_ source: String) -> VoiceRow {
        var row = VoiceRow(draft: ReceiptRow(source: source, included: false, reason: "食材を選んでください"), action: .snapshot)
        row.issue = "食材を選んでください"
        return row
    }
    private static func candidate(_ source: String, ingredient: ReceiptIngredient) -> VoiceRow {
        var draft = ReceiptRow(source: source, masterID: ingredient.id, name: ingredient.name, reason: "")
        draft.unit = ingredient.unit; draft.storage = ingredient.storage; draft.category = ingredient.category
        var row = VoiceRow(draft: draft, action: .snapshot)
        if source.contains("冷凍") { row.draft.storage = .frozen; row.storageSpoken = true }
        else if source.contains("常温") { row.draft.storage = .roomTemperature; row.storageSpoken = true }
        else if source.contains("冷蔵") { row.draft.storage = .refrigerated; row.storageSpoken = true }
        if source.contains("ナイ") || source.contains("無イ") || source.contains("ナクナッタ") || source.contains("アリマセン") || source.contains("切レテ") { row.draft.rough = .unavailable }
        else if source.contains("少ナ") || source.contains("少シ") || source.contains("少量") { row.draft.rough = .low }
        // The quantity parser consumes kana spellings too; preserve explicit uncertainty.
        var quantityText = source
        for alias in VoiceRecognitionHints.aliases(for: ingredient).map(ReceiptParser.normalized).sorted(by: { $0.count > $1.count }) {
            quantityText = quantityText.replacingOccurrences(of: alias, with: "")
        }
        for (word, number) in [("ヒトツ", "1個"), ("フタツ", "2個"), ("ミッツ", "3個"), ("ヨッツ", "4個"), ("イッコ", "1個"), ("ニコ", "2個"), ("サンコ", "3個")] {
            quantityText = quantityText.replacingOccurrences(of: word, with: number)
        }
        quantityText = quantityText.replacingOccurrences(of: "([0-9〇零一二三四五六七八九十]+)ツ", with: "$1個", options: .regularExpression)
        let quantitySource = quantityText.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source
        let metric = quantitySource.replacingOccurrences(of: "きろぐらむ", with: "kg").replacingOccurrences(of: "ぐらむ", with: "g").replacingOccurrences(of: "みりりっとる", with: "ml").replacingOccurrences(of: "りっとる", with: "l").replacingOccurrences(of: "ぱっく", with: "パック")
        let spokenAmount = VoiceParser.quantity(metric)
        let countFoods = Set(["にんじん", "きゅうり", "大根", "ごぼう", "なす", "ズッキーニ", "バナナ"])
        let parsedUnit = spokenAmount.map { value in
            value.1 == .stalk && ingredient.unit == .piece && countFoods.contains(ingredient.name) ? IngredientUnit.piece : value.1
        }
        if let amount = spokenAmount, let unit = parsedUnit, ingredient.allowedUnits.contains(unit), ingredient.category != .seasoning {
            row.draft.exact = true; row.draft.quantity = String(amount.0); row.draft.unit = unit
        } else if (source.contains("半分") || source.contains("半玉") || source.contains("半個")),
                  ingredient.category != .seasoning,
                  ingredient.unit == .piece || ingredient.unit == .portion || ingredient.unit == .block,
                  quantityText.range(of: "[0-9〇零一二三四五六七八九十百千]|ダイタイ|クライ|約", options: .regularExpression) == nil {
            row.draft.exact = true; row.draft.quantity = "0.5"
        } else if ingredient.category != .seasoning,
                  quantityText.range(of: "[0-9〇零一二三四五六七八九十百千]|半分|半玉|半個", options: .regularExpression) != nil {
            row.issue = "数量・単位を確認してください"
        }
        if source.range(of: "[−-]\\s*\\d|取消|取リ消|ジャナクテ|ジャナイ|デハナイ|分カラナイ|ワカラナイ|ダイタイ|クライ|グライ|ホド|程度|以上|以下|未満|[〜～]|[0-9〇零一二三四五六七八九十]+(個|玉|丁)半|約|カモ", options: .regularExpression) != nil {
            row.issue = "内容を確認してください"
        }
        if row.draft.exact && row.draft.rough == .unavailable && (Double(row.draft.quantity) ?? 0) > 0 {
            row.issue = "数量と状態を確認してください"
        }
        return row
    }
    @MainActor static func prepare(_ rows: [VoiceRow], inventory: [InventoryItem]) -> [VoiceRow] {
        rows.map { candidate in
            var row = candidate
            guard row.action == .snapshot, let id = row.draft.masterID else { return row }
            let lots = inventory.filter { !$0.isDeleted && $0.ingredientMasterID == id }
            row.targetID = nil; row.targetVersion = nil
            row.snapshotLots = Dictionary(uniqueKeysWithValues: lots.map { ($0.id, $0.syncVersion) })
            if lots.count == 1 { row.targetID = lots[0].id; row.targetVersion = lots[0].syncVersion }
            return row
        }
    }
    /// Deliberate selection replaces uncertain recognition with a safe rough stock entry.
    @MainActor static func selecting(_ ingredient: ReceiptIngredient, for candidate: VoiceRow, inventory: [InventoryItem]) -> VoiceRow {
        var row = candidate
        row.draft.masterID = ingredient.id; row.draft.name = ingredient.name
        row.draft.unit = ingredient.unit; row.draft.category = ingredient.category
        row.draft.storage = ingredient.storage
        row.draft.exact = false; row.draft.quantity = ""; row.draft.rough = .available
        row.draft.included = true; row.issue = nil; row.storageSpoken = false
        return prepare([row], inventory: inventory)[0]
    }
    static func resolveEditedAmount(_ row: inout VoiceRow) {
        guard row.draft.masterID != nil,
              !row.draft.exact || Double(row.draft.quantity).map({ $0.isFinite && $0 >= 0 }) == true else { return }
        row.issue = nil
    }
    @MainActor static func ready(_ row: VoiceRow, inventory: [InventoryItem]) -> Bool {
        guard row.action == .snapshot, row.draft.masterID != nil, row.issue == nil else { return false }
        let lots = inventory.filter { !$0.isDeleted && $0.ingredientMasterID == row.draft.masterID }
        guard Dictionary(uniqueKeysWithValues: lots.map { ($0.id, $0.syncVersion) }) == row.snapshotLots else { return false }
        if !lots.isEmpty {
            guard let item = lots.first(where: { $0.id == row.targetID }), item.syncVersion == row.targetVersion else { return false }
        } else if row.targetID != nil { return false }
        return !row.draft.exact || (Double(row.draft.quantity).map { $0.isFinite && $0 >= 0 } ?? false)
    }
}


enum VoiceRecognitionHints {
    static func aliases(for ingredient: ReceiptIngredient) -> [String] {
        var names = [ingredient.name] + ingredient.aliases
        if ["鶏むね肉", "鶏もも肉"].contains(ingredient.name) { names.append(String(ingredient.name.dropLast())) }
        return names
    }
    static func make(ingredients: [ReceiptIngredient], stockedIDs: Set<UUID>) -> [String] {
        let common = Set(["ごはん", "卵", "玉ねぎ", "牛乳", "にんじん", "じゃがいも", "キャベツ", "鶏むね肉", "鶏もも肉", "豚こま切れ肉", "豆腐", "納豆", "トマト", "小松菜", "ほうれん草", "もやし", "しょうゆ", "みそ", "しめじ", "えのき", "しいたけ", "冷凍うどん", "ツナ缶", "ピーマン", "なす", "きゅうり", "にんにく", "しょうが", "ブロッコリー", "鮭"])
        let sorted = ingredients.sorted {
            let lhs = stockedIDs.contains($0.id) ? 0 : common.contains($0.name) ? 1 : 2
            let rhs = stockedIDs.contains($1.id) ? 0 : common.contains($1.name) ? 1 : 2
            return lhs != rhs ? lhs < rhs : $0.name < $1.name
        }
        var hints = Array(sorted.prefix(70).map(\.name))
        for ingredient in sorted {
            for alias in aliases(for: ingredient) where !hints.contains(alias) && !alias.isEmpty {
                guard hints.count < 100 else { return hints }
                hints.append(alias)
            }
        }
        return hints
    }
}
