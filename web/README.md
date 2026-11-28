# Tissue Box Web & PWA

Cross-platform Web + Progressive Web App version of **Tissue Box** for Windows, Linux, macOS, and tablets — built with React, TypeScript, Vite, HTML5 Canvas 2D, IndexedDB, and `pdf-lib`.

## Features
- **Full Drawing Parity**: Pen (Catmull-Rom smoothing + draw-and-hold shape snap), Sharpie (two-pass glow/core), Vector Flood Fill (Strict/Auto/Wide gap closing, Replace/Blend mode, opacity cycling, interior holes), Eraser (Full/Partial + All/Pen/Sharpie/Fill target cycling).
- **Selection & Rotation**: Lasso & tap-to-select (Pen, Sharpie, Fill, Image), free-area tap / `Esc` deselect, direct-manipulation rotation handle with cardinal & `Shift`-15° snapping, live angle readout, Reset Rotation, rotated image resizing with dynamic cursors, Copy/Paste/Duplicate/Recolor/Scale.
- **Library & Scenes**: IndexedDB persistence for tissues, folders (drag-and-drop), cached light/dark thumbnails, 30-day Recently Deleted trash with Undo toast, Scenes bookmarks with smooth pan/zoom transitions, and configurable dockable Liquid Glass toolbar.
- **Portable Exports & Offline PWA**: Full `.wb` JSON compatibility with Tissue Box for Mac/iPad, transparent high-DPI PNG export, vector PDF & multi-page Scenes PDF export, and offline installation as a PWA.

## Development
```bash
cd web
npm install
npm run dev      # Start local dev server
npm test         # Run Vitest unit tests
npm run build    # Typecheck and build production bundle + PWA service worker
```

## GitHub Pages Deployment
The workflow in `.github/workflows/deploy-web.yml` automatically tests, builds, and deploys `web/dist` whenever `web/**` changes on `main`.
In your GitHub repository settings, set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**.
