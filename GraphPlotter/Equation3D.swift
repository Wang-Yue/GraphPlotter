import SwiftUI

/// Represents a 3D equation z = f(x, y) to be plotted as a surface.
struct Equation3D: Identifiable {
    let id = UUID()
    var text: String
    var colorScheme: SurfaceColorScheme = .rainbow

    /// Pre-compiled evaluator function taking (x, y) -> z.
    var evaluator: ((Double, Double) -> Double?)?

    init(text: String = "") {
        self.text = text
        self.evaluator = try? ExpressionParser.compile2D(text)
    }

    mutating func updateExpression(_ newText: String) {
        text = newText
        evaluator = try? ExpressionParser.compile2D(newText)
    }

    var isValid: Bool {
        evaluator != nil && !text.isEmpty
    }
}

enum SurfaceColorScheme: String, CaseIterable {
    case rainbow = "Rainbow"
    case coolWarm = "Cool-Warm"
    case terrain = "Terrain"
    case monochrome = "Mono"
}
