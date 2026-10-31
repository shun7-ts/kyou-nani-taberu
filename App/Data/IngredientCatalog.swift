import Foundation

struct IngredientCatalog: Codable {
    var schemaVersion: Int
    var catalogVersion: String
    var locale: String
    var masterIdNamespace: String
    var ingredients: [IngredientSeed]

    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1 else { throw CatalogError.unsupportedSchema }
        guard catalog.locale == "ja-JP", !catalog.ingredients.isEmpty,
              catalog.catalogVersion.range(of: #"^\d+\.\d+\.\d+$"#,
                                           options: .regularExpression) != nil else {
            throw CatalogError.invalidCatalog
        }
        var ids = Set<UUID>()
        var keys = Set<String>()
        for item in catalog.ingredients {
            guard ids.insert(item.id).inserted, keys.insert(item.key).inserted else {
                throw CatalogError.duplicateIdentity
            }
            guard item.key.range(of: #"^[a-z][a-z0-9_]*$"#, options: .regularExpression) != nil,
                  !item.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.allowedUnits.contains(item.defaultUnit),
                  Set(item.allowedUnits).count == item.allowedUnits.count else {
                throw CatalogError.invalidCatalog
            }
        }
        return catalog
    }
}

struct IngredientSeed: Codable {
    var id: UUID
    var key: String
    var canonicalName: String
    var aliases: [String]
    var category: IngredientCategory
    var defaultUnit: IngredientUnit
    var allowedUnits: [IngredientUnit]
    var defaultStorage: StorageMethod
    var stockMode: StockMode
    var isPantryStaple: Bool
    var trackInventory: Bool
    var shoppingEligible: Bool
    var allergens: [String]
    var status: IngredientStatus
}

enum CatalogError: LocalizedError {
    case missingResource, unsupportedSchema, invalidCatalog, duplicateIdentity, changedIdentity
    var errorDescription: String? {
        switch self {
        case .missingResource: "同梱の食材データが見つかりません。"
        case .unsupportedSchema: "食材データの形式に対応していません。"
        case .invalidCatalog: "食材データの内容が不正です。"
        case .duplicateIdentity: "食材データのIDまたはキーが重複しています。"
        case .changedIdentity: "食材の固定IDとキーが既存データと一致しません。"
        }
    }
}

/// Search only: canonical names and curated readings keep kanji matches unambiguous.
enum IngredientSearch {
    static func normalized(_ text: String) -> String {
        let half = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let kana = half.applyingTransform(.hiraganaToKatakana, reverse: true) ?? half
        return kana.lowercased().filter { !$0.isWhitespace }
    }
    static func matches(_ query: String, names: [String]) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { normalized(String($0)) }
        let targets = names.map(normalized)
        return words.allSatisfy { word in targets.contains { $0.contains(word) } }
    }
}


enum IngredientStockFilter: String, CaseIterable {
    case all, stocked, absent
    var label: String {
        switch self { case .all: "すべて"; case .stocked: "冷蔵庫にある"; case .absent: "冷蔵庫にない" }
    }
    func includes(_ id: UUID, stocked: Set<UUID>) -> Bool {
        switch self { case .all: true; case .stocked: stocked.contains(id); case .absent: !stocked.contains(id) }
    }
}


enum IngredientPickerSort: String, CaseIterable {
    case stocked, category, name
    var label: String {
        switch self { case .stocked: "冷蔵庫優先"; case .category: "種類順"; case .name: "名前順" }
    }
}
enum IngredientPickerOrder {
    static func rank(_ category: IngredientCategory) -> Int {
        switch category {
        case .meat: 0; case .fish: 1; case .vegetable: 2; case .mushroom: 3
        case .eggDairy: 4; case .soyProduct: 5; case .staple: 6
        case .processed: 7; case .other: 8; case .seasoning: 9
        }
    }
    static func precedes(_ lhs: IngredientMaster, _ rhs: IngredientMaster, stocked: Set<UUID>, sort: IngredientPickerSort = .stocked) -> Bool {
        if sort == .stocked && stocked.contains(lhs.id) != stocked.contains(rhs.id) { return stocked.contains(lhs.id) }
        if sort != .name && rank(lhs.category) != rank(rhs.category) { return rank(lhs.category) < rank(rhs.category) }
        let comparison = lhs.canonicalName.localizedStandardCompare(rhs.canonicalName)
        return comparison == .orderedSame ? lhs.key < rhs.key : comparison == .orderedAscending
    }
}
