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

    private func compactPresetRow(presets: Binding<[Color]>, selected: Binding<Color>, selectedIndex: Binding<Int>, lastTapIndex: Binding<Int?>) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let color = presets.wrappedValue[i]
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            color == selected.wrappedValue ?
                            Circle().stroke(Color.primary, lineWidth: 1.5) : nil
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
            compactPresetRow(presets: model.appSettings.isDarkMode ? $model.penSettings.darkPresets : $model.penSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.penSettings.darkColor : $model.penSettings.lightColor,
                           selectedIndex: $model.penPresetIndex,
                           lastTapIndex: $lastPenTapIndex)

            compactSlider(value: $model.penSettings.thickness, range: 1...12, label: "\(Int(model.penSettings.thickness))pt", width: 80)

            compactSlider(value: $model.penSettings.smoothness, range: 1...9, label: smoothnessLabel, width: 80)
        }
    }

    private var smoothnessLabel: String {
        let v = Int(model.penSettings.smoothness)
        return v == 1 ? "Off" : "S\(v - 1)"
    }

    // MARK: - Fill

    private var fillSettings: some View {
        HStack(spacing: 12) {
            compactPresetRow(presets: model.appSettings.isDarkMode ? $model.fillSettings.darkPresets : $model.fillSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.fillSettings.darkColor : $model.fillSettings.lightColor,
                           selectedIndex: $model.fillPresetIndex,
                           lastTapIndex: $lastFillTapIndex)

            compactSlider(value: $model.fillSettings.opacity, range: 0.1...1.0, label: "\(Int(model.fillSettings.opacity * 100))%", width: 80)
        }
    }

    // MARK: - Highlighter

    private var highlighterSettings: some View {
        HStack(spacing: 12) {
            compactPresetRow(presets: model.appSettings.isDarkMode ? $model.highlighterSettings.darkPresets : $model.highlighterSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.highlighterSettings.darkColor : $model.highlighterSettings.lightColor,
                           selectedIndex: $model.hlPresetIndex,
                           lastTapIndex: $lastHighlighterTapIndex)

            compactSlider(value: $model.highlighterSettings.thickness, range: 5...30, label: "\(Int(model.highlighterSettings.thickness))pt", width: 80)

            compactSlider(value: $model.highlighterSettings.opacity, range: 0.1...1.0, label: "\(Int(model.highlighterSettings.opacity * 100))%", width: 80)
        }
    }

    // MARK: - Eraser

    private var eraserSettings: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.eraserSettings.mode) {
                ForEach(EraserMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            compactSlider(value: $model.eraserSettings.size, range: 5...60, label: "\(Int(model.eraserSettings.size))pt", width: 80)
        }
    }

    // MARK: - Laser

    private var laserSettings: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.laserSettings.mode) {
                ForEach(LaserMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            if model.laserSettings.mode == .tail {
                compactSlider(value: $model.laserSettings.tailFade, range: 0.3...5.0, label: String(format: "%.1fs", model.laserSettings.tailFade), width: 80)
            }

            ColorPicker("", selection: $model.laserSettings.color)
                .labelsHidden()
                .frame(width: 30)

            compactSlider(value: $model.laserSettings.size, range: 2...20, label: "\(Int(model.laserSettings.size))pt", width: 80)
        }
    }

    // MARK: - Compact Slider

    private func compactSlider<V: BinaryFloatingPoint>(value: Binding<V>, range: ClosedRange<V>, label: String, width: CGFloat) -> some View where V.Stride: BinaryFloatingPoint, V: Sendable {
        HStack(spacing: 4) {
            Slider(value: value, in: range)
                .frame(width: width - 36)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
