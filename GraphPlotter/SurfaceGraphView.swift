import SwiftUI
import SceneKit

struct SurfaceGraphView: NSViewRepresentable {
    let equation: Equation3D
    let range: Double // x and y range: [-range, range]
    let resolution: Int // grid points per axis

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = SCNScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .textBackgroundColor

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = false
        cameraNode.camera?.fieldOfView = 45
        cameraNode.position = SCNVector3(x: CGFloat(range * 1.8), y: CGFloat(range * 1.8), z: CGFloat(range * 1.8))
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scnView.scene?.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Ambient light for better visibility
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 400
        ambientLight.light?.color = NSColor.white
        scnView.scene?.rootNode.addChildNode(ambientLight)

        // Build the scene content
        buildScene(in: scnView.scene!, equation: equation)

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        guard let scene = nsView.scene else { return }

        // Remove old content (keep camera and lights)
        for child in scene.rootNode.childNodes {
            if child.camera == nil && child.light == nil {
                child.removeFromParentNode()
            }
        }

        buildScene(in: scene, equation: equation)
    }

    private func buildScene(in scene: SCNScene, equation: Equation3D) {
        // Add axes
        addAxes(to: scene.rootNode)

        // Add surface if valid
        guard let eval = equation.evaluator else { return }
        addSurface(to: scene.rootNode, evaluator: eval, colorScheme: equation.colorScheme)
    }

    // MARK: - Surface Mesh

    private func addSurface(to parent: SCNNode, evaluator: @escaping (Double, Double) -> Double?, colorScheme: SurfaceColorScheme) {
        let n = resolution
        let step = (range * 2) / Double(n - 1)

        // Evaluate all grid points
        var heights = [[Double?]](repeating: [Double?](repeating: nil, count: n), count: n)
        var minZ = Double.infinity
        var maxZ = -Double.infinity

        for i in 0..<n {
            for j in 0..<n {
                let x = -range + Double(i) * step
                let y = -range + Double(j) * step
                if let z = evaluator(x, y) {
                    let clamped = max(-range * 2, min(range * 2, z))
                    heights[i][j] = clamped
                    minZ = min(minZ, clamped)
                    maxZ = max(maxZ, clamped)
                }
            }
        }

        if minZ >= maxZ { maxZ = minZ + 1 }
        let zRange = maxZ - minZ

        // Build geometry from triangles
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [CGFloat] = [] // RGBA
        var indices: [Int32] = []

        // Create vertex grid
        for i in 0..<n {
            for j in 0..<n {
                let x = -range + Double(i) * step
                let y = -range + Double(j) * step
                let z = heights[i][j] ?? 0

                // In SceneKit: x = math x, y = math z (up), z = math y
                vertices.append(SCNVector3(CGFloat(x), CGFloat(z), CGFloat(y)))

                // Compute normal via finite differences
                let zL = heights[safe: i-1]?[safe: j] ?? z
                let zR = heights[safe: i+1]?[safe: j] ?? z
                let zD = heights[safe: i]?[safe: j-1] ?? z
                let zU = heights[safe: i]?[safe: j+1] ?? z
                let nx = CGFloat((zL - zR) / (2 * step))
                let ny: CGFloat = 1.0
                let nz = CGFloat((zD - zU) / (2 * step))
                let len = sqrt(nx*nx + ny*ny + nz*nz)
                normals.append(SCNVector3(nx/len, ny/len, nz/len))

                // Color based on height
                let t = (z - minZ) / zRange
                let (r, g, b) = colorForValue(t, scheme: colorScheme)
                let alpha: CGFloat = heights[i][j] != nil ? 1.0 : 0.0
                colors.append(contentsOf: [CGFloat(r), CGFloat(g), CGFloat(b), alpha])
            }
        }

        // Create triangle indices
        for i in 0..<(n-1) {
            for j in 0..<(n-1) {
                let topLeft = Int32(i * n + j)
                let topRight = Int32(i * n + j + 1)
                let bottomLeft = Int32((i + 1) * n + j)
                let bottomRight = Int32((i + 1) * n + j + 1)

                // Only create triangles if all 4 corners have valid heights
                guard heights[i][j] != nil,
                      heights[i][j+1] != nil,
                      heights[i+1][j] != nil,
                      heights[i+1][j+1] != nil else { continue }

                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }

        guard !indices.isEmpty else { return }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)

        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<CGFloat>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<CGFloat>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<CGFloat>.size * 4
        )

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])

        let material = SCNMaterial()
        material.isDoubleSided = true
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor.white // vertex colors multiply with this
        geometry.materials = [material]

        let surfaceNode = SCNNode(geometry: geometry)
        parent.addChildNode(surfaceNode)
    }

    private func colorForValue(_ t: Double, scheme: SurfaceColorScheme) -> (Double, Double, Double) {
        let t = max(0, min(1, t))
        switch scheme {
        case .rainbow:
            // HSV rainbow: hue from 240 (blue) to 0 (red)
            let hue = (1 - t) * 0.66
            return hsvToRgb(h: hue, s: 0.85, v: 0.95)
        case .coolWarm:
            // Blue (cool) to Red (warm)
            let r = t
            let b = 1 - t
            let g = 1 - abs(2 * t - 1)
            return (r, g * 0.6, b)
        case .terrain:
            // Blue -> Green -> Yellow -> Brown -> White
            if t < 0.25 {
                let s = t / 0.25
                return (0, 0.2 + 0.6 * s, 0.8 - 0.4 * s)
            } else if t < 0.5 {
                let s = (t - 0.25) / 0.25
                return (0.4 * s, 0.8, 0.4 - 0.4 * s)
            } else if t < 0.75 {
                let s = (t - 0.5) / 0.25
                return (0.4 + 0.4 * s, 0.8 - 0.3 * s, 0)
            } else {
                let s = (t - 0.75) / 0.25
                return (0.8 + 0.2 * s, 0.5 + 0.5 * s, 0.5 * s)
            }
        case .monochrome:
            let v = 0.2 + 0.8 * t
            return (v, v, v)
        }
    }

    private func hsvToRgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let c = v * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h * 6) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    // MARK: - Axes

    private func addAxes(to parent: SCNNode) {
        let r = CGFloat(range)
        let axisRadius: CGFloat = 0.02 * CGFloat(range / 5)

        // X axis (red)
        addAxisLine(parent: parent, from: SCNVector3(-r, 0, 0), to: SCNVector3(r, 0, 0), color: .systemRed, radius: axisRadius, label: "x")
        // Y axis (green) — up in SceneKit
        addAxisLine(parent: parent, from: SCNVector3(0, -r, 0), to: SCNVector3(0, r, 0), color: .systemGreen, radius: axisRadius, label: "z")
        // Z axis (blue) — math y
        addAxisLine(parent: parent, from: SCNVector3(0, 0, -r), to: SCNVector3(0, 0, r), color: .systemBlue, radius: axisRadius, label: "y")

        // Grid on the xz-plane (y=0 in SceneKit = z=0 in math)
        addGroundGrid(parent: parent)
    }

    private func addAxisLine(parent: SCNNode, from: SCNVector3, to: SCNVector3, color: NSColor, radius: CGFloat, label: String) {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)

        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
        let material = SCNMaterial()
        material.diffuse.contents = color
        cylinder.materials = [material]

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((from.x+to.x)/2, (from.y+to.y)/2, (from.z+to.z)/2)
        node.look(at: to, up: SCNVector3(0,1,0), localFront: SCNVector3(0,1,0))
        parent.addChildNode(node)

        // Axis label
        let text = SCNText(string: label, extrusionDepth: 0.1)
        text.font = NSFont.systemFont(ofSize: CGFloat(range * 0.15))
        text.firstMaterial?.diffuse.contents = color
        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(to.x, to.y + CGFloat(range * 0.1), to.z)
        textNode.scale = SCNVector3(1, 1, 1)

        let constraint = SCNBillboardConstraint()
        textNode.constraints = [constraint]
        parent.addChildNode(textNode)
    }

    private func addGroundGrid(parent: SCNNode) {
        let r = CGFloat(range)
        let gridStep = CGFloat(niceGridSpacing())
        let color = NSColor.gray.withAlphaComponent(0.3)
        let radius: CGFloat = 0.005 * CGFloat(range / 5)

        var pos = -r
        while pos <= r {
            // Lines parallel to z (math y)
            addThinLine(parent: parent, from: SCNVector3(pos, 0, -r), to: SCNVector3(pos, 0, r), color: color, radius: radius)
            // Lines parallel to x
            addThinLine(parent: parent, from: SCNVector3(-r, 0, pos), to: SCNVector3(r, 0, pos), color: color, radius: radius)
            pos += gridStep
        }
    }

    private func addThinLine(parent: SCNNode, from: SCNVector3, to: SCNVector3, color: NSColor, radius: CGFloat) {
        let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
        let material = SCNMaterial()
        material.diffuse.contents = color
        cylinder.materials = [material]
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((from.x+to.x)/2, (from.y+to.y)/2, (from.z+to.z)/2)
        node.look(at: to, up: SCNVector3(0,1,0), localFront: SCNVector3(0,1,0))
        parent.addChildNode(node)
    }

    private func niceGridSpacing() -> Double {
        let rawSpacing = range / 4
        let magnitude = pow(10, floor(log10(rawSpacing)))
        let normalized = rawSpacing / magnitude
        let nice: Double
        if normalized < 1.5 { nice = 1 }
        else if normalized < 3.5 { nice = 2 }
        else if normalized < 7.5 { nice = 5 }
        else { nice = 10 }
        return nice * magnitude
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

private extension Array where Element == [Double?] {
    subscript(safe index: Int) -> [Double?]? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

private extension Array where Element == Double? {
    subscript(safe index: Int) -> Double? {
        guard index >= 0 && index < count else { return nil }
        return self[index] ?? nil
    }
}
