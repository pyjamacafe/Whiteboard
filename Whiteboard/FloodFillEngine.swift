import CoreGraphics
import Foundation
import SwiftUI

/// A vectorized filled region (outer contour + optional interior hole contours),
/// rendered with the even-odd fill rule behind pen/sharpie strokes.
nonisolated struct FillShape: Identifiable, Codable, Sendable {
    var id = UUID()
    /// Closed polygon loops in canvas coordinates (outer boundary + any holes).
    var contours: [[CGPoint]]
    let color: CodableColor
    let opacity: Double
    let presetIndex: Int

    init(
        id: UUID = UUID(),
        contours: [[CGPoint]],
        color: Color,
        opacity: Double = 1.0,
        presetIndex: Int = -1
    ) {
        self.id = id
        self.contours = contours
        self.color = CodableColor(color)
        self.opacity = opacity
        self.presetIndex = presetIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, contours, color, opacity, presetIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        contours = try c.decode([[CGPoint]].self, forKey: .contours)
        color = try c.decode(CodableColor.self, forKey: .color)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        presetIndex = try c.decodeIfPresent(Int.self, forKey: .presetIndex) ?? -1
    }

    var uiColor: Color { color.color }

    @MainActor
    func displayColor(for model: DrawingModel) -> Color {
        if presetIndex >= 0, presetIndex < model.fillPresets.count {
            return model.fillPresets[presetIndex].opacity(opacity)
        }
        return color.color.opacity(opacity)
    }

    /// Builds a combined `CGPath` for all contours (suitable for even-odd filling).
    func makeCGPath() -> CGPath {
        let path = CGMutablePath()
        for loop in contours where loop.count >= 3 {
            path.move(to: loop[0])
            for i in 1..<loop.count {
                path.addLine(to: loop[i])
            }
            path.closeSubpath()
        }
        return path
    }

    /// Axis-aligned bounding box of all contour points.
    func boundingBox() -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var found = false
        for loop in contours {
            for p in loop {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
                found = true
            }
        }
        guard found else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Fast local-region scanline flood fill with contour vectorization (Option #2).
/// - Rasterizes only nearby strokes into a bounded 1-byte-per-pixel mask.
/// - Aborts cleanly if the fill touches the outer margin (no bleeding on open shapes).
/// - Expands slightly under the stroke centerline (no white anti-aliasing halo).
/// - Traces closed outer + hole contours and simplifies via RDP into a crisp vector polygon.
nonisolated enum FloodFillEngine {

    /// Maximum raster dimension (pixels) along either axis to guarantee <15ms runtime.
    private static let maxGridDimension: CGFloat = 1024

    /// Computes closed vector contours enclosing `tapPoint` bounded by `strokes`.
    /// Returns `nil` if `tapPoint` is not inside an enclosed region.
    static func computeContours(
        at tapPoint: CGPoint,
        strokes: [Stroke],
        gapTolerance: CGFloat = 2.5
    ) -> [[CGPoint]]? {
        let barrierStrokes = strokes.filter { !$0.isEraser && $0.points.count >= 2 }
        guard !barrierStrokes.isEmpty else { return nil }

        // Gather strokes in a local neighborhood around tapPoint, expanding iteratively
        // to include connected strokes up to a reasonable canvas span.
        let initialRadius: CGFloat = 600
        var searchRect = CGRect(
            x: tapPoint.x - initialRadius,
            y: tapPoint.y - initialRadius,
            width: initialRadius * 2,
            height: initialRadius * 2
        )

        var localStrokes: [Stroke] = []
        var unionBounds = CGRect.null
        for s in barrierStrokes {
            let b = GeometryEngine.strokeBounds(s)
            if b.intersects(searchRect) {
                localStrokes.append(s)
                unionBounds = unionBounds.isNull ? b : unionBounds.union(b)
            }
        }
        guard !localStrokes.isEmpty, !unionBounds.isNull else { return nil }

        // If any included stroke extended beyond searchRect, pull in strokes touching unionBounds once more.
        if !searchRect.contains(unionBounds) {
            searchRect = unionBounds.insetBy(dx: -20, dy: -20)
            localStrokes.removeAll(keepingCapacity: true)
            unionBounds = .null
            for s in barrierStrokes {
                let b = GeometryEngine.strokeBounds(s)
                if b.intersects(searchRect) {
                    localStrokes.append(s)
                    unionBounds = unionBounds.isNull ? b : unionBounds.union(b)
                }
            }
        }

        guard !unionBounds.isNull, unionBounds.contains(tapPoint) else { return nil }

        // Add margin around unionBounds so the outer border is guaranteed empty (bleed detector).
        let margin: CGFloat = max(12, gapTolerance * 2 + 6)
        let region = unionBounds.insetBy(dx: -margin, dy: -margin)
        guard region.width > 2, region.height > 2 else { return nil }

        // Pick grid resolution: prefer 2.0 px/pt for crisp contours, capped at maxGridDimension.
        let maxDim = max(region.width, region.height)
        let gridScale = min(2.0, maxGridDimension / maxDim)
        let w = Int((region.width * gridScale).rounded(.up))
        let h = Int((region.height * gridScale).rounded(.up))
        guard w >= 4, h >= 4 else { return nil }

        // 1. Rasterize barrier strokes into a 1-byte-per-pixel grayscale buffer.
        var barrier = [UInt8](repeating: 0, count: w * h)
        let rasterOK = barrier.withUnsafeMutableBytes { rawBuf -> Bool in
            guard let ptr = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: ptr,
                      width: w,
                      height: h,
                      bitsPerComponent: 8,
                      bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }

            // Map canvas (y-down) to buffer (row 0 = region.minY)
            ctx.translateBy(x: -region.minX * gridScale, y: CGFloat(h) + region.minY * gridScale)
            ctx.scaleBy(x: gridScale, y: -gridScale)
            ctx.setStrokeColor(gray: 1.0, alpha: 1.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let extraWidth = max(0, gapTolerance) * 2
            for s in localStrokes {
                guard let path = GeometryEngine.makeCGPath(for: s) else { continue }
                ctx.setLineWidth(max(s.lineWidth + extraWidth, 1.5 / gridScale))
                ctx.addPath(path)
                ctx.strokePath()
            }
            return true
        }
        guard rasterOK else { return nil }

        // 2. Locate seed pixel (nudge slightly if tap landed directly on a stroke pixel).
        let rawSeedX = Int(((tapPoint.x - region.minX) * gridScale).rounded())
        let rawSeedY = Int(((tapPoint.y - region.minY) * gridScale).rounded())
        guard let (seedX, seedY) = findOpenSeed(near: (rawSeedX, rawSeedY), barrier: barrier, width: w, height: h) else {
            return nil
        }

        // 3. Scanline flood fill — aborts immediately if fill reaches the outer boundary (bleed guard).
        var filled = [UInt8](repeating: 0, count: w * h)
        var minFX = seedX, maxFX = seedX, minFY = seedY, maxFY = seedY

        // Stack of (x, y) seed points for scanline spans
        var stack: [(Int, Int)] = [(seedX, seedY)]
        stack.reserveCapacity(1024)

        @inline(__always)
        func isOpen(_ x: Int, _ y: Int) -> Bool {
            let idx = y * w + x
            return filled[idx] == 0 && barrier[idx] < 64
        }

        while let (sx, sy) = stack.popLast() {
            if !isOpen(sx, sy) { continue }

            // Expand left
            var lx = sx
            while lx > 0 && isOpen(lx - 1, sy) { lx -= 1 }
            // Expand right
            var rx = sx
            while rx < w - 1 && isOpen(rx + 1, sy) { rx += 1 }

            // Bleed check: if the span touches any edge of the raster region, shape is open -> abort!
            if lx == 0 || rx == w - 1 || sy == 0 || sy == h - 1 {
                return nil
            }

            let rowOffset = sy * w
            for x in lx...rx {
                filled[rowOffset + x] = 1
            }
            if lx < minFX { minFX = lx }
            if rx > maxFX { maxFX = rx }
            if sy < minFY { minFY = sy }
            if sy > maxFY { maxFY = sy }

            // Queue spans on row above and row below
            for ny in [sy - 1, sy + 1] {
                var inSpan = false
                for x in lx...rx {
                    if isOpen(x, ny) {
                        if !inSpan {
                            stack.append((x, ny))
                            inSpan = true
                        }
                    } else {
                        inSpan = false
                    }
                }
            }
        }

        // 4. Expand filled mask slightly under the stroke centerline so there is zero halo.
        let expandRadius = min(max(Int(((gapTolerance + 1.0) * gridScale).rounded(.up)), 1), 8)
        let cropMinX = max(0, minFX - expandRadius - 1)
        let cropMaxX = min(w - 1, maxFX + expandRadius + 1)
        let cropMinY = max(0, minFY - expandRadius - 1)
        let cropMaxY = min(h - 1, maxFY + expandRadius + 1)
        let cw = cropMaxX - cropMinX + 1
        let ch = cropMaxY - cropMinY + 1
        guard cw >= 3, ch >= 3 else { return nil }

        // Copy tight crop into a 1px zero-padded grid and apply fast separable dilation
        let pw = cw + 2
        let ph = ch + 2
        var mask = [UInt8](repeating: 0, count: pw * ph)
        for y in 0..<ch {
            let srcRow = (cropMinY + y) * w + cropMinX
            let dstRow = (y + 1) * pw + 1
            for x in 0..<cw {
                mask[dstRow + x] = filled[srcRow + x]
            }
        }

        if expandRadius > 0 {
            mask = dilateSeparable(mask, width: pw, height: ph, radius: expandRadius)
        }

        // 5. Trace closed vector contours (outer boundary + any interior holes).
        let gridLoops = traceContours(mask: mask, width: pw, height: ph)
        guard !gridLoops.isEmpty else { return nil }

        // 6. Map grid coordinates back to canvas space, smooth corners lightly, and simplify via RDP.
        let originX = region.minX + CGFloat(cropMinX - 1) / gridScale
        let originY = region.minY + CGFloat(cropMinY - 1) / gridScale
        let invScale = 1.0 / gridScale

        var contours: [[CGPoint]] = []
        contours.reserveCapacity(gridLoops.count)
        for loop in gridLoops {
            var pts = loop.map { gp in
                CGPoint(x: originX + CGFloat(gp.x) * invScale, y: originY + CGFloat(gp.y) * invScale)
            }
            if pts.count >= 4 {
                pts = chaikinClosed(pts)
            }
            // Simplify closed polygon (append first point so RDP preserves closure, then drop duplicate)
            if pts.count > 4 {
                var closed = pts
                closed.append(pts[0])
                var simplified = GeometryEngine.simplifyRDP(closed, tolerance: max(0.45, 0.7 * invScale))
                if simplified.count > 1, simplified.last == simplified.first {
                    simplified.removeLast()
                }
                pts = simplified
            }
            if pts.count >= 3 {
                contours.append(pts)
            }
        }

        return contours.isEmpty ? nil : contours
    }

    // MARK: - Helpers

    private static func findOpenSeed(
        near seed: (Int, Int),
        barrier: [UInt8],
        width w: Int,
        height h: Int
    ) -> (Int, Int)? {
        let (sx, sy) = seed
        if sx > 0, sx < w - 1, sy > 0, sy < h - 1, barrier[sy * w + sx] < 64 {
            return (sx, sy)
        }
        for r in 1...4 {
            for dy in -r...r {
                for dx in -r...r where abs(dx) == r || abs(dy) == r {
                    let nx = sx + dx, ny = sy + dy
                    if nx > 0, nx < w - 1, ny > 0, ny < h - 1, barrier[ny * w + nx] < 64 {
                        return (nx, ny)
                    }
                }
            }
        }
        return nil
    }

    /// Fast O(w * h) two-pass separable dilation (preserves 1px zero border).
    private static func dilateSeparable(_ src: [UInt8], width w: Int, height h: Int, radius r: Int) -> [UInt8] {
        var horiz = [UInt8](repeating: 0, count: w * h)
        for y in 1..<(h - 1) {
            let row = y * w
            var count = 0
            for x in 1..<min(w - 1, 1 + r) { count += Int(src[row + x]) }
            for x in 1..<(w - 1) {
                let addX = x + r
                if addX < w - 1 { count += Int(src[row + addX]) }
                let remX = x - r - 1
                if remX >= 1 { count -= Int(src[row + remX]) }
                if count > 0 { horiz[row + x] = 1 }
            }
        }

        var dst = [UInt8](repeating: 0, count: w * h)
        for x in 1..<(w - 1) {
            var count = 0
            for y in 1..<min(h - 1, 1 + r) { count += Int(horiz[y * w + x]) }
            for y in 1..<(h - 1) {
                let addY = y + r
                if addY < h - 1 { count += Int(horiz[addY * w + x]) }
                let remY = y - r - 1
                if remY >= 1 { count -= Int(horiz[remY * w + x]) }
                if count > 0 { dst[y * w + x] = 1 }
            }
        }
        return dst
    }

    private struct GridPoint: Hashable {
        let x: Int
        let y: Int
    }

    /// Traces all closed boundary loops (outer + holes) of a 1px-padded binary mask
    /// by chaining directed boundary edges around filled pixels.
    private static func traceContours(mask: [UInt8], width w: Int, height h: Int) -> [[GridPoint]] {
        // Collect directed boundary edges from start vertex -> list of end vertices
        var outgoing: [GridPoint: [GridPoint]] = [:]

        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) where mask[row + x] != 0 {
                if mask[(y - 1) * w + x] == 0 {
                    outgoing[GridPoint(x: x, y: y), default: []].append(GridPoint(x: x + 1, y: y))
                }
                if mask[row + (x + 1)] == 0 {
                    outgoing[GridPoint(x: x + 1, y: y), default: []].append(GridPoint(x: x + 1, y: y + 1))
                }
                if mask[(y + 1) * w + x] == 0 {
                    outgoing[GridPoint(x: x + 1, y: y + 1), default: []].append(GridPoint(x: x, y: y + 1))
                }
                if mask[row + (x - 1)] == 0 {
                    outgoing[GridPoint(x: x, y: y + 1), default: []].append(GridPoint(x: x, y: y))
                }
            }
        }

        var loops: [[GridPoint]] = []
        while let (start, nextList) = outgoing.first {
            guard !nextList.isEmpty else {
                outgoing.removeValue(forKey: start)
                continue
            }

            var loop: [GridPoint] = [start]
            var curr = start
            var prevDir = (0, 0)

            while true {
                guard var candidates = outgoing[curr], !candidates.isEmpty else { break }
                // Pick continuation (prefer turning right at saddle vertices so loops don't cross)
                let chosenIdx: Int
                if candidates.count == 1 || prevDir == (0, 0) {
                    chosenIdx = 0
                } else {
                    // Right turn in y-down coords: (-prevDir.y, prevDir.x)
                    let rightDir = (-prevDir.1, prevDir.0)
                    chosenIdx = candidates.firstIndex(where: {
                        ($0.x - curr.x, $0.y - curr.y) == rightDir
                    }) ?? 0
                }
                let next = candidates.remove(at: chosenIdx)
                if candidates.isEmpty {
                    outgoing.removeValue(forKey: curr)
                } else {
                    outgoing[curr] = candidates
                }

                prevDir = (next.x - curr.x, next.y - curr.y)
                if next == start { break }

                // Collapse collinear grid vertices on the fly
                if loop.count >= 2 {
                    let a = loop[loop.count - 2]
                    let b = loop[loop.count - 1]
                    if (b.x - a.x) * (next.y - b.y) == (b.y - a.y) * (next.x - b.x) {
                        loop[loop.count - 1] = next
                    } else {
                        loop.append(next)
                    }
                } else {
                    loop.append(next)
                }
                curr = next
            }

            if loop.count >= 3 {
                loops.append(loop)
            }
        }
        return loops
    }

    /// One pass of Chaikin's corner-cutting algorithm on a closed polygon to soften
    /// staircase pixel steps into smooth curves.
    private static func chaikinClosed(_ pts: [CGPoint]) -> [CGPoint] {
        let n = pts.count
        guard n >= 3 else { return pts }
        var out: [CGPoint] = []
        out.reserveCapacity(n * 2)
        for i in 0..<n {
            let p0 = pts[i]
            let p1 = pts[(i + 1) % n]
            out.append(CGPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y))
            out.append(CGPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y))
        }
        return out
    }
}
