import SwiftUI

struct ToolSettingsView: View {
    @Bindable var model: DrawingModel
    let tool: Tool

    var body: some View {
        HStack(spacing: 8) {
            switch tool {
            case .pen: penSettings
            case .sharpie: sharpieSettings
            case .eraser: eraserSettings
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
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(width: 300, height: 400)
            .onAppear { color = currentColor }
        }
    }

    @State private var lastPenTapIndex: Int?
    @State private var lastSharpieTapIndex: Int?

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

    // MARK: - Sharpie

    private var sharpieSettings: some View {
        HStack(spacing: 12) {
            squarePresetRow(presets: model.appSettings.isDarkMode ? $model.sharpieSettings.darkPresets : $model.sharpieSettings.lightPresets,
                           selected: model.appSettings.isDarkMode ? $model.sharpieSettings.darkColor : $model.sharpieSettings.lightColor,
                           selectedIndex: $model.sharpiePresetIndex,
                           lastTapIndex: $lastSharpieTapIndex)

            // Width picker: dots of varying size (4–10pt)
            HStack(spacing: 8) {
                ForEach(model.sharpieSettings.widthOptions, id: \.self) { w in
                    Button(action: { model.sharpieSettings.thickness = w }) {
                        Circle()
                            .fill(model.sharpieSettings.thickness == w ? Color.accentColor : Color.primary.opacity(0.4))
                            .frame(width: 4 + w * 2, height: 4 + w * 2)
                            .overlay(
                                model.sharpieSettings.thickness == w ?
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

            Divider().frame(height: 24)

            // Target picker: All / Pen / Sharpie
            HStack(spacing: 4) {
                ForEach(EraseTarget.allCases, id: \.self) { target in
                    Button(action: { model.eraserSettings.eraseTarget = target }) {
                        Text(target.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .background(model.eraserSettings.eraseTarget == target ? Color.accentColor : Color.clear)
                            .foregroundColor(model.eraserSettings.eraseTarget == target ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

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
                }
            }
        }
    }
}
