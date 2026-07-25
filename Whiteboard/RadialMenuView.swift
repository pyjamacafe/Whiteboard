import SwiftUI

struct RadialMenuView: View {
    @ObservedObject var model: DrawingModel
    let center: CGPoint
    let onDismiss: () -> Void
    let onSettings: (() -> Void)?
    var onExport: ((_ format: String) -> Void)?
    var onOpen: (() -> Void)?
    var onHelp: (() -> Void)?

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
                    HStack(spacing: 8) {
                        ForEach(Array(tools.enumerated()), id: \.offset) { idx, item in
                            toolButton(item: item, isDark: isDark)
                        }

                        // Settings gear — opens the settings sidebar
                        Button(action: { onSettings?() }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                .foregroundColor(isDark ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
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
        .onTapGesture { model.selectTool(item.0) }
    }
}
