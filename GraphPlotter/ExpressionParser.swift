import Foundation

/// A recursive-descent parser and evaluator for mathematical expressions.
///
/// `ExpressionParser` takes a string like `"x^2 + sin(x)"` and compiles it into
/// a fast closure `(Double) -> Double?` (or `(Double, Double) -> Double?` for two
/// variables). The closure can then be called millions of times to plot graphs
/// without re-parsing.
///
/// # Architecture Overview
///
/// The parser works in two phases:
///
/// 1. **Tokenization** (`tokenize`): Converts the raw string into a flat array
///    of `Token` values. For example, `"2x + sin(pi)"` becomes:
///    ```
///    [.number(2), .variable, .op("+"), .function("sin"), .leftParen, .number(π), .rightParen]
///    ```
///
/// 2. **Parsing** (`parseExpression` and friends): Walks the token array using
///    recursive descent, building a tree of closures that mirrors the mathematical
///    structure. Each closure takes `(x, y) -> Double` and computes one sub-expression.
///
/// # Supported Syntax
///
/// **Operators** (in order of increasing precedence):
/// - `+`, `-`  — addition, subtraction (lowest precedence)
/// - `*`, `/`  — multiplication, division
/// - `^`       — exponentiation (right-associative, so `2^3^2` = `2^(3^2)` = 512)
/// - Unary `-` — negation (e.g., `-x`, `-(x+1)`)
///
/// **Implicit multiplication** — a `*` sign is not required between:
/// - A number and a variable: `2x` → `2 * x`
/// - A number and a function: `3sin(x)` → `3 * sin(x)`
/// - A number and a parenthesized group: `2(x+1)` → `2 * (x+1)`
/// - A variable and a parenthesized group: `x(x+1)` → `x * (x+1)`
///
/// **Variables:**
/// - `x` — primary variable (used in both 1D and 2D modes)
/// - `y` — secondary variable (used in 2D mode for implicit/3D equations)
///
/// **Constants:**
/// - `pi` → `Double.pi` (3.14159...)
/// - `e`  → Euler's number (2.71828...)
///
/// **Functions** (must be followed by parentheses):
/// - Trigonometric: `sin(x)`, `cos(x)`, `tan(x)`
/// - Inverse trig:  `asin(x)`, `acos(x)`, `atan(x)`
/// - Exponential:   `exp(x)` (e^x), `ln(x)` (natural log), `log(x)` (log base 10)
/// - Other:         `sqrt(x)`, `abs(x)`, `floor(x)`, `ceil(x)`, `sign(x)`
///
/// # Usage Examples
///
/// **Quick one-off evaluation (1D):**
/// ```swift
/// // Evaluate x^2 + 1 at x = 3  →  10.0
/// let result = ExpressionParser.evaluate("x^2 + 1", x: 3)
/// ```
///
/// **Compile once, evaluate many times (1D) — used for plotting y = f(x):**
/// ```swift
/// let f = try ExpressionParser.compile("sin(x)/x")
///
/// // Plot 1000 points
/// for i in 0..<1000 {
///     let x = -10 + 20 * Double(i) / 999
///     if let y = f(x) {
///         plot(x, y)  // f returns nil for NaN/Infinity (e.g., x=0 for 1/x)
///     }
/// }
/// ```
///
/// **Compile a two-variable expression (2D) — used for implicit curves and 3D surfaces:**
/// ```swift
/// // Implicit circle: x^2 + y^2 - 4 = 0
/// let f = try ExpressionParser.compile2D("x^2 + y^2 - 4")
///
/// // Evaluate at a grid point
/// if let value = f(1.0, 1.0) {
///     // value = 1 + 1 - 4 = -2.0  (inside the circle, since < 0)
/// }
///
/// // 3D surface: z = sin(x) * cos(y)
/// let surface = try ExpressionParser.compile2D("sin(x)*cos(y)")
/// if let z = surface(Double.pi / 2, 0) {
///     // z = sin(π/2) * cos(0) = 1.0
/// }
/// ```
///
/// **Implicit multiplication:**
/// ```swift
/// // All equivalent to "2 * x^2 + 3 * sin(x)"
/// ExpressionParser.evaluate("2x^2 + 3sin(x)", x: 1)
/// ExpressionParser.evaluate("2*x^2 + 3*sin(x)", x: 1)
/// ```
///
/// **Error handling:**
/// ```swift
/// do {
///     let f = try ExpressionParser.compile("sin(")
/// } catch {
///     print(error.localizedDescription)
///     // "expected ')' after function argument"
/// }
///
/// // Returns nil for undefined results (not a crash)
/// let f = try ExpressionParser.compile("1/x")
/// f(0)   // nil  (division by zero → Infinity → filtered out)
/// f(2)   // 0.5
/// ```
///
/// # Grammar (Formal Specification)
///
/// The parser implements this precedence-climbing grammar, listed from
/// lowest to highest precedence:
///
/// ```
/// expression = term (('+' | '-') term)*
/// term       = power (('*' | '/') power)*
///            | power  variable                    // implicit multiply: 2x
///            | power  function '(' expression ')' // implicit multiply: 2sin(x)
///            | power  '(' expression ')'          // implicit multiply: 2(x+1)
/// power      = unary ('^' power)?                 // right-associative
/// unary      = ('-' | '+')? atom
/// atom       = NUMBER
///            | 'x'                                // variable
///            | 'y'                                // variable (2D)
///            | FUNCTION '(' expression ')'
///            | '(' expression ')'
/// ```
///
/// Right-associativity of `^` means `2^3^2` parses as `2^(3^2)` = 512, not
/// `(2^3)^2` = 64. This matches standard mathematical convention.
///
/// # Implementation Notes
///
/// - All internal evaluator closures use the signature `(Double, Double) -> Double`
///   where the two parameters are `(x, y)`. The 1D `compile` method simply wraps
///   this by always passing `y = 0`, so there is no code duplication between 1D and 2D.
///
/// - The parser returns closures rather than an AST node tree. This avoids the overhead
///   of tree traversal and virtual dispatch during evaluation, which matters when the
///   closure is called millions of times per frame for plotting.
///
/// - Results of `NaN` or `Infinity` are mapped to `nil` by the public `compile`/`compile2D`
///   methods. This lets the graph renderer skip undefined points (e.g., `sqrt(-1)`, `1/0`,
///   `tan(π/2)`) instead of drawing garbage.
struct ExpressionParser {

    /// The flat list of tokens produced by the tokenizer.
    private let tokens: [Token]

    /// Current read position in the `tokens` array, advanced as the parser consumes tokens.
    private var position: Int = 0

    /// A token is the smallest meaningful unit of an expression.
    ///
    /// The tokenizer converts raw characters into these typed values so the parser
    /// doesn't have to deal with string manipulation.
    ///
    /// Example: `"2x + sin(pi)"` tokenizes to:
    /// ```
    /// [.number(2), .variable, .op("+"), .function("sin"),
    ///  .leftParen, .number(3.14159...), .rightParen]
    /// ```
    /// Note that `pi` is resolved to its numeric value during tokenization,
    /// so the parser never sees it as a name.
    enum Token: Equatable {
        /// A numeric literal, e.g., `3.14`, `42`. Constants like `pi` and `e`
        /// are also represented as numbers after tokenization.
        case number(Double)

        /// The variable `x` (primary variable, always available).
        case variable

        /// The variable `y` (secondary variable, used in 2D expressions).
        case variableY

        /// A binary or unary operator: `+`, `-`, `*`, `/`, or `^`.
        case op(Character)

        /// An opening parenthesis `(`.
        case leftParen

        /// A closing parenthesis `)`.
        case rightParen

        /// A named function like `sin`, `cos`, `sqrt`, etc.
        /// The associated value is the lowercased function name.
        case function(String)

        /// A comma `,` (reserved for future multi-argument functions).
        case comma
    }

    /// Errors that can occur during tokenization or parsing.
    enum ParseError: Error, LocalizedError {
        /// A character was found that isn't part of the supported syntax.
        /// Example: `"x & 2"` → `.unexpectedCharacter("&")`
        case unexpectedCharacter(Character)

        /// The expression ended before the parser expected it to.
        /// Example: `"sin("` → `.unexpectedEnd` (missing argument and closing paren)
        case unexpectedEnd

        /// A token was found where a different one was expected.
        /// Example: `"sin x"` → `.unexpectedToken("expected '(' after function sin")`
        case unexpectedToken(String)

        /// Division by zero was detected. (Currently unused — division by zero
        /// produces `Infinity`, which is mapped to `nil` by the compile methods.)
        case divisionByZero

        var errorDescription: String? {
            switch self {
            case .unexpectedCharacter(let c): return "Unexpected character: '\(c)'"
            case .unexpectedEnd: return "Unexpected end of expression"
            case .unexpectedToken(let t): return "Unexpected token: \(t)"
            case .divisionByZero: return "Division by zero"
            }
        }
    }

    /// The set of recognized function names. Any multi-letter word that isn't
    /// `x`, `y`, `pi`, or `e` must be in this set, or tokenization will fail.
    private static let functions = Set([
        "sin", "cos", "tan", "asin", "acos", "atan",
        "sqrt", "abs", "ln", "log", "exp", "floor", "ceil", "sign"
    ])

    /// Create a parser by tokenizing the given expression string.
    ///
    /// This is the only initializer. It eagerly tokenizes the entire string;
    /// parsing happens later when `parseExpression()` is called.
    ///
    /// - Throws: `ParseError.unexpectedCharacter` if the string contains
    ///   unsupported characters (e.g., `@`, `#`, `!`).
    init(_ expression: String) throws {
        self.tokens = try ExpressionParser.tokenize(expression)
    }

    // ┌─────────────────────────────────────────────────────────────────┐
    // │ PHASE 1: TOKENIZER                                             │
    // │                                                                 │
    // │ Converts a raw string into an array of Token values.            │
    // │ Handles: numbers, variables, constants, functions, operators,   │
    // │ parentheses, and whitespace (which is simply skipped).          │
    // └─────────────────────────────────────────────────────────────────┘

    /// Converts an expression string into an array of tokens.
    ///
    /// Scans left-to-right through the string, greedily consuming characters:
    /// - Digits and `.` → accumulate into a number literal
    /// - Letters → accumulate into a word, then classify as variable/constant/function
    /// - Operators and parens → emit directly as single-character tokens
    /// - Whitespace → skip silently
    ///
    /// ## Tokenization Examples
    /// ```
    /// "3.14"         → [.number(3.14)]
    /// "2x"           → [.number(2), .variable]
    /// "sin(x)"       → [.function("sin"), .leftParen, .variable, .rightParen]
    /// "pi"           → [.number(3.14159...)]
    /// "-x^2"         → [.op("-"), .variable, .op("^"), .number(2)]
    /// "x^2 + y^2"    → [.variable, .op("^"), .number(2), .op("+"),
    ///                    .variableY, .op("^"), .number(2)]
    /// ```
    private static func tokenize(_ expr: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(expr)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Skip whitespace between tokens
            if c.isWhitespace {
                i += 1
                continue
            }

            // Numbers: greedily consume digits and at most one decimal point.
            // Examples: "42" → 42.0, "3.14" → 3.14, ".5" → 0.5
            if c.isNumber || c == "." {
                var numStr = String(c)
                i += 1
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    numStr.append(chars[i])
                    i += 1
                }
                guard let value = Double(numStr) else {
                    throw ParseError.unexpectedCharacter(c)
                }
                tokens.append(.number(value))
                continue
            }

            // Words: greedily consume letters, then classify the result.
            // - "x" → .variable
            // - "y" → .variableY
            // - "pi" → .number(Double.pi)
            // - "e" → .number(M_E)     (Euler's number)
            // - "sin", "cos", etc. → .function("sin"), .function("cos"), etc.
            // - anything else → error
            if c.isLetter {
                var name = String(c)
                i += 1
                while i < chars.count && chars[i].isLetter {
                    name.append(chars[i])
                    i += 1
                }
                let lower = name.lowercased()
                if lower == "x" {
                    tokens.append(.variable)
                } else if lower == "y" {
                    tokens.append(.variableY)
                } else if lower == "pi" {
                    tokens.append(.number(Double.pi))
                } else if lower == "e" && !functions.contains(lower) {
                    tokens.append(.number(M_E))
                } else if functions.contains(lower) {
                    tokens.append(.function(lower))
                } else {
                    throw ParseError.unexpectedCharacter(c)
                }
                continue
            }

            // Single-character operators and punctuation
            switch c {
            case "+", "-", "*", "/", "^":
                tokens.append(.op(c))
            case "(":
                tokens.append(.leftParen)
            case ")":
                tokens.append(.rightParen)
            case ",":
                tokens.append(.comma)
            default:
                throw ParseError.unexpectedCharacter(c)
            }
            i += 1
        }

        return tokens
    }

    // ┌─────────────────────────────────────────────────────────────────┐
    // │ PHASE 2: RECURSIVE-DESCENT PARSER                              │
    // │                                                                 │
    // │ Consumes tokens and builds a tree of closures. Each closure     │
    // │ takes (x: Double, y: Double) -> Double and computes one node    │
    // │ of the expression tree.                                         │
    // │                                                                 │
    // │ The parser is structured as one function per precedence level:  │
    // │                                                                 │
    // │   parseExpression  (lowest precedence:  + -)                    │
    // │     └─ parseTerm   (medium precedence:  * / and implicit mul)   │
    // │         └─ parsePower (exponentiation:  ^, right-associative)   │
    // │             └─ parseUnary  (unary - +)                          │
    // │                 └─ parseAtom (highest: numbers, vars, funcs)    │
    // │                                                                 │
    // │ Each function calls the one below it, ensuring that higher-     │
    // │ precedence operations bind more tightly. This is the standard   │
    // │ technique for implementing operator precedence in a recursive-  │
    // │ descent parser.                                                 │
    // └─────────────────────────────────────────────────────────────────┘

    // MARK: - Public API

    /// One-shot evaluation: parse and evaluate in a single call.
    ///
    /// Convenience method for when you only need a single value.
    /// For repeated evaluation (e.g., plotting), use `compile` instead.
    ///
    /// ```swift
    /// ExpressionParser.evaluate("x^2 + 1", x: 3)  // → 10.0
    /// ExpressionParser.evaluate("sqrt(-1)", x: 0)  // → nil (NaN)
    /// ```
    ///
    /// - Parameters:
    ///   - expression: The math expression string.
    ///   - x: The value to substitute for `x`.
    /// - Returns: The result, or `nil` if the expression is invalid or produces NaN/Infinity.
    static func evaluate(_ expression: String, x: Double) -> Double? {
        guard var parser = try? ExpressionParser(expression) else { return nil }
        guard let result = try? parser.parseExpression() else { return nil }
        let value = result(x, 0)
        if value.isNaN || value.isInfinite { return nil }
        return value
    }

    /// Compile a one-variable expression into a reusable closure.
    ///
    /// The returned closure takes a single `Double` (the value of `x`) and returns
    /// the result, or `nil` if the result is `NaN` or `Infinity`.
    ///
    /// This is the primary method used by the 2D graph renderer for explicit
    /// equations like `y = sin(x)/x`.
    ///
    /// ```swift
    /// let f = try ExpressionParser.compile("x^2 + 1")
    /// f(0)    // → 1.0
    /// f(3)    // → 10.0
    /// f(-2)   // → 5.0
    ///
    /// let g = try ExpressionParser.compile("1/x")
    /// g(2)    // → 0.5
    /// g(0)    // → nil  (Infinity is filtered out)
    /// ```
    ///
    /// - Parameter expression: The math expression string (should only use `x`).
    /// - Throws: `ParseError` if the expression has syntax errors.
    /// - Returns: A closure `(Double) -> Double?`.
    static func compile(_ expression: String) throws -> (Double) -> Double? {
        var parser = try ExpressionParser(expression)
        let evaluator = try parser.parseExpression()
        guard parser.position >= parser.tokens.count else {
            throw ParseError.unexpectedToken("extra tokens after expression")
        }
        return { x in
            let val = evaluator(x, 0)
            if val.isNaN || val.isInfinite { return nil }
            return val
        }
    }

    /// Compile a two-variable expression into a reusable closure.
    ///
    /// The returned closure takes `(x, y)` and returns the result, or `nil`
    /// for `NaN`/`Infinity`. Used in two contexts:
    ///
    /// 1. **Implicit 2D curves**: For an equation like `x^2 + y^2 = 4`, the caller
    ///    rearranges it to `x^2 + y^2 - 4` and compiles it here. The graph renderer
    ///    then finds the zero contour using marching squares.
    ///
    /// 2. **3D surfaces**: For `z = sin(x)*cos(y)`, the expression `sin(x)*cos(y)`
    ///    is compiled here. The 3D renderer evaluates it on a grid to build a mesh.
    ///
    /// ```swift
    /// // Implicit circle
    /// let circle = try ExpressionParser.compile2D("x^2 + y^2 - 4")
    /// circle(2, 0)    // → 0.0  (on the circle)
    /// circle(0, 0)    // → -4.0 (inside)
    /// circle(3, 0)    // → 5.0  (outside)
    ///
    /// // 3D surface
    /// let surface = try ExpressionParser.compile2D("x*y")
    /// surface(3, 4)   // → 12.0
    /// ```
    ///
    /// - Parameter expression: The math expression string (may use both `x` and `y`).
    /// - Throws: `ParseError` if the expression has syntax errors.
    /// - Returns: A closure `(Double, Double) -> Double?`.
    static func compile2D(_ expression: String) throws -> (Double, Double) -> Double? {
        var parser = try ExpressionParser(expression)
        let evaluator = try parser.parseExpression()
        guard parser.position >= parser.tokens.count else {
            throw ParseError.unexpectedToken("extra tokens after expression")
        }
        return { x, y in
            let val = evaluator(x, y)
            if val.isNaN || val.isInfinite { return nil }
            return val
        }
    }

    // MARK: - Recursive-Descent Parse Methods

    /// Parses an **expression** (lowest precedence level): addition and subtraction.
    ///
    /// Grammar: `expression = term (('+' | '-') term)*`
    ///
    /// This handles chains of `+` and `-`, which are left-associative:
    /// `a - b + c` is parsed as `(a - b) + c`.
    ///
    /// Example parse of `"x + 2 - 1"`:
    /// ```
    /// parseExpression()
    ///   ├─ parseTerm() → closure for "x"
    ///   ├─ sees '+', consumes it
    ///   ├─ parseTerm() → closure for "2"
    ///   ├─ combines into closure for "x + 2"
    ///   ├─ sees '-', consumes it
    ///   ├─ parseTerm() → closure for "1"
    ///   └─ combines into closure for "(x + 2) - 1"
    /// ```
    private mutating func parseExpression() throws -> (Double, Double) -> Double {
        var result = try parseTerm()

        while position < tokens.count {
            if case .op(let c) = tokens[position], c == "+" || c == "-" {
                position += 1
                let right = try parseTerm()
                let left = result
                if c == "+" {
                    result = { x, y in left(x, y) + right(x, y) }
                } else {
                    result = { x, y in left(x, y) - right(x, y) }
                }
            } else {
                break
            }
        }
        return result
    }

    /// Parses a **term** (medium precedence): multiplication, division, and
    /// implicit multiplication.
    ///
    /// Grammar:
    /// ```
    /// term = power (('*' | '/') power)*
    ///      | power variable          // implicit: 2x
    ///      | power function(...)     // implicit: 3sin(x)
    ///      | power '(' expr ')'     // implicit: 2(x+1)
    /// ```
    ///
    /// Implicit multiplication is the key feature that makes expressions read
    /// naturally. When the parser finishes a `power` and sees a variable, function,
    /// or opening paren as the next token — without an explicit operator — it
    /// inserts a multiplication.
    ///
    /// Example parse of `"2x"`:
    /// ```
    /// parseTerm()
    ///   ├─ parsePower() → closure for "2"
    ///   ├─ sees .variable (no explicit '*')
    ///   ├─ parseAtom() → closure for "x"
    ///   └─ combines into closure for "2 * x"    (implicit multiplication)
    /// ```
    ///
    /// Example parse of `"6/3x"` → `(6/3) * x` = `2x`:
    /// ```
    /// parseTerm()
    ///   ├─ parsePower() → closure for "6"
    ///   ├─ sees '/', consumes it
    ///   ├─ parsePower() → closure for "3"
    ///   ├─ combines into closure for "6 / 3"
    ///   ├─ sees .variable (implicit multiply)
    ///   ├─ parseAtom() → closure for "x"
    ///   └─ combines into closure for "(6 / 3) * x"
    /// ```
    private mutating func parseTerm() throws -> (Double, Double) -> Double {
        var result = try parsePower()

        while position < tokens.count {
            if case .op(let c) = tokens[position], c == "*" || c == "/" {
                // Explicit multiplication or division
                position += 1
                let right = try parsePower()
                let left = result
                if c == "*" {
                    result = { x, y in left(x, y) * right(x, y) }
                } else {
                    result = { x, y in left(x, y) / right(x, y) }
                }
            } else if case .leftParen = tokens[position] {
                // Implicit multiplication: "2(x+1)" → "2 * (x+1)"
                let right = try parseAtom()
                let left = result
                result = { x, y in left(x, y) * right(x, y) }
            } else if case .function(_) = tokens[position] {
                // Implicit multiplication: "3sin(x)" → "3 * sin(x)"
                let right = try parseAtom()
                let left = result
                result = { x, y in left(x, y) * right(x, y) }
            } else if case .variable = tokens[position] {
                // Implicit multiplication: "2x" → "2 * x"
                let right = try parseAtom()
                let left = result
                result = { x, y in left(x, y) * right(x, y) }
            } else if case .variableY = tokens[position] {
                // Implicit multiplication: "2y" → "2 * y"
                let right = try parseAtom()
                let left = result
                result = { x, y in left(x, y) * right(x, y) }
            } else {
                break
            }
        }
        return result
    }

    /// Parses a **power** expression: exponentiation.
    ///
    /// Grammar: `power = unary ('^' power)?`
    ///
    /// Note the recursive call to `parsePower` (not `parseUnary`) on the right
    /// side of `^`. This makes exponentiation **right-associative**:
    ///
    /// ```
    /// "2^3^2"  →  2^(3^2)  =  2^9  =  512     (right-associative)
    ///     NOT  →  (2^3)^2  =  8^2  =  64      (would be left-associative)
    /// ```
    ///
    /// Example parse of `"x^2"`:
    /// ```
    /// parsePower()
    ///   ├─ parseUnary() → parseAtom() → closure for "x"
    ///   ├─ sees '^', consumes it
    ///   ├─ parsePower() → parseUnary() → parseAtom() → closure for "2"
    ///   └─ combines into closure for "pow(x, 2)"
    /// ```
    private mutating func parsePower() throws -> (Double, Double) -> Double {
        let base = try parseUnary()

        if position < tokens.count, case .op("^") = tokens[position] {
            position += 1
            let exponent = try parsePower() // Recurse into parsePower for right-associativity
            return { x, y in pow(base(x, y), exponent(x, y)) }
        }
        return base
    }

    /// Parses a **unary** prefix: optional `-` or `+` before an atom.
    ///
    /// Grammar: `unary = ('-' | '+')? atom`
    ///
    /// This handles expressions like `-x`, `-(x+1)`, `-sin(x)`.
    /// A unary `+` is allowed but has no effect.
    ///
    /// Example parse of `"-x"`:
    /// ```
    /// parseUnary()
    ///   ├─ sees '-', consumes it
    ///   ├─ parseAtom() → closure for "x"
    ///   └─ wraps into closure for "-x"  (negation)
    /// ```
    private mutating func parseUnary() throws -> (Double, Double) -> Double {
        if position < tokens.count, case .op(let c) = tokens[position], c == "-" || c == "+" {
            position += 1
            let operand = try parseAtom()
            if c == "-" {
                return { x, y in -operand(x, y) }
            }
            return operand
        }
        return try parseAtom()
    }

    /// Parses an **atom** (highest precedence): the indivisible building blocks.
    ///
    /// Grammar:
    /// ```
    /// atom = NUMBER
    ///      | 'x'
    ///      | 'y'
    ///      | FUNCTION '(' expression ')'
    ///      | '(' expression ')'
    /// ```
    ///
    /// An atom is either a leaf value (number, variable) or a grouped sub-expression
    /// (parentheses, function call). After parsing an atom, control returns to a
    /// higher-level method which may combine it with operators.
    ///
    /// Example parse of `"sin(x + 1)"`:
    /// ```
    /// parseAtom()
    ///   ├─ sees .function("sin"), consumes it
    ///   ├─ sees '(', consumes it
    ///   ├─ parseExpression()        // recurse for the argument
    ///   │   ├─ parseTerm() → ... → closure for "x"
    ///   │   ├─ sees '+', consumes it
    ///   │   ├─ parseTerm() → ... → closure for "1"
    ///   │   └─ returns closure for "x + 1"
    ///   ├─ sees ')', consumes it
    ///   └─ wraps into closure for "sin(x + 1)"
    /// ```
    ///
    /// Example parse of `"(x + 1)"`:
    /// ```
    /// parseAtom()
    ///   ├─ sees '(', consumes it
    ///   ├─ parseExpression() → closure for "x + 1"
    ///   ├─ sees ')', consumes it
    ///   └─ returns the closure directly (parens just group, no wrapping needed)
    /// ```
    private mutating func parseAtom() throws -> (Double, Double) -> Double {
        guard position < tokens.count else {
            throw ParseError.unexpectedEnd
        }

        switch tokens[position] {
        case .number(let value):
            position += 1
            return { _, _ in value }

        case .variable:
            position += 1
            return { x, _ in x }

        case .variableY:
            position += 1
            return { _, y in y }

        case .function(let name):
            position += 1
            guard position < tokens.count, case .leftParen = tokens[position] else {
                throw ParseError.unexpectedToken("expected '(' after function \(name)")
            }
            position += 1 // consume '('
            let arg = try parseExpression() // parse the argument expression
            guard position < tokens.count, case .rightParen = tokens[position] else {
                throw ParseError.unexpectedToken("expected ')' after function argument")
            }
            position += 1 // consume ')'

            // Return a closure that evaluates the argument, then applies the function
            return { x, y in
                let val = arg(x, y)
                switch name {
                case "sin":   return sin(val)
                case "cos":   return cos(val)
                case "tan":   return tan(val)
                case "asin":  return asin(val)
                case "acos":  return acos(val)
                case "atan":  return atan(val)
                case "sqrt":  return sqrt(val)
                case "abs":   return abs(val)
                case "ln":    return log(val)    // natural logarithm
                case "log":   return log10(val)  // base-10 logarithm
                case "exp":   return exp(val)
                case "floor": return floor(val)
                case "ceil":  return ceil(val)
                case "sign":  return val > 0 ? 1 : (val < 0 ? -1 : 0)
                default:      return .nan
                }
            }

        case .leftParen:
            position += 1 // consume '('
            let result = try parseExpression()
            guard position < tokens.count, case .rightParen = tokens[position] else {
                throw ParseError.unexpectedToken("expected ')'")
            }
            position += 1 // consume ')'
            return result

        default:
            throw ParseError.unexpectedToken("unexpected token at position \(position)")
        }
    }
}
