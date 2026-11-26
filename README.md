# Tissue Box

Tissue Box is a cross-platform vector sketching app for iPad and Mac — built with SwiftUI and Core Graphics — designed like a café napkin for quickly sketching and conveying ideas. Each canvas is a **Tissue**.

Repository: [github.com/pyjamacafe/Whiteboard](https://github.com/pyjamacafe/Whiteboard)

## Features

### Drawing Tools
- **Pen (`P`)** — Smooth vector strokes with Gaussian pre-filtering and centripetal Catmull-Rom spline interpolation. Adjustable width (2–4 pt) and 8 theme-adaptive color presets.
- **Sharpie (`S`)** — Two-pass glow/core stroke style with its own color presets and width options.
- **Fill (`F`)** — Fast local scanline flood fill converted into crisp vector polygons (supporting interior holes via the even-odd fill rule and sharp corner preservation). Includes zero-bleeding open-shape detection, visual opacity swatches (`25%`–`100%`), an icon-only gap-closing cycle button (**Strict**, **Auto**, **Wide**), an icon-only **Replace / Blend** mode toggle (Replace by default so refilling swaps colors cleanly without blending), and theme-adaptive colors.
- **Eraser (`E`)** — Full-stroke or partial erase modes with adjustable size and segment-to-segment hit testing. Choose the erase target (**All**, **Pen**, or **Sharpie**); erasing **All** also removes touched fills.
- **Select (`⇧S`)** — Lasso-select strokes, fills, and placed images. Move, copy/paste, resize images with corner handles, or double-tap for quick actions.

### Canvas
- Infinite pannable/zoomable canvas with spatial-indexed viewport culling and cached vector paths.
- Dashed grid, dots, ruled, or plain background.
- Per-canvas Light/Dark mode toggle with synchronized theme-adaptive stroke and fill palettes.
- Apple Pencil support: double-tap toggles Eraser (on both iPadOS and macOS Sidecar), Apple Pencil Pro squeeze cycles drawing tools on iPadOS, single-finger dragging pans the canvas when using Apple Pencil, plus a **Draw with Apple Pencil Only** toggle (off by default on macOS for mouse/trackpad drawing, on by default on iPad for palm rejection).

### Library & Interface
- Native **Liquid Glass** styling (macOS 26 / iOS 26) with unified titlebar toolbar (`+`, Open, Search, Theme, Sort, View), floating glass sidebar, concentric capsule canvas toolbars, and compact icon-only More menu with hover tooltips.
- Responsive `NavigationSplitView` welcome screen (minimum macOS window size `800×560`) with **All Tissues**, **Recents**, **Folders** (drag-and-drop), and **Recently Deleted** (30-day retention, Restore, Delete Permanently, Empty Trash, and Undo toast).
- Instant **New Tissue (`⌘N`)** creation, time-grouped List view with mini thumbnails, uniform `4:3` Grid view with blank-canvas previews, search (`⌘F`), and sorting.
- Fast atomic background auto-save using binary property lists + external image assets (with full backward compatibility for legacy JSON `.wb` files) and disk-cached thumbnails.
- Bounded undo/redo history capturing strokes, fills, placed images, and selection state.
- Import/export: portable `.wb` JSON format, transparent high-DPI PNG, and vector PDF.

## Keyboard Shortcuts (macOS)
| Key | Action |
|-----|--------|
| `P` | Pen |
| `S` | Sharpie |
| `F` | Fill |
| `E` | Eraser |
| `⇧S` | Select |
| `1`–`8` | Select color preset |
| `⌘Z` / `⌘⇧Z` | Undo / Redo |
| `⌘C` / `⌘V` | Copy / Paste selection |
| `⌘I` | Import image |
| `⌘S` / `⌘O` / `⌘W` | Save / Open / Close tissue |
| `⌘N` / `⌘F` | New tissue / Search (Welcome screen) |
| `Tab` | Toggle toolbar |
| `Delete` | Delete selected |

## Architecture
- **`DrawingModel`** (`@Observable`) — Central state, undo/redo coordination, auto-save flushing, and async disk+memory thumbnails.
- **`CanvasView`** — Platform-specific isolated rendering layers: UIKit `UIView` + `CGContext` on iOS, SwiftUI `Canvas` + GPU `CALayer` hover indicator on macOS.
- **`GeometryEngine`** — Catmull-Rom smoothing, `SpatialHashGrid` (256 pt uniform grid), RDP simplification, segment-to-segment erasing, and unified bounding boxes.
- **`FloodFillEngine`** — Local 1-byte-per-pixel scanline flood fill, separable under-stroke expansion, directed contour tracing (outer + holes), and Chaikin/RDP vectorization.
- **`BoardStore`** — `nonisolated` atomic disk persistence for boards, external image assets, disk thumbnails, folders, and 30-day trash.
- **`StrokeRenderer`** — Shared Core Graphics renderer for PNG, vector PDF, thumbnails, and iOS canvas so exports match live rendering.
- **`WhiteboardTests`** — Unit test suite covering geometry, flood fill, history, persistence, trash/restore, color sync, and exports.

## Releases & Installation
Pre-built macOS releases (`.dmg` and `.zip` with `SHA256SUMS.txt`) are published automatically via GitHub Actions on version tags (`v*`).

Because releases are ad-hoc signed, macOS Gatekeeper may prompt on first launch:
```bash
xattr -dr com.apple.quarantine "/Applications/Tissue Box.app"
```

## Build Requirements
- macOS 27 (Golden Gate)+ / iPadOS 27+ (pre-built GitHub Releases target macOS 27+ Apple Silicon)
- Xcode 26+
- Swift 5.9+

## License
Released under the [MIT License](LICENSE). Copyright © 2025-2026 Piyush Itankar.
