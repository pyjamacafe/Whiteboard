import SwiftUI

struct ToolSettingsView: View {
    @ObservedObject var model: DrawingModel
    let tool: Tool

    var body: some View {
        Group {
            switch tool {
            case .pen: penSettings
            case .eraser: eraserSettings
            case .fill: fillSettings
            case .highlighter: highlighterSettings
            case .laser: laserSettings
            case .select: EmptyView()
            }
        }
        .padding(12)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .frame(maxWidth: 280)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Preset row

    private func presetRow(presets: Binding<[Color]>, selected: Binding<Color>, selectedIndex: Binding<Int>, lastTapIndex: Binding<Int?>) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                let color = presets.wrappedValue[i]
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            color == selected.wrappedValue ?
                            Circle().stroke(Color.primary, lineWidth: 2) : nil
                        )
                        .shadow(color: .black.opacity(0.1), radius: 1)
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
        VStack(alignment: .leading, spacing: 10) {
            presetRow(presets: model.appSettings.isDarkMode ? $model.penSettings.darkPresets : $model.penSettings.lightPresets,
                     selected: model.appSettings.isDarkMode ? $model.penSettings.darkColor : $model.penSettings.lightColor,
                     selectedIndex: $model.penPresetIndex,
                     lastTapIndex: $lastPenTapIndex)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Thickness").font(.caption)
                    Spacer()
                    Text("\(model.penSettings.thickness, specifier: "%.0f")pt").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.penSettings.thickness, in: 1...12, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Smoothness").font(.caption)
                    Spacer()
                    Text(smoothnessLabel).font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.penSettings.smoothness, in: 1...9, step: 1)
            }
        }
    }

    private var smoothnessLabel: String {
        let v = Int(model.penSettings.smoothness)
        return v == 1 ? "Off" : "Low \(v - 1)/8"
    }

    // MARK: - Fill

    private var fillSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetRow(presets: model.appSettings.isDarkMode ? $model.fillSettings.darkPresets : $model.fillSettings.lightPresets,
                     selected: model.appSettings.isDarkMode ? $model.fillSettings.darkColor : $model.fillSettings.lightColor,
                     selectedIndex: $model.fillPresetIndex,
                     lastTapIndex: $lastFillTapIndex)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity").font(.caption)
                    Spacer()
                    Text("\(Int(model.fillSettings.opacity * 100))%").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.fillSettings.opacity, in: 0.1...1.0, step: 0.05)
            }
        }
    }

    // MARK: - Highlighter

    private var highlighterSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetRow(presets: model.appSettings.isDarkMode ? $model.highlighterSettings.darkPresets : $model.highlighterSettings.lightPresets,
                     selected: model.appSettings.isDarkMode ? $model.highlighterSettings.darkColor : $model.highlighterSettings.lightColor,
                     selectedIndex: $model.hlPresetIndex,
                     lastTapIndex: $lastHighlighterTapIndex)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Thickness").font(.caption)
                    Spacer()
                    Text("\(model.highlighterSettings.thickness, specifier: "%.0f")pt").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.highlighterSettings.thickness, in: 5...30, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity").font(.caption)
                    Spacer()
                    Text("\(Int(model.highlighterSettings.opacity * 100))%").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.highlighterSettings.opacity, in: 0.1...1.0, step: 0.05)
            }
        }
    }

    // MARK: - Eraser

    private var eraserSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $model.eraserSettings.mode) {
                ForEach(EraserMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size").font(.caption)
                    Spacer()
                    Text("\(model.eraserSettings.size, specifier: "%.0f")pt").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.eraserSettings.size, in: 5...60, step: 1)
            }
        }
    }

    // MARK: - Laser

    private var laserSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $model.laserSettings.mode) {
                ForEach(LaserMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if model.laserSettings.mode == .tail {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tail Fade").font(.caption)
                        Spacer()
                        Text("\(model.laserSettings.tailFade, specifier: "%.1f")s").font(.caption).foregroundColor(.secondary)
                    }
                    Slider(value: $model.laserSettings.tailFade, in: 0.3...5.0, step: 0.1)
                }
            }

            ColorPicker("Color", selection: $model.laserSettings.color)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size").font(.caption)
                    Spacer()
                    Text("\(model.laserSettings.size, specifier: "%.0f")pt").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: $model.laserSettings.size, in: 2...20, step: 1)
            }
        }
    }
}
