import SwiftUI

struct ToolSettingsView: View {
    @Bindable var model: DrawingModel
    let tool: Tool

    var body: some View {
        HStack(spacing: 8) {
            switch tool {
            case .pen: penSettings
            case .sharpie: sharpieSettings
            case .fill: fillSettings
            case .shape: shapeSettings
            case .text: textSettings
            case .eraser: eraserSettings
            case .select: EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlassCapsule()
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        .fixedSize()
    }

    private func squarePresetRow(presets: Binding<[Color]>, selected: Binding<Color>, selectedIndex: Binding<Int>, lastTapIndex: Binding<Int?>) -> some View {
        HStack(spacing: 4) {
            ForEach(presets.wrappedValue.indices, id: \.self) { i in
                let color = presets.wrappedValue[i]
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            i == selectedIndex.wrappedValue ?
                            RoundedRectangle(cornerRadius: 4).stroke(Color.primary, lineWidth: 1.5) : nil
                        )
                        .shadow(color: .black.opacity(0.1), radius: 0.5)
                        .onTapGesture {
                            if lastTapIndex.wrappedValue == i {
                                lastTapIndex.wrappedValue = nil
                                colorPickerIndex = i
                                showColorPicker = true
                            } else {
                                lastTapIndex.wrappedValue = i
                                selected.wrappedValue = color
                                selectedIndex.wrappedValue = i
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    if lastTapIndex.wrappedValue == i {
                                        lastTapIndex.wrappedValue = nil
                                    }
                                }
                            }
                        }
                        .pointingHand()
                }
            }
        }
        .sheet(isPresented: $showColorPicker) {
            if let idx = colorPickerIndex, presets.wrappedValue.indices.contains(idx) {
                ColorPickerView(currentColor: presets.wrappedValue[idx]) { newColor in
                    if presets.wrappedValue.indices.contains(idx) {
                        presets.wrappedValue[idx] = newColor
                        if selectedIndex.wrappedValue == idx {
                            selected.wrappedValue = newColor
                        }
                    }
                }
            }
        }
    }

    @State private var colorPickerIndex: Int?
    @State private var showColorPicker: Bool = false

    private struct ColorPickerView: View {
        let currentColor: Color
        let onSelect: (Color) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var color: Color = .black

        var body: some View {
            VStack(spacing: 20) {
                ColorPicker("Choose color", selection: $color)
                    .labelsHidden()
                    .padding()
                Button("Done") {
                    onSelect(color)
                    dismiss()
                }
                .liquidGlassProminentButton()
            }
            .padding()
            .frame(width: 300, height: 400)
            .onAppear { color = currentColor }
        }
    }

    @State private var lastPenTapIndex: Int?
    @State private var lastSharpieTapIndex: Int?
    @State private var lastFillTapIndex: Int?
    @State private var lastShapeTapIndex: Int?
    @State private var lastTextTapIndex: Int?

    // MARK: - Pen

    private var penSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(presets: model.appSettings.isDarkMode ? $model.penSettings.darkPresets : $model.penSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.penSettings.darkColor : $model.penSettings.lightColor,
                           selectedIndex: $model.penPresetIndex,
                           lastTapIndex: $lastPenTapIndex)

            // Width picker: dots of varying size (2–5pt)
            HStack(spacing: 4) {
                ForEach(model.penSettings.widthOptions, id: \.self) { w in
                    Button(action: { model.penSettings.thickness = w }) {
                        Circle()
                            .fill(model.penSettings.thickness == w ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: 4 + w * 2, height: 4 + w * 2)
                            .overlay(
                                model.penSettings.thickness == w ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .pencilHoverEffect()
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }
        }
    }

    // MARK: - Sharpie

    private var sharpieSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(presets: model.appSettings.isDarkMode ? $model.sharpieSettings.darkPresets : $model.sharpieSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.sharpieSettings.darkColor : $model.sharpieSettings.lightColor,
                           selectedIndex: $model.sharpiePresetIndex,
                           lastTapIndex: $lastSharpieTapIndex)

            // Width picker: dots of varying size (4–10pt)
            HStack(spacing: 4) {
                ForEach(model.sharpieSettings.widthOptions, id: \.self) { w in
                    Button(action: { model.sharpieSettings.thickness = w }) {
                        Circle()
                            .fill(model.sharpieSettings.thickness == w ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: 4 + w * 2, height: 4 + w * 2)
                            .overlay(
                                model.sharpieSettings.thickness == w ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .pencilHoverEffect()
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }
        }
    }

    // MARK: - Fill

    private var fillSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(
                presets: model.appSettings.isDarkMode ? $model.fillSettings.darkPresets : $model.fillSettings.lightPresets,
                selected: model.appSettings.isDarkMode ? $model.fillSettings.darkColor : $model.fillSettings.lightColor,
                selectedIndex: $model.fillPresetIndex,
                lastTapIndex: $lastFillTapIndex
            )

            Divider().frame(height: 24)

            // Single opacity swatch cycling 25% -> 50% -> 75% -> 100% -> 25%
            Button(action: cycleFillOpacity) {
                ZStack {
                    CheckerboardSwatch()
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.fillColor.opacity(model.fillSettings.opacity))
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .help("Opacity: \(Int((model.fillSettings.opacity * 100).rounded()))% (tap to cycle 25% / 50% / 75% / 100%)")
            .pointingHand()

            // Single icon-only cycle button for Gap Closing: Strict (0) -> Auto (2.5) -> Wide (5)
            Button(action: cycleFillGapTolerance) {
                Image(systemName: fillGapIcon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .help("Gap Closing: \(fillGapLabel) (tap to cycle Strict / Auto / Wide)")
            .pointingHand()

            // Icon-only toggle between Replace (default, no blending) and Blend
            Button(action: {
                model.fillSettings.overlapMode = model.fillSettings.overlapMode == .replace ? .blend : .replace
            }) {
                Image(systemName: model.fillSettings.overlapMode == .replace ? "square.filled.on.square" : "square.on.square")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(model.fillSettings.overlapMode == .blend ? Color.accentColor : Color.primary.opacity(0.08))
                    .foregroundColor(model.fillSettings.overlapMode == .blend ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .help(model.fillSettings.overlapMode == .replace
                  ? "Replace Mode: refilling replaces the existing color (tap to switch to Blend)"
                  : "Blend Mode: refilling layers colors together (tap to switch to Replace)")
            .pointingHand()
        }
    }

    private var fillGapLabel: String {
        if model.fillSettings.gapTolerance < 1.0 { return "Strict" }
        if model.fillSettings.gapTolerance < 4.0 { return "Auto" }
        return "Wide"
    }

    private var fillGapIcon: String {
        if model.fillSettings.gapTolerance < 1.0 { return "lock.fill" }
        if model.fillSettings.gapTolerance < 4.0 { return "wand.and.stars" }
        return "arrow.left.and.right"
    }

    private var eraseTargetIcon: String {
        switch model.eraserSettings.eraseTarget {
        case .all: return "square.stack.3d.up"
        case .pen: return "pencil.tip"
        case .sharpie: return "highlighter"
        case .fill: return "paint.bucket.classic"
        }
    }

    private func cycleEraseTarget() {
        let all = EraseTarget.allCases
        if let idx = all.firstIndex(of: model.eraserSettings.eraseTarget) {
            model.eraserSettings.eraseTarget = all[(idx + 1) % all.count]
        } else {
            model.eraserSettings.eraseTarget = .all
        }
    }

    private func cycleFillOpacity() {
        let options = model.fillSettings.opacityOptions
        guard !options.isEmpty else { return }
        if let idx = options.firstIndex(where: { abs($0 - model.fillSettings.opacity) < 0.01 }) {
            model.fillSettings.opacity = options[(idx + 1) % options.count]
        } else {
            model.fillSettings.opacity = options[0]
        }
    }

    private func cycleFillGapTolerance() {
        if model.fillSettings.gapTolerance < 1.0 {
            model.fillSettings.gapTolerance = 2.5
        } else if model.fillSettings.gapTolerance < 4.0 {
            model.fillSettings.gapTolerance = 5.0
        } else {
            model.fillSettings.gapTolerance = 0
        }
    }

    // MARK: - Shape

    private var shapeSettings: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(ShapeKind.allCases) { kind in
                    Button(action: { model.shapeSettings.kind = kind }) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(model.shapeSettings.kind == kind ? Color.accentColor : Color.clear)
                            .foregroundColor(model.shapeSettings.kind == kind ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                            .pencilHoverEffect()
                    }
                    .buttonStyle(.plain)
                    .help(kind.title)
                    .pointingHand()
                }
            }

            Divider().frame(height: 24)

            squarePresetRow(
                presets: model.appSettings.isDarkMode ? $model.shapeSettings.darkPresets : $model.shapeSettings.lightPresets,
                selected: model.appSettings.isDarkMode ? $model.shapeSettings.darkColor : $model.shapeSettings.lightColor,
                selectedIndex: $model.shapePresetIndex,
                lastTapIndex: $lastShapeTapIndex
            )

            Divider().frame(height: 24)

            HStack(spacing: 4) {
                ForEach(model.shapeSettings.widthOptions, id: \.self) { w in
                    Button(action: { model.shapeSettings.lineWidth = w }) {
                        Circle()
                            .fill(model.shapeSettings.lineWidth == w ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: 4 + w * 2, height: 4 + w * 2)
                            .overlay(
                                model.shapeSettings.lineWidth == w ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .pencilHoverEffect()
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }

            if !model.shapeSettings.kind.isLineLike {
                Divider().frame(height: 24)

                Button(action: { model.shapeSettings.isFilled.toggle() }) {
                    Image(systemName: model.shapeSettings.isFilled ? "square.fill" : "square")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background(model.shapeSettings.isFilled ? Color.accentColor : Color.primary.opacity(0.08))
                        .foregroundColor(model.shapeSettings.isFilled ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .pencilHoverEffect()
                }
                .buttonStyle(.plain)
                .help(model.shapeSettings.isFilled ? "Filled Shape (tap for Outline Only)" : "Outline Only (tap for Translucent Fill)")
                .pointingHand()
            }
        }
    }

    // MARK: - Text

    private var textSettings: some View {
        let labels = ["S", "M", "L", "XL"]
        return HStack(spacing: 12) {
            squarePresetRow(
                presets: model.appSettings.isDarkMode ? $model.textSettings.darkPresets : $model.textSettings.lightPresets,
                selected: model.appSettings.isDarkMode ? $model.textSettings.darkColor : $model.textSettings.lightColor,
                selectedIndex: $model.textPresetIndex,
                lastTapIndex: $lastTextTapIndex
            )

            Divider().frame(height: 24)

            HStack(spacing: 4) {
                ForEach(Array(model.textSettings.sizeOptions.enumerated()), id: \.offset) { idx, sz in
                    let isSelected = abs(model.textSettings.fontSize - sz) < 0.5
                    Button(action: { model.setTextFontSize(sz) }) {
                        Text(idx < labels.count ? labels[idx] : "\(Int(sz))")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 24)
                            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                            .pencilHoverEffect()
                    }
                    .buttonStyle(.plain)
                    .help("Font Size: \(Int(sz))pt")
                    .pointingHand()
                }
            }

            Divider().frame(height: 24)

            Button(action: { model.toggleTextBold() }) {
                Image(systemName: "bold")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 24)
                    .background(model.textSettings.isBold ? Color.accentColor : Color.primary.opacity(0.08))
                    .foregroundColor(model.textSettings.isBold ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .help("Toggle Bold")
            .pointingHand()
        }
    }

    // MARK: - Eraser

    private var eraserSettings: some View {
        HStack(spacing: 12) {
            // Mode icons
            HStack(spacing: 4) {
                ForEach(EraserMode.allCases, id: \.self) { mode in
                    Button(action: { model.eraserSettings.mode = mode }) {
                        Image(systemName: mode == .partial ? "circle.dotted" : "circle.fill")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(model.eraserSettings.mode == mode ? Color.accentColor : Color.clear)
                            .foregroundColor(model.eraserSettings.mode == mode ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                            .pencilHoverEffect()
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }

            Divider().frame(height: 24)

            // Single icon-only cycle button for Erase Target: All -> Pen -> Sharpie -> Fill
            Button(action: cycleEraseTarget) {
                Image(systemName: eraseTargetIcon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(model.eraserSettings.eraseTarget == .all ? Color.primary.opacity(0.08) : Color.accentColor)
                    .foregroundColor(model.eraserSettings.eraseTarget == .all ? .primary : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .help("Erase Target: \(model.eraserSettings.eraseTarget.rawValue) (tap to cycle All / Pen / Sharpie / Fill)")
            .pointingHand()

            Divider().frame(height: 24)

            // Size dots
            HStack(spacing: 6) {
                ForEach([10, 20, 30, 40, 50, 60], id: \.self) { s in
                    Button(action: { model.eraserSettings.size = CGFloat(s) }) {
                        Circle()
                            .fill(Int(model.eraserSettings.size) == s ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: CGFloat(s) * 0.4 + 4, height: CGFloat(s) * 0.4 + 4)
                            .overlay(
                                Int(model.eraserSettings.size) == s ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }
        }
    }
}

private struct CheckerboardSwatch: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 5
            let light = Color.white
            let dark = Color.gray.opacity(0.32)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let color = (row + col).isMultiple(of: 2) ? light : dark
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(color))
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}
