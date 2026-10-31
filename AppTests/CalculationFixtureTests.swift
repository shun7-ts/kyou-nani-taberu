import XCTest
@testable import KyouNaniTaberu

@MainActor
final class CalculationFixtureTests: XCTestCase {
    struct Fixtures: Decodable {
        let unitConversions: [Conversion]
        let scalingCases: [Scaling]
        let availabilityCases: [AvailabilityCase]
        struct Conversion: Decodable {
            let id: String; let sourceQuantity: Double; let sourceUnit: IngredientUnit; let targetUnit: IngredientUnit
            let expectedStatus: String; let expectedQuantity: Double?
        }
        struct Scaling: Decodable {
            let id: String; let recipeKey: String; let servings: Int; let ingredientKey: String
            let expectedQuantity: Double; let expectedUnit: IngredientUnit
        }
        struct AvailabilityCase: Decodable {
            let id: String; let recipeKey: String; let servings: Int; let ingredientKey: String
            let lots: [Lot]; let expected: Expected
            struct Lot: Decodable {
                let id: String; let quantity: Double?; let unit: IngredientUnit?
                let roughState: String?; let expiresInDays: Int?; let storage: StorageMethod
            }
            struct Expected: Decodable {
                let status: String; let shortageQuantity: Double?; let unit: IngredientUnit?
                let consumptionOrder: [String]?; let thawing: String
            }
        }
    }
    func testAll24SharedCalculationCasesInSwift() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "calculation-test-cases-v1", withExtension: "json"))
        let cases = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        let recipes = try RecipeCatalog.load()
        for test in cases.unitConversions {
            let result = Units.convert(test.sourceQuantity, from: test.sourceUnit, to: test.targetUnit)
            if let expected = test.expectedQuantity { XCTAssertEqual(try XCTUnwrap(result), expected, accuracy: 1e-9, test.id) }
            else { XCTAssertNil(result, test.id) }
        }
        for test in cases.scalingCases {
            let recipe = try XCTUnwrap(recipes.first { $0.key == test.recipeKey })
            let ingredient = try XCTUnwrap(recipe.ingredients.first { $0.ingredientKey == test.ingredientKey })
            XCTAssertEqual(ingredient.amount(servings: test.servings, base: recipe.baseServings), test.expectedQuantity, accuracy: 1e-9, test.id)
            XCTAssertEqual(ingredient.unit, test.expectedUnit, test.id)
        }
        let now = Date.now
        for test in cases.availabilityCases {
            let recipe = try XCTUnwrap(recipes.first { $0.key == test.recipeKey })
            let ingredient = try XCTUnwrap(recipe.ingredients.first { $0.ingredientKey == test.ingredientKey })
            let ids = test.lots.map { _ in UUID() }
            let lots = test.lots.enumerated().map { index, lot in
                StockLot(id: ids[index], quantity: lot.quantity, unit: lot.unit,
                    roughState: lot.roughState == "none" ? .unavailable : lot.roughState.flatMap(RoughStockState.init(rawValue:)),
                    storage: lot.storage,
                    expiresAt: lot.expiresInDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: now) },
                    purchasedAt: now)
            }
            let result = RecipeAvailability.evaluate(ingredient, servings: test.servings, base: recipe.baseServings, lots: lots, on: now)
            XCTAssertEqual(result.status.rawValue, test.expected.status, test.id)
            if let expected = test.expected.shortageQuantity { XCTAssertEqual(result.shortage, expected, accuracy: 1e-9, test.id) }
            if let unit = test.expected.unit { XCTAssertEqual(result.unit, unit, test.id) }
            if let order = test.expected.consumptionOrder {
                XCTAssertEqual(result.consumption.map { test.lots[ids.firstIndex(of: $0.id)!].id }, order, test.id)
            }
            XCTAssertEqual(result.thawing, test.expected.thawing, test.id)
        }
    }
    func testRoughQuantityRequiresConfirmationAndExpiredStockIsExcluded() throws {
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "teriyaki_chicken" })
        let ingredient = try XCTUnwrap(recipe.ingredients.first { $0.ingredientKey == "chicken_thigh" })
        XCTAssertEqual(RecipeAvailability.evaluate(ingredient, servings: 1,
            lots: [StockLot(id: UUID(), roughState: .available)]).status, .confirmation)
        let expired = StockLot(id: UUID(), quantity: 999, unit: .gram,
            expiresAt: Calendar.current.date(byAdding: .day, value: -1, to: .now))
        XCTAssertEqual(RecipeAvailability.evaluate(ingredient, servings: 1, lots: [expired]).shortage, 180)
    }
    func testRoughStockMatchesButDoesNotGuaranteeEnoughQuantity() throws {
        let recipe = try XCTUnwrap(RecipeCatalog.load().first { $0.key == "teriyaki_chicken" })
        let ingredient = try XCTUnwrap(recipe.ingredients.first { $0.ingredientKey == "chicken_thigh" })
        let rough = [StockLot(id: UUID(), roughState: .available)]
        XCTAssertTrue(RecipeAvailability.matches(ingredient, lots: rough))
        XCTAssertEqual(RecipeAvailability.evaluate(ingredient, servings: 1, lots: rough).status, .confirmation)
        XCTAssertFalse(RecipeAvailability.matches(ingredient, lots: [StockLot(id: UUID(), roughState: .low)]))
    }

}
