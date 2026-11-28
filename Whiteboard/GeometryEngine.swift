import CoreGraphics
import Foundation

/// 2D uniform-grid spatial hash for O(1)-bucket queries over dense boards.
nonisolated final class SpatialHashGrid {
    struct CellKey: Hashable {
        let x: Int
        let y: Int
    }

    let cellSize: CGFloat
    private var buckets: [CellKey: [Int]] = [:]
    private var boundsByIndex: [CGRect] = []
    private var indexedCount: Int = 0
    private var firstId: UUID?
    private var lastId: UUID?

    init(cellSize: CGFloat = 256) {
        self.cellSize = max(cellSize, 32)
    }

    /// Rebuilds or incrementally updates the index to match `strokes`.
    func sync(with strokes: [Stroke]) {
        if strokes.count == indexedCount,
           strokes.first?.id == firstId,
           strokes.last?.id == lastId {
            return
        }

        // Fast path: a single stroke was appended to the end.
        if strokes.count == indexedCount + 1,
           indexedCount > 0,
           strokes.first?.id == firstId,
           strokes[indexedCount - 1].id == lastId {
            let idx = indexedCount
            let b = GeometryEngine.strokeBounds(strokes[idx])
            boundsByIndex.append(b)
            insert(index: idx, bounds: b)
            indexedCount = strokes.count
            lastId = strokes.last?.id
            return
        }

        rebuild(with: strokes)
    }

    func rebuild(with strokes: [Stroke]) {
        buckets.removeAll(keepingCapacity: true)
        boundsByIndex.removeAll(keepingCapacity: true)
        boundsByIndex.reserveCapacity(strokes.count)
        for (idx, stroke) in strokes.enumerated() {
            let b = GeometryEngine.strokeBounds(stroke)
            boundsByIndex.append(b)
            insert(index: idx, bounds: b)
        }
        indexedCount = strokes.count
        firstId = strokes.first?.id
        lastId = strokes.last?.id
    }

    func invalidate() {
        buckets.removeAll(keepingCapacity: true)
        boundsByIndex.removeAll(keepingCapacity: true)
        indexedCount = 0
        firstId = nil
        lastId = nil
    }

    /// Returns sorted stroke indices whose bounding boxes intersect `rect`.
    func queryIndices(in rect: CGRect) -> [Int] {
        guard !rect.isNull, !rect.isEmpty,
              rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite,
              indexedCount > 0 else { return [] }
        let minCX = Int(floor(rect.minX / cellSize))
        let maxCX = Int(floor(rect.maxX / cellSize))
        let minCY = Int(floor(rect.minY / cellSize))
        let maxCY = Int(floor(rect.maxY / cellSize))
        guard minCX <= maxCX, minCY <= maxCY else { return [] }

        // Guard against huge query rects (e.g. extreme zoom out): fall back to direct bounds check.
        let spanX = maxCX - minCX + 1
        let spanY = maxCY - minCY + 1
        if spanX > 64 || spanY > 64 || spanX * spanY > 2048 {
            var result: [Int] = []
            for idx in 0..<boundsByIndex.count where boundsByIndex[idx].intersects(rect) {
                result.append(idx)
            }
            return result
        }

        var seen = Set<Int>()
        var result: [Int] = []
        for cx in minCX...maxCX {
            for cy in minCY...maxCY {
                guard let indices = buckets[CellKey(x: cx, y: cy)] else { continue }
                for idx in indices where seen.insert(idx).inserted {
                    if idx < boundsByIndex.count && boundsByIndex[idx].intersects(rect) {
                        result.append(idx)
                    }
                }
            }
        }
        result.sort()
        return result
    }

    private func insert(index: Int, bounds: CGRect) {
        guard !bounds.isNull, !bounds.isEmpty,
              bounds.minX.isFinite, bounds.minY.isFinite, bounds.maxX.isFinite, bounds.maxY.isFinite else { return }
        let minCX = Int(floor(bounds.minX / cellSize))
        let maxCX = Int(floor(bounds.maxX / cellSize))
        let minCY = Int(floor(bounds.minY / cellSize))
        let maxCY = Int(floor(bounds.maxY / cellSize))
        guard minCX <= maxCX, minCY <= maxCY else { return }

        // Cap per-stroke bucket fanout to prevent runaway loops on gigantic strokes.
        let clampedMaxCX = min(maxCX, minCX + 64)
        let clampedMaxCY = min(maxCY, minCY + 64)
        for cx in minCX...clampedMaxCX {
            for cy in minCY...clampedMaxCY {
                buckets[CellKey(x: cx, y: cy), default: []].append(index)
            }
        }
    }
}

/// Incrementally builds a smooth quadratic `CGMutablePath` for the active
/// in-progress stroke so drag events do O(1) work instead of re-smoothing all
/// prior points on every frame.
final class IncrementalStrokePath {
    private(set) var strokeId: UUID?
    private(set) var pointCount: Int = 0
    private var path = CGMutablePath()
    private var lastPoint: CGPoint = .zero

    func reset() {
        strokeId = nil
        pointCount = 0
        path = CGMutablePath()
        lastPoint = .zero
    }

    func path(for stroke: Stroke) -> CGPath? {
        guard stroke.points.count >= 2 else { return nil }
        if stroke.id != strokeId || stroke.points.count < pointCount {
            strokeId = stroke.id
            pointCount = 0
            path = CGMutablePath()
        }

        if pointCount == 0 {
            let p0 = stroke.points[0]
            path.move(to: p0)
            lastPoint = p0
            pointCount = 1
        }

        while pointCount < stroke.points.count {
            let pt = stroke.points[pointCount]
            let mid = CGPoint(x: (lastPoint.x + pt.x) * 0.5, y: (lastPoint.y + pt.y) * 0.5)
            path.addQuadCurve(to: mid, control: lastPoint)
            lastPoint = pt
            pointCount += 1
        }

        return path
    }
}

/// Pure geometry, spline smoothing, simplification, hit-testing, and erasing algorithms.
nonisolated enum GeometryEngine {

    // MARK: - Point Simplification (Ramer-Douglas-Peucker)

    /// Reduces redundant collinear/near-collinear points while preserving stroke
    /// shape within `tolerance` (in canvas points).
    static func simplifyRDP(_ points: [CGPoint], tolerance: CGFloat = 0.3) -> [CGPoint] {
        guard points.count > 2, tolerance > 0 else { return points }
        let tolSq = tolerance * tolerance
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end - start > 1 else { continue }
            let a = points[start]
            let b = points[end]
            var maxDistSq: CGFloat = 0
            var maxIdx = start

            for i in (start + 1)..<end {
                let dSq = pointSegmentDistanceSquared(points[i], a, b)
                if dSq > maxDistSq {
                    maxDistSq = dSq
                    maxIdx = i
                }
            }

            if maxDistSq > tolSq {
                keep[maxIdx] = true
                stack.append((start, maxIdx))
                stack.append((maxIdx, end))
            }
        }

        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for i in 0..<points.count where keep[i] {
            result.append(points[i])
        }
        return result
    }

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

    static func boundingBox(of strokes: [Stroke], images: [PlacedImage], fills: [FillShape] = [], padding: CGFloat = 0) -> CGRect? {
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
            let rect = img.rotatedBoundingBox()
            guard rect.width > 0, rect.height > 0 else { continue }
            minX = min(minX, rect.minX)
            maxX = max(maxX, rect.maxX)
            minY = min(minY, rect.minY)
            maxY = max(maxY, rect.maxY)
            hasContent = true
        }

        for fill in fills {
            let rect = fill.boundingBox()
            guard !rect.isNull else { continue }
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

    static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
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

    static func segmentSegmentDistanceSquared(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
        if segmentsIntersect(a, b, c, d) { return 0 }
        return min(
            min(pointSegmentDistanceSquared(a, c, d), pointSegmentDistanceSquared(b, c, d)),
            min(pointSegmentDistanceSquared(c, a, b), pointSegmentDistanceSquared(d, a, b))
        )
    }

    // MARK: - Erasing

    /// Erases strokes touched by `eraser`, optionally using a `SpatialHashGrid`
    /// to skip strokes outside the eraser's bounding box in O(1) buckets.
    static func erase(
        strokes: [Stroke],
        with eraser: Stroke,
        mode: EraserMode,
        target: EraseTarget,
        spatialGrid: SpatialHashGrid? = nil
    ) -> [Stroke] {
        guard !eraser.points.isEmpty, target != .fill else { return strokes }

        let radius = max(eraser.lineWidth / 2, 0.5)
        let radiusSq = radius * radius
        let eraserBounds = strokeBounds(eraser).insetBy(dx: -radius, dy: -radius)

        let candidateIndices: Set<Int>?
        if let grid = spatialGrid {
            grid.sync(with: strokes)
            candidateIndices = Set(grid.queryIndices(in: eraserBounds))
        } else {
            candidateIndices = nil
        }

        let isTargeted: (Stroke) -> Bool = { stroke in
            switch target {
            case .all: return true
            case .pen: return !stroke.isSharpie
            case .sharpie: return stroke.isSharpie
            case .fill: return false
            }
        }

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
            var kept: [Stroke] = []
            kept.reserveCapacity(strokes.count)
            for (idx, pen) in strokes.enumerated() {
                if let candidates = candidateIndices, !candidates.contains(idx) {
                    kept.append(pen)
                    continue
                }
                if pen.isEraser || !isTargeted(pen) || !strokeHit(pen) {
                    kept.append(pen)
                }
            }
            return kept
        }

        var result: [Stroke] = []
        result.reserveCapacity(strokes.count)
        for (idx, pen) in strokes.enumerated() {
            if let candidates = candidateIndices, !candidates.contains(idx) {
                result.append(pen)
                continue
            }
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

    static func resizedRect(start: CGRect, corner: Int, offset: CGSize, minSize: CGFloat = 10) -> CGRect? {
        guard start.width > 0, start.height > 0,
              start.width.isFinite, start.height.isFinite,
              offset.width.isFinite, offset.height.isFinite else { return nil }

        let aspect = start.width / start.height
        let dragX = abs(offset.width) >= abs(offset.height)
        var newRect = start

        switch corner {
        case 0:
            if dragX {
                let newW = max(minSize, start.width - offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height - offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
            }
        case 1:
            if dragX {
                let newW = max(minSize, start.width + offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height - offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
            }
        case 2:
            if dragX {
                let newW = max(minSize, start.width + offset.width)
                let newH = newW / aspect
                newRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
            } else {
                let newH = max(minSize, start.height + offset.height)
                let newW = newH * aspect
                newRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
            }
        case 3:
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

    // MARK: - Rotation Helpers

    /// Normalizes an angle in radians to the half-open interval `(-π, π]`.
    static func normalizeAngle(_ radians: CGFloat) -> CGFloat {
        var a = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        if abs(a) < 1e-6 { return 0 }
        return a
    }

    /// Rotates a point around `pivot` by `radians` (clockwise in y-down coordinates).
    static func rotatePoint(_ point: CGPoint, around pivot: CGPoint, by radians: CGFloat) -> CGPoint {
        guard radians != 0 else { return point }
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        let cosA = cos(radians)
        let sinA = sin(radians)
        return CGPoint(
            x: pivot.x + dx * cosA - dy * sinA,
            y: pivot.y + dx * sinA + dy * cosA
        )
    }

    /// Snaps an angle (radians):
    /// - When `snapToStep` is true, snaps to nearest `stepRadians` (default 15°).
    /// - Otherwise applies a light magnetic snap when within `cardinalThreshold` (default 4°)
    ///   of cardinal angles (0°, ±90°, 180°).
    static func snapRotationAngle(
        _ radians: CGFloat,
        snapToStep: Bool,
        stepRadians: CGFloat = .pi / 12,
        cardinalThreshold: CGFloat = 4 * .pi / 180
    ) -> (angle: CGFloat, snapped: Bool) {
        let normalized = normalizeAngle(radians)
        if snapToStep, stepRadians > 0 {
            let stepped = (normalized / stepRadians).rounded() * stepRadians
            return (normalizeAngle(stepped), true)
        }
        let cardinals: [CGFloat] = [-.pi, -.pi / 2, 0, .pi / 2, .pi]
        for c in cardinals {
            if abs(normalized - c) <= cardinalThreshold {
                return (normalizeAngle(c), true)
            }
        }
        return (normalized, false)
    }

    // MARK: - Shape Recognition (Draw & Hold)

    /// Recognizes a hand-drawn straight line, circle/ellipse, or rectangle from raw stroke points.
    /// Returns snapped points if a clean geometric match is found, or `nil` otherwise.
    static func recognizeShape(from points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 6, let first = points.first, let last = points.last else { return nil }

        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        var totalLength: CGFloat = 0
        for i in 1..<points.count {
            let p = points[i]
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
            totalLength += hypot(p.x - points[i - 1].x, p.y - points[i - 1].y)
        }
        let width = maxX - minX
        let height = maxY - minY
        let diag = hypot(width, height)
        guard diag >= 28, totalLength >= 28 else { return nil }

        let endDist = hypot(last.x - first.x, last.y - first.y)

        // 1. Straight line check
        if endDist >= 28 && totalLength <= endDist * 1.18 {
            let ldx = last.x - first.x
            let ldy = last.y - first.y
            let lenSq = max(ldx * ldx + ldy * ldy, 1e-6)
            var maxDev: CGFloat = 0
            for p in points {
                let t = min(max(((p.x - first.x) * ldx + (p.y - first.y) * ldy) / lenSq, 0), 1)
                let projX = first.x + t * ldx
                let projY = first.y + t * ldy
                let d = hypot(p.x - projX, p.y - projY)
                if d > maxDev { maxDev = d }
            }
            if maxDev / endDist < 0.085 {
                let steps = 16
                return (0...steps).map { i in
                    let t = CGFloat(i) / CGFloat(steps)
                    return CGPoint(x: first.x + (last.x - first.x) * t, y: first.y + (last.y - first.y) * t)
                }
            }
        }

        // Closed shape threshold: start and end reasonably close
        let isClosed = endDist <= max(36, diag * 0.28)
        guard isClosed, width >= 18, height >= 18 else { return nil }

        // 2. Circle / Ellipse check
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let rx = width / 2
        let ry = height / 2
        var radialErrSum: CGFloat = 0
        for p in points {
            let nx = (p.x - cx) / rx
            let ny = (p.y - cy) / ry
            radialErrSum += abs(hypot(nx, ny) - 1.0)
        }
        if radialErrSum / CGFloat(points.count) < 0.14 {
            let aspect = rx / ry
            let (finalRx, finalRy): (CGFloat, CGFloat) = (aspect > 0.85 && aspect < 1.18)
                ? ((rx + ry) / 2, (rx + ry) / 2)
                : (rx, ry)
            let segments = 64
            return (0...segments).map { i in
                let angle = (CGFloat(i) / CGFloat(segments)) * .pi * 2
                return CGPoint(x: cx + cos(angle) * finalRx, y: cy + sin(angle) * finalRy)
            }
        }

        // 3. Axis-aligned Rectangle check
        var edgeErrSum: CGFloat = 0
        for p in points {
            let dMin = min(min(abs(p.x - minX), abs(p.x - maxX)), min(abs(p.y - minY), abs(p.y - maxY)))
            edgeErrSum += dMin
        }
        let perimeter = 2 * (width + height)
        if (edgeErrSum / CGFloat(points.count)) / diag < 0.085 && totalLength >= perimeter * 0.78 && totalLength <= perimeter * 1.35 {
            let corners = [
                CGPoint(x: minX, y: minY),
                CGPoint(x: maxX, y: minY),
                CGPoint(x: maxX, y: maxY),
                CGPoint(x: minX, y: maxY),
                CGPoint(x: minX, y: minY),
            ]
            var dense: [CGPoint] = []
            let stepsPerEdge = 8
            for e in 0..<4 {
                let a = corners[e], b = corners[e + 1]
                for s in 0..<stepsPerEdge {
                    let t = CGFloat(s) / CGFloat(stepsPerEdge)
                    dense.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            dense.append(corners[0])
            return dense
        }

        return nil
    }
}
