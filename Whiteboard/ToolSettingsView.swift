import SwiftUI

extension Int: Identifiable {
    public var id: Int { self }
}

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

    private func presetRow(presets: Binding<[Color]>, selected: Binding<Color>, lastTapIndex: Binding<Int?>) -> some View {
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
                                // Double-tap → show color picker to change preset
                                lastTapIndex.wrappedValue = nil
                                showingColorPickerIndex = i
                            } else {
                                lastTapIndex.wrappedValue = i
                                selected.wrappedValue = color
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
        .sheet(item: $showingColorPickerIndex) { idx in
            ColorPickerView(currentColor: presets.wrappedValue[idx]) { newColor in
                presets.wrappedValue[idx] = newColor
            }
        }
    }

    @State private var showingColorPickerIndex: Int?

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
            presetRow(presets: $model.penSettings.presets, selected: $model.penSettings.color, lastTapIndex: $lastPenTapIndex)

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
                Slider(value: $model.penSettings.smoothness, in: 1...8, step: 1)
            }
        }
    }

    private var smoothnessLabel: String {
        switch Int(model.penSettings.smoothness) {
        case 1: return "Off"
        case 2...3: return "Low"
        case 4...5: return "Medium"
        case 6...7: return "High"
        default: return "Max"
        }
    }

    // MARK: - Fill

    private var fillSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetRow(presets: $model.fillSettings.presets, selected: $model.fillSettings.color, lastTapIndex: $lastFillTapIndex)

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
            presetRow(presets: $model.highlighterSettings.presets, selected: $model.highlighterSettings.color, lastTapIndex: $lastHighlighterTapIndex)

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
}
