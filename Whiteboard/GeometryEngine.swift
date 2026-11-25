import CoreGraphics
import Foundation

/// Pure geometry, spline smoothing, hit-testing, and erasing algorithms.
enum GeometryEngine {

    // MARK: - Smoothing

    /// Applies Gaussian pre-filtering (window radius 2) followed by centripetal
    /// Catmull-Rom to cubic Bézier control-point generation.
    static func smoothCatmullRom(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        let gaussWeights: [CGFloat] = [0.061, 0.242, 0.394, 0.242, 0.061]
        var smoothed = points
        for i in 0..<points.count {
            var sx: CGFloat = 0, sy: CGFloat = 0, sw: CGFloat = 0
            for w in -2...2 {
                let idx = i + w
                guard idx >= 0, idx < points.count else { continue }
                let weight = gaussWeights[w + 2]
                sx += points[idx].x * weight
                sy += points[idx].y * weight
                sw += weight
            }
            if sw > 0 {
                smoothed[i] = CGPoint(x: sx / sw, y: sy / sw)
            }
        }

        var result: [CGPoint] = [smoothed[0]]
        result.reserveCapacity(1 + (smoothed.count - 1) * 3)
        for i in 0..<smoothed.count - 1 {
            let p0 = i > 0 ? smoothed[i - 1] : smoothed[i]
            let p1 = smoothed[i]
            let p2 = smoothed[i + 1]
            let p3 = i + 2 < smoothed.count ? smoothed[i + 2] : smoothed[i + 1]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            result.append(cp1)
            result.append(cp2)
            result.append(p2)
        }
        return result
    }

    /// Builds a `CGPath` in canvas coordinates for a stroke, applying Catmull-Rom
    /// smoothing when enabled and falling back cleanly for 2-point strokes.
    static func makeCGPath(for stroke: Stroke) -> CGPath? {
        guard stroke.points.count >= 2 else { return nil }
        let path = CGMutablePath()

        if stroke.isCatmullRom {
            let smoothed = smoothCatmullRom(stroke.points)
            if smoothed.count >= 4 {
                path.move(to: smoothed[0])
                var i = 1
                while i + 2 < smoothed.count {
                    path.addCurve(to: smoothed[i + 2], control1: smoothed[i], control2: smoothed[i + 1])
                    i += 3
                }
                while i < smoothed.count {
                    path.addLine(to: smoothed[i])
                    i += 1
                }
                return path
            }
        }

        // Fallback (2-point Catmull-Rom or non-Catmull-Rom strokes)
        path.move(to: stroke.points[0])
        var prev = stroke.points[0]
        for i in 1..<stroke.points.count {
            let pt = stroke.points[i]
            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
            prev = pt
        }
        if let last = stroke.points.last {
            path.addLine(to: last)
        }
        return path
    }

    // MARK: - Bounding Boxes

    /// Returns the axis-aligned bounding box of a single stroke, expanded by half
    /// its visual line width (including Sharpie glow margin).
    static func strokeBounds(_ stroke: Stroke) -> CGRect {
        guard let first = stroke.points.first else { return .null }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in stroke.points.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        let margin = (stroke.isSharpie ? stroke.lineWidth + 3 : stroke.lineWidth) / 2 + 2
        return CGRect(x: minX - margin, y: minY - margin, width: (maxX - minX) + margin * 2, height: (maxY - minY) + margin * 2)
    }

    /// Computes a unified bounding box over all non-eraser strokes and placed images,
    /// properly supporting negative infinite-canvas coordinates.
    static func boundingBox(of strokes: [Stroke], images: [PlacedImage], padding: CGFloat = 0) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var hasContent = false

        for s in strokes where !s.isEraser {
            guard !s.points.isEmpty else { continue }
            let halfWidth = (s.isSharpie ? s.lineWidth + 3 : s.lineWidth) / 2
            for p in s.points {
                minX = min(minX, p.x - halfWidth)
                maxX = max(maxX, p.x + halfWidth)
                minY = min(minY, p.y - halfWidth)
                maxY = max(maxY, p.y + halfWidth)
                hasContent = true
            }
        }

        for img in images {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            guard rect.width > 0, rect.height > 0 else { continue }
            minX = min(minX, rect.minX)
            maxX = max(maxX, rect.maxX)
            minY = min(minY, rect.minY)
            maxY = max(maxY, rect.maxY)
            hasContent = true
        }

        guard hasContent, maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(1, maxX - minX) + padding * 2,
            height: max(1, maxY - minY) + padding * 2
        )
    }

    // MARK: - Hit Testing & Distance

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func pointInPolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func pointSegmentDistanceSquared(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            let px = p.x - a.x, py = p.y - a.y
            return px * px + py * py
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let rx = p.x - projX, ry = p.y - projY
        return rx * rx + ry * ry
    }

    static func pointSegmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pointSegmentDistanceSquared(p, a, b))
    }

    /// Returns whether two line segments AB and CD properly intersect.
    private static func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ o: CGPoint, _ u: CGPoint, _ v: CGPoint) -> CGFloat {
            (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x)
        }
        let d1 = cross(a, b, c)
        let d2 = cross(a, b, d)
        let d3 = cross(c, d, a)
        let d4 = cross(c, d, b)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
               ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// Minimum squared distance between line segments AB and CD.
    static func segmentSegmentDistanceSquared(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
        if segmentsIntersect(a, b, c, d) { return 0 }
        return min(
            min(pointSegmentDistanceSquared(a, c, d), pointSegmentDistanceSquared(b, c, d)),
            min(pointSegmentDistanceSquared(c, a, b), pointSegmentDistanceSquared(d, a, b))
        )
    }

    // MARK: - Erasing

    /// Erases strokes touched by `eraser` using bounding-box pre-filtering and
    /// segment-to-segment distance checks so fast sparse strokes don't skip lines.
    static func erase(
        strokes: [Stroke],
        with eraser: Stroke,
        mode: EraserMode,
        target: EraseTarget
    ) -> [Stroke] {
        guard !eraser.points.isEmpty else { return strokes }

        let radius = max(eraser.lineWidth / 2, 0.5)
        let radiusSq = radius * radius
        let eraserBounds = strokeBounds(eraser).insetBy(dx: -radius, dy: -radius)

        let isTargeted: (Stroke) -> Bool = { stroke in
            switch target {
            case .all: return true
            case .pen: return !stroke.isSharpie
            case .sharpie: return stroke.isSharpie
            }
        }

        // Pre-build eraser segments (or single point if count == 1)
        let eraserSegments: [(CGPoint, CGPoint)]
        if eraser.points.count >= 2 {
            eraserSegments = (0..<(eraser.points.count - 1)).map { (eraser.points[$0], eraser.points[$0 + 1]) }
        } else {
            eraserSegments = [(eraser.points[0], eraser.points[0])]
        }

        func pointHit(_ p: CGPoint) -> Bool {
            for (ea, eb) in eraserSegments {
                if pointSegmentDistanceSquared(p, ea, eb) < radiusSq {
                    return true
                }
            }
            return false
        }

        func strokeHit(_ pen: Stroke) -> Bool {
            guard strokeBounds(pen).intersects(eraserBounds) else { return false }
            if pen.points.count == 1 {
                return pointHit(pen.points[0])
            }
            for i in 0..<(pen.points.count - 1) {
                let pa = pen.points[i], pb = pen.points[i + 1]
                for (ea, eb) in eraserSegments {
                    if segmentSegmentDistanceSquared(pa, pb, ea, eb) < radiusSq {
                        return true
                    }
                }
            }
            return false
        }

        if mode == .full {
            return strokes.filter { $0.isEraser || !isTargeted($0) || !strokeHit($0) }
        }

        // Partial erase: split targeted strokes where points/segments fall inside the eraser radius.
        var result: [Stroke] = []
        result.reserveCapacity(strokes.count)
        for pen in strokes {
            if pen.isEraser || !isTargeted(pen) || !strokeBounds(pen).intersects(eraserBounds) {
                result.append(pen)
                continue
            }

            var segment: [CGPoint] = []
            for i in 0..<pen.points.count {
                let pp = pen.points[i]
                let erasedPoint = pointHit(pp)
                let erasedEdge: Bool
                if i > 0 && !erasedPoint && !segment.isEmpty {
                    let prev = pen.points[i - 1]
                    erasedEdge = eraserSegments.contains { ea, eb in
                        segmentSegmentDistanceSquared(prev, pp, ea, eb) < radiusSq
                    }
                } else {
                    erasedEdge = false
                }

                if erasedPoint || erasedEdge {
                    if segment.count >= 2 {
                        result.append(Stroke(
                            points: segment,
                            color: pen.uiColor,
                            lineWidth: pen.lineWidth,
                            isEraser: false,
                            presetIndex: pen.presetIndex,
                            isCatmullRom: pen.isCatmullRom,
                            isSharpie: pen.isSharpie
                        ))
                    }
                    segment = erasedPoint ? [] : [pp]
                } else {
                    segment.append(pp)
                }
            }
            if segment.count >= 2 {
                result.append(Stroke(
                    points: segment,
                    color: pen.uiColor,
                    lineWidth: pen.lineWidth,
                    isEraser: false,
                    presetIndex: pen.presetIndex,
                    isCatmullRom: pen.isCatmullRom,
                    isSharpie: pen.isSharpie
                ))
            }
        }
        return result
    }

    // MARK: - Image Resizing

    /// Aspect-ratio-locked corner resize that guards against zero dimensions / NaN.
    static func resizedRect(start: CGRect, corner: Int, offset: CGSize, minSize: CGFloat = 10) -> CGRect? {
        guard start.width > 0, start.height > 0,
              start.width.isFinite, start.height.isFinite,
              offset.width.isFinite, offset.height.isFinite else { return nil }

        let aspect = start.width / start.height
        let dragX = abs(offset.width) >= abs(offset.height)
        var newRect = start

        switch corner {
        case 0: // top-left
            if dragX {
                let newW = max(minSize, start.width - offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height - offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
            }
        case 1: // top-right
            if dragX {
                let newW = max(minSize, start.width + offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height - offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
            }
        case 2: // bottom-right
            if dragX {
                let newW = max(minSize, start.width + offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height + offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
            }
        case 3: // bottom-left
            if dragX {
                let newW = max(minSize, start.width - offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.maxX - newW, y: start.minY, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height + offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.maxX - newW, y: start.minY, width: newW, height: newH)
            }
        default:
            return nil
        }

        guard newRect.width >= minSize, newRect.height >= minSize,
              newRect.origin.x.isFinite, newRect.origin.y.isFinite else { return nil }
        return newRect
    }
}
