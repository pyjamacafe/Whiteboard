# Doodles — Whiteboard App

Doodles is a cross-platform vector drawing whiteboard for iPad and Mac, built with SwiftUI and Core Graphics.

## Features

### Drawing Tools
- **Pen** — Smooth vector strokes with Catmull-Rom spline interpolation and Gaussian pre-filtering. Adjustable width (2–4pt) and color presets that adapt to light/dark theme.
- **Eraser** — Full-stroke or partial erase modes with adjustable size.
- **Highlighter** — Translucent strokes composited as a group for uniform opacity. Fixed opacity, adjustable thickness and color.
- **Fill (Bucket)** — Tap to flood-fill enclosed areas using a planar straight-line graph (PSLG) / doubly-connected edge list (DCEL) enclosure detector. Also supports drag-to-fill: draw a lasso around an area to fill the stroke-bounded enclosure within it.
- **Laser Pointer** — Pointer with tail and red glow. Strokes persist individually with a 3-second fade. Optional retain mode keeps strokes indefinitely. White on light theme, black on dark theme.
- **Select** — Lasso-select strokes and fill regions. Move, delete, or double-tap selections for quick delete menu.

### Canvas
- Infinite scrollable/pannable canvas with pinch-to-zoom
- Grid, dots, or ruled background
- Manual dark/light mode toggle (per-canvas, not system-wide)
- Apple Pencil support: double-tap toggles pen/eraser; squeeze toggles toolbar

### Document Management
- Board library with automatic save to `~/Library/Application Support/com.whiteboard.boards/`
- Thumbnail grid with folder organization
- Undo/redo with full state snapshots (strokes, fills, selection, laser strokes)
- Import/export: `.wb` native format, PNG, PDF
- Trash with 30-day retention and restore

### File Format
Drawings are saved as `.wb` files (JSON-encoded `SaveData`), containing:
- Stroke data with point arrays, colors, widths, and preset indices for theme adaptation
- Fill regions with closed paths and colors
- Board metadata (name, modification date, folder)

## Toolbar & Settings
The toolbar appears at the top of the canvas and includes:
- Tool buttons (pen, eraser, fill, highlighter, select, laser)
- Undo, Redo, Home
- Settings menu with undo/redo, appearance toggles, defaults management, and export actions
- Per-tool settings ribbon (double-tap a tool or tap when "Reveal Options on Single Tap" is enabled)

## Keyboard Shortcuts (macOS)
| Key | Action |
|-----|--------|
| `P` | Pen |
| `E` | Eraser |
| `F` | Fill |
| `H` | Highlighter |
| `S` | Select |
| `L` | Laser |
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
- Layers: grid background → fill regions → highlighter strokes → pen/eraser strokes → lasso/selection overlays → laser pointer

### Fill Engine
The flood fill uses a two-phase approach:
1. **Endpoint bridging**: Connects nearby stroke endpoints (≤3pt) to create a connected planar graph from separate strokes.
2. **DCEL detection**: Splits segments at intersections, builds a half-edge adjacency structure, sorts edges by angle, and traverses CCW cycles using the left-hand turn rule. Only positive-area (CCW) cycles are returned as fillable enclosures.

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
