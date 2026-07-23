import SwiftUI

struct ContentView: View {
    @StateObject private var model = DrawingModel()
    @State private var hoveredTool: String?

    var body: some View {
        ZStack {
            CanvasView(model: model)
                .ignoresSafeArea()

            VStack {
                toolbar
                Spacer()
            }
        }
    }

    private func toolButton(systemName: String, tool: Tool) -> some View {
        let isSelected = model.currentTool == tool
        let isHovered = hoveredTool == systemName
        return Button(action: { model.selectTool(tool) }) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(
                    isSelected ? Color.accentColor :
                    isHovered ? Color.primary.opacity(0.12) : .clear
                )
                .foregroundColor(
                    isSelected ? .white :
                    isHovered ? .primary : .secondary
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onHover { hovering in
            hoveredTool = hovering ? systemName : nil
        }
    }

    private func actionButton(systemName: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        let isHovered = hoveredTool == systemName
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 40, height: 40)
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
            toolButton(systemName: "paintbucket.fill", tool: .fill)

            Divider()
                .frame(height: 24)

            actionButton(systemName: "arrow.uturn.backward", action: { model.undo() }, disabled: model.strokes.isEmpty && model.fillRegions.isEmpty)
            actionButton(systemName: "trash", action: { model.clear() }, disabled: model.strokes.isEmpty && model.fillRegions.isEmpty)
        }
        .buttonStyle(.plain)
        .padding(2)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
        .padding(.top, 2)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
