import Foundation
import SwiftData

@MainActor
struct IngredientMasterImporter {
    static func bundledData(in bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: "ingredient-master-v1", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        var catalog = try IngredientCatalog.decode(Data(contentsOf: url))
        guard let additionsURL = bundle.url(forResource: "ingredient-additions-v1", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let additions = try JSONDecoder().decode(IngredientAdditions.self, from: Data(contentsOf: additionsURL))
        guard Set(additions.aliasesByKey.keys).isSubset(of: Set(catalog.ingredients.map(\.key))) else {
            throw CatalogError.invalidCatalog
        }
        for index in catalog.ingredients.indices {
            let old = catalog.ingredients[index].aliases
            catalog.ingredients[index].aliases = old + (additions.aliasesByKey[catalog.ingredients[index].key] ?? []).filter { !old.contains($0) }
        }
        catalog.ingredients += additions.ingredients
        catalog.catalogVersion = additions.catalogVersion
        let data = try JSONEncoder().encode(catalog)
        _ = try IngredientCatalog.decode(data)
        return data
    }

    /// Uses a dedicated context so import failures never discard the user's pending edits.
    @discardableResult
    static func load(into container: ModelContainer, data: Data? = nil) throws -> Int {
        let catalog = try IngredientCatalog.decode(data ?? bundledData())
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let existing = try context.fetch(FetchDescriptor<IngredientMaster>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
        // Validate every identity before mutating anything. Missing catalog entries are retained.
        for seed in catalog.ingredients {
            if let old = byID[seed.id], old.key != seed.key { throw CatalogError.changedIdentity }
            if let old = byKey[seed.key], old.id != seed.id { throw CatalogError.changedIdentity }
        }
        do {
            for seed in catalog.ingredients {
                if let old = byID[seed.id] {
                    old.update(from: seed, catalogVersion: catalog.catalogVersion)
                } else {
                    context.insert(IngredientMaster(seed: seed, catalogVersion: catalog.catalogVersion))
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return catalog.ingredients.count
    }
}

private struct IngredientAdditions: Decodable {
    let catalogVersion: String
    let aliasesByKey: [String: [String]]
    let ingredients: [IngredientSeed]
}
