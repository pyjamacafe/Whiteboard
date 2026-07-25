import SwiftUI

struct RadialMenuView: View {
    @ObservedObject var model: DrawingModel
    let center: CGPoint
    let onDismiss: () -> Void
    let onSettings: (() -> Void)?
    var onExport: ((_ format: String) -> Void)?
    var onOpen: (() -> Void)?
    var onHelp: (() -> Void)?
    @State private var settingsTool: Tool?
    @State private var lastTapTime: Date = .distantPast
    @State private var showSettingsMenu = false

    private let tools: [(Tool, String)] = [
        (.pen, "pencil.tip"),
        (.eraser, "eraser"),
        (.highlighter, "highlighter"),
        (.fill, "drop.fill"),
        (.select, "cursorarrow.click"),
        (.laser, "laser.burst"),
    ]

    var body: some View {
        GeometryReader { geo in
            let isDark = model.appSettings.isDarkMode
            let ribbonW: CGFloat = CGFloat(tools.count) * 54 + 60
            let ribbonH: CGFloat = 56
            let posX = max(ribbonW / 2, min(center.x, geo.size.width - ribbonW / 2))
            let posY = max(ribbonH + 10, min(center.y - 30, geo.size.height - ribbonH - 10))

            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }

                VStack(spacing: 6) {
                    if let tool = settingsTool, tool != .select {
                        ToolSettingsView(model: model, tool: tool)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    HStack(spacing: 8) {
                        ForEach(Array(tools.enumerated()), id: \.offset) { idx, item in
                            toolButton(item: item, isDark: isDark)
                        }

                        // Settings gear — shows a popover menu
                        Button(action: { showSettingsMenu.toggle() }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                .foregroundColor(isDark ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSettingsMenu, arrowEdge: .bottom) {
                            settingsPopoverContent(isDark: isDark)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isDark ? Color(red: 44/255, green: 44/255, blue: 46/255) : Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(isDark ? 0.3 : 0.15), radius: 12, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                }
                .position(x: posX, y: posY)
            }
        }
        .animation(.easeOut(duration: 0.2), value: settingsTool)
    }

    private func settingsPopoverContent(isDark: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    settingsButton("Undo", "arrow.uturn.backward") { model.undo() }
                        .disabled(!model.canUndo)
                    settingsButton("Redo", "arrow.uturn.forward") { model.redo() }
                        .disabled(!model.canRedo)
                    settingsButton("Delete Selected", "trash") { model.deleteSelected() }
                        .disabled(model.strokes.isEmpty && model.fillRegions.isEmpty)
                    settingsButton("Center", "viewfinder") { model.needsRecenter = true }
                    settingsButton("Home", "house") { model.showWelcome = true }
                }

                Divider()

                Group {
                    Toggle(isOn: $model.appSettings.isDarkMode) {
                        Label(model.appSettings.isDarkMode ? "Dark Mode" : "Light Mode", systemImage: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.callout)
                    }.toggleStyle(.switch)

                    Picker("Background", selection: $model.appSettings.canvasBackground) {
                        ForEach(CanvasBackground.allCases, id: \.self) { bg in
                            Text(bg.rawValue.capitalized).tag(bg)
                        }
                    }
                }

                Divider()

                Group {
                    settingsButton("Save Defaults", "bookmark") { model.saveDefaults() }
                    if model.hasDefaults {
                        settingsButton("Restore Defaults", "bookmark.fill") { model.loadDefaults() }
                        settingsButton("Reset to Factory", "arrow.counterclockwise") { model.resetToFactory() }
                    }
                }

                Divider()

                Group {
                    settingsButton("Save .wb", "square.and.arrow.down") { onExport?("wb") }
                    settingsButton("Export PNG", "photo") { onExport?("png") }
                    settingsButton("Export PDF", "doc.richtext") { onExport?("pdf") }
                    settingsButton("Open…", "folder") { onOpen?(); onDismiss() }
                }

                Divider()

                settingsButton("Help", "questionmark.circle") { onHelp?(); onDismiss() }
            }
            .padding(12)
        }
        .frame(width: 260, height: 400)
        .foregroundColor(isDark ? .white : .primary)
        .background(isDark ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color.primary.opacity(0.06))
    }

    private func settingsButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); onDismiss() }) {
            Label(title, systemImage: icon)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func toolButton(item: (Tool, String), isDark: Bool) -> some View {
        let isSelected = model.currentTool == item.0
        return Button(action: {}) {
            Image(systemName: item.1)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(isSelected ? Color.accentColor : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                .foregroundColor(isSelected ? .white : (isDark ? .white : .primary))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            TapGesture().onEnded {
                let now = Date()
                if now.timeIntervalSince(lastTapTime) < 0.3 {
                    withAnimation { settingsTool = settingsTool == item.0 ? nil : item.0 }
                    lastTapTime = .distantPast
                } else {
                    lastTapTime = now
                    model.selectTool(item.0)
                }
            }
        )
    }
}
