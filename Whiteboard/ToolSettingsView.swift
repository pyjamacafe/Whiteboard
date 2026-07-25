import SwiftUI

struct ToolSettingsView: View {
    @ObservedObject var model: DrawingModel
    let tool: Tool

    var body: some View {
        HStack(spacing: 8) {
            switch tool {
            case .pen: penSettings
            case .eraser: eraserSettings
            case .fill: fillSettings
            case .highlighter: highlighterSettings
            case .laser: laserSettings
            case .select: EmptyView()
            }
        }
        .padding(5)
        .background(model.appSettings.isDarkMode ? Color(red: 44/255, green: 44/255, blue: 46/255) : Color(.sRGB, red: 0.97, green: 0.97, blue: 0.97, opacity: 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        .fixedSize()
    }

    private func squarePresetRow(presets: Binding<[Color]>, selected: Binding<Color>, selectedIndex: Binding<Int>, lastTapIndex: Binding<Int?>) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let color = presets.wrappedValue[i]
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            color == selected.wrappedValue ?
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
                }
            }
        }
        .sheet(isPresented: $showColorPicker) {
            if let idx = colorPickerIndex {
                ColorPickerView(currentColor: presets.wrappedValue[idx]) { newColor in
                    presets.wrappedValue[idx] = newColor
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
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(width: 300, height: 400)
            .onAppear { color = currentColor }
        }
    }

    @State private var lastPenTapIndex: Int?
    @State private var lastFillTapIndex: Int?
    @State private var lastHighlighterTapIndex: Int?

    // MARK: - Pen

    private var penSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(presets: model.appSettings.isDarkMode ? $model.penSettings.darkPresets : $model.penSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.penSettings.darkColor : $model.penSettings.lightColor,
                           selectedIndex: $model.penPresetIndex,
                           lastTapIndex: $lastPenTapIndex)

            // Width picker: dots of varying size (2–5pt)
            HStack(spacing: 8) {
                ForEach(model.penSettings.widthOptions, id: \.self) { w in
                    Button(action: { model.penSettings.thickness = w }) {
                        Circle()
                            .fill(model.penSettings.thickness == w ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: 4 + w * 2, height: 4 + w * 2)
                            .overlay(
                                model.penSettings.thickness == w ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Fill

    private var fillSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(presets: model.appSettings.isDarkMode ? $model.fillSettings.darkPresets : $model.fillSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.fillSettings.darkColor : $model.fillSettings.lightColor,
                           selectedIndex: $model.fillPresetIndex,
                           lastTapIndex: $lastFillTapIndex)

            // Opacity circles showing the selected fill color at each level
            HStack(spacing: 6) {
                ForEach(model.fillSettings.opacityOptions, id: \.self) { op in
                    Button(action: { model.fillSettings.opacity = op }) {
                        Circle()
                            .fill(model.fillColor.opacity(op))
                            .frame(width: 18, height: 18)
                            .overlay(
                                model.fillSettings.opacity == op ?
                                Circle().stroke(Color.primary, lineWidth: 1.5) : nil
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Highlighter

    private var highlighterSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(presets: model.appSettings.isDarkMode ? $model.highlighterSettings.darkPresets : $model.highlighterSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.highlighterSettings.darkColor : $model.highlighterSettings.lightColor,
                           selectedIndex: $model.hlPresetIndex,
                           lastTapIndex: $lastHighlighterTapIndex)

            // Thickness dots
            HStack(spacing: 6) {
                ForEach(model.highlighterSettings.thicknessOptions, id: \.self) { t in
                    Button(action: { model.highlighterSettings.thickness = t }) {
                        Circle()
                            .fill(model.highlighterSettings.thickness == t ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: t * 0.5 + 4, height: t * 0.5 + 4)
                            .overlay(
                                model.highlighterSettings.thickness == t ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    }
                    .buttonStyle(.plain)
                }
            }

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
                }
            }
        }
    }

    // MARK: - Laser

    private var laserSettings: some View {
        HStack(spacing: 12) {
            Button(action: { model.laserSettings.retainStrokes.toggle() }) {
                Image(systemName: model.laserSettings.retainStrokes ? "pin.fill" : "pin")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .background(model.laserSettings.retainStrokes ? Color.accentColor : Color.clear)
                    .foregroundColor(model.laserSettings.retainStrokes ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Size dots
            HStack(spacing: 6) {
                ForEach([1.5, 2.5, 4, 6, 8], id: \.self) { s in
                    Button(action: { model.laserSettings.size = s }) {
                        Circle()
                            .fill(abs(model.laserSettings.size - s) < 0.01 ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: s * 1.5 + 4, height: s * 1.5 + 4)
                            .overlay(
                                abs(model.laserSettings.size - s) < 0.01 ?
                                Circle().stroke(Color.primary, lineWidth: 1) : nil
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
