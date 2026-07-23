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
                .frame(width: 32, height: 32)
                .background(
                    isSelected ? Color.accentColor :
                    isHovered ? Color.primary.opacity(0.12) : .clear
                )
                .foregroundColor(
                    isSelected ? .white :
                    isHovered ? .primary : .secondary
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
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
            toolButton(systemName: "cursorarrow.click", tool: .select)

            Divider()
                .frame(height: 24)

            actionButton(systemName: "arrow.uturn.backward", action: { model.undo() }, disabled: !model.canUndo)
            actionButton(systemName: "arrow.uturn.forward", action: { model.redo() }, disabled: !model.canRedo)
            actionButton(systemName: "trash", action: { model.deleteSelected() }, disabled: model.strokes.isEmpty && model.fillRegions.isEmpty)
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
