import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Caches smoothed `CGPath`, SwiftUI `Path`, and bounding box per stroke so
/// redraws avoid recomputing Catmull-Rom splines or copying path geometry.
final class StrokePathCache {
    struct Entry {
        let pointCount: Int
        let firstPoint: CGPoint
        let lastPoint: CGPoint
        let cgPath: CGPath
        let swiftUIPath: Path
        let bounds: CGRect
    }

    private var entries: [UUID: Entry] = [:]

    func entry(for stroke: Stroke) -> Entry? {
        guard let first = stroke.points.first, let last = stroke.points.last, stroke.points.count >= 2 else {
            return nil
        }
        if let cached = entries[stroke.id],
           cached.pointCount == stroke.points.count,
           cached.firstPoint == first,
           cached.lastPoint == last {
            return cached
        }
        guard let cgPath = GeometryEngine.makeCGPath(for: stroke) else { return nil }
        let entry = Entry(
            pointCount: stroke.points.count,
            firstPoint: first,
            lastPoint: last,
            cgPath: cgPath,
            swiftUIPath: Path(cgPath),
            bounds: GeometryEngine.strokeBounds(stroke)
        )
        entries[stroke.id] = entry
        return entry
    }

    func prune(activeIds: Set<UUID>) {
        if entries.count > activeIds.count + 64 {
            entries = entries.filter { activeIds.contains($0.key) }
        }
    }
}

// MARK: - iOS Canvas

#if os(iOS)

struct CanvasView: UIViewRepresentable {
    var model: DrawingModel
    var onBeginDraw: (() -> Void)?

    func makeUIView(context: Context) -> DrawingCanvasView {
        let view = DrawingCanvasView()
        view.model = model
        view.onBeginDraw = onBeginDraw
        return view
    }

    func updateUIView(_ uiView: DrawingCanvasView, context: Context) {
        uiView.model = model
        uiView.onBeginDraw = onBeginDraw
        let _ = model.committedRevision
        let _ = model.appSettings.isDarkMode
        let _ = model.appSettings.isWarmPaper
        let _ = model.appSettings.canvasBackground
        let _ = model.selectionBoundary.count
        let _ = model.selectionLasso.count
        let _ = model.selectedImageIds.count
        let _ = model.isRotating
        let _ = model.selectionRotationAngle
        let _ = model.isRotationSnapped
        let _ = model.needsRecenter
        let _ = model.needsFitToContent
        let _ = model.needsResetZoom
        let _ = model.pendingSceneNavigation?.id
        uiView.refresh()
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
        guard let ctx = UIGraphicsGetCurrentContext(), let model = model, scale > 0 else { return }

        let isDark = model.appSettings.isDarkMode
        let isWarm = model.appSettings.isWarmPaper
        let bg: UIColor = isDark ? UIColor.black : (isWarm ? UIColor(red: 250/255, green: 245/255, blue: 235/255, alpha: 1) : .white)
        let fg: UIColor = isDark
            ? UIColor(red: 56/255, green: 56/255, blue: 58/255, alpha: 1)
            : (isWarm ? UIColor(red: 214/255, green: 204/255, blue: 186/255, alpha: 1) : .systemGray5)
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
        ctx.setLineDash(phase: 0, lengths: [3 / scale, 6 / scale])
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
        ctx.setLineDash(phase: 0, lengths: [])
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

// MARK: - Committed Layer View (Spatial-Culled Cached Paths; Never Redrawn During Active Drag)

class CommittedLayerView: UIView {
    weak var model: DrawingModel?
    var offset: CGSize = .zero
    var scale: CGFloat = 1.0
    private let pathCache = StrokePathCache()

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
        guard let ctx = UIGraphicsGetCurrentContext(), let model = model, scale > 0 else { return }

        let visibleCanvasRect = CGRect(
            x: (rect.minX - offset.width) / scale,
            y: (rect.minY - offset.height) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )

        ctx.saveGState()
        ctx.translateBy(x: offset.width, y: offset.height)
        ctx.scaleBy(x: scale, y: scale)

        for img in model.placedImages {
            let imgRect = img.rotatedBoundingBox()
            guard imgRect.intersects(visibleCanvasRect) else { continue }
            let cached: UIImage? = {
                if let hit = model.imageCache[img.id] { return hit }
                if let decoded = UIImage(data: img.imageData) {
                    model.imageCache[img.id] = decoded
                    return decoded
                }
                return nil
            }()
            StrokeRenderer.drawPlacedImage(img, in: ctx, cachedImage: cached)
        }

        for fill in model.fills {
            let box = fill.boundingBox()
            guard !box.isNull, box.intersects(visibleCanvasRect) else { continue }
            StrokeRenderer.drawFill(fill, in: ctx, fillPresets: model.fillPresets)
        }

        model.spatialGrid.sync(with: model.strokes)
        let visibleIndices = model.spatialGrid.queryIndices(in: visibleCanvasRect)
        let penPresets = model.penPresets
        let sharpiePresets = model.sharpiePresets
        let isDark = model.appSettings.isDarkMode
        let eraserWidth = model.eraserSettings.size / scale

        for idx in visibleIndices {
            let stroke = model.strokes[idx]
            guard let entry = pathCache.entry(for: stroke) else { continue }
            StrokeRenderer.drawStroke(
                stroke,
                in: ctx,
                penPresets: penPresets,
                sharpiePresets: sharpiePresets,
                isDarkMode: isDark,
                eraserWidthOverride: stroke.isEraser ? eraserWidth : nil,
                cachedPath: entry.cgPath
            )
        }
        pathCache.prune(activeIds: Set(model.strokes.map(\.id)))

        ctx.restoreGState()
    }
}

// MARK: - Live Overlay View (Active Stroke + Lasso + Selection Only)

class LiveOverlayView: UIView {
    weak var model: DrawingModel?
    var offset: CGSize = .zero
    var scale: CGFloat = 1.0
    var dashPhase: CGFloat = 0
    private let incrementalPath = IncrementalStrokePath()

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
        guard let ctx = UIGraphicsGetCurrentContext(), let model = model, scale > 0 else { return }

        ctx.saveGState()
        ctx.translateBy(x: offset.width, y: offset.height)
        ctx.scaleBy(x: scale, y: scale)

        if let current = model.currentStroke, let path = GeometryEngine.makeCGPath(for: current) {
            StrokeRenderer.drawStroke(
                current,
                in: ctx,
                penPresets: model.penPresets,
                sharpiePresets: model.sharpiePresets,
                isDarkMode: model.appSettings.isDarkMode,
                eraserWidthOverride: current.isEraser ? (model.eraserSettings.size / scale) : nil,
                cachedPath: path
            )
        }

        if !model.selectionLasso.isEmpty {
            drawDashedPolygon(model.selectionLasso, close: false, color: UIColor.systemBlue.withAlphaComponent(0.6), in: ctx)
        }

        if !model.selectionBoundary.isEmpty {
            drawDashedPolygon(model.selectionBoundary, close: true, color: UIColor.systemBlue, in: ctx)
        }

        for img in model.placedImages where model.selectedImageIds.contains(img.id) {
            let corners = img.rotatedCorners()
            guard corners.count == 4 else { continue }
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(2 / scale)
            ctx.setLineDash(phase: dashPhase / scale, lengths: [8 / scale, 5 / scale])
            ctx.beginPath()
            ctx.move(to: corners[0])
            ctx.addLine(to: corners[1])
            ctx.addLine(to: corners[2])
            ctx.addLine(to: corners[3])
            ctx.closePath()
            ctx.strokePath()

            ctx.setLineDash(phase: 0, lengths: [])
            let handleSize: CGFloat = 10 / scale
            for corner in corners {
                let handle = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2, width: handleSize, height: handleSize)
                ctx.setFillColor(UIColor.systemBlue.cgColor)
                ctx.fillEllipse(in: handle)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(1.5 / scale)
                ctx.strokeEllipse(in: handle)
            }
            ctx.restoreGState()
        }

        if model.currentTool == .select, let geom = model.rotationHandleGeometry(scale: scale) {
            drawRotationHandle(geom, model: model, in: ctx)
        }

        ctx.restoreGState()
    }

    private func drawRotationHandle(_ geom: DrawingModel.RotationHandleGeometry, model: DrawingModel, in ctx: CGContext) {
        let accent: UIColor = (model.isRotating && model.isRotationSnapped) ? .systemOrange : .systemBlue

        ctx.saveGState()
        // Stem connecting selection edge to rotation knob
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.6 / scale)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: geom.stemStart)
        ctx.addLine(to: geom.handleCenter)
        ctx.strokePath()

        // Circular rotation knob
        let radius: CGFloat = (model.isRotating ? 10.5 : 9.0) / scale
        let knobRect = CGRect(
            x: geom.handleCenter.x - radius,
            y: geom.handleCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let knobFill: UIColor = model.isRotating
            ? accent
            : (model.appSettings.isDarkMode ? UIColor(white: 0.14, alpha: 1) : .white)
        ctx.setFillColor(knobFill.cgColor)
        ctx.fillEllipse(in: knobRect)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.8 / scale)
        ctx.strokeEllipse(in: knobRect)

        // Small circular arrow glyph inside the knob
        let iconColor: UIColor = model.isRotating ? .white : accent
        let arcR = radius * 0.46
        ctx.setStrokeColor(iconColor.cgColor)
        ctx.setLineWidth(1.4 / scale)
        ctx.beginPath()
        ctx.addArc(center: geom.handleCenter, radius: arcR, startAngle: -.pi * 0.75, endAngle: .pi * 0.55, clockwise: false)
        ctx.strokePath()
        let tipAngle: CGFloat = .pi * 0.55
        let tip = CGPoint(
            x: geom.handleCenter.x + cos(tipAngle) * arcR,
            y: geom.handleCenter.y + sin(tipAngle) * arcR
        )
        let arrowLen = 2.8 / scale
        ctx.beginPath()
        ctx.move(to: CGPoint(x: tip.x + arrowLen, y: tip.y - arrowLen * 0.6))
        ctx.addLine(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x + arrowLen * 0.4, y: tip.y + arrowLen))
        ctx.strokePath()

        // Live angle readout pill while actively rotating
        if model.isRotating {
            let dx = geom.handleCenter.x - geom.stemStart.x
            let dy = geom.handleCenter.y - geom.stemStart.y
            let len = max(hypot(dx, dy), 0.001)
            let ux = dx / len
            let uy = dy / len
            let badgeCanvas = CGPoint(
                x: geom.handleCenter.x + ux * (26 / scale),
                y: geom.handleCenter.y + uy * (26 / scale)
            )
            ctx.saveGState()
            ctx.translateBy(x: badgeCanvas.x, y: badgeCanvas.y)
            ctx.scaleBy(x: 1 / scale, y: 1 / scale)
            let text = model.activeRotationLabel as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let padX: CGFloat = 7
            let padY: CGFloat = 3
            let pillRect = CGRect(
                x: -(textSize.width / 2 + padX),
                y: -(textSize.height / 2 + padY),
                width: textSize.width + padX * 2,
                height: textSize.height + padY * 2
            )
            let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
            let pillColor: UIColor = model.isRotationSnapped ? .systemOrange : UIColor.black.withAlphaComponent(0.78)
            ctx.setFillColor(pillColor.cgColor)
            ctx.addPath(pillPath.cgPath)
            ctx.fillPath()
            UIGraphicsPushContext(ctx)
            text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2), withAttributes: attrs)
            UIGraphicsPopContext()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private func drawDashedPolygon(_ pts: [CGPoint], close: Bool, color: UIColor, in ctx: CGContext) {
        guard !pts.isEmpty else { return }
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2 / scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: dashPhase / scale, lengths: [8 / scale, 5 / scale])

        let path = CGMutablePath()
        path.move(to: pts[0])
        var prev = pts[0]
        for i in 1..<pts.count {
            let pt = pts[i]
            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
            prev = pt
        }
        if close { path.closeSubpath() }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Canvas Container View

class DrawingCanvasView: UIView {
    weak var model: DrawingModel? {
        didSet {
            committedLayer.model = model
            liveOverlay.model = model
            gridView.model = model
        }
    }
    var onBeginDraw: (() -> Void)?
    var lastTouchPoint: CGPoint = .zero

    private var offset: CGSize = .zero {
        didSet {
            gridView.offset = offset
            committedLayer.offset = offset
            liveOverlay.offset = offset
            reportViewport()
        }
    }
    private var scale: CGFloat = 1.0 {
        didSet {
            gridView.scale = scale
            committedLayer.scale = scale
            liveOverlay.scale = scale
            if abs((model?.zoomDisplayScale ?? 1.0) - scale) > 0.005 {
                model?.zoomDisplayScale = scale
            }
            reportViewport()
        }
    }

    private var sceneAnimLink: CADisplayLink?
    private var sceneAnimStart: CFTimeInterval = 0
    private var sceneAnimFromOffset: CGSize = .zero
    private var sceneAnimToOffset: CGSize = .zero
    private var sceneAnimFromScale: CGFloat = 1.0
    private var sceneAnimToScale: CGFloat = 1.0

    private func reportViewport() {
        guard let model, bounds.width > 0, bounds.height > 0 else { return }
        let safeScale = max(scale, 0.01)
        model.currentViewportCenter = CGPoint(
            x: (bounds.width / 2 - offset.width) / safeScale,
            y: (bounds.height / 2 - offset.height) / safeScale
        )
        model.currentViewportScale = safeScale
        model.captureDefaultSceneIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportViewport()
    }

    private let gridView = CanvasGridView()
    private let committedLayer = CommittedLayerView()
    private let liveOverlay = LiveOverlayView()
    private var dashPhase: CGFloat = 0
    private var displayLink: CADisplayLink?

    private let hoverIndicatorLayer: CALayer = {
        let layer = CALayer()
        layer.isHidden = true
        return layer
    }()
    private var isTouchActive: Bool = false
    private var hasUsedPencil: Bool = false
    private var isPencilActive: Bool = false
    private var isPencilHovering: Bool = false
    private var lastPencilEndTime: CFTimeInterval = 0
    private var fingerPanStartTime: CFTimeInterval = 0
    private var fingerPanStartOffset: CGSize = .zero
    private var fingerPanMovedPastDeadzone: Bool = false
    private var shapeHoldWorkItem: DispatchWorkItem?
    private var shapeHoldAnchor: CGPoint = .zero

    private lazy var twoFingerTapGesture: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        g.numberOfTouchesRequired = 2
        g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return g
    }()

    private lazy var threeFingerTapGesture: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
        g.numberOfTouchesRequired = 3
        g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return g
    }()

    private lazy var pinchGesture: UIPinchGestureRecognizer = {
        let g = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        g.delegate = self
        return g
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        g.minimumNumberOfTouches = 2
        g.maximumNumberOfTouches = 2
        g.delegate = self
        return g
    }()

    /// Single-finger pan gesture active when drawing with Apple Pencil (or when Pencil Only is on).
    private lazy var fingerPanGesture: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        g.minimumNumberOfTouches = 1
        g.maximumNumberOfTouches = 1
        g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        g.delegate = self
        return g
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        stopDashAnimation()
        stopSceneAnimation()
        shapeHoldWorkItem?.cancel()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopDashAnimation()
            stopSceneAnimation()
            shapeHoldWorkItem?.cancel()
        } else {
            syncDashAnimationState()
        }
    }

    private func syncDashAnimationState() {
        guard let model = model else { stopDashAnimation(); return }
        let needsAnimation = !model.selectionBoundary.isEmpty || !model.selectionLasso.isEmpty || !model.selectedImageIds.isEmpty
        if needsAnimation {
            startDashAnimation()
        } else {
            stopDashAnimation()
        }
    }

    private func startDashAnimation() {
        guard displayLink == nil, window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepDash(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDashAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func stepDash(_ link: CADisplayLink) {
        guard let model = model,
              (!model.selectionBoundary.isEmpty || !model.selectionLasso.isEmpty || !model.selectedImageIds.isEmpty) else {
            stopDashAnimation()
            return
        }
        dashPhase += 1
        liveOverlay.dashPhase = dashPhase
        liveOverlay.setNeedsDisplay()
    }

    private func setup() {
        isMultipleTouchEnabled = true
        addGestureRecognizer(pinchGesture)
        addGestureRecognizer(panGesture)
        addGestureRecognizer(fingerPanGesture)
        twoFingerTapGesture.require(toFail: threeFingerTapGesture)
        addGestureRecognizer(twoFingerTapGesture)
        addGestureRecognizer(threeFingerTapGesture)

        gridView.frame = bounds
        gridView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(gridView)

        committedLayer.frame = bounds
        committedLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(committedLayer)

        liveOverlay.frame = bounds
        liveOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(liveOverlay)

        layer.addSublayer(hoverIndicatorLayer)

        if #available(iOS 17.0, *) {
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            addGestureRecognizer(hover)
        }
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            isPencilHovering = true
            let loc = gesture.location(in: self)
            if !isTouchActive {
                showHoverIndicator(at: loc)
            }
        case .ended, .cancelled:
            isPencilHovering = false
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
        let color: UIColor
        let borderColor: UIColor?
        let inkBase: UIColor = model.appSettings.isDarkMode ? .white : .black
        switch model.currentTool {
        case .eraser:
            size = max(model.eraserSettings.size, 8)
            color = UIColor.systemRed.withAlphaComponent(0.22)
            borderColor = UIColor.systemRed.withAlphaComponent(0.75)
        case .pen:
            size = max(model.penSettings.thickness * 1.5, 4)
            color = inkBase.withAlphaComponent(0.4)
            borderColor = nil
        case .sharpie:
            size = max(model.sharpieSettings.thickness * 1.5, 4)
            color = inkBase.withAlphaComponent(0.4)
            borderColor = nil
        case .fill:
            size = 10
            color = UIColor(model.fillColor).withAlphaComponent(0.6)
            borderColor = inkBase.withAlphaComponent(0.35)
        default:
            size = 4
            color = inkBase.withAlphaComponent(0.4)
            borderColor = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverIndicatorLayer.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        hoverIndicatorLayer.cornerRadius = size / 2
        hoverIndicatorLayer.backgroundColor = color.cgColor
        hoverIndicatorLayer.borderColor = borderColor?.cgColor
        hoverIndicatorLayer.borderWidth = borderColor != nil ? 1.5 : 0
        hoverIndicatorLayer.isHidden = false
        CATransaction.commit()
    }

    private func hideHoverIndicator() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverIndicatorLayer.isHidden = true
        CATransaction.commit()
    }

    private func toCanvas(_ point: CGPoint) -> CGPoint {
        let safeScale = max(scale, 0.01)
        return CGPoint(
            x: (point.x - offset.width) / safeScale,
            y: (point.y - offset.height) / safeScale
        )
    }

    func refresh() {
        if let model = model, model.needsRecenter {
            centerOnContent()
            model.needsRecenter = false
        }
        if let model = model, model.needsResetZoom {
            model.needsResetZoom = false
            let target = CanvasScene(name: "Reset", center: model.currentViewportCenter, scale: 1.0)
            animateToScene(target)
        }
        if let model = model, model.needsFitToContent {
            model.needsFitToContent = false
            fitContentToViewport()
        }
        if let model = model, let targetScene = model.pendingSceneNavigation {
            model.pendingSceneNavigation = nil
            animateToScene(targetScene)
        }
        committedLayer.model = model
        liveOverlay.model = model
        gridView.model = model
        syncDashAnimationState()
        gridView.setNeedsDisplay()
        committedLayer.setNeedsDisplay()
        liveOverlay.setNeedsDisplay()
    }

    private func fitContentToViewport() {
        guard let model, bounds.width > 0, bounds.height > 0 else { return }
        guard let box = GeometryEngine.boundingBox(of: model.strokes, images: model.placedImages, fills: model.fills, padding: 60),
              box.width > 0, box.height > 0 else {
            centerOnContent()
            return
        }
        let fitScale = min(max(min(bounds.width / box.width, bounds.height / box.height), 0.3), 2.5)
        let target = CanvasScene(name: "Fit", center: CGPoint(x: box.midX, y: box.midY), scale: fitScale)
        animateToScene(target)
    }

    @objc private func handleTwoFingerTap() {
        guard let model, model.canUndo else { return }
        model.undo()
        refresh()
    }

    @objc private func handleThreeFingerTap() {
        guard let model, model.canRedo else { return }
        model.redo()
        refresh()
    }

    private func scheduleShapeHoldCheck(at point: CGPoint) {
        shapeHoldWorkItem?.cancel()
        shapeHoldAnchor = point
        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model,
                  model.currentTool == .pen || model.currentTool == .sharpie else { return }
            if model.snapCurrentStrokeToShape() {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.liveOverlay.setNeedsDisplay()
            }
        }
        shapeHoldWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: item)
    }

    private func centerOnContent() {
        stopSceneAnimation()
        offset = .zero
        scale = 1.0
    }

    private func animateToScene(_ scene: CanvasScene) {
        stopSceneAnimation()
        let targetScale = min(max(scene.cgScale, 0.3), 5.0)
        let targetOffset = CGSize(
            width: bounds.width / 2 - scene.center.x * targetScale,
            height: bounds.height / 2 - scene.center.y * targetScale
        )
        guard window != nil else {
            scale = targetScale
            offset = targetOffset
            return
        }
        sceneAnimFromOffset = offset
        sceneAnimToOffset = targetOffset
        sceneAnimFromScale = scale
        sceneAnimToScale = targetScale
        sceneAnimStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepSceneAnimation(_:)))
        link.add(to: .main, forMode: .common)
        sceneAnimLink = link
    }

    private func stopSceneAnimation() {
        sceneAnimLink?.invalidate()
        sceneAnimLink = nil
    }

    @objc private func stepSceneAnimation(_ link: CADisplayLink) {
        let duration: CFTimeInterval = 0.32
        let rawT = min(max((CACurrentMediaTime() - sceneAnimStart) / duration, 0), 1)
        // Smooth cubic ease-in-out
        let t = rawT < 0.5 ? 4 * rawT * rawT * rawT : 1 - pow(-2 * rawT + 2, 3) / 2
        let f = CGFloat(t)
        scale = sceneAnimFromScale + (sceneAnimToScale - sceneAnimFromScale) * f
        offset = CGSize(
            width: sceneAnimFromOffset.width + (sceneAnimToOffset.width - sceneAnimFromOffset.width) * f,
            height: sceneAnimFromOffset.height + (sceneAnimToOffset.height - sceneAnimFromOffset.height) * f
        )
        gridView.setNeedsDisplay()
        committedLayer.setNeedsDisplay()
        liveOverlay.setNeedsDisplay()
        if rawT >= 1 {
            stopSceneAnimation()
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model = model else { return }
        let pencilTouch = touches.first(where: { $0.type == .pencil })
        if pencilTouch != nil {
            hasUsedPencil = true
            isPencilActive = true
            // Cancel any accidental palm pan that began just before the Pencil landed
            if fingerPanGesture.state == .began || fingerPanGesture.state == .changed {
                let elapsed = CACurrentMediaTime() - fingerPanStartTime
                fingerPanGesture.isEnabled = false
                fingerPanGesture.isEnabled = true
                if elapsed < 0.25 {
                    offset = fingerPanStartOffset
                    gridView.setNeedsDisplay()
                    committedLayer.setNeedsDisplay()
                    liveOverlay.setNeedsDisplay()
                }
            }
        } else if isPencilActive {
            // Ignore stray palm/finger touches while actively writing with Apple Pencil
            return
        }

        guard let touch = pencilTouch ?? touches.first else { return }
        isTouchActive = true
        hideHoverIndicator()
        model.showDeleteMenu = false
        lastTouchPoint = touch.location(in: self)
        model.lastCanvasTapLocation = toCanvas(touch.location(in: self))
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let pencilModeActive = model.appSettings.pencilOnly || hasUsedPencil
        guard !pencilModeActive || touch.type == .pencil || model.currentTool == .select else { return }
        #endif

        onBeginDraw?()

        if model.currentTool == .select {
            let cp = toCanvas(touch.location(in: self))
            let hasSelection = !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty || !model.selectionBoundary.isEmpty
            if hasSelection {
                if model.hitTestRotateHandle(cp, scale: scale) {
                    model.beginRotate(at: cp, scale: scale)
                    liveOverlay.setNeedsDisplay()
                    return
                }
                if model.hitTestResizeHandle(cp, scale: scale) != nil {
                    let now = Date()
                    if now.timeIntervalSince(Self.lastSelectTap) < 0.4 {
                        Self.lastSelectTap = .distantPast
                        model.showDeleteMenu = true
                        let tapLoc = touch.location(in: self)
                        model.deleteMenuLocation = CGPoint(x: tapLoc.x + 60, y: tapLoc.y)
                        liveOverlay.setNeedsDisplay()
                        return
                    }
                    Self.lastSelectTap = now
                    model.beginMove(at: cp, scale: scale)
                    liveOverlay.setNeedsDisplay()
                    return
                }
                let onSelected = model.isPointOnSelectedItem(cp) || (!model.selectionBoundary.isEmpty && model.isPointInSelectionBoundary(cp))
                if onSelected {
                    let now = Date()
                    if now.timeIntervalSince(Self.lastSelectTap) < 0.4 {
                        Self.lastSelectTap = .distantPast
                        model.showDeleteMenu = true
                        let tapLoc = touch.location(in: self)
                        model.deleteMenuLocation = CGPoint(x: tapLoc.x + 60, y: tapLoc.y)
                        liveOverlay.setNeedsDisplay()
                        return
                    }
                    Self.lastSelectTap = now
                    model.beginMove(at: cp, scale: scale)
                } else {
                    model.clearSelection()
                    model.pendingDeselectPoint = cp
                    syncDashAnimationState()
                    liveOverlay.setNeedsDisplay()
                    return
                }
            } else {
                let now = Date()
                if !model.hasElement(at: cp, scale: scale), now.timeIntervalSince(Self.lastEmptyTap) < 0.4 {
                    Self.lastEmptyTap = .distantPast
                    model.showDeleteMenu = true
                    let tapLoc = touch.location(in: self)
                    model.deleteMenuLocation = CGPoint(x: tapLoc.x + 60, y: tapLoc.y)
                    liveOverlay.setNeedsDisplay()
                    return
                }
                Self.lastEmptyTap = model.hasElement(at: cp, scale: scale) ? .distantPast : now
                model.beginLasso(at: cp)
                syncDashAnimationState()
            }
            liveOverlay.setNeedsDisplay()
            return
        }

        if model.currentTool == .fill {
            if model.floodFill(at: toCanvas(touch.location(in: self))) {
                committedLayer.setNeedsDisplay()
            }
            return
        }

        if model.currentTool == .eraser {
            showHoverIndicator(at: lastTouchPoint)
        }
        let startPt = toCanvas(touch.location(in: self))
        model.beginStroke(at: startPt, isEraser: model.currentTool == .eraser)
        if model.currentTool == .pen || model.currentTool == .sharpie {
            scheduleShapeHoldCheck(at: lastTouchPoint)
        }
        liveOverlay.setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model = model else { return }
        let touch: UITouch
        if isPencilActive {
            guard let pt = touches.first(where: { $0.type == .pencil }) else { return }
            touch = pt
        } else {
            guard let first = touches.first else { return }
            touch = first
        }
        lastTouchPoint = touch.location(in: self)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if touch.type == .pencil {
            hasUsedPencil = true
        }
        let pencilModeActive = model.appSettings.pencilOnly || hasUsedPencil
        guard !pencilModeActive || touch.type == .pencil || model.currentTool == .select else { return }
        #endif

        if model.currentTool == .fill { return }

        if model.currentTool == .select {
            if model.showDeleteMenu { return }
            if let start = model.pendingDeselectPoint {
                let cur = toCanvas(touch.location(in: self))
                let threshold = 6 / max(scale, 0.1)
                if GeometryEngine.distanceSquared(start, cur) > threshold * threshold {
                    model.pendingDeselectPoint = nil
                    model.beginLasso(at: start)
                    model.addLassoPoint(cur)
                    syncDashAnimationState()
                    liveOverlay.setNeedsDisplay()
                }
                return
            }
            if model.isRotating {
                let cur = toCanvas(touch.location(in: self))
                model.updateRotate(to: cur, snapTo15Degrees: false)
                committedLayer.setNeedsDisplay()
                liveOverlay.setNeedsDisplay()
            } else if model.isMoving || model.isResizing {
                let cur = toCanvas(touch.location(in: self))
                let delta = CGSize(width: cur.x - model.lastMovePoint.x, height: cur.y - model.lastMovePoint.y)
                model.moveSelected(by: delta)
                model.lastMovePoint = cur
                committedLayer.setNeedsDisplay()
                liveOverlay.setNeedsDisplay()
            } else if !model.selectedImageIds.isEmpty {
                // Image selected — ignore touch moves unless dragging/resizing
            } else {
                let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
                for ct in coalesced {
                    model.addLassoPoint(toCanvas(ct.location(in: self)))
                }
                liveOverlay.setNeedsDisplay()
            }
            return
        }

        guard model.currentStroke != nil else { return }

        if model.currentTool == .eraser {
            showHoverIndicator(at: lastTouchPoint)
        }

        if model.currentTool == .pen || model.currentTool == .sharpie {
            if hypot(lastTouchPoint.x - shapeHoldAnchor.x, lastTouchPoint.y - shapeHoldAnchor.y) > 6 {
                scheduleShapeHoldCheck(at: lastTouchPoint)
            }
        }

        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        for ct in coalesced {
            model.addPoint(toCanvas(ct.location(in: self)))
        }
        liveOverlay.setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        shapeHoldWorkItem?.cancel()
        shapeHoldWorkItem = nil
        if isPencilActive {
            guard touches.contains(where: { $0.type == .pencil }) else { return }
            isPencilActive = false
            lastPencilEndTime = CACurrentMediaTime()
        }
        isTouchActive = false
        if model?.currentTool == .select {
            if model?.showDeleteMenu == true { return }
            if let tapPt = model?.pendingDeselectPoint {
                model?.pendingDeselectPoint = nil
                _ = model?.selectElement(at: tapPt, scale: scale)
            } else if model?.isRotating == true {
                model?.commitRotate()
                committedLayer.setNeedsDisplay()
            } else if model?.isMoving == true || model?.isResizing == true {
                model?.commitMove()
                committedLayer.setNeedsDisplay()
            } else {
                model?.endLasso(scale: scale)
            }
            syncDashAnimationState()
            liveOverlay.setNeedsDisplay()
            return
        }
        if model?.currentTool == .fill {
            hideHoverIndicator()
            return
        }
        model?.endStroke()
        hideHoverIndicator()
        committedLayer.setNeedsDisplay()
        liveOverlay.setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        shapeHoldWorkItem?.cancel()
        shapeHoldWorkItem = nil
        if isPencilActive {
            guard touches.contains(where: { $0.type == .pencil }) else { return }
            isPencilActive = false
            lastPencilEndTime = CACurrentMediaTime()
        }
        isTouchActive = false
        if model?.currentTool == .select {
            model?.pendingDeselectPoint = nil
            if model?.isRotating == true {
                model?.commitRotate()
                committedLayer.setNeedsDisplay()
            } else if model?.isMoving == true || model?.isResizing == true {
                model?.commitMove()
                committedLayer.setNeedsDisplay()
            } else {
                model?.endLasso(scale: scale)
            }
            syncDashAnimationState()
            liveOverlay.setNeedsDisplay()
            return
        }
        if model?.currentTool == .fill {
            hideHoverIndicator()
            return
        }
        model?.endStroke()
        hideHoverIndicator()
        committedLayer.setNeedsDisplay()
        liveOverlay.setNeedsDisplay()
    }

    // MARK: - Gestures

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        scale = min(max(scale * gesture.scale, 0.3), 5.0)
        gesture.scale = 1
        gridView.setNeedsDisplay()
        committedLayer.setNeedsDisplay()
        liveOverlay.setNeedsDisplay()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture === fingerPanGesture {
            if gesture.state == .began {
                fingerPanStartTime = CACurrentMediaTime()
                fingerPanStartOffset = offset
                fingerPanMovedPastDeadzone = false
                return
            }
            guard gesture.state == .changed else { return }
            if isPencilActive || isPencilHovering || (CACurrentMediaTime() - lastPencilEndTime) < 0.35 {
                gesture.isEnabled = false
                gesture.isEnabled = true
                return
            }
            let t = gesture.translation(in: self)
            if !fingerPanMovedPastDeadzone {
                // Ignore subtle resting-palm micro-jitter (< 10 pt)
                guard hypot(t.x, t.y) >= 10 else { return }
                fingerPanMovedPastDeadzone = true
            }
            offset.width += t.x
            offset.height += t.y
            gesture.setTranslation(.zero, in: self)
            gridView.setNeedsDisplay()
            committedLayer.setNeedsDisplay()
            liveOverlay.setNeedsDisplay()
            return
        }

        guard gesture.state == .changed else { return }
        let t = gesture.translation(in: self)
        offset.width += t.x
        offset.height += t.y
        gesture.setTranslation(.zero, in: self)
        gridView.setNeedsDisplay()
        committedLayer.setNeedsDisplay()
        liveOverlay.setNeedsDisplay()
    }
}

// MARK: - Gesture Recognizer Delegate (iOS)

extension DrawingCanvasView: UIGestureRecognizerDelegate {
    private var isPencilRecentlyActive: Bool {
        isPencilActive || isPencilHovering || (CACurrentMediaTime() - lastPencilEndTime) < 0.35
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === fingerPanGesture {
            guard touch.type == .direct else { return false }
            // Reject large palm contacts (fingertips are typically 15–28 pt; palms are 35–90+ pt)
            if touch.majorRadius > 32 { return false }
            if isPencilRecentlyActive { return false }
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === fingerPanGesture {
            guard let model else { return false }
            guard !isPencilRecentlyActive else { return false }
            let pencilModeActive = model.appSettings.pencilOnly || hasUsedPencil
            return pencilModeActive && model.currentTool != .select
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === pinchGesture && otherGestureRecognizer === panGesture) ||
        (gestureRecognizer === panGesture && otherGestureRecognizer === pinchGesture)
    }
}

// MARK: - Tap Timestamps (iOS)

extension DrawingCanvasView {
    static var lastSelectTap: Date = .distantPast
    static var lastEmptyTap: Date = .distantPast
}

// MARK: - macOS Canvas

#else

/// Isolated background layer — only redraws when offset, scale, background style,
/// or dark mode changes.
private struct BackgroundGridCanvas: View {
    let background: CanvasBackground
    let isDarkMode: Bool
    let isWarmPaper: Bool
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let safeScale = max(scale, 0.01)
            let spacing: CGFloat = 30 * safeScale
            let bg = isDarkMode
                ? Color.black
                : (isWarmPaper ? Color(red: 250/255, green: 245/255, blue: 235/255) : Color.white)
            let fg = isDarkMode
                ? Color(red: 56/255, green: 56/255, blue: 58/255)
                : (isWarmPaper ? Color(red: 196/255, green: 184/255, blue: 164/255).opacity(0.45) : Color.gray.opacity(0.2))

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            switch background {
            case .none: break
            case .grid:
                let gridPath = gridLines(spacing: spacing, size: size, offset: offset)
                context.stroke(gridPath, with: .color(fg), style: StrokeStyle(lineWidth: 0.5, dash: [3, 6]))
            case .dots:
                let dotsPath = dotGrid(spacing: spacing, size: size, offset: offset)
                context.fill(dotsPath, with: .color(fg))
            case .ruled:
                let ruledPath = ruledLines(spacing: spacing, size: size, offset: offset)
                context.stroke(ruledPath, with: .color(fg), lineWidth: 0.5)
            }
        }
    }

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
            let r: CGFloat = 1.5
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
}

/// Isolated committed-content layer — draws spatial-culled cached `Path`s using a
/// single GPU `GraphicsContext` transform (no 28MB CPU bitmap copy, no per-stroke
/// vertex transformation, and NEVER invalidated by mouse hover or active stroke drag!).
private struct CommittedStrokesCanvas: View {
    let model: DrawingModel
    let pathCache: StrokePathCache
    let committedRevision: Int
    let isDarkMode: Bool
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let _ = committedRevision
            let safeScale = max(scale, 0.01)
            let visibleCanvasRect = CGRect(
                x: -offset.width / safeScale,
                y: -offset.height / safeScale,
                width: size.width / safeScale,
                height: size.height / safeScale
            )

            // Apply viewport transform once on the GPU GraphicsContext
            context.translateBy(x: offset.width, y: offset.height)
            context.scaleBy(x: safeScale, y: safeScale)

            // Placed images
            for img in model.placedImages {
                let canvasImgBounds = img.rotatedBoundingBox()
                guard canvasImgBounds.intersects(visibleCanvasRect) else { continue }
                let nsImage: NSImage? = {
                    if let cached = model.imageCache[img.id] { return cached }
                    if let imgObj = NSImage(data: img.imageData) {
                        model.imageCache[img.id] = imgObj
                        return imgObj
                    }
                    return nil
                }()
                if let nsImg = nsImage {
                    let canvasImgRect = CGRect(origin: img.cgPosition, size: img.cgSize)
                    if img.rotation != 0 {
                        var imgCtx = context
                        let center = img.cgCenter
                        imgCtx.translateBy(x: center.x, y: center.y)
                        imgCtx.rotate(by: Angle(radians: img.rotation))
                        imgCtx.draw(
                            Image(nsImage: nsImg),
                            in: CGRect(
                                x: -canvasImgRect.width / 2,
                                y: -canvasImgRect.height / 2,
                                width: canvasImgRect.width,
                                height: canvasImgRect.height
                            )
                        )
                    } else {
                        context.draw(Image(nsImage: nsImg), in: canvasImgRect)
                    }
                }
            }

            // Vectorized fills (rendered behind strokes with even-odd rule for holes)
            for fill in model.fills {
                let box = fill.boundingBox()
                guard !box.isNull, box.intersects(visibleCanvasRect) else { continue }
                context.fill(
                    Path(fill.makeCGPath()),
                    with: .color(fill.displayColor(for: model)),
                    style: FillStyle(eoFill: true)
                )
            }

            // Spatial-indexed viewport query for committed strokes
            model.spatialGrid.sync(with: model.strokes)
            let visibleIndices = model.spatialGrid.queryIndices(in: visibleCanvasRect)
            let baseColor = isDarkMode ? Color.black : Color.white
            let eraserWidth = model.eraserSettings.size / safeScale

            for idx in visibleIndices {
                let stroke = model.strokes[idx]
                guard let entry = pathCache.entry(for: stroke) else { continue }
                drawCachedStroke(
                    entry.swiftUIPath,
                    stroke: stroke,
                    baseColor: baseColor,
                    eraserWidth: eraserWidth,
                    in: &context
                )
            }
            pathCache.prune(activeIds: Set(model.strokes.map(\.id)))
        }
    }

    private func drawCachedStroke(
        _ path: Path,
        stroke: Stroke,
        baseColor: Color,
        eraserWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        if stroke.isEraser {
            context.blendMode = .clear
            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(lineWidth: eraserWidth, lineCap: .round, lineJoin: .round)
            )
            context.blendMode = .normal
        } else if stroke.isSharpie {
            let glowColor = stroke.displayColor(for: model)
            context.stroke(
                path,
                with: .color(glowColor),
                style: StrokeStyle(lineWidth: stroke.lineWidth + 3, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                path,
                with: .color(baseColor),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )
        } else {
            context.stroke(
                path,
                with: .color(stroke.displayColor(for: model)),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

/// Isolated live layer — draws ONLY the active in-progress stroke (via O(1)
/// `IncrementalStrokePath`) and selection/lasso overlays.
private struct LiveInteractionCanvas: View {
    let model: DrawingModel
    let incrementalPath: IncrementalStrokePath
    let activePointCount: Int
    let offset: CGSize
    let scale: CGFloat

    private var hasActiveSelection: Bool {
        !model.selectionBoundary.isEmpty
            || !model.selectionLasso.isEmpty
            || !model.selectedImageIds.isEmpty
            || !model.selectedStrokeIds.isEmpty
            || !model.selectedFillIds.isEmpty
    }

    var body: some View {
        TimelineView(.animation(paused: !hasActiveSelection)) { timeline in
            let dashPhase: CGFloat = hasActiveSelection
                ? CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100) * 60)
                : 0

            Canvas { context, _ in
                let _ = activePointCount
                let safeScale = max(scale, 0.01)

                // Active stroke rendered with the exact same path algorithm as committed strokes
                if let current = model.currentStroke,
                   let cgPath = GeometryEngine.makeCGPath(for: current) {
                    context.drawLayer { layerCtx in
                        layerCtx.translateBy(x: offset.width, y: offset.height)
                        layerCtx.scaleBy(x: safeScale, y: safeScale)
                        let path = Path(cgPath)
                        if current.isEraser {
                            layerCtx.stroke(
                                path,
                                with: .color(.red.opacity(0.25)),
                                style: StrokeStyle(lineWidth: model.eraserSettings.size / safeScale, lineCap: .round, lineJoin: .round)
                            )
                        } else if current.isSharpie {
                            layerCtx.stroke(
                                path,
                                with: .color(current.displayColor(for: model)),
                                style: StrokeStyle(lineWidth: current.lineWidth + 3, lineCap: .round, lineJoin: .round)
                            )
                            let baseColor = model.appSettings.isDarkMode ? Color.black : Color.white
                            layerCtx.stroke(
                                path,
                                with: .color(baseColor),
                                style: StrokeStyle(lineWidth: current.lineWidth, lineCap: .round, lineJoin: .round)
                            )
                        } else {
                            layerCtx.stroke(
                                path,
                                with: .color(current.displayColor(for: model)),
                                style: StrokeStyle(lineWidth: current.lineWidth, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                }

                let tf = CGAffineTransform(translationX: offset.width, y: offset.height)
                    .scaledBy(x: safeScale, y: safeScale)

                if !model.selectionLasso.isEmpty {
                    let lPath = smoothPolygonPath(model.selectionLasso, close: false, transform: tf)
                    context.stroke(
                        lPath,
                        with: .color(.blue.opacity(0.6)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: dashPhase)
                    )
                }

                if !model.selectionBoundary.isEmpty {
                    let bPath = smoothPolygonPath(model.selectionBoundary, close: true, transform: tf)
                    context.stroke(
                        bPath,
                        with: .color(.blue),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: dashPhase)
                    )
                }

                for img in model.placedImages where model.selectedImageIds.contains(img.id) {
                    let corners = img.rotatedCorners().map { $0.applying(tf) }
                    guard corners.count == 4 else { continue }
                    var borderPath = Path()
                    borderPath.move(to: corners[0])
                    borderPath.addLine(to: corners[1])
                    borderPath.addLine(to: corners[2])
                    borderPath.addLine(to: corners[3])
                    borderPath.closeSubpath()
                    context.stroke(
                        borderPath,
                        with: .color(.blue),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: dashPhase)
                    )
                    let hs: CGFloat = 9
                    for corner in corners {
                        let handle = CGRect(x: corner.x - hs / 2, y: corner.y - hs / 2, width: hs, height: hs)
                        context.fill(Path(ellipseIn: handle), with: .color(.blue))
                        context.stroke(Path(ellipseIn: handle), with: .color(.white), lineWidth: 1.5)
                    }
                }

                // Read rotation state so @Observable tracks live drag frames
                let isRotating = model.isRotating
                let isSnapped = model.isRotationSnapped
                let _ = model.selectionRotationAngle
                if model.currentTool == .select, let geom = model.rotationHandleGeometry(scale: safeScale) {
                    let stemStart = geom.stemStart.applying(tf)
                    let handleCenter = geom.handleCenter.applying(tf)
                    let accent: Color = (isRotating && isSnapped) ? .orange : .blue

                    var stemPath = Path()
                    stemPath.move(to: stemStart)
                    stemPath.addLine(to: handleCenter)
                    context.stroke(stemPath, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                    let radius: CGFloat = isRotating ? 10 : 9
                    let knobRect = CGRect(
                        x: handleCenter.x - radius,
                        y: handleCenter.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let knobFill: Color = isRotating
                        ? accent
                        : (model.appSettings.isDarkMode ? Color(white: 0.14) : .white)
                    context.fill(Path(ellipseIn: knobRect), with: .color(knobFill))
                    context.stroke(Path(ellipseIn: knobRect), with: .color(accent), lineWidth: 1.75)

                    let glyphColor: Color = isRotating ? .white : accent
                    let glyph = context.resolve(
                        Text(Image(systemName: "arrow.trianglehead.2.clockwise"))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(glyphColor)
                    )
                    context.draw(glyph, at: handleCenter, anchor: .center)

                    if isRotating {
                        let dx = handleCenter.x - stemStart.x
                        let dy = handleCenter.y - stemStart.y
                        let len = max(hypot(dx, dy), 0.001)
                        let badgeCenter = CGPoint(
                            x: handleCenter.x + (dx / len) * 26,
                            y: handleCenter.y + (dy / len) * 26
                        )
                        let label = context.resolve(
                            Text(model.activeRotationLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                        )
                        let textSize = label.measure(in: CGSize(width: 100, height: 30))
                        let padX: CGFloat = 7
                        let padY: CGFloat = 3
                        let pillRect = CGRect(
                            x: badgeCenter.x - textSize.width / 2 - padX,
                            y: badgeCenter.y - textSize.height / 2 - padY,
                            width: textSize.width + padX * 2,
                            height: textSize.height + padY * 2
                        )
                        let pillBg: Color = isSnapped ? .orange : Color.black.opacity(0.78)
                        context.fill(Path(roundedRect: pillRect, cornerRadius: pillRect.height / 2), with: .color(pillBg))
                        context.draw(label, at: badgeCenter, anchor: .center)
                    }
                }
            }
        }
    }

    private func smoothPolygonPath(_ pts: [CGPoint], close: Bool, transform tf: CGAffineTransform) -> Path {
        var path = Path()
        guard !pts.isEmpty else { return path }
        path.move(to: pts[0].applying(tf))
        var prev = pts[0]
        for i in 1..<pts.count {
            let pt = pts[i]
            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
            path.addQuadCurve(to: mid.applying(tf), control: prev.applying(tf))
            prev = pt
        }
        if close { path.closeSubpath() }
        return path
    }
}

struct CanvasView: View {
    var model: DrawingModel
    var onBeginDraw: (() -> Void)?

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var pointCount: Int = 0

    static var lastSelectTap: Date = .distantPast
    static var lastEmptyTap: Date = .distantPast

    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var changeModeMonitor: Any?
    @State private var sceneAnimTimer: Timer?
    @State private var shapeHoldWorkItem: DispatchWorkItem?
    @State private var shapeHoldAnchor: CGPoint = .zero
    @State private var viewSize: CGSize?
    @State private var pathCache = StrokePathCache()
    @State private var incrementalPath = IncrementalStrokePath()

    private var pointerHandler: CanvasPointerHandler {
        CanvasPointerHandler(
            model: model,
            offset: offset,
            scale: max(scale, 0.01),
            onPoint: { count in
                pointCount = count
                if count == 0 {
                    shapeHoldWorkItem?.cancel()
                    shapeHoldWorkItem = nil
                } else if let pt = model.currentStroke?.points.last,
                          (model.currentTool == .pen || model.currentTool == .sharpie) {
                    if hypot(pt.x - shapeHoldAnchor.x, pt.y - shapeHoldAnchor.y) > 6 / max(scale, 0.1) || shapeHoldWorkItem == nil {
                        scheduleMacShapeHold(at: pt)
                    }
                }
            },
            onBeginDraw: onBeginDraw,
            onPan: { delta in
                offset.width += delta.width
                offset.height += delta.height
            }
        )
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BackgroundGridCanvas(
                background: model.appSettings.canvasBackground,
                isDarkMode: model.appSettings.isDarkMode,
                isWarmPaper: model.appSettings.isWarmPaper,
                offset: offset,
                scale: scale
            )

            CommittedStrokesCanvas(
                model: model,
                pathCache: pathCache,
                committedRevision: model.committedRevision,
                isDarkMode: model.appSettings.isDarkMode,
                offset: offset,
                scale: scale
            )

            LiveInteractionCanvas(
                model: model,
                incrementalPath: incrementalPath,
                activePointCount: pointCount,
                offset: offset,
                scale: scale
            )
        }
        .overlay(DrawingInputOverlay(handler: pointerHandler, currentTool: model.currentTool))
        .onChange(of: offset) { _, _ in reportMacViewport() }
        .onChange(of: scale) { _, newScale in
            if abs(model.zoomDisplayScale - newScale) > 0.005 {
                model.zoomDisplayScale = newScale
            }
            reportMacViewport()
        }
        .onChange(of: viewSize) { _, _ in reportMacViewport() }
        .onChange(of: model.needsRecenter) { _, needs in
            if needs, let size = viewSize {
                centerOnContent(canvasSize: size)
                model.needsRecenter = false
            }
        }
        .onChange(of: model.needsResetZoom) { _, needs in
            if needs {
                model.needsResetZoom = false
                let target = CanvasScene(name: "Reset", center: model.currentViewportCenter, scale: 1.0)
                animateMacToScene(target)
            }
        }
        .onChange(of: model.needsFitToContent) { _, needs in
            if needs {
                model.needsFitToContent = false
                fitMacContentToViewport()
            }
        }
        .onChange(of: model.pendingSceneNavigation) { _, scene in
            if let scene {
                model.pendingSceneNavigation = nil
                animateMacToScene(scene)
            }
        }
        .onAppear {
            installMonitors()
            reportMacViewport()
        }
        .onDisappear {
            sceneAnimTimer?.invalidate()
            sceneAnimTimer = nil
            shapeHoldWorkItem?.cancel()
            shapeHoldWorkItem = nil
            removeMonitors()
        }
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let keyWindow = NSApp.keyWindow {
                if keyWindow.attachedSheet != nil { return event }
                if keyWindow.firstResponder is NSTextView { return event }
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCmd = flags.contains(.command)
            let hasShift = flags.contains(.shift)
            let hasCtrlOrOpt = flags.contains(.control) || flags.contains(.option)
            let char = event.charactersIgnoringModifiers?.lowercased()

            if hasCmd && !hasCtrlOrOpt {
                switch char {
                case "z":
                    if hasShift { model.redo() } else { model.undo() }
                    return nil
                case "s":
                    model.save()
                    return nil
                case "c":
                    model.copySelected()
                    return nil
                case "v":
                    model.paste()
                    return nil
                case "i":
                    model.pendingAction = .importImage
                    return nil
                case "=":
                    model.resizeSelectedImages(by: 1.25)
                    return nil
                case "-":
                    model.resizeSelectedImages(by: 0.8)
                    return nil
                default:
                    return event
                }
            }

            if !hasCmd && !hasCtrlOrOpt {
                if event.keyCode == 53 || char == "\u{1B}" {
                    if model.currentTool == .select && (model.hasAnySelectionOrLasso || model.showDeleteMenu) {
                        model.clearLassoSelection()
                        return nil
                    }
                    if model.showDeleteMenu {
                        model.showDeleteMenu = false
                        return nil
                    }
                    return event
                }

                if event.keyCode == 48 || char == "\t" {
                    model.isToolbarVisible.toggle()
                    return nil
                }

                if char == "\u{7F}" || event.keyCode == 51 || event.keyCode == 117 {
                    model.deleteSelected()
                    return nil
                }

                switch char {
                case "p":
                    model.selectTool(.pen)
                    return nil
                case "f":
                    model.selectTool(.fill)
                    return nil
                case "s":
                    model.selectTool(hasShift ? .select : .sharpie)
                    return nil
                case "e":
                    let prior = model.currentTool
                    model.selectTool(.eraser)
                    switch prior {
                    case .pen: model.eraserSettings.eraseTarget = .pen
                    case .sharpie: model.eraserSettings.eraseTarget = .sharpie
                    case .fill: model.eraserSettings.eraseTarget = .fill
                    default: model.eraserSettings.eraseTarget = .all
                    }
                    return nil
                case "x" where hasShift:
                    model.addScene()
                    return nil
                case "," where !hasShift:
                    model.goToPreviousScene()
                    return nil
                case "." where !hasShift:
                    model.goToNextScene()
                    return nil
                case "0":
                    if model.currentTool == .eraser {
                        model.eraserSettings.eraseTarget = .all
                        return nil
                    }
                case "1", "2", "3", "4", "5", "6", "7", "8":
                    if let c = char, let digit = Int(c) {
                        if model.currentTool == .eraser {
                            switch digit {
                            case 1: model.eraserSettings.eraseTarget = .pen; return nil
                            case 2: model.eraserSettings.eraseTarget = .sharpie; return nil
                            case 3: model.eraserSettings.eraseTarget = .fill; return nil
                            default: break
                            }
                        }
                        let idx = digit - 1
                        switch model.currentTool {
                        case .pen where idx < model.penPresets.count:
                            model.selectPenPreset(idx)
                            return nil
                        case .sharpie where idx < model.sharpiePresets.count:
                            model.selectSharpiePreset(idx)
                            return nil
                        case .fill where idx < model.fillPresets.count:
                            model.selectFillPreset(idx)
                            return nil
                        default: break
                        }
                    }
                default: break
                }
            }

            return event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Only pan the canvas when scrolling on the main canvas window itself —
            // ignore sheets (sheetParent != nil), popovers (parent != nil), and windows with an active sheet.
            guard let win = event.window,
                  win === NSApp.keyWindow,
                  win.attachedSheet == nil,
                  win.sheetParent == nil,
                  win.parent == nil,
                  !model.showAbout else {
                return event
            }
            offset.width += event.scrollingDeltaX
            offset.height += event.scrollingDeltaY
            return event
        }

        // Apple Pencil (2nd gen / Pro) double-tap over Sidecar arrives as `.changeMode`.
        // Don't require `NSApp.keyWindow != nil` since Sidecar focus sync can leave keyWindow
        // momentarily nil while the canvas is still the active window.
        changeModeMonitor = NSEvent.addLocalMonitorForEvents(matching: .changeMode) { event in
            let activeWindow = event.window ?? NSApp.keyWindow ?? NSApp.mainWindow
            if activeWindow?.attachedSheet == nil,
               !model.showWelcome,
               !model.showAbout {
                model.toggleEraserFromPencil()
            }
            return nil
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = changeModeMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        scrollMonitor = nil
        changeModeMonitor = nil
    }

    private func centerOnContent(canvasSize: CGSize) {
        sceneAnimTimer?.invalidate()
        sceneAnimTimer = nil
        offset = .zero
        scale = 1.0
        reportMacViewport()
    }

    private func reportMacViewport() {
        guard let size = viewSize, size.width > 0, size.height > 0 else { return }
        let safeScale = max(scale, 0.01)
        model.currentViewportCenter = CGPoint(
            x: (size.width / 2 - offset.width) / safeScale,
            y: (size.height / 2 - offset.height) / safeScale
        )
        model.currentViewportScale = safeScale
        model.captureDefaultSceneIfNeeded()
    }

    private func fitMacContentToViewport() {
        let size = viewSize ?? CGSize(width: 1000, height: 700)
        guard let box = GeometryEngine.boundingBox(of: model.strokes, images: model.placedImages, fills: model.fills, padding: 60),
              box.width > 0, box.height > 0 else {
            centerOnContent(canvasSize: size)
            return
        }
        let fitScale = min(max(min(size.width / box.width, size.height / box.height), 0.3), 2.5)
        let target = CanvasScene(name: "Fit", center: CGPoint(x: box.midX, y: box.midY), scale: fitScale)
        animateMacToScene(target)
    }

    private func scheduleMacShapeHold(at pt: CGPoint) {
        shapeHoldWorkItem?.cancel()
        shapeHoldAnchor = pt
        let item = DispatchWorkItem {
            if model.snapCurrentStrokeToShape() {
                pointCount &+= 1
            }
        }
        shapeHoldWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: item)
    }

    private func animateMacToScene(_ scene: CanvasScene) {
        sceneAnimTimer?.invalidate()
        sceneAnimTimer = nil
        let size = viewSize ?? CGSize(width: 1000, height: 700)
        let fromOffset = offset
        let fromScale = scale
        let toScale = min(max(scene.cgScale, 0.3), 5.0)
        let toOffset = CGSize(
            width: size.width / 2 - scene.center.x * toScale,
            height: size.height / 2 - scene.center.y * toScale
        )
        let startTime = CACurrentMediaTime()
        let duration: CFTimeInterval = 0.32
        sceneAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let rawT = min(max((CACurrentMediaTime() - startTime) / duration, 0), 1)
            let t = rawT < 0.5 ? 4 * rawT * rawT * rawT : 1 - pow(-2 * rawT + 2, 3) / 2
            let f = CGFloat(t)
            MainActor.assumeIsolated {
                scale = fromScale + (toScale - fromScale) * f
                offset = CGSize(
                    width: fromOffset.width + (toOffset.width - fromOffset.width) * f,
                    height: fromOffset.height + (toOffset.height - fromOffset.height) * f
                )
                if rawT >= 1 {
                    timer.invalidate()
                    sceneAnimTimer = nil
                }
            }
        }
    }
}

// MARK: - Pointer Input + GPU Hover Indicator (macOS)

struct DrawingInputOverlay: NSViewRepresentable {
    let handler: CanvasPointerHandler
    let currentTool: Tool

    static var debugInputLogging = false

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: InputView, context: Context) {
        nsView.handler = handler
        nsView.refreshHoverDot()
    }

    final class InputView: NSView {
        var handler: CanvasPointerHandler?
        private var lastHoverPoint: CGPoint?
        private var hasUsedPencil: Bool = false
        private var isFingerPanning: Bool = false
        private var lastPanPoint: CGPoint = .zero
        private var isShowingCustomCursor: Bool = false

        /// GPU-composited hover dot — moving the mouse updates this CALayer directly
        /// with ZERO SwiftUI state mutations or Canvas redraws!
        private let hoverDotLayer: CALayer = {
            let layer = CALayer()
            layer.isHidden = true
            return layer
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(hoverDotLayer)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer?.addSublayer(hoverDotLayer)
        }

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        func refreshHoverDot() {
            guard let point = lastHoverPoint else { return }
            updateHoverDot(at: point)
        }

        private func resizeCursor(forCorner corner: Int, rotation: CGFloat) -> NSCursor {
            let baseAngle: CGFloat
            switch corner {
            case 0: baseAngle = -3 * .pi / 4
            case 1: baseAngle = -.pi / 4
            case 2: baseAngle = .pi / 4
            default: baseAngle = 3 * .pi / 4
            }
            var angle = (baseAngle + rotation).truncatingRemainder(dividingBy: .pi)
            if angle < 0 { angle += .pi }
            if angle < .pi / 8 || angle >= 7 * .pi / 8 {
                return NSCursor.frameResize(position: .left, directions: .all)
            } else if angle < 3 * .pi / 8 {
                return NSCursor.frameResize(position: .topLeft, directions: .all)
            } else if angle < 5 * .pi / 8 {
                return NSCursor.frameResize(position: .top, directions: .all)
            } else {
                return NSCursor.frameResize(position: .topRight, directions: .all)
            }
        }

        private func canvasPoint(forViewPoint p: CGPoint) -> CGPoint {
            guard let h = handler else { return p }
            let safeScale = max(h.scale, 0.01)
            return CGPoint(
                x: (p.x - h.offset.width) / safeScale,
                y: (p.y - h.offset.height) / safeScale
            )
        }

        /// Updates the pointer cursor on macOS when hovering or dragging image resize handles
        /// or the selection rotation handle. Returns true when a handle cursor is active.
        @discardableResult
        private func updateSelectCursor(at point: CGPoint?) -> Bool {
            guard !isFingerPanning else { return false }
            guard let point, let h = handler, h.model.currentTool == .select else {
                if isShowingCustomCursor {
                    NSCursor.arrow.set()
                    isShowingCustomCursor = false
                }
                return false
            }

            let model = h.model
            let cp = canvasPoint(forViewPoint: point)
            let safeScale = max(h.scale, 0.01)

            if model.isResizing,
               let imgId = model.resizeImageId,
               let img = model.placedImages.first(where: { $0.id == imgId }) {
                resizeCursor(forCorner: model.resizeCorner, rotation: img.cgRotation).set()
                isShowingCustomCursor = true
                return true
            }
            if model.isRotating {
                NSCursor.closedHand.set()
                isShowingCustomCursor = true
                return true
            }
            if let hit = model.hitTestResizeHandle(cp, scale: safeScale),
               let img = model.placedImages.first(where: { $0.id == hit.imgId }) {
                resizeCursor(forCorner: hit.corner, rotation: img.cgRotation).set()
                isShowingCustomCursor = true
                return true
            }
            if model.hitTestRotateHandle(cp, scale: safeScale) {
                NSCursor.openHand.set()
                isShowingCustomCursor = true
                return true
            }

            if isShowingCustomCursor {
                NSCursor.arrow.set()
                isShowingCustomCursor = false
            }
            return false
        }

        private func updateHoverDot(at point: CGPoint?) {
            lastHoverPoint = point
            let handleCursorActive = updateSelectCursor(at: point)
            guard let point, let model = handler?.model, !handleCursorActive else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                hoverDotLayer.isHidden = true
                CATransaction.commit()
                return
            }
            let size: CGFloat
            let color: CGColor
            switch model.currentTool {
            case .eraser:
                size = max(model.eraserSettings.size, 4)
                color = NSColor.systemRed.withAlphaComponent(0.25).cgColor
            case .pen:
                size = max(model.penSettings.thickness * 1.5, 4)
                color = (model.appSettings.isDarkMode ? NSColor.white : NSColor.black).withAlphaComponent(0.4).cgColor
            case .sharpie:
                size = max(model.sharpieSettings.thickness * 1.5, 4)
                color = (model.appSettings.isDarkMode ? NSColor.white : NSColor.black).withAlphaComponent(0.4).cgColor
            case .fill:
                size = 10
                color = StrokeRenderer.cgColor(from: model.fillColor.opacity(0.6))
            case .select:
                size = 4
                color = (model.appSettings.isDarkMode ? NSColor.white : NSColor.black).withAlphaComponent(0.4).cgColor
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hoverDotLayer.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            hoverDotLayer.cornerRadius = size / 2
            hoverDotLayer.backgroundColor = color
            hoverDotLayer.isHidden = false
            CATransaction.commit()
        }

        private func log(_ event: NSEvent, _ phase: String) {
            guard DrawingInputOverlay.debugInputLogging else { return }
            let device: String
            if event.type == .tabletProximity || event.subtype == .tabletProximity {
                device = "\(event.pointingDeviceType.rawValue)"
            } else {
                device = "n/a"
            }
            print("[CanvasInput] \(phase) type=\(event.type.rawValue) subtype=\(event.subtype.rawValue) device=\(device)")
        }

        private func isPencil(_ event: NSEvent) -> Bool {
            if event.type == .tabletPoint || event.type == .tabletProximity { return true }
            if event.subtype == .tabletPoint || event.subtype == .tabletProximity { return true }
            return false
        }

        private func shouldPanWithNonPencil(_ event: NSEvent, handler: CanvasPointerHandler) -> Bool {
            guard handler.model.currentTool != .select else { return false }
            guard !isPencil(event) else { return false }
            return handler.model.appSettings.pencilOnly || hasUsedPencil
        }

        private func shouldAcceptInput(_ event: NSEvent, handler: CanvasPointerHandler) -> Bool {
            if handler.model.currentTool == .select { return true }
            if !handler.model.appSettings.pencilOnly { return true }
            return isPencil(event)
        }

        private func canvasPoint(for event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            guard let h = handler else { return p }
            let safeScale = max(h.scale, 0.01)
            return CGPoint(
                x: (p.x - h.offset.width) / safeScale,
                y: (p.y - h.offset.height) / safeScale
            )
        }

        override func tabletProximity(with event: NSEvent) {
            super.tabletProximity(with: event)
            hasUsedPencil = true
        }

        override func mouseDown(with event: NSEvent) {
            log(event, "down")
            super.mouseDown(with: event)
            if isPencil(event) { hasUsedPencil = true }
            guard let h = handler else { return }
            let loc = convert(event.locationInWindow, from: nil)
            if shouldPanWithNonPencil(event, handler: h) {
                isFingerPanning = true
                lastPanPoint = loc
                updateHoverDot(at: nil)
                NSCursor.closedHand.push()
                return
            }
            guard shouldAcceptInput(event, handler: h) else { return }
            h.onChange(canvasPoint(for: event), drawing: true, shiftPressed: event.modifierFlags.contains(.shift))
            updateHoverDot(at: loc)
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            if isPencil(event) { hasUsedPencil = true }
            guard let h = handler else { return }
            let loc = convert(event.locationInWindow, from: nil)
            if isFingerPanning {
                let delta = CGSize(width: loc.x - lastPanPoint.x, height: loc.y - lastPanPoint.y)
                lastPanPoint = loc
                h.onPan(delta)
                return
            }
            guard shouldAcceptInput(event, handler: h) else { return }
            h.onChange(canvasPoint(for: event), drawing: false, shiftPressed: event.modifierFlags.contains(.shift))
            updateHoverDot(at: loc)
        }

        override func mouseUp(with event: NSEvent) {
            log(event, "up")
            super.mouseUp(with: event)
            if isFingerPanning {
                isFingerPanning = false
                NSCursor.pop()
                return
            }
            guard let h = handler, shouldAcceptInput(event, handler: h) else { return }
            h.onEnd()
            updateHoverDot(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            if isPencil(event) { hasUsedPencil = true }
            updateHoverDot(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            updateHoverDot(at: nil)
        }

        override func touchesBegan(with event: NSEvent) { super.touchesBegan(with: event) }
        override func touchesMoved(with event: NSEvent) { super.touchesMoved(with: event) }
        override func touchesEnded(with event: NSEvent) { super.touchesEnded(with: event) }
        override func touchesCancelled(with event: NSEvent) { super.touchesCancelled(with: event) }
    }
}

struct CanvasPointerHandler {
    let model: DrawingModel
    let offset: CGSize
    let scale: CGFloat
    let onPoint: (Int) -> Void
    let onBeginDraw: (() -> Void)?
    let onPan: (CGSize) -> Void

    func onChange(_ canvas: CGPoint, drawing: Bool, shiftPressed: Bool = false) {
        if drawing {
            onBeginDraw?()
            model.lastCanvasTapLocation = canvas
        }

        if model.currentTool == .select {
            if let start = model.pendingDeselectPoint, !drawing {
                let threshold = 6 / max(scale, 0.1)
                if GeometryEngine.distanceSquared(start, canvas) > threshold * threshold {
                    model.pendingDeselectPoint = nil
                    model.beginLasso(at: start)
                    model.addLassoPoint(canvas)
                }
                return
            }
            if model.isRotating {
                model.updateRotate(to: canvas, snapTo15Degrees: shiftPressed)
                return
            }
            if model.isMoving || model.isResizing {
                let delta = CGSize(width: canvas.x - model.lastMovePoint.x, height: canvas.y - model.lastMovePoint.y)
                model.moveSelected(by: delta)
                model.lastMovePoint = canvas
                return
            }
            let hasSelection = !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty || !model.selectionBoundary.isEmpty
            if drawing && hasSelection {
                if model.hitTestRotateHandle(canvas, scale: scale) {
                    model.beginRotate(at: canvas, scale: scale)
                    return
                }
                if model.hitTestResizeHandle(canvas, scale: scale) != nil {
                    model.beginMove(at: canvas, scale: scale)
                    return
                }
                let onSelected = model.isPointOnSelectedItem(canvas) || (!model.selectionBoundary.isEmpty && model.isPointInSelectionBoundary(canvas))
                if onSelected {
                    let now = Date()
                    if now.timeIntervalSince(CanvasView.lastSelectTap) < 0.4 {
                        CanvasView.lastSelectTap = .distantPast
                        model.showDeleteMenu = true
                        model.deleteMenuLocation = CGPoint(x: canvas.x * scale + offset.width + 60, y: canvas.y * scale + offset.height)
                        return
                    }
                    CanvasView.lastSelectTap = now
                    model.beginMove(at: canvas, scale: scale)
                } else {
                    model.clearSelection()
                    model.pendingDeselectPoint = canvas
                }
                return
            }
            if drawing && model.selectionLasso.isEmpty {
                let now = Date()
                let onElement = model.hasElement(at: canvas, scale: scale)
                if !onElement, now.timeIntervalSince(CanvasView.lastEmptyTap) < 0.4 {
                    CanvasView.lastEmptyTap = .distantPast
                    model.showDeleteMenu = true
                    model.deleteMenuLocation = CGPoint(x: canvas.x * scale + offset.width + 60, y: canvas.y * scale + offset.height)
                    return
                }
                CanvasView.lastEmptyTap = onElement ? .distantPast : now
                model.beginLasso(at: canvas)
            } else if !model.selectionLasso.isEmpty {
                model.addLassoPoint(canvas)
            }
            return
        }

        if model.currentTool == .fill {
            if drawing {
                model.floodFill(at: canvas)
            }
            return
        }

        if model.currentStroke == nil {
            model.beginStroke(at: canvas, isEraser: model.currentTool == .eraser)
        } else {
            model.addPoint(canvas)
        }
        onPoint(model.currentStroke?.points.count ?? 0)
    }

    func onEnd() {
        if model.currentTool == .fill { return }
        if model.currentTool == .select {
            if let tapPt = model.pendingDeselectPoint {
                model.pendingDeselectPoint = nil
                _ = model.selectElement(at: tapPt, scale: scale)
            } else if model.isRotating {
                model.commitRotate()
            } else if model.isMoving || model.isResizing {
                model.commitMove()
            } else {
                model.endLasso(scale: scale)
            }
            return
        }
        model.endStroke()
        onPoint(0)
    }
}

#endif
