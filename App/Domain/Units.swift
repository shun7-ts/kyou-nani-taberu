import Foundation

enum Units {
    static func convert(_ quantity: Double, from: IngredientUnit, to: IngredientUnit) -> Double? {
        guard quantity.isFinite, quantity >= 0 else { return nil }
        if from == to { return quantity }
        switch (from, to) {
        case (.kilogram, .gram), (.liter, .milliliter): return quantity * 1000
        case (.gram, .kilogram), (.milliliter, .liter): return quantity / 1000
        default: return nil
        }
    }
}
