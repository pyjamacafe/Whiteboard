import SwiftUI
import CoreGraphics

// MARK: - Planar Straight-Line Graph (PSLG) Enclosure Detection

enum FloodFill {

    static func fillPath(at canvasPoint: CGPoint, strokes: [Stroke]) -> CGPath? {
        print("[FF] fillPath at (\(canvasPoint.x), \(canvasPoint.y))")

        var segs: [(CGPoint, CGPoint)] = []
        for s in strokes where !s.isEraser {
            for i in 0..<s.points.count - 1 {
                segs.append((s.points[i], s.points[i + 1]))
            }
            if s.points.count >= 3 {
                let d = s.points.first!.distance(to: s.points.last!)
                if d < 30 {
                    segs.append((s.points.last!, s.points.first!))
                    print("[FF] closed stroke loop (dist=\(d))")
                }
            }
        }
        print("[FF] segments: \(segs.count)")
        guard !segs.isEmpty else { print("[FF] no segments"); return nil }

        let enclosures = EnclosureDetector.detect(from: segs)
        print("[FF] enclosures found: \(enclosures.count)")

        var best: (path: CGPath, area: CGFloat)?
        for (idx, path) in enclosures.enumerated() {
            let box = path.boundingBox
            print("[FF] enclosure \(idx): box=\(box), null=\(box.isNull)")
            guard !box.isNull else { continue }
            let boxContains = box.contains(canvasPoint)
            print("[FF]   box contains tap: \(boxContains)")
            guard boxContains else { continue }
            let pts = pathPoints(path)
            let pip = pointInPolygon(canvasPoint, pts)
            print("[FF]   pointInPolygon: \(pip), pts=\(pts.count)")
            guard pip else { continue }
            let area = abs(signedArea(pts))
            print("[FF]   area: \(area)")
            if best == nil || area < best!.area {
                best = (path, area)
            }
        }
        print("[FF] best: \(best != nil ? "found area \(best!.area)" : "nil")")
        return best?.path
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
}

// MARK: - PSLG Engine

private struct Vertex: Hashable {
    let point: CGPoint
    func hash(into hasher: inout Hasher) {
        hasher.combine(Int(point.x * 100))
        hasher.combine(Int(point.y * 100))
    }
    static func == (lhs: Vertex, rhs: Vertex) -> Bool {
        lhs.point.distance(to: rhs.point) < 0.01
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
    static func detect(from segments: [(CGPoint, CGPoint)]) -> [CGPath] {
        print("[DCEL] input segments: \(segments.count)")

        // Phase 1: split segments at intersection points
        var split = segments
        var splitCount = 0
        var i = 0
        while i < split.count {
            var j = i + 1
            var advanced = false
            while j < split.count {
                let s1 = split[i], s2 = split[j]
                if let p = intersect(s1.0, s1.1, s2.0, s2.1) {
                    let on1 = !isEndpoint(p, s1.0, s1.1)
                    let on2 = !isEndpoint(p, s2.0, s2.1)
                    if on1 {
                        split.remove(at: i)
                        split.insert((s1.0, p), at: i)
                        split.insert((p, s1.1), at: i + 1)
                        splitCount += 1
                        advanced = true
                        break
                    }
                    if on2 {
                        split.remove(at: j)
                        split.insert((s2.0, p), at: j)
                        split.insert((p, s2.1), at: j + 1)
                        splitCount += 1
                        j += 1
                    }
                }
                j += 1
            }
            if !advanced { i += 1 }
        }
        print("[DCEL] after split: \(split.count) segments, \(splitCount) splits")

        // Phase 2: build DCEL graph
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
        print("[DCEL] vertices: \(adj.count), half-edges: \(allEdges.count)")

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
                print("[DCEL] cycle \(cycleCount): pts=\(pts.count), area=\(area)")
                if area > 0 {
                    let path = CGMutablePath()
                    path.move(to: pts[0])
                    for k in 1..<pts.count { path.addLine(to: pts[k]) }
                    path.closeSubpath()
                    paths.append(path)
                }
                cycleCount += 1
            }
        }
        print("[DCEL] total cycles: \(cycleCount), positive-area (enclosures): \(paths.count)")
        return paths
    }

    // MARK: - Helpers

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

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x, dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
