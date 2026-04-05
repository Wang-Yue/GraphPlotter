import SwiftUI

struct GraphView: View {
    let equations: [Equation]
    @Binding var centerX: Double
    @Binding var centerY: Double
    @Binding var scale: Double // pixels per unit

    private let minScale: Double = 10
    private let maxScale: Double = 500

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawAxes(context: context, size: size)
                drawEquations(context: context, size: size)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Coordinate Conversion

    /// Convert math coordinates to screen point.
    private func toScreen(_ mathX: Double, _ mathY: Double, size: CGSize) -> CGPoint {
        let px = size.width / 2 + (mathX - centerX) * scale
        let py = size.height / 2 - (mathY - centerY) * scale
        return CGPoint(x: px, y: py)
    }

    /// Convert screen point to math coordinates.
    private func toMath(_ point: CGPoint, size: CGSize) -> (Double, Double) {
        let mx = centerX + (point.x - size.width / 2) / scale
        let my = centerY - (point.y - size.height / 2) / scale
        return (mx, my)
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridSpacing = niceGridSpacing()
        let (minX, maxY) = toMath(.zero, size: size)
        let (maxX, minY) = toMath(CGPoint(x: size.width, y: size.height), size: size)

        let startX = (minX / gridSpacing).rounded(.down) * gridSpacing
        let startY = (minY / gridSpacing).rounded(.down) * gridSpacing

        let gridColor = Color.gray.opacity(0.15)
        let thinLine = StrokeStyle(lineWidth: 0.5)

        // Vertical grid lines
        var gx = startX
        while gx <= maxX {
            let p1 = toScreen(gx, minY, size: size)
            let p2 = toScreen(gx, maxY, size: size)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path, with: .color(gridColor), style: thinLine)
            gx += gridSpacing
        }

        // Horizontal grid lines
        var gy = startY
        while gy <= maxY {
            let p1 = toScreen(minX, gy, size: size)
            let p2 = toScreen(maxX, gy, size: size)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path, with: .color(gridColor), style: thinLine)
            gy += gridSpacing
        }

        // Grid labels
        let labelColor = Color.secondary
        let font = Font.system(size: 10, design: .monospaced)

        gx = startX
        while gx <= maxX {
            if abs(gx) > gridSpacing * 0.1 {
                let screenPt = toScreen(gx, 0, size: size)
                let label = formatNumber(gx)
                let text = Text(label).font(font).foregroundColor(labelColor)
                context.draw(context.resolve(text), at: CGPoint(x: screenPt.x, y: toScreen(0, 0, size: size).y + 12))
            }
            gx += gridSpacing
        }

        gy = startY
        while gy <= maxY {
            if abs(gy) > gridSpacing * 0.1 {
                let screenPt = toScreen(0, gy, size: size)
                let label = formatNumber(gy)
                let text = Text(label).font(font).foregroundColor(labelColor)
                context.draw(context.resolve(text), at: CGPoint(x: toScreen(0, 0, size: size).x - 20, y: screenPt.y))
            }
            gy += gridSpacing
        }
    }

    private func niceGridSpacing() -> Double {
        let targetPixelSpacing: Double = 80
        let rawSpacing = targetPixelSpacing / scale
        let magnitude = pow(10, floor(log10(rawSpacing)))
        let normalized = rawSpacing / magnitude

        let nice: Double
        if normalized < 1.5 { nice = 1 }
        else if normalized < 3.5 { nice = 2 }
        else if normalized < 7.5 { nice = 5 }
        else { nice = 10 }

        return nice * magnitude
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e6 {
            return String(format: "%g", value)
        }
        return String(format: "%.2g", value)
    }

    // MARK: - Axes

    private func drawAxes(context: GraphicsContext, size: CGSize) {
        let axisColor = Color.primary.opacity(0.6)
        let axisStyle = StrokeStyle(lineWidth: 1.5)

        let origin = toScreen(0, 0, size: size)

        // X axis
        if origin.y >= 0 && origin.y <= size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: origin.y))
            path.addLine(to: CGPoint(x: size.width, y: origin.y))
            context.stroke(path, with: .color(axisColor), style: axisStyle)
        }

        // Y axis
        if origin.x >= 0 && origin.x <= size.width {
            var path = Path()
            path.move(to: CGPoint(x: origin.x, y: 0))
            path.addLine(to: CGPoint(x: origin.x, y: size.height))
            context.stroke(path, with: .color(axisColor), style: axisStyle)
        }

        // Origin label
        let text = Text("0").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
        if origin.x >= 0 && origin.x <= size.width && origin.y >= 0 && origin.y <= size.height {
            context.draw(context.resolve(text), at: CGPoint(x: origin.x - 10, y: origin.y + 12))
        }
    }

    // MARK: - Plot Equations

    private func drawEquations(context: GraphicsContext, size: CGSize) {
        for equation in equations where equation.isVisible && equation.isValid {
            switch equation.type {
            case .explicit:
                drawExplicitEquation(equation, context: context, size: size)
            case .implicit:
                drawImplicitEquation(equation, context: context, size: size)
            }
        }
    }

    // MARK: Explicit: y = f(x)

    private func drawExplicitEquation(_ equation: Equation, context: GraphicsContext, size: CGSize) {
        guard let eval = equation.evaluator else { return }

        let steps = Int(size.width * 2)
        let (minX, _) = toMath(.zero, size: size)
        let (maxX, _) = toMath(CGPoint(x: size.width, y: size.height), size: size)
        let dx = (maxX - minX) / Double(steps)

        var path = Path()
        var isDrawing = false
        var prevScreenY: CGFloat?

        for i in 0...steps {
            let mx = minX + Double(i) * dx
            guard let my = eval(mx) else {
                isDrawing = false
                prevScreenY = nil
                continue
            }

            let screenPt = toScreen(mx, my, size: size)

            let margin = size.height * 3
            if screenPt.y < -margin || screenPt.y > size.height + margin {
                isDrawing = false
                prevScreenY = nil
                continue
            }

            if let prev = prevScreenY, abs(screenPt.y - prev) > size.height * 0.8 {
                isDrawing = false
            }

            if isDrawing {
                path.addLine(to: screenPt)
            } else {
                path.move(to: screenPt)
                isDrawing = true
            }
            prevScreenY = screenPt.y
        }

        context.stroke(path, with: .color(equation.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    // MARK: Implicit: f(x, y) = 0 via Marching Squares

    private func drawImplicitEquation(_ equation: Equation, context: GraphicsContext, size: CGSize) {
        guard let eval = equation.implicitEvaluator else { return }

        // Grid resolution: ~3 pixels per cell for good detail
        let cellSize: Double = 3.0
        let cols = Int(size.width / cellSize) + 1
        let rows = Int(size.height / cellSize) + 1

        // Evaluate f(x,y) at every grid vertex
        var grid = [[Double?]](repeating: [Double?](repeating: nil, count: cols + 1), count: rows + 1)
        for r in 0...(rows) {
            for c in 0...(cols) {
                let screenPt = CGPoint(x: Double(c) * cellSize, y: Double(r) * cellSize)
                let (mx, my) = toMath(screenPt, size: size)
                grid[r][c] = eval(mx, my)
            }
        }

        // March through cells, find zero-crossings via linear interpolation
        var path = Path()

        for r in 0..<rows {
            for c in 0..<cols {
                guard let v0 = grid[r][c],
                      let v1 = grid[r][c+1],
                      let v2 = grid[r+1][c+1],
                      let v3 = grid[r+1][c] else { continue }

                let cellX = Double(c) * cellSize
                let cellY = Double(r) * cellSize

                // Classify corners: bit 0=TL, 1=TR, 2=BR, 3=BL
                var config = 0
                if v0 > 0 { config |= 1 }
                if v1 > 0 { config |= 2 }
                if v2 > 0 { config |= 4 }
                if v3 > 0 { config |= 8 }

                if config == 0 || config == 15 { continue }

                // Edge midpoints with linear interpolation
                // Top edge (v0 - v1)
                let topT = v0 / (v0 - v1)
                let top = CGPoint(x: cellX + topT * cellSize, y: cellY)
                // Right edge (v1 - v2)
                let rightT = v1 / (v1 - v2)
                let right = CGPoint(x: cellX + cellSize, y: cellY + rightT * cellSize)
                // Bottom edge (v3 - v2)
                let bottomT = v3 / (v3 - v2)
                let bottom = CGPoint(x: cellX + bottomT * cellSize, y: cellY + cellSize)
                // Left edge (v0 - v3)
                let leftT = v0 / (v0 - v3)
                let left = CGPoint(x: cellX, y: cellY + leftT * cellSize)

                // Draw line segments based on marching squares lookup
                let segments: [(CGPoint, CGPoint)]
                switch config {
                case 1, 14:
                    segments = [(top, left)]
                case 2, 13:
                    segments = [(top, right)]
                case 3, 12:
                    segments = [(left, right)]
                case 4, 11:
                    segments = [(right, bottom)]
                case 5:
                    // Saddle point: use center value to disambiguate
                    let center = (v0 + v1 + v2 + v3) / 4
                    if center > 0 {
                        segments = [(top, right), (bottom, left)]
                    } else {
                        segments = [(top, left), (bottom, right)]
                    }
                case 6, 9:
                    segments = [(top, bottom)]
                case 7, 8:
                    segments = [(left, bottom)]
                case 10:
                    let center = (v0 + v1 + v2 + v3) / 4
                    if center > 0 {
                        segments = [(top, left), (bottom, right)]
                    } else {
                        segments = [(top, right), (bottom, left)]
                    }
                default:
                    segments = []
                }

                for (a, b) in segments {
                    path.move(to: a)
                    path.addLine(to: b)
                }
            }
        }

        context.stroke(path, with: .color(equation.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

}

// MARK: - Input handling (pan + zoom) via NSViewRepresentable

struct GraphInteractionView: NSViewRepresentable {
    @Binding var centerX: Double
    @Binding var centerY: Double
    @Binding var scale: Double

    func makeNSView(context: Context) -> GraphNSView {
        let view = GraphNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: GraphNSView, context: Context) {
        context.coordinator.centerX = $centerX
        context.coordinator.centerY = $centerY
        context.coordinator.scale = $scale
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(centerX: $centerX, centerY: $centerY, scale: $scale)
    }

    class Coordinator {
        var centerX: Binding<Double>
        var centerY: Binding<Double>
        var scale: Binding<Double>

        var dragStartCenter: (Double, Double)?

        init(centerX: Binding<Double>, centerY: Binding<Double>, scale: Binding<Double>) {
            self.centerX = centerX
            self.centerY = centerY
            self.scale = scale
        }
    }
}

class GraphNSView: NSView {
    var coordinator: GraphInteractionView.Coordinator?
    private var dragStartLocation: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        dragStartLocation = location
        guard let coord = coordinator else { return }
        coord.dragStartCenter = (coord.centerX.wrappedValue, coord.centerY.wrappedValue)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coord = coordinator,
              let startLoc = dragStartLocation,
              let startCenter = coord.dragStartCenter else { return }

        let currentLoc = convert(event.locationInWindow, from: nil)
        let dx = Double(currentLoc.x - startLoc.x) / coord.scale.wrappedValue
        let dy = Double(currentLoc.y - startLoc.y) / coord.scale.wrappedValue

        coord.centerX.wrappedValue = startCenter.0 - dx
        coord.centerY.wrappedValue = startCenter.1 - dy
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        coordinator?.dragStartCenter = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let coord = coordinator else { return }
        let scale = coord.scale.wrappedValue
        let location = convert(event.locationInWindow, from: nil)
        let size = bounds.size

        let delta = Double(event.scrollingDeltaY)
        let zoomFactor = 1.0 + delta * 0.05
        let newScale = (scale * zoomFactor).clamped(to: 10...500)

        // Zoom toward cursor: convert cursor to math coords before and after
        // NSView has origin at bottom-left, so y is already "up"
        let mathBeforeX = coord.centerX.wrappedValue + (Double(location.x) - size.width / 2) / scale
        let mathBeforeY = coord.centerY.wrappedValue + (Double(location.y) - size.height / 2) / scale

        coord.scale.wrappedValue = newScale

        let mathAfterX = coord.centerX.wrappedValue + (Double(location.x) - size.width / 2) / newScale
        let mathAfterY = coord.centerY.wrappedValue + (Double(location.y) - size.height / 2) / newScale

        coord.centerX.wrappedValue += mathBeforeX - mathAfterX
        coord.centerY.wrappedValue += mathBeforeY - mathAfterY
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
