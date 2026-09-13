# Doodles — Whiteboard App

Doodles is a cross-platform vector drawing whiteboard for iPad and Mac, built with SwiftUI and Core Graphics.

## Features

### Drawing Tools
- **Pen** — Smooth vector strokes with Catmull-Rom spline interpolation and Gaussian pre-filtering. Adjustable width (2–4pt) and color presets that adapt to light/dark theme.
- **Sharpie** — A heavier, pen-like tool with its own color presets (same width options as the pen).
- **Eraser** — Full-stroke or partial erase modes with adjustable size. Choose the erase target: **All**, **Pen**, or **Sharpie**, so you can selectively erase one stroke type without affecting the other.
- **Select** — Lasso-select strokes and images. Move, delete, or double-tap selections for quick delete menu.

### Canvas
- Infinite scrollable/pannable canvas with pinch-to-zoom
- Grid (dashed), dots, or ruled background
- Manual dark/light mode toggle (per-canvas, not system-wide); background is white in light mode and black in dark mode
- Apple Pencil support: double-tap toggles pen/eraser; squeeze toggles toolbar

### Document Management
- Board library with automatic save to `~/Library/Application Support/com.whiteboard.boards/`
- Thumbnail grid with folder organization
- Undo/redo with full state snapshots (strokes, selection)
- Import/export: `.wb` native format, PNG, PDF
- Trash with 30-day retention and restore

### File Format
Drawings are saved as `.wb` files (JSON-encoded `SaveData`), containing:
- Stroke data with point arrays, colors, widths, and preset indices for theme adaptation
- Placed images
- Board metadata (name, modification date, folder)

## Toolbar & Settings
The toolbar appears at the top of the canvas and includes:
- Tool buttons (pen, eraser, select)
- Undo, Redo, Home
- Settings menu with undo/redo, appearance toggles, defaults management, and export actions
- Per-tool settings ribbon (double-tap a tool or tap when "Reveal Options on Single Tap" is enabled)

## Keyboard Shortcuts (macOS)
| Key | Action |
|-----|--------|
| `P` | Pen |
| `X` | Sharpie |
| `E` | Eraser |
| `S` | Select |
| `1`–`8` | Select color preset |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘S` | Save |
| `⌘O` | Open |
| `⌘W` | Close board |
| `Tab` | Toggle toolbar |
| `Delete` | Delete selected |

## Architecture

### Canvas Rendering
- **iOS**: UIKit `UIView` with `CGContext` drawing, wrapped in `UIViewRepresentable`
- **macOS**: Pure SwiftUI with `GraphicsContext` and `Path`
- Layers: grid background → placed images → pen/eraser strokes → lasso/selection overlays

### Color System
Colors are stored with a `presetIndex` that maps to the current theme's color palette at render time. Strokes created before the preset system (backward compat) have `presetIndex = -1` and use their stored absolute color. A one-time migration on file load matches old colors to the closest preset.

### Smoothing
Pen strokes are smoothed using:
1. **Gaussian-weighted moving average** (window radius 2, σ ≈ 1.0) to reduce high-frequency jitter.
2. **Centripetal Catmull-Rom to cubic Bézier** conversion: `cp1 = p1 + (p2 - p0) / 6`, `cp2 = p2 - (p3 - p1) / 6`.
Smoothing is applied at render time; raw input points are stored.

## Build Requirements
- iOS 17+ / macOS 14+
- Xcode 15+
- Swift 5.9+

## License
All Rights Reserved. See `LICENSE` for details.
