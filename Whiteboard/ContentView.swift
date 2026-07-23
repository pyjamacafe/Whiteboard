import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject var model: DrawingModel
    @State private var hoveredTool: String?
    @State private var settingsTool: Tool?
    @State private var lastTapTime: Date = .distantPast
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack {
            CanvasView(model: model, onBeginDraw: { settingsTool = nil; showSettings = false })
                .ignoresSafeArea()

            VStack {
                if model.isToolbarVisible { toolbar }
                if model.isToolbarVisible, let tool = settingsTool, tool != .select {
                    ToolSettingsView(model: model, tool: tool)
                        .padding(.top, 4)
                        .onTapGesture { }
                }
                if model.isToolbarVisible && showSettings {
                    SettingsPopupView(model: model)
                        .padding(.top, 4)
                        .onTapGesture { }
                }
                Spacer()
            }
        }
        .onTapGesture { settingsTool = nil }
        .onChange(of: model.pendingAction) { action in
            guard let action = action else { return }
            showSettings = true
            model.pendingAction = nil
        }
        .background(
            Button("") { model.isToolbarVisible.toggle() }
                .keyboardShortcut(.tab, modifiers: [])
                .hidden()
                .frame(width: 0, height: 0)
        )
        .background(
            Button("") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
        )
        .background(
            Button("") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .hidden()
                .frame(width: 0, height: 0)
        )
        .background(
            Button("") { model.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .hidden()
                .frame(width: 0, height: 0)
        )
        .background(
            Button("") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
        )
        .background(
            Button("") { showSettings = true }
                .keyboardShortcut("o", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
        )
    }

    private func toolColor(_ tool: Tool) -> Color {
        switch tool {
        case .pen: return model.penColor
        case .highlighter: return model.hlColor
        case .fill: return model.fillColor
        default: return Color.accentColor
        }
    }

    private func contrastingColor(for color: Color) -> Color {
        #if os(iOS)
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black : .white
        #else
        let nsColor = NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard let converted = nsColor.usingColorSpace(.sRGB) else { return .white }
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black : .white
        #endif
    }

    private func toolButton(systemName: String, tool: Tool) -> some View {
        let isSelected = model.currentTool == tool
        let isHovered = hoveredTool == systemName
        let bg: Color = isSelected ? toolColor(tool) : isHovered ? Color.primary.opacity(0.12) : .clear
        let fg: Color = isSelected ? contrastingColor(for: bg) : isHovered ? .primary : .secondary
        return Button(action: {}) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(bg)
                .foregroundColor(fg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .onHover { hovering in
            hoveredTool = hovering ? systemName : nil
        }
        .highPriorityGesture(
            TapGesture().onEnded {
                let now = Date()
                if now.timeIntervalSince(lastTapTime) < 0.3 {
                    settingsTool = settingsTool == tool ? nil : tool
                    lastTapTime = .distantPast
                } else {
                    lastTapTime = now
                    model.selectTool(tool)
                    if settingsTool != nil { settingsTool = tool }
                }
            }
        )
    }

    private func actionButton(systemName: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        let isHovered = hoveredTool == systemName
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(isHovered ? Color.primary.opacity(0.12) : .clear)
                .foregroundColor(isHovered ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(disabled)
        .onHover { hovering in
            hoveredTool = hovering ? systemName : nil
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            toolButton(systemName: "pencil.tip", tool: .pen)
            toolButton(systemName: "eraser", tool: .eraser)
            toolButton(systemName: "drop.fill", tool: .fill)
            toolButton(systemName: "highlighter", tool: .highlighter)
            toolButton(systemName: "cursorarrow.click", tool: .select)

            Divider()
                .frame(height: 24)

            actionButton(systemName: "arrow.uturn.backward", action: { model.undo() }, disabled: !model.canUndo)
            actionButton(systemName: "arrow.uturn.forward", action: { model.redo() }, disabled: !model.canRedo)
            actionButton(systemName: "trash", action: { model.deleteSelected() }, disabled: model.strokes.isEmpty && model.fillRegions.isEmpty)
            actionButton(systemName: "gearshape", action: { showSettings.toggle() }, disabled: false)
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
        .padding(.top, 12)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
    }
}
