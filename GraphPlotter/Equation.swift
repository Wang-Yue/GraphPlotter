import SwiftUI

enum EquationType {
    case explicit    // y = f(x)
    case implicit    // f(x, y) = 0
}

/// Represents a single equation to be plotted.
struct Equation: Identifiable {
    let id = UUID()
    var text: String
    var color: Color
    var isVisible: Bool = true
    var type: EquationType = .explicit

    /// Evaluator for explicit equations: f(x) -> y
    var evaluator: ((Double) -> Double?)?

    /// Evaluator for implicit equations: f(x, y) -> value (contour at 0)
    var implicitEvaluator: ((Double, Double) -> Double?)?

    init(text: String = "", color: Color = .blue) {
        self.text = text
        self.color = color
        compile(text)
    }

    mutating func updateExpression(_ newText: String) {
        text = newText
        compile(newText)
    }

    private mutating func compile(_ expr: String) {
        evaluator = nil
        implicitEvaluator = nil

        guard !expr.isEmpty else { return }

        if let eqIndex = expr.firstIndex(of: "=") {
            // Implicit equation: "lhs = rhs" → f(x,y) = lhs - rhs
            let lhs = String(expr[expr.startIndex..<eqIndex]).trimmingCharacters(in: .whitespaces)
            let rhs = String(expr[expr.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

            // Build "lhs - (rhs)" so f(x,y) = 0 at the curve
            let combined: String
            if rhs.isEmpty || rhs == "0" {
                combined = lhs
            } else {
                combined = "(\(lhs))-(\(rhs))"
            }

            if let eval = try? ExpressionParser.compile2D(combined) {
                type = .implicit
                implicitEvaluator = eval
                return
            }
        }

        // Try as explicit y = f(x) — only uses x variable
        if let eval = try? ExpressionParser.compile(expr) {
            type = .explicit
            evaluator = eval
        }
    }

    var isValid: Bool {
        !text.isEmpty && (evaluator != nil || implicitEvaluator != nil)
    }
}

/// Predefined colors for equations.
extension Color {
    static let graphColors: [Color] = [
        .blue, .red, .green, .orange, .purple, .cyan, .pink, .yellow
    ]
}
