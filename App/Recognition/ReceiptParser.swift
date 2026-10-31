import Foundation

struct ReceiptIngredient {
    let id: UUID
    let name: String
    let aliases: [String]
    let unit: IngredientUnit
    let allowedUnits: [IngredientUnit]
    let storage: StorageMethod
    var category: IngredientCategory = .other
}

struct ReceiptRow: Identifiable {
    let id: UUID
    var source: String
    var masterID: UUID?
    var name: String
    var category: IngredientCategory = .other
    var included: Bool
    var confirmed = false
    var suggestedMasterIDs: [UUID] = []
    var exact = false
    var quantity = ""
    var unit: IngredientUnit = .piece
    var rough: RoughStockState = .available
    var storage: StorageMethod = .refrigerated
    var purchasedAt = Date.now
    var expiresAt: Date?
    var expiryKind: ExpiryKind = .unspecified
    var merge = true
    var storageOverridden = false
    var purchaseDateOverridden = false
    var reason: String
    init(id: UUID = UUID(), source: String = "手入力", masterID: UUID? = nil, name: String = "",
         included: Bool = true, reason: String = "食材と量を確認してください") {
        self.id = id; self.source = source; self.masterID = masterID; self.name = name
        self.included = included; self.reason = reason
    }
}

enum ReceiptError: LocalizedError {
    case noText, noProducts, invalidImage, tooLarge, tooManyRows, unconfirmed, alreadySaved, invalidRow
    var errorDescription: String? {
        switch self {
        case .noText: "文字を読み取れませんでした。明るい場所で撮った写真を選ぶか、手入力してください。"
        case .noProducts: "商品を見つけられませんでした。商品名と価格の部分を撮り直すか、手入力してください。"
        case .invalidImage: "この写真を読み込めませんでした。別の写真を選んでください。"
        case .tooLarge: "写真が大きすぎます。レシート部分を切り抜いた写真を選んでください。"
        case .tooManyRows: "項目が多いため、レシートを分けて読み取ってください。"
        case .unconfirmed: "登録するすべての項目で、食材と量を確認してください。"
        case .alreadySaved: "この読み取り結果は登録済みです。"
        case .invalidRow: "食材名・数量・単位を確認してください。"
        }
    }
}

enum ReceiptParser {
    private struct Line {
        let source: String
        let folded: String
        let key: String
        init(_ source: String) {
            self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
            folded = self.source.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
            key = ReceiptParser.normalized(self.source)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*※●○◆◇★☆・:："))
        }
        func matches(_ pattern: String) -> Bool {
            let kanaPattern = pattern.applyingTransform(.hiraganaToKatakana, reverse: false) ?? pattern
            return key.range(of: kanaPattern, options: .regularExpression) != nil
        }
        var endsProducts: Bool {
            matches(#"^小計(?=$|[:¥￥0-9（(]|金額|額|税込|税抜)|^(小計|合計|総合計|総額|お会計|お支払[イい]?|支払[イい]?|現金|カード|paypay|電子マネー)$|^(小計|合計|総合計|総額|お会計|paypay|お買上[ゲげ]?|お支払[イい]?|支払[イい]?|現金|カード|visa|mastercard|jcb|クレジット(?:売上)?|電子マネー|お預[リりカか]?|預[リり]|お釣[リり]?|釣[リり])(?:金額|額|合計|計|税込|[（(]税込[）)])?[:¥￥0-9+−-]"#)
        }
        var metadata: Bool {
            guard !key.isEmpty else { return true }
            // Apply structural rules before looking for food aliases. A shop, address or advert
            // can itself contain words such as 「レモン」 or 「米」.
            if endsProducts { return true }
            if matches(#"^(小計|内税|外税|税抜|税込|税額|消費税|対象額|対象金額|課税|非課税|軽減税率|税率|税対象|領収|レシート|お買上|お買イ上|買上点数|買上数|取引|伝票|レジ|担当|責任者|会員|顧客|電話|tel|fax|住所|店舗|店名|営業時間|登録番号|事業者番号|適格請求|承認番号|端末番号|伝票番号|カード番号|カード会社|クレジット|電子マネー|paypay|交通系|残高|チャージ|支払方法|支払区分|利用控|ポイント|保有ポイント|今回ポイント|累計ポイント|付与ポイント|利用ポイント|値引|値下|割引|割戻|クーポン|サービス券|返品合計|返金合計)"#) { return true }
            if matches(#"^(内|外|うち)?[（(]?[0-9]+(?:\.[0-9]+)?%|^[（(](内|外|税)|^t[0-9]{13}$"#) { return true }
            if matches(#"^[〒0-9¥￥.,:;/+−%*#()（）-]+(円|点|個|枚|月|日|年|曜日)*$|^〒|^[0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}|^[0-9]{1,2}:[0-9]{2}|^[0-9]{2,4}-[0-9]{2,4}-[0-9]{3,4}"#) { return true }
            if matches(#"(都|道|府|県).+(市|区|郡)|[市区町村].*[0-9]+(丁目|番地|番|号)|[0-9]+丁目|https?://|www\.|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|株式会社|有限会社|[（(]株[）)]"#) { return true }
            if matches(#"(スーパー|マーケット|ストア|センター|本店|支店|店|食品館|青果|青果市場|精肉|鮮魚)$|^(スーパー|マーケット|ストア)|御来店|ご来店|来店|アリガトウ|ありがとう|マタノ|またの|毎度|イラッシャイ|いらっしゃい|本日.*(オススメ|おすすめ|特価)|次回|キャンペーン|抽選|アンケート|お問[イい]合[ワわ]せ|お客様|お客サマ|会員募集|求人|チラシ|広告|セール|割引対象|軽減税率対象|※.*対象"#) { return true }
            return false
        }
        var priceOnly: Bool {
            matches(#"^[¥￥]?[+−-]?[0-9][0-9,]{0,8}(\.[0-9]{1,2})?円?[*※軽外内]*$"#)
        }
        var hasPrice: Bool {
            folded.range(of: #"[¥￥]\s*[+−-]?\s*[0-9]|[0-9][0-9,]*\s*円|\s[+−-]?[0-9][0-9,]*(?:\.[0-9]{1,2})?\s*[*※軽外内]*$"#, options: .regularExpression) != nil
        }
        var needsProductChoice: Bool {
            // The ingredient is only part of these product names, not the product itself.
            matches(#"c[.]?c[.]?レモン|ジュース|ソーダ|サイダー|スカッシュ|炭酸飲料|フレーバー|洗剤|洗浄|漂白|シャンプー|芳香|石[鹸けん]|セッケン|スポンジ"#)
        }
        var isShoppingBag: Bool {
            // Exclude known bag charges, not arbitrary 「袋」: foods such as 油揚げ・袋麺 stay usable.
            let label = ReceiptParser.unvoiced(key)
            return label.range(of: #"レシ(?:袋|フクロ|[・._-]?ハ[ッツ]?ク|用袋)|買イ?物(?:袋|フクロ)|ショッヒンク[・._-]?(?:ハ[ッツ]?ク|袋)|ヒニ[ー]?ル(?:袋|フクロ)|ホリ(?:袋|フクロ)|有料(?:袋|フクロ)|手(?:提ケ?|サケ)(?:袋|フクロ|ハ[ッツ]?ク)|エコハ[ッツ]?ク|袋代|袋料金|袋[（(]有料"#,
                options: .regularExpression) != nil
        }
    }
    private static let quantityRegex = try! NSRegularExpression(pattern: #"([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?)\s*(kg|ml|g|l|個|枚|袋|缶|パック|丁|束)"#)

    static func normalized(_ text: String) -> String {
        text.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
            .applyingTransform(.hiraganaToKatakana, reverse: false)?
            .filter { !$0.isWhitespace } ?? text
    }
    /// OCR-only tolerance. Missing dakuten/handakuten widens suggestions, never auto-selects a food.
    private static func unvoiced(_ text: String) -> String {
        String(String.UnicodeScalarView(normalized(text).decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            $0.value != 0x3099 && $0.value != 0x309A
        }))
    }
    static func searchMatches(_ query: String, names: [String]) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { unvoiced(String($0)) }
        let targets = names.map(unvoiced)
        return words.allSatisfy { word in targets.contains { $0.contains(word) } }
    }
    /// Explicit ingredient selection keeps edited dates/storage and compatible quantities.
    static func resolving(_ draft: ReceiptRow, as ingredient: ReceiptIngredient) -> ReceiptRow {
        var row = draft
        row.masterID = ingredient.id; row.name = ingredient.name; row.category = ingredient.category
        row.included = true; row.confirmed = false; row.suggestedMasterIDs = []
        if !row.exact || !ingredient.allowedUnits.contains(row.unit) {
            row.exact = false; row.quantity = ""; row.unit = ingredient.unit
            let input = row.source.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
            let quantities = quantityRegex.matches(in: input, range: NSRange(input.startIndex..., in: input))
            let units: [String: IngredientUnit] = ["kg": .kilogram, "g": .gram, "ml": .milliliter, "l": .liter,
                "個": .piece, "枚": .slice, "袋": .bag, "缶": .can, "パック": .pack, "丁": .block, "束": .bunch]
            if quantities.count == 1, !input.contains("×"), !input.contains("点"),
               input.range(of: #"[x*]\s*\d|\d\s*(本|セット|組)"#, options: .regularExpression) == nil,
               let valueRange = Range(quantities[0].range(at: 1), in: input),
               let unitRange = Range(quantities[0].range(at: 2), in: input),
               let unit = units[String(input[unitRange])], ingredient.allowedUnits.contains(unit),
               let value = Double(input[valueRange].replacingOccurrences(of: ",", with: "")), value > 0 {
                row.exact = true; row.quantity = String(value); row.unit = unit
            }
        }
        if row.source.range(of: #"[−-]\s*\d|返品|返金|取消"#, options: .regularExpression) != nil {
            row.included = false; row.exact = false
        }
        return row
    }
    static func parse(_ lines: [String], ingredients: [ReceiptIngredient]) throws -> [ReceiptRow] {
        guard lines.count <= 120 else { throw ReceiptError.tooManyRows }
        let inputLines = lines.map(Line.init).filter { !$0.source.isEmpty }
        let indexed = ingredients.map { ingredient in
            (ingredient: ingredient, keys: Set(([ingredient.name] + ingredient.aliases).map(normalized)),
                unvoicedKeys: Set(([ingredient.name] + ingredient.aliases).map(unvoiced)))
        }
        var ended = false
        var rows: [ReceiptRow] = []
        for (index, line) in inputLines.enumerated() {
            // Totals/payment delimit the end of the products, even if a footer advert has a price.
            if line.endsProducts { ended = true }
            guard !ended, !line.metadata, !line.priceOnly, !line.isShoppingBag else { continue }
            let text = line.source, normalizedText = line.key
            let matches = indexed.filter { entry in
                entry.keys.contains { key in
                    if key.count >= 2 { return normalizedText.contains(key) }
                    guard key.count == 1, normalizedText.hasPrefix(key) else { return false }
                    let remainder = normalizedText.dropFirst()
                    return remainder.isEmpty || remainder.first.map { $0.isNumber || "¥￥@".contains($0) } == true
                }
            }.map(\.ingredient)
            // Unknown text needs evidence of a product row. OCR sometimes separates its price.
            // Known foods remain usable without a price; price is never interpreted as quantity.
            let nextIsPrice = inputLines.indices.contains(index + 1) && inputLines[index + 1].priceOnly
            let unvoicedText = unvoiced(normalizedText)
            let suggestions = line.needsProductChoice ? [] : (matches.isEmpty ? indexed.filter { entry in
                entry.unvoicedKeys.contains { $0.count >= 3 && unvoicedText.contains($0) }
            }.map(\.ingredient) : matches)
            guard !matches.isEmpty || !suggestions.isEmpty || line.hasPrice || nextIsPrice else { continue }
            let ingredient = matches.count == 1 && !line.needsProductChoice ? matches[0] : nil
            var row = ReceiptRow(source: text, masterID: ingredient?.id,
                name: ingredient?.name ?? "", included: ingredient != nil,
                reason: ingredient == nil ? "食材未確定・非食品の可能性。登録する場合は食材を選んでください" : "食材候補が一致。数量や商品違いを確認してください")
            row.suggestedMasterIDs = ingredient == nil ? suggestions.map(\.id) : []
            if let ingredient {
                row.storage = ingredient.storage
                row = resolving(row, as: ingredient)
            }
            if text.range(of: #"[−-]\s*\d|返品|返金|取消"#, options: .regularExpression) != nil {
                row.included = false; row.exact = false
                row.reason = "返品・取消の可能性があります。内容を確認してください"
            }
            rows.append(row)
        }
        return rows
    }
}
