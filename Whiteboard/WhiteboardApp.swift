import SwiftUI

@main
struct WhiteboardApp: App {
    @StateObject private var model = DrawingModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Open…") { model.openCmd() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Export PNG") { model.exportPNG() }
                Button("Export PDF") { model.exportPDF() }
            }
            CommandMenu("Tools") {
                Button("Pen") { model.selectTool(.pen) }
                    .keyboardShortcut("p", modifiers: [])
                Button("Highlighter") { model.selectTool(.highlighter) }
                    .keyboardShortcut("h", modifiers: [])
                Button("Fill") { model.selectTool(.fill) }
                    .keyboardShortcut("f", modifiers: [])
                Button("Eraser") { model.selectTool(.eraser) }
                    .keyboardShortcut("e", modifiers: [])
                Button("Selection") { model.selectTool(.select) }
                    .keyboardShortcut("s", modifiers: [])
                Divider()
                Button(model.isToolbarVisible ? "Hide Toolbar" : "Show Toolbar") {
                    model.isToolbarVisible.toggle()
                }
                .keyboardShortcut(.tab, modifiers: [])
            }
        }
    }
}
