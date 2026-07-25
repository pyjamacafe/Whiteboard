import SwiftUI
import CoreGraphics
import os

// MARK: - Planar Straight-Line Graph (PSLG) Enclosure Detection

private let log = OSLog(subsystem: "com.whiteboard", category: "floodfill")
private var _fillId: UInt64 = 0

enum FloodFill {

    static func fillPath(at canvasPoint: CGPoint, strokes: [Stroke]) -> CGPath? {
        _fillId += 1
        let fid = _fillId
        os_log("[%llu] fillPath at (%.1f, %.1f) strokes=%d", log: log, type: .debug, fid, canvasPoint.x, canvasPoint.y, strokes.count)

        var segs: [(CGPoint, CGPoint)] = []
        for s in strokes where !s.isEraser {
            for i in 0..<s.points.count - 1 {
                segs.append((s.points[i], s.points[i + 1]))
            }
            if s.points.count >= 3 {
                let d = s.points.first!.distance(to: s.points.last!)
                if d < 30 {
                    segs.append((s.points.last!, s.points.first!))
                }
            }
        }
        guard !segs.isEmpty else { os_log("[%llu] no segments", log: log, type: .debug, fid); return nil }
        os_log("[%llu] total segments before filter: %d", log: log, type: .debug, fid, segs.count)

        let searchRadius: CGFloat = 500
        let tapRect = CGRect(x: canvasPoint.x - searchRadius, y: canvasPoint.y - searchRadius,
                             width: searchRadius * 2, height: searchRadius * 2)
        let nearSegs = segs.filter { segRect($0).intersects(tapRect) }
        os_log("[%llu] nearSegs (within 500pt): %d", log: log, type: .debug, fid, nearSegs.count)
        let sortedSegs = nearSegs.sorted(by: { a, b in
            let da = min(a.0.distance(to: canvasPoint), a.1.distance(to: canvasPoint))
            let db = min(b.0.distance(to: canvasPoint), b.1.distance(to: canvasPoint))
            return da < db
        })
        let cappedSegs = sortedSegs.count > 2000 ? Array(sortedSegs.prefix(2000)) : sortedSegs
        os_log("[%llu] cappedSegs: %d", log: log, type: .debug, fid, cappedSegs.count)

        // Bridge nearby stroke-endpoints so barely-touching strokes
        // form a connected graph for the DCEL.
        // Only bridge endpoints that appear once (true stroke ends)
        // to avoid linking intermediate vertices.
        var endpointCount = [CGPoint: Int]()
        for seg in cappedSegs {
            endpointCount[seg.0, default: 0] += 1
            endpointCount[seg.1, default: 0] += 1
        }
        let bridgeThreshold: CGFloat = 3
        var bridged = cappedSegs
        var bridgeCount = 0
        var bridgedPoints = Set<UInt64>()
        func pointKey(_ p: CGPoint) -> UInt64 {
            UInt64(bitPattern: Int64(p.x * 100)) << 32 | UInt64(bitPattern: Int64(p.y * 100))
        }
        for i in 0..<cappedSegs.count {
            let a1 = cappedSegs[i].0, a2 = cappedSegs[i].1
            for j in (i + 1)..<cappedSegs.count {
                let b1 = cappedSegs[j].0, b2 = cappedSegs[j].1
                let pairs: [(CGPoint, CGPoint)] = [
                    (a1, b1), (a1, b2), (a2, b1), (a2, b2),
                ]
                for (p, q) in pairs where p != q {
                    guard endpointCount[p, default: 0] == 1,
                          endpointCount[q, default: 0] == 1 else { continue }
                    guard !bridgedPoints.contains(pointKey(p)),
                          !bridgedPoints.contains(pointKey(q)) else { continue }
                    if p.distance(to: q) < bridgeThreshold {
                        bridgedPoints.insert(pointKey(p))
                        bridgedPoints.insert(pointKey(q))
                        bridged.append((p, q))
                        bridgeCount += 1
                    }
                }
            }
        }
        if bridgeCount > 0 {
            os_log("[%llu] added %d bridge segments, total: %d", log: log, type: .debug, fid, bridgeCount, bridged.count)
        }

        let enclosures = EnclosureDetector.detect(from: bridged, fillId: fid)
        os_log("[%llu] DCEL enclosures found: %d", log: log, type: .debug, fid, enclosures.count)

        // If DCEL found nothing, try simple closed-stroke detection
        if enclosures.isEmpty {
            os_log("[%llu] trying closedStrokeFill fallback", log: log, type: .debug, fid)
            if let simple = closedStrokeFill(canvasPoint, strokes, fillId: fid) {
                os_log("[%llu] closedStrokeFill returned a path", log: log, type: .debug, fid)
                return simple
            }
        }

        var best: (path: CGPath, area: CGFloat)?
        for (idx, path) in enclosures.enumerated() {
            let box = path.boundingBox
            guard !box.isNull else { os_log("[%llu] path[%d] null bbox", log: log, type: .debug, fid, idx); continue }
            guard box.contains(canvasPoint) else { os_log("[%llu] path[%d] bbox doesn't contain tap", log: log, type: .debug, fid, idx); continue }
            let pts = pathPoints(path)
            guard pointInPolygon(canvasPoint, pts) else { os_log("[%llu] path[%d] point not in polygon", log: log, type: .debug, fid, idx); continue }
            let area = abs(signedArea(pts))
            os_log("[%llu] path[%d] valid, area=%.1f", log: log, type: .debug, fid, idx, area)
            if best == nil || area < best!.area {
                best = (path, area)
            }
        }
        if let b = best { os_log("[%llu] best area=%.1f", log: log, type: .debug, fid, b.area) }
        else { os_log("[%llu] no valid enclosure matched tap point", log: log, type: .debug, fid) }
        return best?.path
    }

    private static func segRect(_ seg: (CGPoint, CGPoint)) -> CGRect {
        CGRect(x: min(seg.0.x, seg.1.x), y: min(seg.0.y, seg.1.y),
               width: abs(seg.1.x - seg.0.x), height: abs(seg.1.y - seg.0.y))
    }

    private static func pathPoints(_ path: CGPath) -> [CGPoint] {
        var pts: [CGPoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            if e.type == .moveToPoint || e.type == .addLineToPoint {
                pts.append(e.points[0])
            }
        }
        return pts
    }

    private static func pointInPolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    private static func closedStrokeFill(_ point: CGPoint, _ strokes: [Stroke], fillId fid: UInt64) -> CGPath? {
        let threshold: CGFloat = 30
        var best: (path: CGMutablePath, area: CGFloat)?
        for (si, s) in strokes.enumerated() where !s.isEraser && s.points.count >= 3 {
            let d = s.points.first!.distance(to: s.points.last!)
            guard d < threshold else { continue }
            os_log("[%llu] closedStrokeFill stroke[%d] start->end=%.1f", log: log, type: .debug, fid, si, d)
            guard pointInPolygon(point, s.points) else { os_log("[%llu]   point not inside", log: log, type: .debug, fid); continue }
            let simplified = rdpSimplify(s.points, epsilon: 3)
            guard simplified.count >= 3 else { continue }
            let area = abs(signedArea(simplified))
            os_log("[%llu]   area=%.1f pts=%d", log: log, type: .debug, fid, area, simplified.count)
            let path = CGMutablePath()
            path.move(to: simplified[0])
            for p in simplified.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            if best == nil || area < best!.area {
                best = (path, area)
            }
        }
        return best?.path
    }

    private static func rdpSimplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var dmax: CGFloat = 0
        var idx = 0
        for i in 1..<points.count - 1 {
            let d = perpDist(points[i], points[0], points[points.count - 1])
            if d > dmax { dmax = d; idx = i }
        }
        if dmax > epsilon {
            return rdpSimplify(Array(points[0...idx]), epsilon: epsilon).dropLast()
                + rdpSimplify(Array(points[idx..<points.count]), epsilon: epsilon)
        }
        return [points[0], points[points.count - 1]]
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var area: CGFloat = 0
        var j = points.count - 1
        for i in 0..<points.count {
            area += (points[j].x + points[i].x) * (points[j].y - points[i].y)
            j = i
        }
        return area / 2
    }

    private static func perpDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq != 0 else { return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let px = a.x + t * dx, py = a.y + t * dy
        return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py))
    }
}

// MARK: - PSLG Engine

private struct Vertex: Hashable {
    let point: CGPoint
    func hash(into hasher: inout Hasher) {
        hasher.combine(point.x)
        hasher.combine(point.y)
    }
    static func == (lhs: Vertex, rhs: Vertex) -> Bool {
        lhs.point == rhs.point
    }
}

private class HalfEdge: Hashable {
    let id = UUID()
    var origin: Vertex
    var twin: HalfEdge?
    var next: HalfEdge?
    var visited = false

    init(origin: Vertex) { self.origin = origin }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HalfEdge, rhs: HalfEdge) -> Bool { lhs.id == rhs.id }
}

private enum EnclosureDetector {

    /// Detect all enclosed cycles from a set of line segments.
    static func detect(from segments: [(CGPoint, CGPoint)], fillId fid: UInt64) -> [CGPath] {
        var split = segments
        os_log("[%llu] detect: %d input segments", log: log, type: .debug, fid, split.count)

        // Phase 1: split segments at intersections
        var i = 0
        var totalSplits = 0
        while i < split.count {
            var j = i + 1
            var advanced = false
            while j < split.count {
                let s1 = split[i], s2 = split[j]
                if segRect(s1).intersects(segRect(s2)) {
                    if let p = intersect(s1.0, s1.1, s2.0, s2.1) {
                        let on1 = !isEndpoint(p, s1.0, s1.1)
                        let on2 = !isEndpoint(p, s2.0, s2.1)
                        if on1 { totalSplits += 1 }
                        if on2 && !on1 { totalSplits += 1 }
                        if on1 {
                            split.remove(at: i)
                            split.insert((s1.0, p), at: i)
                            split.insert((p, s1.1), at: i + 1)
                            advanced = true; break
                        }
                        if on2 {
                            split.remove(at: j)
                            split.insert((s2.0, p), at: j)
                            split.insert((p, s2.1), at: j + 1)
                            j += 1
                        }
                    }
                }
                j += 1
            }
            if !advanced { i += 1 }
        }
        os_log("[%llu] after intersection split: %d segments (%d splits)", log: log, type: .debug, fid, split.count, totalSplits)

        var adj = [Vertex: [HalfEdge]]()
        var allEdges = [HalfEdge]()

        for seg in split {
            let v1 = Vertex(point: seg.0), v2 = Vertex(point: seg.1)
            let e1 = HalfEdge(origin: v1), e2 = HalfEdge(origin: v2)
            e1.twin = e2; e2.twin = e1
            adj[v1, default: []].append(e1)
            adj[v2, default: []].append(e2)
            allEdges.append(e1)
            allEdges.append(e2)
        }
        os_log("[%llu] adj vertices: %d, edges: %d", log: log, type: .debug, fid, adj.count, allEdges.count)

        // Sort edges around each vertex by angle (CCW) and link 'next' pointers
        for (v, edges) in adj {
            let sorted = edges.sorted { a, b in
                let da = a.twin!.origin.point
                let db = b.twin!.origin.point
                return atan2(da.y - v.point.y, da.x - v.point.x) <
                       atan2(db.y - v.point.y, db.x - v.point.x)
            }
            for e in sorted {
                guard let twin = e.twin else { continue }
                let twinOrigin = twin.origin
                guard let twinEdges = adj[twinOrigin] else { continue }
                let twinSorted = twinEdges.sorted { a, b in
                    let da = a.twin!.origin.point
                    let db = b.twin!.origin.point
                    return atan2(da.y - twinOrigin.point.y, da.x - twinOrigin.point.x) <
                           atan2(db.y - twinOrigin.point.y, db.x - twinOrigin.point.x)
                }
                if let idx = twinSorted.firstIndex(of: twin) {
                    let nextIdx = (idx + 1) % twinSorted.count
                    twin.next = twinSorted[nextIdx]
                }
            }
        }

        // Phase 3: traverse cycles using left-hand turn rule
        var paths = [CGPath]()
        var cycleCount = 0
        for start in allEdges where !start.visited {
            var pts = [CGPoint]()
            var cur: HalfEdge? = start
            while let c = cur, !c.visited {
                c.visited = true
                pts.append(c.origin.point)
                cur = c.twin?.next
            }
            if pts.count >= 3 {
                let area = signedArea(pts)
                cycleCount += 1
                if area > 0 {
                    let path = CGMutablePath()
                    path.move(to: pts[0])
                    for k in 1..<pts.count { path.addLine(to: pts[k]) }
                    path.closeSubpath()
                    paths.append(path)
                    os_log("[%llu]   cycle[%d] CCW pts=%d area=%.1f", log: log, type: .debug, fid, cycleCount, pts.count, area)
                } else {
                    os_log("[%llu]   cycle[%d] CW (hole) pts=%d area=%.1f — skipped", log: log, type: .debug, fid, cycleCount, pts.count, area)
                }
            }
        }
        os_log("[%llu] detect returning %d enclosures", log: log, type: .debug, fid, paths.count)
        return paths
    }

    // MARK: - Helpers

    private static func segRect(_ seg: (CGPoint, CGPoint)) -> CGRect {
        CGRect(x: min(seg.0.x, seg.1.x), y: min(seg.0.y, seg.1.y),
               width: abs(seg.1.x - seg.0.x), height: abs(seg.1.y - seg.0.y))
    }

    private static func intersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let d1x = b.x - a.x, d1y = b.y - a.y
        let d2x = d.x - c.x, d2y = d.y - c.y
        let denom = d1x * d2y - d1y * d2x
        guard abs(denom) > 1e-10 else { return nil }
        let t = ((c.x - a.x) * d2y - (c.y - a.y) * d2x) / denom
        let u = ((c.x - a.x) * d1y - (c.y - a.y) * d1x) / denom
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return CGPoint(x: a.x + t * d1x, y: a.y + t * d1y)
    }

    private static func isEndpoint(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Bool {
        p.distance(to: a) < 0.01 || p.distance(to: b) < 0.01
    }

    private static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 3 else { return 0 }
        var area: CGFloat = 0
        var j = pts.count - 1
        for i in 0..<pts.count {
            area += (pts[j].x + pts[i].x) * (pts[j].y - pts[i].y)
            j = i
        }
        return area / 2
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x, dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
