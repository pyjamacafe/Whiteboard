import SwiftUI
import Combine

// MARK: - iOS Canvas

#if os(iOS)

struct CanvasView: UIViewRepresentable {
    @ObservedObject var model: DrawingModel
    var onBeginDraw: (() -> Void)?

    func makeUIView(context: Context) -> DrawingCanvasView {
        let view = DrawingCanvasView()
        view.model = model
        view.onBeginDraw = onBeginDraw
        return view
    }

    func updateUIView(_ uiView: DrawingCanvasView, context: Context) {
        uiView.model = model
        if model.needsDelete {
            print("[sel] updateUIView processing needsDelete")
            model.deleteSelected()
            model.needsDelete = false
            print("[sel] updateUIView after delete — strokes=\(model.strokes.count) fillRegions=\(model.fillRegions.count)")
        }
        uiView.refresh()
        uiView.onBeginDraw = onBeginDraw
    }
}

// MARK: - Grid View

class CanvasGridView: UIView {
    weak var model: DrawingModel?
    var offset: CGSize = .zero
    var scale: CGFloat = 1.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let model = model else { return }

        let isDark = model.appSettings.isDarkMode
        let bg: UIColor = isDark ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1) : .white
        let fg: UIColor = isDark ? UIColor(red: 56/255, green: 56/255, blue: 58/255, alpha: 1) : .systemGray5
        ctx.setFillColor(bg.cgColor)
        ctx.fill(rect)

        ctx.saveGState()
        ctx.translateBy(x: offset.width, y: offset.height)
        ctx.scaleBy(x: scale, y: scale)

        let spacing: CGFloat = 30
        let canvasRect = CGRect(
            x: (rect.minX - offset.width) / scale,
            y: (rect.minY - offset.height) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )

        switch model.appSettings.canvasBackground {
        case .none: break
        case .grid: drawGrid(in: ctx, spacing: spacing, canvasRect: canvasRect, color: fg)
        case .dots: drawDots(in: ctx, spacing: spacing, canvasRect: canvasRect, color: fg)
        case .ruled: drawRuled(in: ctx, spacing: spacing, canvasRect: canvasRect, color: fg)
        }

        ctx.restoreGState()
    }

    private func drawGrid(in ctx: CGContext, spacing: CGFloat, canvasRect: CGRect, color: UIColor) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5 / scale)
        let startX = (canvasRect.minX / spacing).rounded(.down) * spacing
        let startY = (canvasRect.minY / spacing).rounded(.down) * spacing
        var x = startX
        while x <= canvasRect.maxX {
            ctx.move(to: CGPoint(x: x, y: canvasRect.minY - spacing))
            ctx.addLine(to: CGPoint(x: x, y: canvasRect.maxY + spacing))
            x += spacing
        }
        var y = startY
        while y <= canvasRect.maxY {
            ctx.move(to: CGPoint(x: canvasRect.minX - spacing, y: y))
            ctx.addLine(to: CGPoint(x: canvasRect.maxX + spacing, y: y))
            y += spacing
        }
        ctx.strokePath()
    }

    private func drawDots(in ctx: CGContext, spacing: CGFloat, canvasRect: CGRect, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        let r = max(1.5 / scale, 1)
        let startX = (canvasRect.minX / spacing).rounded(.down) * spacing
        let startY = (canvasRect.minY / spacing).rounded(.down) * spacing
        var x = startX
        while x <= canvasRect.maxX {
            var y = startY
            while y <= canvasRect.maxY {
                let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.addEllipse(in: dot)
                y += spacing
            }
            x += spacing
        }
        ctx.fillPath()
    }

    private func drawRuled(in ctx: CGContext, spacing: CGFloat, canvasRect: CGRect, color: UIColor) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5 / scale)
        let startY = (canvasRect.minY / spacing).rounded(.down) * spacing
        var y = startY
        while y <= canvasRect.maxY {
            ctx.move(to: CGPoint(x: canvasRect.minX - spacing, y: y))
            ctx.addLine(to: CGPoint(x: canvasRect.maxX + spacing, y: y))
            y += spacing
        }
        ctx.strokePath()
    }
}

// MARK: - Stroke Layer View

class StrokeLayerView: UIView {
    weak var model: DrawingModel?
    var offset: CGSize = .zero
    var scale: CGFloat = 1.0
    var dashPhase: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let model = model else { return }

        ctx.saveGState()
        ctx.translateBy(x: offset.width, y: offset.height)
        ctx.scaleBy(x: scale, y: scale)

        for region in model.fillRegions {
            drawFill(region, in: ctx)
        }
        // Highlighter strokes composited as a group — overlapping areas don't darken
        ctx.saveGState()
        ctx.setAlpha(CGFloat(model.highlighterSettings.opacity))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for stroke in model.strokes where stroke.isHighlighter {
            drawStroke(stroke, in: ctx)
        }
        if let current = model.currentStroke, current.isHighlighter {
            drawStroke(current, in: ctx)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        for stroke in model.strokes where !stroke.isHighlighter {
            drawStroke(stroke, in: ctx)
        }
        if let current = model.currentStroke, !current.isHighlighter {
            drawStroke(current, in: ctx)
        }

        // Lasso being drawn
        if !model.selectionLasso.isEmpty {
            ctx.saveGState()
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(2 / scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let dashes: [CGFloat] = [8 / scale, 5 / scale]
            ctx.setLineDash(phase: dashPhase / scale, lengths: dashes)

            let lasso = model.selectionLasso
            let lPath = CGMutablePath()
            lPath.move(to: lasso[0])
            var prev = lasso[0]
            for i in 1..<lasso.count {
                let pt = lasso[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                lPath.addQuadCurve(to: mid, control: prev)
                prev = pt
            }
            ctx.addPath(lPath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Fill lasso being drawn
        if !model.fillLassoPoints.isEmpty {
            ctx.saveGState()
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(2 / scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let dashes: [CGFloat] = [8 / scale, 5 / scale]
            ctx.setLineDash(phase: dashPhase / scale, lengths: dashes)

            let fPts = model.fillLassoPoints
            let fPath = CGMutablePath()
            fPath.move(to: fPts[0])
            var prev = fPts[0]
            for i in 1..<fPts.count {
                let pt = fPts[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                fPath.addQuadCurve(to: mid, control: prev)
                prev = pt
            }
            ctx.addPath(fPath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Selection boundary — retained lasso outline
        if !model.selectionBoundary.isEmpty {
            let pts = model.selectionBoundary
            ctx.saveGState()
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(2 / scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let dashes: [CGFloat] = [8 / scale, 5 / scale]
            ctx.setLineDash(phase: dashPhase / scale, lengths: dashes)
            let bPath = CGMutablePath()
            bPath.move(to: pts[0])
            var prev = pts[0]
            for i in 1..<pts.count {
                let pt = pts[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                bPath.addQuadCurve(to: mid, control: prev)
                prev = pt
            }
            bPath.closeSubpath()
            ctx.addPath(bPath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Persistent laser strokes with glow
        for strokeEntry in model.persistentLaserStrokes where strokeEntry.points.count >= 2 {
            let strokePts = strokeEntry.points
            let now = Date()
            let age = strokeEntry.isRetained ? 0 : now.timeIntervalSince(strokeEntry.time)
            let fadeAlpha = max(0, 1 - CGFloat(age / model.laserSettings.tailFade))
            guard fadeAlpha > 0 else { continue }
            if fadeAlpha < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.setNeedsDisplay()
                }
            }
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let ls = model.laserSettings.size / scale
            let basePath = CGMutablePath()
            basePath.move(to: strokePts[0])
            var prev = strokePts[0]
            for i in 1..<strokePts.count {
                let pt = strokePts[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                basePath.addQuadCurve(to: mid, control: prev)
                prev = pt
            }
            basePath.addLine(to: strokePts.last!)
            // Glow (red shadow)
            ctx.setLineWidth(ls * 3)
            ctx.setStrokeColor(UIColor.red.withAlphaComponent(max(0.9 * fadeAlpha, 0)).cgColor)
            ctx.addPath(basePath)
            ctx.strokePath()
            ctx.setLineWidth(ls)
            let isDark = model.appSettings.isDarkMode
            ctx.setStrokeColor((isDark ? UIColor.black : UIColor.white).withAlphaComponent(fadeAlpha).cgColor)
            ctx.addPath(basePath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Current laser tail
        if !model.laserTail.isEmpty {
            let pts = model.laserTail
            let now = Date()
            let fade = model.laserSettings.tailFade
            let alpha = model.laserTailFadeStart.map { max(0, 1 - now.timeIntervalSince($0) / fade) } ?? 1
            if alpha <= 0 { model.laserTail.removeAll(); model.laserTailFadeStart = nil }
            if alpha > 0, alpha < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.setNeedsDisplay()
                }
            }
            if alpha > 0 && pts.count >= 2 {
                ctx.saveGState()
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                let ls = model.laserSettings.size / scale
                let smoothPath = CGMutablePath()
                smoothPath.move(to: pts[0].point)
                var prev = pts[0].point
                for i in 1..<pts.count {
                    let pt = pts[i].point
                    let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                    smoothPath.addQuadCurve(to: mid, control: prev)
                    prev = pt
                }
                smoothPath.addLine(to: pts.last!.point)
                let isDark = model.appSettings.isDarkMode
                // Glow (red shadow) with alpha
                ctx.setLineWidth(ls * 3)
                ctx.setStrokeColor(UIColor.red.withAlphaComponent(CGFloat(alpha) * 0.9).cgColor)
                ctx.addPath(smoothPath)
                ctx.strokePath()
                // Core stroke with alpha
                ctx.setLineWidth(ls)
                ctx.setStrokeColor((isDark ? UIColor.black : UIColor.white).withAlphaComponent(CGFloat(alpha)).cgColor)
                ctx.addPath(smoothPath)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        // Laser pointer dot
        if model.currentTool == .laser, let lp = model.laserPointer {
            ctx.saveGState()
            ctx.setBlendMode(.normal)
            let ls = model.laserSettings.size / scale
            let isDark = model.appSettings.isDarkMode
            let lc = isDark ? UIColor.black : UIColor.white

            for i in (0...3).reversed() {
                let r = ls + CGFloat(i) * 4 / scale
                ctx.setFillColor(UIColor.red.withAlphaComponent(0.08 - CGFloat(i) * 0.02).cgColor)
                ctx.addEllipse(in: CGRect(x: lp.x - r, y: lp.y - r, width: r * 2, height: r * 2))
                ctx.fillPath()
            }
            ctx.setFillColor(lc.cgColor)
            ctx.addEllipse(in: CGRect(x: lp.x - ls / 2, y: lp.y - ls / 2, width: ls, height: ls))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.restoreGState()
        ctx.restoreGState()
    }

    private func drawFill(_ region: FillRegion, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setFillColor(UIColor(region.displayColor(for: model!)).cgColor)
        ctx.addPath(region.cgPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count >= 2 else { return }

        let path = CGMutablePath()
        if stroke.isCatmullRom {
            let smoothed = model!.smoothCatmullRom(stroke.points)
            guard smoothed.count >= 4 else {
                // Fallback to raw points
                path.move(to: stroke.points[0])
                var prev = stroke.points[0]
                for i in 1..<stroke.points.count {
                    let pt = stroke.points[i]
                    let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                    path.addQuadCurve(to: mid, control: prev)
                    prev = pt
                }
                path.addLine(to: stroke.points.last!)
                return
            }
            path.move(to: smoothed[0])
            var i = 1
            while i + 2 < smoothed.count {
                let cp1 = smoothed[i]
                let cp2 = smoothed[i + 1]
                let on = smoothed[i + 2]
                path.addCurve(to: on, control1: cp1, control2: cp2)
                i += 3
            }
            while i < smoothed.count {
                path.addLine(to: smoothed[i])
                i += 1
            }
        } else {
            path.move(to: stroke.points[0])
            var prev = stroke.points[0]
            for i in 1..<stroke.points.count {
                let pt = stroke.points[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                path.addQuadCurve(to: mid, control: prev)
                prev = pt
            }
            path.addLine(to: stroke.points.last!)
        }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if stroke.isEraser {
            ctx.setBlendMode(.clear)
            ctx.setLineWidth((model?.eraserSettings.size ?? 20) / scale)
        } else {
            ctx.setBlendMode(.normal)
            let color = stroke.displayColor(for: model!)
            ctx.setStrokeColor(UIColor(color).cgColor)
            ctx.setLineWidth(stroke.lineWidth)
        }

        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

}

// MARK: - Canvas Container View

class DrawingCanvasView: UIView {
    weak var model: DrawingModel? {
        didSet {
            strokeLayer.model = model
            gridView.model = model
        }
    }
    var onBeginDraw: (() -> Void)?
    var lastTouchPoint: CGPoint = .zero

    private var offset: CGSize = .zero {
        didSet {
            gridView.offset = offset
            strokeLayer.offset = offset
        }
    }
    private var scale: CGFloat = 1.0 {
        didSet {
            gridView.scale = scale
            strokeLayer.scale = scale
        }
    }

    private let gridView = CanvasGridView()
    private let strokeLayer = StrokeLayerView()
    private var dashPhase: CGFloat = 0
    private var displayLink: CADisplayLink?

    private func startDashAnimation() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepDash(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDashAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func stepDash(_ link: CADisplayLink) {
        guard let model = model, (!model.selectionBoundary.isEmpty || !model.selectionLasso.isEmpty) else {
            stopDashAnimation()
            return
        }
        dashPhase += 1
        strokeLayer.dashPhase = dashPhase
        strokeLayer.setNeedsDisplay()
    }

    private lazy var pinchGesture: UIPinchGestureRecognizer = {
        let g = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        return g
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        g.minimumNumberOfTouches = 2
        g.maximumNumberOfTouches = 2
        return g
    }()

    private weak var hoverIndicator: CALayer?
    private var isTouchActive: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isMultipleTouchEnabled = true
        #if targetEnvironment(macCatalyst)
        addGestureRecognizer(pinchGesture)
        #endif
        addGestureRecognizer(panGesture)

        gridView.frame = bounds
        gridView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(gridView)

        strokeLayer.frame = bounds
        strokeLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(strokeLayer)

        if #available(iOS 17.0, *) {
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            addGestureRecognizer(hover)
        }

        if #available(iOS 12.1, *) {
            let interaction = UIPencilInteraction()
            interaction.delegate = self
            addInteraction(interaction)
        }

        let fillDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleFillDoubleTap(_:)))
        fillDoubleTap.numberOfTapsRequired = 2
        fillDoubleTap.delaysTouchesBegan = false
        fillDoubleTap.delaysTouchesEnded = false
        addGestureRecognizer(fillDoubleTap)
    }

    @objc private func handleFillDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let model = model, model.currentTool == .fill else { return }
        if gesture.state == .recognized {
            let loc = gesture.location(in: self)
            model.performFill(at: toCanvas(loc))
            strokeLayer.setNeedsDisplay()
            gridView.setNeedsDisplay()
        }
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let loc = gesture.location(in: self)
            if !isTouchActive {
                showHoverIndicator(at: loc)
            }
        case .ended, .cancelled:
            if !isTouchActive {
                hideHoverIndicator()
            }
        default:
            break
        }
    }

    private func showHoverIndicator(at point: CGPoint) {
        guard let model = model else { return }
        let size: CGFloat
        var color: UIColor
        switch model.currentTool {
        case .eraser:
            size = model.eraserSettings.size
            color = UIColor.red.withAlphaComponent(0.25)
        case .pen:
            size = model.penSettings.thickness * 1.5
            color = UIColor.black.withAlphaComponent(0.4)
        case .highlighter:
            size = model.highlighterSettings.thickness
            color = UIColor(model.hlColor).withAlphaComponent(CGFloat(model.highlighterSettings.opacity))
        default:
            size = 4
            color = UIColor.black.withAlphaComponent(0.4)
        }
        let indicator = CALayer()
        indicator.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2,
                                 width: size, height: size)
        indicator.cornerRadius = size / 2
        indicator.backgroundColor = color.cgColor
        hoverIndicator?.removeFromSuperlayer()
        layer.addSublayer(indicator)
        hoverIndicator = indicator
    }

    private func hideHoverIndicator() {
        hoverIndicator?.removeFromSuperlayer()
        hoverIndicator = nil
    }

    private func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }

    func refresh() {
        if let model = model, model.needsRecenter {
            centerOnContent()
            model.needsRecenter = false
        }
        // Force model to be up to date
        strokeLayer.model = model
        gridView.model = model
        gridView.setNeedsDisplay()
        strokeLayer.setNeedsDisplay()
    }

    private func centerOnContent() {
        offset = .zero
        scale = 1.0
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let model = model else { return }
        isTouchActive = true
        hideHoverIndicator()
        lastTouchPoint = touch.location(in: self)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard touch.type == .pencil else { return }
        #endif

        onBeginDraw?()

        if model.currentTool == .fill {
            model.beginFillLasso(at: toCanvas(touch.location(in: self)))
            strokeLayer.setNeedsDisplay()
            return
        }

        if model.currentTool == .select {
            let cp = toCanvas(touch.location(in: self))
            if !model.selectedStrokeIds.isEmpty || !model.selectedFillIds.isEmpty || !model.selectionBoundary.isEmpty {
                let onSelected = model.isPointOnSelectedItem(cp) || (!model.selectionBoundary.isEmpty && model.isPointInSelectionBoundary(cp))
                print("[sel] touchesBegan select — selection exists, onSelected=\(onSelected)")
                if onSelected {
                    let now = Date()
                    if now.timeIntervalSince(Self.lastSelectTap) < 0.3 {
                        Self.lastSelectTap = .distantPast
                        print("[sel] double-tap detected — showing delete menu, selections=\(model.selectedStrokeIds.count)/\(model.selectedFillIds.count) boundary=\(model.selectionBoundary.count)")
                        model.showDeleteMenu = true
                        let tapLoc = touch.location(in: self)
                        model.deleteMenuLocation = CGPoint(x: tapLoc.x + 60, y: tapLoc.y)
                        strokeLayer.model = model
                        gridView.model = model
                        strokeLayer.setNeedsDisplay()
                        gridView.setNeedsDisplay()
                        return
                    }
                    Self.lastSelectTap = now
                    model.beginMove(at: cp)
                } else {
                    // Tap outside selection — deselect
                    model.selectedStrokeIds.removeAll()
                    model.selectedFillIds.removeAll()
                    model.selectionBoundary.removeAll()
                }
            } else {
                model.beginLasso(at: cp)
                startDashAnimation()
            }
            strokeLayer.setNeedsDisplay()
            return
        }

        if model.currentTool == .laser {
            let cp = toCanvas(touch.location(in: self))
            model.laserTail = [(cp, Date())]
            model.laserPointer = cp
            model.laserTailFadeStart = nil
            strokeLayer.setNeedsDisplay()
            return
        }

        model.beginStroke(at: toCanvas(touch.location(in: self)), isEraser: model.currentTool == .eraser)
        strokeLayer.setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let model = model else { return }
        lastTouchPoint = touch.location(in: self)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard touch.type == .pencil else { return }
        #endif

        if model.currentTool == .laser {
            let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
            for ct in coalesced {
                let cp = toCanvas(ct.location(in: self))
                model.laserPointer = cp
                model.laserTail.append((cp, Date()))
            }
            strokeLayer.setNeedsDisplay()
            return
        }

        if model.currentTool == .select {
            if model.showDeleteMenu { return }
            if model.isMoving {
                let cur = toCanvas(touch.location(in: self))
                let offset = CGSize(width: cur.x - model.lastMovePoint.x, height: cur.y - model.lastMovePoint.y)
                model.moveSelected(by: offset)
                model.lastMovePoint = cur
            } else {
                let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
                for ct in coalesced {
                    model.addLassoPoint(toCanvas(ct.location(in: self)))
                }
            }
            strokeLayer.setNeedsDisplay()
            return
        }

        if model.currentTool == .fill {
            let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
            for ct in coalesced {
                model.addFillLassoPoint(toCanvas(ct.location(in: self)))
            }
            strokeLayer.setNeedsDisplay()
            return
        }

        guard model.currentStroke != nil else { return }

        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        for ct in coalesced {
            model.addPoint(toCanvas(ct.location(in: self)))
        }
        strokeLayer.setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouchActive = false
        if model?.currentTool == .laser {
            if let model = model, !model.laserTail.isEmpty {
                let strokePts = model.laserTail.map { $0.point }
                model.persistentLaserStrokes.append((points: strokePts, time: Date(), isRetained: model.laserSettings.retainStrokes))
                if !model.laserSettings.retainStrokes {
                    model.laserTailFadeStart = Date()
                } else {
                    model.laserTail.removeAll()
                }
                model.laserPointer = nil
            }
            strokeLayer.setNeedsDisplay()
            return
        }
        if model?.currentTool == .select {
            if model?.showDeleteMenu == true { return }
            print("[sel] touchesEnded select — isMoving=\(model?.isMoving == true) calling \(model?.isMoving == true ? "commitMove" : "endLasso")")
            if model?.isMoving == true {
                model?.commitMove()
            } else {
                model?.endLasso()
            }
            strokeLayer.setNeedsDisplay()
            return
        }
        if model?.currentTool == .fill {
            model?.endFillLasso()
            strokeLayer.setNeedsDisplay()
            gridView.setNeedsDisplay()
            return
        }
        model?.endStroke()
        hideHoverIndicator()
        strokeLayer.setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouchActive = false
        if model?.currentTool == .select {
            model?.endLasso()
            strokeLayer.setNeedsDisplay()
            return
        }
        if model?.currentTool == .fill {
            model?.fillLassoPoints = []
            strokeLayer.setNeedsDisplay()
            return
        }
        model?.endStroke()
        strokeLayer.setNeedsDisplay()
    }

    // MARK: - Gestures

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        scale = min(max(scale * gesture.scale, 0.3), 5.0)
        gesture.scale = 1
        gridView.setNeedsDisplay()
        strokeLayer.setNeedsDisplay()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let t = gesture.translation(in: self)
        offset.width += t.x
        offset.height += t.y
        gesture.setTranslation(.zero, in: self)
        gridView.setNeedsDisplay()
        strokeLayer.setNeedsDisplay()
    }
}

// MARK: - Pencil Interaction

@available(iOS 12.1, *)
extension DrawingCanvasView: UIPencilInteractionDelegate {
    static var lastPencilTap: Date = .distantPast
    static var lastSelectTap: Date = .distantPast

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        guard let model = model else { return }
        // Double-tap → toggle eraser / previous active tool
        if model.currentTool == .eraser {
            model.selectTool(model.previousTool)
        } else {
            model.previousTool = model.currentTool
            model.selectTool(.eraser)
        }
    }

    @available(iOS 17.5, *)
    @available(iOS 17.5, *)
    func pencilInteractionDidSqueeze(_ interaction: UIPencilInteraction) { }
}

// MARK: - macOS Canvas

#else

struct CanvasView: View {
    @ObservedObject var model: DrawingModel
    var onBeginDraw: (() -> Void)?
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var pointCount: Int = 0
    @State private var hoverLocation: CGPoint?

    static var lastSelectTap: Date = .distantPast

    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var macDashPhase: CGFloat = 0
    @State private var dashTimer: Timer?
    @State private var viewSize: CGSize?

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Color.clear.onAppear { viewSize = geo.size }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Canvas { context, size in
                let spacing: CGFloat = 30 * scale
                let isDark = model.appSettings.isDarkMode
                let bg = isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.white
                let fg = isDark ? Color(red: 56/255, green: 56/255, blue: 58/255) : Color.gray.opacity(0.2)

                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

                switch model.appSettings.canvasBackground {
                case .none: break
                case .grid:
                    let gridPath = gridLines(spacing: spacing, size: size, offset: offset)
                    context.stroke(gridPath, with: .color(fg), lineWidth: 0.5)
                case .dots:
                    let dotsPath = dotGrid(spacing: spacing, size: size, offset: offset)
                    context.fill(dotsPath, with: .color(fg))
                case .ruled:
                    let ruledPath = ruledLines(spacing: spacing, size: size, offset: offset)
                    context.stroke(ruledPath, with: .color(fg), lineWidth: 0.5)
                }
            }

            Canvas { context, size in
                let _ = pointCount
                let _ = hoverLocation

                let tf = CGAffineTransform(translationX: offset.width, y: offset.height)
                    .scaledBy(x: scale, y: scale)

                for region in model.fillRegions {
                    drawFill(region, in: &context, transform: tf)
                }
                // Highlighter strokes — composite all as a single layer at uniform opacity
                let hlOpacity = model.highlighterSettings.opacity
                if hlOpacity > 0 {
                    context.opacity = hlOpacity
                    context.drawLayer { layer in
                        for s in model.strokes where s.isHighlighter {
                            if let path = makeSmoothPath(s, transform: tf) {
                                layer.stroke(path, with: .color(s.uiColor),
                                            style: StrokeStyle(lineWidth: s.lineWidth * scale, lineCap: .round, lineJoin: .round))
                            }
                        }
                        if let c = model.currentStroke, c.isHighlighter,
                           let path = makeSmoothPath(c, transform: tf) {
                            layer.stroke(path, with: .color(c.uiColor),
                                        style: StrokeStyle(lineWidth: c.lineWidth * scale, lineCap: .round, lineJoin: .round))
                        }
                    }
                    context.opacity = 1
                }
                for stroke in model.strokes where !stroke.isHighlighter {
                    drawStroke(stroke, in: &context, transform: tf)
                }
                if let current = model.currentStroke, !current.isHighlighter {
                    drawStroke(current, in: &context, transform: tf)
                }

                // Lasso being drawn
                if !model.selectionLasso.isEmpty {
                    var lPath = Path()
                    let lPts = model.selectionLasso
                    lPath.move(to: lPts[0].applying(tf))
                    var prev = lPts[0]
                    for i in 1..<lPts.count {
                        let pt = lPts[i]
                        let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                        lPath.addQuadCurve(to: mid.applying(tf), control: prev.applying(tf))
                        prev = pt
                    }
                    context.stroke(lPath, with: .color(.blue.opacity(0.6)),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: macDashPhase))
                }

                // Fill lasso being drawn
                if !model.fillLassoPoints.isEmpty {
                    var fPath = Path()
                    let fPts = model.fillLassoPoints
                    fPath.move(to: fPts[0].applying(tf))
                    var prev = fPts[0]
                    for i in 1..<fPts.count {
                        let pt = fPts[i]
                        let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                        fPath.addQuadCurve(to: mid.applying(tf), control: prev.applying(tf))
                        prev = pt
                    }
                    context.stroke(fPath, with: .color(.yellow.opacity(0.8)),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: macDashPhase))
                }

                // Selection boundary — retained lasso outline
                if !model.selectionBoundary.isEmpty {
                    let pts = model.selectionBoundary
                    var bPath = Path()
                    bPath.move(to: pts[0].applying(tf))
                    var prev = pts[0]
                    for i in 1..<pts.count {
                        let pt = pts[i]
                        let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                        bPath.addQuadCurve(to: mid.applying(tf), control: prev.applying(tf))
                        prev = pt
                    }
                    bPath.closeSubpath()
                    context.stroke(bPath, with: .color(.blue),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: macDashPhase))
                }

                // Persistent laser strokes with glow (macOS)
                for strokeEntry in model.persistentLaserStrokes where strokeEntry.points.count >= 2 {
                    let strokePts = strokeEntry.points
                    let now = Date()
            let age = strokeEntry.isRetained ? 0 : now.timeIntervalSince(strokeEntry.time)
                    let fadeAlpha = max(0, 1 - CGFloat(age / model.laserSettings.tailFade))
                    guard fadeAlpha > 0 else { continue }
                    var basePath = Path()
                    basePath.move(to: strokePts[0].applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: offset.width, y: offset.height)))
                    var prev = strokePts[0]
                    for i in 1..<strokePts.count {
                        let pt = strokePts[i]
                        let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                        basePath.addQuadCurve(to: mid.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: offset.width, y: offset.height)), control: prev.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: offset.width, y: offset.height)))
                        prev = pt
                    }
                    basePath.addLine(to: strokePts.last!.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: offset.width, y: offset.height)))
                    let ls = model.laserSettings.size
                    context.stroke(basePath, with: .color(Color.red.opacity(Double(fadeAlpha) * 0.9)), style: StrokeStyle(lineWidth: ls * 3, lineCap: .round, lineJoin: .round))
                    context.stroke(basePath, with: .color((model.appSettings.isDarkMode ? Color.black : Color.white).opacity(Double(fadeAlpha))), style: StrokeStyle(lineWidth: ls, lineCap: .round, lineJoin: .round))
                }

                // Current laser tail
                if !model.laserTail.isEmpty {
                    let now = Date()
                    let fade = model.laserSettings.tailFade
                    let alpha = model.laserTailFadeStart.map { max(0, 1 - now.timeIntervalSince($0) / fade) } ?? 1
                    if alpha <= 0 { model.laserTail.removeAll(); model.laserTailFadeStart = nil }
                    let pts = model.laserTail
                    if alpha > 0, pts.count >= 2 {
                        var tailPath = Path()
                        tailPath.move(to: CGPoint(x: pts[0].point.x * scale + offset.width, y: pts[0].point.y * scale + offset.height))
                        var prev = pts[0].point
                        for i in 1..<pts.count {
                            let pt = pts[i].point
                            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                            tailPath.addQuadCurve(to: CGPoint(x: mid.x * scale + offset.width, y: mid.y * scale + offset.height),
                                                  control: CGPoint(x: prev.x * scale + offset.width, y: prev.y * scale + offset.height))
                            prev = pt
                        }
                        tailPath.addLine(to: CGPoint(x: pts.last!.point.x * scale + offset.width, y: pts.last!.point.y * scale + offset.height))
                        let isDark = model.appSettings.isDarkMode
                        let ls = model.laserSettings.size
                        // Glow with alpha
                        context.stroke(tailPath, with: .color(Color.red.opacity(Double(alpha) * 0.9)),
                                      style: StrokeStyle(lineWidth: ls * 3, lineCap: .round, lineJoin: .round))
                        // Core with alpha
                        context.stroke(tailPath, with: .color((isDark ? Color.black : Color.white).opacity(Double(alpha))),
                                      style: StrokeStyle(lineWidth: ls, lineCap: .round, lineJoin: .round))
                    }
                }

                // Laser pointer dot
                if model.currentTool == .laser, let lp = model.laserPointer {
                    let ls = model.laserSettings.size
                    let lc = model.appSettings.isDarkMode ? Color.black : Color.white
                    let cp = CGPoint(x: lp.x * scale + offset.width, y: lp.y * scale + offset.height)
                    for i in (0...3).reversed() {
                        let r = ls + CGFloat(i) * 4
                        let dot = Path(ellipseIn: CGRect(x: cp.x - r, y: cp.y - r, width: r * 2, height: r * 2))
                        context.fill(dot, with: .color(Color.red.opacity(0.08 - Double(i) * 0.02)))
                    }
                    let core = Path(ellipseIn: CGRect(x: cp.x - ls / 2, y: cp.y - ls / 2, width: ls, height: ls))
                    context.fill(core, with: .color(lc))
                }

                if let loc = hoverLocation {
                    let dotSize: CGFloat = model.currentTool == .eraser ? model.eraserSettings.size : model.currentTool == .pen ? model.penSettings.thickness : 4
                    let dot = Path(ellipseIn: CGRect(
                        x: loc.x - dotSize / 2, y: loc.y - dotSize / 2,
                        width: dotSize, height: dotSize
                    ))
                    context.fill(dot, with: .color(model.currentTool == .eraser ? .red.opacity(0.25) : .black.opacity(0.4)))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hoverLocation = value.location
                        onBeginDraw?()
                        let cp = CGPoint(
                            x: (value.location.x - offset.width) / scale,
                            y: (value.location.y - offset.height) / scale
                        )

                        if model.currentTool == .fill {
                            if model.fillLassoPoints.isEmpty {
                                model.beginFillLasso(at: cp)
                            } else {
                                model.addFillLassoPoint(cp)
                            }
                            return
                        }

                        if model.currentTool == .select {
                            if model.isMoving {
                                let offset = CGSize(width: cp.x - model.lastMovePoint.x, height: cp.y - model.lastMovePoint.y)
                                model.moveSelected(by: offset)
                                model.lastMovePoint = cp
                            } else if !model.selectedStrokeIds.isEmpty || !model.selectedFillIds.isEmpty || !model.selectionBoundary.isEmpty {
                                let onSelected = model.isPointOnSelectedItem(cp) || (!model.selectionBoundary.isEmpty && model.isPointInSelectionBoundary(cp))
                                if onSelected {
                                    let now = Date()
                                    if now.timeIntervalSince(Self.lastSelectTap) < 0.3 {
                                        Self.lastSelectTap = .distantPast
                    model.showDeleteMenu = true
                    model.deleteMenuLocation = CGPoint(x: cp.x * scale + offset.width + 60, y: cp.y * scale + offset.height)
                                        return
                                    }
                                    Self.lastSelectTap = now
                                    model.beginMove(at: cp)
                                } else {
                                    model.selectedStrokeIds.removeAll()
                                    model.selectedFillIds.removeAll()
                                    model.selectionBoundary.removeAll()
                                }
                            } else if model.selectionLasso.isEmpty {
                                model.beginLasso(at: cp)
                            } else {
                                model.addLassoPoint(cp)
                            }
                            return
                        }

                        if model.currentTool == .laser {
                            if model.laserTail.isEmpty {
                                model.laserTail = [(cp, Date())]
                                model.laserTailFadeStart = nil
                            } else {
                                model.laserTail.append((cp, Date()))
                            }
                            model.laserPointer = cp
                            pointCount += 1
                            return
                        }

                        if model.currentStroke == nil {
                            model.beginStroke(at: cp, isEraser: model.currentTool == .eraser)
                        } else {
                            model.addPoint(cp)
                        }
                        pointCount = model.currentStroke?.points.count ?? 0
                    }
                    .onEnded { _ in
                        if model.currentTool == .fill {
                            model.endFillLasso()
                            return
                        }
                        if model.currentTool == .select {
                            if model.isMoving { model.commitMove() }
                            else { model.endLasso() }
                            return
                        }
                        if model.currentTool == .laser {
                            if !model.laserTail.isEmpty {
                                let strokePts = model.laserTail.map { $0.point }
                model.persistentLaserStrokes.append((points: strokePts, time: Date(), isRetained: model.laserSettings.retainStrokes))
                                if !model.laserSettings.retainStrokes {
                                    model.laserTailFadeStart = Date()
                                } else {
                                    model.laserTail.removeAll()
                                }
                            }
                            model.laserPointer = nil
                            pointCount += 1
                            return
                        }
                        model.endStroke()
                        pointCount = 0
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
            .onReceive(Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()) { _ in
                if !model.selectionBoundary.isEmpty || !model.selectionLasso.isEmpty {
                    macDashPhase += 1
                }
            }
            .onReceive(model.$needsRecenter) { needs in
                if needs, let size = viewSize {
                    centerOnContent(canvasSize: size)
                    model.needsRecenter = false
                }
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let hasCmd = event.modifierFlags.contains(.command)
                let hasShift = event.modifierFlags.contains(.shift)
                let char = event.charactersIgnoringModifiers?.lowercased()

                switch char {
                case "p": model.selectTool(.pen)
                case "f": model.selectTool(.fill)
                case "h": model.selectTool(.highlighter)
                case "s": model.selectTool(.select)
                case "e": model.selectTool(.eraser)
                case "l": model.selectTool(.laser)
                case "1", "2", "3", "4", "5", "6", "7", "8":
                    if let c = char, let digit = Int(c) {
                        let idx = digit - 1
                        switch model.currentTool {
                        case .pen where idx < model.penPresets.count:
                            model.penSettings.lightColor = model.penPresets[idx]
                            model.penSettings.darkColor = model.penPresets[idx]
                            model.penPresetIndex = idx
                        case .highlighter where idx < model.hlPresets.count:
                            model.highlighterSettings.lightColor = model.hlPresets[idx]
                            model.highlighterSettings.darkColor = model.hlPresets[idx]
                            model.hlPresetIndex = idx
                        case .fill where idx < model.fillPresets.count:
                            model.fillSettings.lightColor = model.fillPresets[idx]
                            model.fillSettings.darkColor = model.fillPresets[idx]
                            model.fillPresetIndex = idx
                        default: break
                        }
                    }
                default: break
                }

                if hasCmd && !hasShift && char == "z" { model.undo(); return nil }
                if hasCmd && hasShift && char == "z" { model.redo(); return nil }
                if hasCmd && char == "s" { model.save(); return nil }

                if char == "\u{7F}" || char == "\u{7B}" || event.keyCode == 51 || event.keyCode == 117 {
                    model.deleteSelected()
                    return nil
                }

                return event
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                offset.width += event.scrollingDeltaX
                offset.height += event.scrollingDeltaY
                return event
            }
        }
        .onDisappear {
            for monitor in [keyMonitor, scrollMonitor] {
                if let m = monitor as? AnyObject { NSEvent.removeMonitor(m) }
            }
        }
    }

    // MARK: - Background helpers

    private func gridLines(spacing: CGFloat, size: CGSize, offset: CGSize) -> Path {
        Path { path in
            let ox = offset.width.truncatingRemainder(dividingBy: spacing)
            let oy = offset.height.truncatingRemainder(dividingBy: spacing)
            let sx = ox < 0 ? ox + spacing : ox
            let sy = oy < 0 ? oy + spacing : oy
            var x = sx
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing
            }
            var y = sy
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing
            }
        }
    }

    private func ruledLines(spacing: CGFloat, size: CGSize, offset: CGSize) -> Path {
        Path { path in
            let oy = offset.height.truncatingRemainder(dividingBy: spacing)
            let sy = oy < 0 ? oy + spacing : oy
            var y = sy
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing
            }
        }
    }

    private func dotGrid(spacing: CGFloat, size: CGSize, offset: CGSize) -> Path {
        Path { path in
            let ox = offset.width.truncatingRemainder(dividingBy: spacing)
            let oy = offset.height.truncatingRemainder(dividingBy: spacing)
            let sx = ox < 0 ? ox + spacing : ox
            let sy = oy < 0 ? oy + spacing : oy
            let r: CGFloat = max(1.5, 1)
            var x = sx
            while x < size.width {
                var y = sy
                while y < size.height {
                    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    y += spacing
                }
                x += spacing
            }
        }
    }

    private func makeSmoothPath(_ stroke: Stroke, transform: CGAffineTransform) -> Path? {
        guard stroke.points.count >= 2 else { return nil }
        var path = Path()
        if stroke.isCatmullRom {
            path.move(to: stroke.points[0].applying(transform))
            var i = 1
            while i + 2 < stroke.points.count {
                let cp1 = stroke.points[i].applying(transform)
                let cp2 = stroke.points[i + 1].applying(transform)
                let on = stroke.points[i + 2].applying(transform)
                path.addCurve(to: on, control1: cp1, control2: cp2)
                i += 3
            }
            while i < stroke.points.count {
                path.addLine(to: stroke.points[i].applying(transform))
                i += 1
            }
        } else {
            path.move(to: stroke.points[0].applying(transform))
            var prev = stroke.points[0]
            for i in 1..<stroke.points.count {
                let pt = stroke.points[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                path.addQuadCurve(to: mid.applying(transform), control: prev.applying(transform))
                prev = pt
            }
            path.addLine(to: stroke.points.last!.applying(transform))
        }
        return path
    }

    private func centerOnContent(canvasSize: CGSize) {
        offset = .zero
        scale = 1.0
    }

    private func drawFill(_ region: FillRegion, in context: inout GraphicsContext, transform: CGAffineTransform) {
        let path = Path(region.cgPath).applying(transform)
        context.fill(path, with: .color(region.displayColor(for: model)))
    }

    private func drawStroke(_ stroke: Stroke, in context: inout GraphicsContext, transform: CGAffineTransform) {
        guard stroke.points.count >= 2 else { return }

        let path: Path
        if stroke.isCatmullRom {
            let smoothed = model.smoothCatmullRom(stroke.points)
            if smoothed.count >= 4 {
                var p = Path()
                p.move(to: smoothed[0].applying(transform))
                var i = 1
                while i + 2 < smoothed.count {
                    let cp1 = smoothed[i].applying(transform)
                    let cp2 = smoothed[i + 1].applying(transform)
                    let on = smoothed[i + 2].applying(transform)
                    p.addCurve(to: on, control1: cp1, control2: cp2)
                    i += 3
                }
                while i < smoothed.count {
                    p.addLine(to: smoothed[i].applying(transform))
                    i += 1
                }
                path = p
            } else {
                path = makeSmoothPath(stroke, transform: transform) ?? Path()
            }
        } else {
            var p = Path()
            p.move(to: stroke.points[0].applying(transform))
            var prev = stroke.points[0]
            for i in 1..<stroke.points.count {
                let pt = stroke.points[i]
                let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                p.addQuadCurve(to: mid.applying(transform), control: prev.applying(transform))
                prev = pt
            }
            p.addLine(to: stroke.points.last!.applying(transform))
            path = p
        }

        if stroke.isEraser {
            context.blendMode = .clear
            context.stroke(path, with: .color(.white),
                          style: StrokeStyle(lineWidth: model.eraserSettings.size, lineCap: .round, lineJoin: .round))
            context.blendMode = .normal
        } else {
            context.stroke(path, with: .color(stroke.displayColor(for: model)),
                          style: StrokeStyle(lineWidth: stroke.lineWidth * scale,
                                           lineCap: .round, lineJoin: .round))
        }
    }
}

#endif
