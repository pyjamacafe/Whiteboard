import SwiftUI

@main
struct DoodlesApp: App {
    @State private var model = DrawingModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onChange(of: model.currentBoardId) { _, _ in setTitle() }
                .onChange(of: model.showWelcome) { _, _ in setTitle() }
                .onChange(of: model.welcomeFolderName) { _, _ in setTitle() }
                .onAppear {
                    setTitle()
                }
                #if os(macOS)
                .background(WindowAccessor(model: model))
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.flushAutoSave(drainBackgroundQueue: true)
                }
                #endif
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
                Button("Sharpie") { model.selectTool(.sharpie) }
                    .keyboardShortcut("s", modifiers: [])
                Button("Eraser") { model.selectTool(.eraser) }
                    .keyboardShortcut("e", modifiers: [])
                Button("Selection") { model.selectTool(.select) }
                    .keyboardShortcut("s", modifiers: [.shift])
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
        if model.showWelcome {
            if let folder = model.welcomeFolderName {
                t = "Doodles | \(folder)"
            } else {
                t = "Doodles | All Boards"
            }
        } else if let id = model.currentBoardId,
                let board = model.boards.first(where: { $0.id == id }) {
            t = "Doodles | \(board.name)"
        } else { t = "Doodles" }
        NSApp.windows.first?.title = t
        #endif
    }
}


#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    let model: DrawingModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.delegate = context.coordinator
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    class Coordinator: NSObject, NSWindowDelegate {
        let model: DrawingModel
        init(model: DrawingModel) { self.model = model }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            model.flushAutoSave()
            if !model.showWelcome { model.closeBoard(); return false }
            return true
        }
    }
}
#endif
