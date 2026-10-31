import Foundation

struct InventoryPresets: Decodable {
    let schemaVersion: Int
    let sections: [Section]
    struct Section: Decodable, Identifiable {
        let id: String
        let mode: String
        let title: String
        let collapsedByDefault: Bool
        let groupSelectionEnabled: Bool
        let items: [Item]
    }
    struct Item: Decodable, Identifiable {
        var id: String { ingredientKey }
        let ingredientKey: String
        let label: String
    }
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "initial-inventory-presets-v1", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let presets = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard presets.schemaVersion == 1 else { throw CatalogError.unsupportedSchema }
        return presets
    }
}
