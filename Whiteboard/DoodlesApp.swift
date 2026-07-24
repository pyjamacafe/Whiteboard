import SwiftUI

@main
struct DoodlesApp: App {
    @StateObject private var model = DrawingModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onReceive(model.$currentBoardId) { _ in setTitle() }
                .onReceive(model.$showWelcome) { _ in setTitle() }
                .onAppear { setTitle() }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Open…") { model.openCmd() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Close Doodle") { model.closeBoard() }
                    .keyboardShortcut("w", modifiers: .command)
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

    private func setTitle() {
        #if os(macOS)
        let t: String
        if model.showWelcome { t = "Doodles" }
        else if let id = model.currentBoardId,
                let board = model.boards.first(where: { $0.id == id }) {
            t = "Doodles | \(board.name)"
        } else { t = "Doodles" }
        NSApp.windows.first?.title = t
        #endif
    }
}
