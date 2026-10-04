import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

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
        let bg: UIColor = isDark ? UIColor.black : .white
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

        // Placed images
        for img in model.placedImages {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
            ctx.scaleBy(x: 1, y: -1)
            // Use cached UIImage for fast redraws
            let uiImage: UIImage? = {
                if let cached = model.imageCache[img.id] as? UIImage { return cached }
                if let decoded = UIImage(data: img.imageData) {
                    model.imageCache[img.id] = decoded
                    return decoded
                }
                return nil
            }()
            if let cgImg = uiImage?.cgImage {
                ctx.draw(cgImg, in: CGRect(origin: .zero, size: rect.size))
            }
            ctx.restoreGState()
        }
        for stroke in model.strokes {
            drawStroke(stroke, in: ctx)
        }
        if let current = model.currentStroke {
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

        // Selection rects for placed images
        for img in model.placedImages where model.selectedImageIds.contains(img.id) {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(2 / scale)
            ctx.setLineDash(phase: dashPhase / scale, lengths: [8 / scale, 5 / scale])
            ctx.stroke(rect)
            // Resize handles at corners
            let handleSize: CGFloat = 10 / scale
            for corner in [rect.origin, CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] {
                let handle = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2, width: handleSize, height: handleSize)
                ctx.setFillColor(UIColor.systemBlue.cgColor)
                ctx.fill(handle)
            }
            ctx.restoreGState()
        }

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
            // Sharpie — glow is the stroke's stored color, core is the background base color
            if stroke.isSharpie {
                let glowColor = stroke.uiColor
                ctx.setStrokeColor(UIColor(glowColor).cgColor)
                ctx.setLineWidth(stroke.lineWidth + 3)
                ctx.addPath(path)
                ctx.strokePath()
                let baseColor = (model?.appSettings.isDarkMode ?? false) ? UIColor.black : UIColor.white
                ctx.setStrokeColor(baseColor.cgColor)
                ctx.setLineWidth(stroke.lineWidth)
            } else {
                let color = stroke.displayColor(for: model!)
                ctx.setStrokeColor(UIColor(color).cgColor)
                ctx.setLineWidth(stroke.lineWidth)
            }
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
        case .sharpie:
            size = model.sharpieSettings.thickness * 1.5
            color = UIColor.black.withAlphaComponent(0.4)
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
        // Dismiss delete menu on any canvas tap
        model.showDeleteMenu = false
        lastTouchPoint = touch.location(in: self)
        model.lastCanvasTapLocation = toCanvas(touch.location(in: self))
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard touch.type == .pencil || model.currentTool == .select else { return }
        #endif

        onBeginDraw?()

        if model.currentTool == .select {
            let cp = toCanvas(touch.location(in: self))
            // Check if tap is on an unselected image
            if let imgId = model.hitTestImage(cp), !model.selectedImageIds.contains(imgId) {
                // Tap on unselected image — select it, deselect everything else
                model.selectedStrokeIds.removeAll()
                model.selectedImageIds = [imgId]
                model.selectionBoundary.removeAll()
                strokeLayer.setNeedsDisplay()
                gridView.setNeedsDisplay()
                return
            }
            if !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectionBoundary.isEmpty {
                // Check for resize handle hit first (handle is outside image rect)
                if model.hitTestResizeHandle(cp) != nil {
                    let now = Date()
                    if now.timeIntervalSince(Self.lastSelectTap) < 0.4 {
                        Self.lastSelectTap = .distantPast
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
                    strokeLayer.model = model
                    gridView.model = model
                    strokeLayer.setNeedsDisplay()
                    gridView.setNeedsDisplay()
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
                        strokeLayer.model = model
                        gridView.model = model
                        strokeLayer.setNeedsDisplay()
                        gridView.setNeedsDisplay()
                        return
                    }
                    Self.lastSelectTap = now
                    model.beginMove(at: cp)
                } else {
                    // Tap outside selection — deselect, don't start new lasso
                    model.selectedStrokeIds.removeAll()
                    model.selectedImageIds.removeAll()
                    model.selectionBoundary.removeAll()
                    strokeLayer.model = model
                    gridView.model = model
                    strokeLayer.setNeedsDisplay()
                    gridView.setNeedsDisplay()
                    return
                }
            } else {
                // Nothing selected — check for double-tap to show paste menu
                let now = Date()
                if now.timeIntervalSince(Self.lastEmptyTap) < 0.4 {
                    Self.lastEmptyTap = .distantPast
                    model.showDeleteMenu = true
                    let tapLoc = touch.location(in: self)
                    model.deleteMenuLocation = CGPoint(x: tapLoc.x + 60, y: tapLoc.y)
                    strokeLayer.model = model
                    gridView.model = model
                    strokeLayer.setNeedsDisplay()
                    gridView.setNeedsDisplay()
                    return
                }
                Self.lastEmptyTap = now
                model.beginLasso(at: cp)
            }
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

        if model.currentTool == .select {
            if model.showDeleteMenu { return }
            if model.isMoving || model.isResizing {
                let cur = toCanvas(touch.location(in: self))
                let offset = CGSize(width: cur.x - model.lastMovePoint.x, height: cur.y - model.lastMovePoint.y)
                model.moveSelected(by: offset)
                model.lastMovePoint = cur
            } else if !model.selectedImageIds.isEmpty {
                // Image selected — ignore touch moves (avoids accidental lasso points)
            } else {
                let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
                for ct in coalesced {
                    model.addLassoPoint(toCanvas(ct.location(in: self)))
                }
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
        if model?.currentTool == .select {
            if model?.showDeleteMenu == true { return }
            if model?.isMoving == true || model?.isResizing == true {
                model?.commitMove()
            } else {
                model?.endLasso()
            }
            strokeLayer.setNeedsDisplay()
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
    static var lastEmptyTap: Date = .distantPast

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
    static var lastEmptyTap: Date = .distantPast

    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var macDashPhase: CGFloat = 0
    @State private var dashTimer: Timer?
    @State private var viewSize: CGSize?

    private var pointerHandler: CanvasPointerHandler {
        CanvasPointerHandler(
            model: model,
            offset: offset,
            scale: scale,
            onHover: { hoverLocation = $0 },
            onPoint: { pointCount = $0 },
            onBeginDraw: onBeginDraw
        )
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Color.clear.onAppear { viewSize = geo.size }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Canvas { context, size in
                let spacing: CGFloat = 30 * scale
                let isDark = model.appSettings.isDarkMode
                let bg = isDark ? Color.black : Color.white
                let fg = isDark ? Color(red: 56/255, green: 56/255, blue: 58/255) : Color.gray.opacity(0.2)

                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

                switch model.appSettings.canvasBackground {
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

            Canvas { context, size in
                let _ = pointCount
                let _ = hoverLocation

                let tf = CGAffineTransform(translationX: offset.width, y: offset.height)
                    .scaledBy(x: scale, y: scale)

                // Placed images
                for img in model.placedImages {
                    let rect = CGRect(origin: img.cgPosition, size: img.cgSize).applying(tf)
                    // Use cached NSImage for fast redraws
                    let nsImage: NSImage? = {
                        if let cached = model.imageCache[img.id] as? NSImage { return cached }
                        if let imgObj = NSImage(data: img.imageData) {
                            model.imageCache[img.id] = imgObj
                            return imgObj
                        }
                        return nil
                    }()
                    if let nsImg = nsImage {
                        // Scale to rect size and draw with top-left anchor
                        let resized = NSImage(size: rect.size)
                        resized.lockFocus()
                        nsImg.draw(in: NSRect(origin: .zero, size: rect.size),
                                   from: NSRect(origin: .zero, size: nsImg.size),
                                   operation: .copy, fraction: 1)
                        resized.unlockFocus()
                        context.draw(Image(nsImage: resized), at: rect.origin, anchor: .topLeading)
                    }
                }
                for stroke in model.strokes {
                    drawStroke(stroke, in: &context, transform: tf)
                }
                if let current = model.currentStroke {
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

                // Selection rects for placed images (macOS)
                for img in model.placedImages where model.selectedImageIds.contains(img.id) {
                    let rect = CGRect(origin: img.cgPosition, size: img.cgSize).applying(tf)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 0), with: .color(.blue),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 5], dashPhase: macDashPhase))
                    let hs: CGFloat = 8
                    for corner in [rect.origin, CGPoint(x: rect.maxX, y: rect.minY),
                                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] {
                        let handle = CGRect(x: corner.x - hs / 2, y: corner.y - hs / 2, width: hs, height: hs)
                        context.fill(Path(ellipseIn: handle), with: .color(.blue))
                    }
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
            .overlay(DrawingInputOverlay(handler: pointerHandler))
            .onReceive(Timer.publish(every: 1/60.0, on: .main, in: .common).autoconnect()) { _ in
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
                case "p":
                    model.selectTool(.pen)
                case "s":
                    if hasShift {
                        model.selectTool(.select)
                    } else {
                        model.selectTool(.sharpie)
                    }
                case "e":
                    let prior = model.currentTool
                    model.selectTool(.eraser)
                    switch prior {
                    case .pen: model.eraserSettings.eraseTarget = .pen
                    case .sharpie: model.eraserSettings.eraseTarget = .sharpie
                    default: model.eraserSettings.eraseTarget = .all
                    }
                case "1", "2", "3", "4", "5", "6", "7", "8":
                    if let c = char, let digit = Int(c) {
                        let idx = digit - 1
                        switch model.currentTool {
                        case .pen where idx < model.penPresets.count:
                            model.penSettings.lightColor = model.penPresets[idx]
                            model.penSettings.darkColor = model.penPresets[idx]
                            model.penPresetIndex = idx
                        case .sharpie where idx < model.sharpiePresets.count:
                            model.sharpieSettings.lightColor = model.sharpiePresets[idx]
                            model.sharpieSettings.darkColor = model.sharpiePresets[idx]
                            model.sharpiePresetIndex = idx
                        default: break
                        }
                    }
                default: break
                }

                if hasCmd && !hasShift && char == "z" { model.undo(); return nil }
                if hasCmd && hasShift && char == "z" { model.redo(); return nil }
                if hasCmd && char == "s" { model.save(); return nil }
                if hasCmd && char == "c" { model.copySelected(); return nil }
                if hasCmd && char == "v" { model.paste(); return nil }
                if hasCmd && char == "i" { model.pendingAction = .importImage; return nil }
                if hasCmd && char == "=" { model.resizeSelectedImages(by: 1.25); return nil }
                if hasCmd && char == "-" { model.resizeSelectedImages(by: 0.8); return nil }

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
            // Sharpie — glow is the stroke's stored color, core is the background base color
            if stroke.isSharpie {
                context.stroke(path, with: .color(stroke.uiColor),
                              style: StrokeStyle(lineWidth: (stroke.lineWidth + 3) * scale,
                                                lineCap: .round, lineJoin: .round))
                let baseColor = model.appSettings.isDarkMode ? Color.black : Color.white
                context.stroke(path, with: .color(baseColor),
                              style: StrokeStyle(lineWidth: stroke.lineWidth * scale,
                                                lineCap: .round, lineJoin: .round))
            } else {
                context.stroke(path, with: .color(stroke.displayColor(for: model)),
                              style: StrokeStyle(lineWidth: stroke.lineWidth * scale,
                                                lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Pointer Input (macOS)

/// Routes AppKit mouse/tablet events into the SwiftUI `CanvasView`,
/// preserving device information so we can distinguish pencil from finger/mouse.
struct DrawingInputOverlay: NSViewRepresentable {
    let handler: CanvasPointerHandler

    /// Temporary diagnostic flag — set back to true if you need to inspect event types again.
    static var debugInputLogging = false

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: InputView, context: Context) {
        nsView.handler = handler
    }

    final class InputView: NSView {
        var handler: CanvasPointerHandler?

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }  // top-left origin, matches SwiftUI

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

        private func log(_ event: NSEvent, _ phase: String) {
            guard DrawingInputOverlay.debugInputLogging else { return }
            let device: String
            if #available(macOS 10.15, *) {
                device = "\(event.pointingDeviceType.rawValue)"
            } else {
                device = "?"
            }
            print("[CanvasInput] \(phase) type=\(event.type.rawValue) subtype=\(event.subtype.rawValue) device=\(device)")
        }

        private func isPencil(_ event: NSEvent) -> Bool {
            // Sidecar delivers Apple Pencil as tablet events; finger/mouse come through
            // as regular mouse events.
            if event.type == .tabletPoint { return true }
            if event.subtype == .tabletPoint || event.subtype == .tabletProximity { return true }
            if #available(macOS 10.15, *), event.pointingDeviceType == .pen || event.pointingDeviceType == .eraser {
                return true
            }
            return false
        }

        private func canvasPoint(for event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            guard let h = handler else { return p }
            return CGPoint(
                x: (p.x - h.offset.width) / h.scale,
                y: (p.y - h.offset.height) / h.scale
            )
        }

        override func mouseDown(with event: NSEvent) {
            log(event, "down")
            // Always forward to AppKit first. Sidecar delivers finger/palm input
            // as digitizer touches that AppKit tracks internally; skipping super
            // leaves its touch state unbalanced and trips the
            // "Missing Touches" assertion in -[NSEvent _initDigitizerTouchesFromIOHidEvent:].
            super.mouseDown(with: event)
            guard let h = handler else { return }
            // Drawing tools accept only pencil input; select accepts any pointer.
            // Finger/palm/mouse events are ignored for drawing so they can't perturb
            // an in-progress pencil stroke, but AppKit has already seen the event.
            if h.model.currentTool != .select && !isPencil(event) {
                return
            }
            let loc = convert(event.locationInWindow, from: nil)
            h.onHover(loc)
            h.onChange(canvasPoint(for: event), drawing: true)
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            guard let h = handler else { return }
            if h.model.currentTool != .select && !isPencil(event) {
                return
            }
            let loc = convert(event.locationInWindow, from: nil)
            h.onHover(loc)
            h.onChange(canvasPoint(for: event), drawing: false)
        }

        override func mouseUp(with event: NSEvent) {
            log(event, "up")
            super.mouseUp(with: event)
            guard let h = handler else { return }
            if h.model.currentTool != .select && !isPencil(event) {
                return
            }
            h.onEnd()
        }

        override func mouseMoved(with event: NSEvent) {
            guard let h = handler else { return }
            h.onHover(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            handler?.onHover(nil)
        }

        // Sidecar digitizer touches (finger/palm) are tracked by AppKit as touch
        // sequences. Forward every phase to super so AppKit's touch state stays
        // balanced; we intentionally do not consume these for drawing.
        override func touchesBegan(with event: NSEvent) {
            super.touchesBegan(with: event)
        }

        override func touchesMoved(with event: NSEvent) {
            super.touchesMoved(with: event)
        }

        override func touchesEnded(with event: NSEvent) {
            super.touchesEnded(with: event)
        }

        override func touchesCancelled(with event: NSEvent) {
            super.touchesCancelled(with: event)
        }
    }
}

/// Captures the current canvas transform and model so the overlay can forward
/// pointer input back into `CanvasView` without creating a reference cycle.
struct CanvasPointerHandler {
    let model: DrawingModel
    let offset: CGSize
    let scale: CGFloat
    let onHover: (CGPoint?) -> Void
    let onPoint: (Int) -> Void
    let onBeginDraw: (() -> Void)?

    func onChange(_ canvas: CGPoint, drawing: Bool) {
        if drawing {
            onBeginDraw?()
            model.lastCanvasTapLocation = canvas
        }

        if model.currentTool == .select {
            // macOS: tap on unselected image selects it
            if let imgId = model.hitTestImage(canvas), !model.selectedImageIds.contains(imgId) {
                model.selectedStrokeIds.removeAll()
                model.selectedImageIds = [imgId]
                model.selectionBoundary.removeAll()
                return
            }
            if model.isMoving || model.isResizing {
                let delta = CGSize(width: canvas.x - model.lastMovePoint.x, height: canvas.y - model.lastMovePoint.y)
                model.moveSelected(by: delta)
                model.lastMovePoint = canvas
            } else if !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectionBoundary.isEmpty {
                // Check for resize handle hit first
                if model.hitTestResizeHandle(canvas) != nil {
                    model.beginMove(at: canvas)
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
                    model.beginMove(at: canvas)
                } else {
                    model.selectedStrokeIds.removeAll()
                    model.selectedImageIds.removeAll()
                    model.selectionBoundary.removeAll()
                }
            } else if model.selectionLasso.isEmpty {
                // Nothing selected — check for double-tap to show paste menu
                let now = Date()
                if now.timeIntervalSince(CanvasView.lastEmptyTap) < 0.4 {
                    CanvasView.lastEmptyTap = .distantPast
                    model.showDeleteMenu = true
                    model.deleteMenuLocation = CGPoint(x: canvas.x * scale + offset.width + 60, y: canvas.y * scale + offset.height)
                    return
                }
                CanvasView.lastEmptyTap = now
                model.beginLasso(at: canvas)
            } else {
                model.addLassoPoint(canvas)
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
        if model.currentTool == .select {
            if model.isMoving { model.commitMove() }
            else if model.isResizing { model.commitMove() }
            else { model.endLasso() }
            return
        }
        model.endStroke()
        onPoint(0)
    }
}

#endif
