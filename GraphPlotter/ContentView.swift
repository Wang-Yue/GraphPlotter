import SwiftUI

enum GraphMode: String, CaseIterable {
    case twoDim = "2D"
    case threeDim = "3D"
}

struct ContentView: View {
    @State private var mode: GraphMode = .twoDim

    // 2D state
    @State private var equations: [Equation] = [
        Equation(text: "x^2", color: .blue),
        Equation(text: "sin(x)", color: .red),
        Equation(text: "x^2+y^2=4", color: .green),
    ]
    @State private var centerX: Double = 0
    @State private var centerY: Double = 0
    @State private var scale: Double = 60

    // 3D state
    @State private var equation3D = Equation3D(text: "sin(x)*cos(y)")
    @State private var range3D: Double = 5
    @State private var resolution3D: Int = 80

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)

            // Main graph area
            ZStack {
                if mode == .twoDim {
                    GraphView(
                        equations: equations,
                        centerX: $centerX,
                        centerY: $centerY,
                        scale: $scale
                    )
                    GraphInteractionView(
                        centerX: $centerX,
                        centerY: $centerY,
                        scale: $scale
                    )
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            graphControls2D.padding(8)
                        }
                    }
                } else {
                    SurfaceGraphView(
                        equation: equation3D,
                        range: range3D,
                        resolution: resolution3D
                    )
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Mode picker
            Picker("Mode", selection: $mode) {
                ForEach(GraphMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            if mode == .twoDim {
                sidebar2D
            } else {
                sidebar3D
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 2D Sidebar

    private var sidebar2D: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Equations")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(equations.enumerated()), id: \.element.id) { index, _ in
                        equationRow(index: index)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Button(action: addEquation) {
                    Label("Add Equation", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(12)
                Spacer()
            }
        }
    }

    private func equationRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                equations[index].isVisible.toggle()
            } label: {
                Circle()
                    .fill(equations[index].isVisible ? equations[index].color : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help(equations[index].isVisible ? "Hide" : "Show")

            VStack(alignment: .leading, spacing: 2) {
                Text(equations[index].type == .implicit ? "f(x,y) = 0" : "y =")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. x^2+sin(x) or x^2+y^2=1", text: Binding(
                    get: { equations[index].text },
                    set: { equations[index].updateExpression($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }

            if equations.count > 1 {
                Button {
                    equations.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    !equations[index].text.isEmpty && !equations[index].isValid
                        ? Color.red.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private func addEquation() {
        let colorIndex = equations.count % Color.graphColors.count
        equations.append(Equation(text: "", color: Color.graphColors[colorIndex]))
    }

    private var graphControls2D: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { scale = min(scale * 1.3, 500) }
            } label: { Image(systemName: "plus.magnifyingglass") }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { scale = max(scale / 1.3, 10) }
            } label: { Image(systemName: "minus.magnifyingglass") }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    centerX = 0; centerY = 0; scale = 60
                }
            } label: { Image(systemName: "house") }
            .help("Reset view")
        }
        .buttonStyle(.bordered)
    }

    // MARK: - 3D Sidebar

    private var sidebar3D: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3D Surface")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("z = f(x, y)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. sin(x)*cos(y)", text: Binding(
                    get: { equation3D.text },
                    set: { equation3D.updateExpression($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                if !equation3D.text.isEmpty && !equation3D.isValid {
                    Text("Invalid expression")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)

            Divider()

            // Color scheme
            VStack(alignment: .leading, spacing: 4) {
                Text("Color Scheme")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Colors", selection: $equation3D.colorScheme) {
                    ForEach(SurfaceColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 12)

            // Range slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Range: [-\(String(format: "%.1f", range3D)), \(String(format: "%.1f", range3D))]")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $range3D, in: 1...20, step: 0.5)
            }
            .padding(.horizontal, 12)

            // Resolution slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Resolution: \(resolution3D)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: Binding(
                    get: { Double(resolution3D) },
                    set: { resolution3D = Int($0) }
                ), in: 20...150, step: 10)
            }
            .padding(.horizontal, 12)

            Divider()

            // Example equations
            VStack(alignment: .leading, spacing: 6) {
                Text("Examples")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(exampleEquations3D, id: \.self) { example in
                    Button {
                        equation3D.updateExpression(example)
                    } label: {
                        Text(example)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
    }

    private let exampleEquations3D = [
        "sin(x)*cos(y)",
        "x^2 + y^2",
        "sin(sqrt(x^2+y^2))",
        "cos(x)*sin(y)",
        "x*y/(x^2+y^2+1)",
        "exp(-(x^2+y^2)/4)",
    ]
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
