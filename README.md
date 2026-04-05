# GraphPlotter

A native macOS application for plotting mathematical equation graphs. Built with SwiftUI and SceneKit.

## Features

### 2D Graphing
- **Explicit equations**: `y = f(x)` — e.g., `x^2`, `sin(x)/x`, `exp(-x^2)`
- **Implicit equations**: `f(x, y) = 0` — e.g., `x^2+y^2=4` (circle), `x^2/4+y^2=1` (ellipse)
- Multiple equations with color-coded curves
- Toggle visibility per equation
- Drag to pan, scroll to zoom (zoom targets cursor position)
- Auto-scaling grid with labeled axes

### 3D Surface Plotting
- **Surface equations**: `z = f(x, y)` — e.g., `sin(x)*cos(y)`, `x^2+y^2`
- Interactive 3D rotation, zoom, and pan (SceneKit)
- Color schemes: Rainbow, Cool-Warm, Terrain, Monochrome
- Adjustable range and mesh resolution
- Axis labels and ground grid

### Expression Syntax

| Feature | Examples |
|---|---|
| Arithmetic | `x+1`, `x-2`, `3*x`, `x/2` |
| Exponentiation | `x^2`, `2^x`, `x^(1/3)` |
| Implicit multiply | `2x`, `3sin(x)`, `2(x+1)` |
| Functions | `sin`, `cos`, `tan`, `asin`, `acos`, `atan` |
| | `sqrt`, `abs`, `ln`, `log`, `exp` |
| | `floor`, `ceil`, `sign` |
| Constants | `pi`, `e` |
| Variables | `x` (1D & 2D), `y` (2D only) |

## Requirements

- macOS 14.0+
- Xcode 15+ or Swift 5.9+

## Build & Run

### Using Swift Package Manager

```bash
cd GraphPlotter
swift run
```

### Using Xcode

```bash
open GraphPlotter.xcodeproj
```

Then press **Cmd+R** to build and run.

## Project Structure

```
GraphPlotter/
  GraphPlotterApp.swift      # App entry point, NSApplication activation
  ContentView.swift          # Main UI: sidebar + graph area, 2D/3D mode toggle
  ExpressionParser.swift     # Recursive-descent math expression parser
  Equation.swift             # 2D equation model (explicit & implicit)
  Equation3D.swift           # 3D surface equation model
  GraphView.swift            # 2D graph renderer (Canvas) + marching squares
  SurfaceGraphView.swift     # 3D surface renderer (SceneKit)
```

## Example Equations

### 2D

- `x^2 + sin(x)` — parabola with oscillation
- `tan(x)` — tangent with asymptotes
- `x^2+y^2=4` — circle of radius 2
- `x^2-y^2=1` — hyperbola
- `sin(x)+sin(y)=1` — wavy implicit curve

### 3D

- `sin(x)*cos(y)` — egg carton surface
- `x^2 + y^2` — paraboloid
- `sin(sqrt(x^2+y^2))` — ripple
- `exp(-(x^2+y^2)/4)` — Gaussian bell

## License

This project is licensed under the BSD 2-Clause License. See [LICENSE](LICENSE) for details.
