import SwiftUI

struct ContentView: View {
    @StateObject private var model = DrawingModel()

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

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: { model.selectTool(.pen) }) {
                Image(systemName: "pencil.tip")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(model.currentTool == .pen ? Color.accentColor : .clear)
                    .foregroundColor(model.currentTool == .pen ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button(action: { model.selectTool(.eraser) }) {
                Image(systemName: "eraser")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(model.currentTool == .eraser ? Color.accentColor : .clear)
                    .foregroundColor(model.currentTool == .eraser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
                .frame(height: 24)

            Button(action: { model.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .disabled(model.strokes.isEmpty)

            Button(action: { model.clear() }) {
                Image(systemName: "trash")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .disabled(model.strokes.isEmpty)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top)
        .shadow(radius: 4)
    }
}
