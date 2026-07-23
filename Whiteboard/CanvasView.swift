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
        let view = DrawingCanvasView()
        view.model = model
        return view
    }

    func updateUIView(_ uiView: DrawingCanvasView, context: Context) {
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
        let bg: UIColor = isDark ? .black : .white
        let fg: UIColor = isDark ? .systemGray4 : .systemGray5
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

        ctx.restoreGState()
        ctx.restoreGState()
    }

    private func drawFill(_ region: FillRegion, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.setFillColor(UIColor(region.uiColor).cgColor)
        ctx.addPath(region.cgPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count >= 2 else { return }

        let path = CGMutablePath()
        path.move(to: stroke.points[0])
        var prev = stroke.points[0]
        for i in 1..<stroke.points.count {
            let pt = stroke.points[i]
            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
            prev = pt
        }
        path.addLine(to: stroke.points.last!)

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if stroke.isEraser {
            ctx.setBlendMode(.clear)
            ctx.setLineWidth((model?.eraserSettings.size ?? 20) / scale)
        } else {
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(stroke.uiColor.cgColor)
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
        addGestureRecognizer(pinchGesture)
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
            showHoverIndicator(at: loc)
        case .ended, .cancelled:
            hideHoverIndicator()
        default:
            break
        }
    }

    private func showHoverIndicator(at point: CGPoint) {
        guard let model = model else { return }
        let size: CGFloat = model.currentTool == .eraser ? model.eraserSettings.size : model.currentTool == .pen ? model.penSettings.thickness : 4
        let indicator = CALayer()
        indicator.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2,
                                 width: size, height: size)
        indicator.cornerRadius = size / 2
        indicator.backgroundColor = (model?.currentTool == .eraser ?
            UIColor.red.withAlphaComponent(0.25).cgColor :
            UIColor.black.withAlphaComponent(0.4).cgColor)
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
        gridView.setNeedsDisplay()
        strokeLayer.setNeedsDisplay()
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let model = model else { return }

        onBeginDraw?()

        if model.currentTool == .fill {
            model.performFill(at: toCanvas(touch.location(in: self)))
            strokeLayer.setNeedsDisplay()
            gridView.setNeedsDisplay()
            return
        }

        if model.currentTool == .select {
            if !model.selectedStrokeIds.isEmpty || !model.selectedFillIds.isEmpty {
                let cp = toCanvas(touch.location(in: self))
                model.beginMove(at: cp)
            } else {
                model.beginLasso(at: toCanvas(touch.location(in: self)))
                startDashAnimation()
            }
            strokeLayer.setNeedsDisplay()
            return
        }

        model.beginStroke(at: toCanvas(touch.location(in: self)), isEraser: model.currentTool == .eraser)
        strokeLayer.setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let model = model else { return }

        if model.currentTool == .select {
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

        guard model.currentTool != .fill, model.currentStroke != nil else { return }

        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        for ct in coalesced {
            model.addPoint(toCanvas(ct.location(in: self)))
        }
        strokeLayer.setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if model?.currentTool == .select {
            if model?.isMoving == true {
                model?.commitMove()
            } else {
                model?.endLasso()
            }
            strokeLayer.setNeedsDisplay()
            return
        }
        guard model?.currentTool != .fill else { return }
        model?.endStroke()
        strokeLayer.setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if model?.currentTool == .select {
            model?.endLasso()
            strokeLayer.setNeedsDisplay()
            return
        }
        guard model?.currentTool != .fill else { return }
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
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        toggleTool()
    }

    @available(iOS 17.5, *)
    func pencilInteractionDidSqueeze(_ interaction: UIPencilInteraction) {
        toggleTool()
    }

    private func toggleTool() {
        guard let model = model else { return }
        model.selectTool(model.currentTool == .pen ? .eraser : .pen)
    }
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
    @State private var didFill: Bool = false

    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var macDashPhase: CGFloat = 0
    @State private var dashTimer: Timer?

    var body: some View {
        ZStack {
            Canvas { context, size in
                let spacing: CGFloat = 30 * scale
                let isDark = model.appSettings.isDarkMode
                let bg = isDark ? Color.black : Color.white
                let fg = isDark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2)

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

                        if model.currentTool == .fill {
                            guard !didFill else { return }
                            didFill = true
                            let cp = CGPoint(
                                x: (value.location.x - offset.width) / scale,
                                y: (value.location.y - offset.height) / scale
                            )
                            model.performFill(at: cp)
                            return
                        }

                        if model.currentTool == .select {
                            let cp = CGPoint(
                                x: (value.location.x - offset.width) / scale,
                                y: (value.location.y - offset.height) / scale
                            )
                            if model.isMoving {
                                let offset = CGSize(width: cp.x - model.lastMovePoint.x, height: cp.y - model.lastMovePoint.y)
                                model.moveSelected(by: offset)
                                model.lastMovePoint = cp
                            } else if !model.selectedStrokeIds.isEmpty || !model.selectedFillIds.isEmpty {
                                model.beginMove(at: cp)
                            } else if model.selectionLasso.isEmpty {
                                model.beginLasso(at: cp)
                            } else {
                                model.addLassoPoint(cp)
                            }
                            return
                        }

                        let cp = CGPoint(
                            x: (value.location.x - offset.width) / scale,
                            y: (value.location.y - offset.height) / scale
                        )
                        if model.currentStroke == nil {
                            model.beginStroke(at: cp, isEraser: model.currentTool == .eraser)
                        } else {
                            model.addPoint(cp)
                        }
                        pointCount = model.currentStroke?.points.count ?? 0
                    }
                    .onEnded { _ in
                        if model.currentTool == .fill {
                            didFill = false
                            return
                        }
                        if model.currentTool == .select {
                            if model.isMoving { model.commitMove() }
                            else { model.endLasso() }
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
                case "1", "2", "3", "4", "5", "6", "7", "8":
                    if let c = char, let digit = Int(c) {
                        let idx = digit - 1
                        switch model.currentTool {
                        case .pen where idx < model.penSettings.presets.count:
                            model.penSettings.color = model.penSettings.presets[idx]
                        case .highlighter where idx < model.highlighterSettings.presets.count:
                            model.highlighterSettings.color = model.highlighterSettings.presets[idx]
                        case .fill where idx < model.fillSettings.presets.count:
                            model.fillSettings.color = model.fillSettings.presets[idx]
                        default: break
                        }
                    }
                default: break
                }

                if hasCmd && !hasShift && char == "z" { model.undo(); return nil }
                if hasCmd && hasShift && char == "z" { model.redo(); return nil }

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
        path.move(to: stroke.points[0].applying(transform))
        var prev = stroke.points[0]
        for i in 1..<stroke.points.count {
            let pt = stroke.points[i]
            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
            path.addQuadCurve(to: mid.applying(transform), control: prev.applying(transform))
            prev = pt
        }
        path.addLine(to: stroke.points.last!.applying(transform))
        return path
    }

    private func drawFill(_ region: FillRegion, in context: inout GraphicsContext, transform: CGAffineTransform) {
        let path = Path(region.cgPath).applying(transform)
        context.fill(path, with: .color(region.uiColor))
    }

    private func drawStroke(_ stroke: Stroke, in context: inout GraphicsContext, transform: CGAffineTransform) {
        guard stroke.points.count >= 2 else { return }

        var path = Path()
        path.move(to: stroke.points[0].applying(transform))
        var prev = stroke.points[0]
        for i in 1..<stroke.points.count {
            let pt = stroke.points[i]
            let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
            path.addQuadCurve(to: mid.applying(transform), control: prev.applying(transform))
            prev = pt
        }
        path.addLine(to: stroke.points.last!.applying(transform))

        if stroke.isEraser {
            context.blendMode = .clear
            context.stroke(path, with: .color(.white),
                          style: StrokeStyle(lineWidth: model.eraserSettings.size, lineCap: .round, lineJoin: .round))
            context.blendMode = .normal
        } else {
            context.stroke(path, with: .color(stroke.uiColor),
                          style: StrokeStyle(lineWidth: stroke.lineWidth * scale,
                                           lineCap: .round, lineJoin: .round))
        }
    }
}

#endif
