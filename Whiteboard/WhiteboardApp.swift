import SwiftUI

@main
struct WhiteboardApp: App {
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
                .frame(minWidth: 800, minHeight: 560)
                .background(WindowAccessor(model: model))
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.flushAutoSave(drainBackgroundQueue: true)
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified)
        #endif
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Tissue Box") { model.showAbout = true }
            }
            CommandGroup(after: .saveItem) {
                Button("Open…") { model.openCmd() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Close Tissue") { model.closeBoard() }
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
                Button("Fill") { model.selectTool(.fill) }
                    .keyboardShortcut("f", modifiers: [])
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
        // On the Welcome screen, NavigationSplitView manages the unified titlebar
        // via .navigationTitle / .navigationSubtitle.
        guard !model.showWelcome else { return }
        let t: String
        if let id = model.currentBoardId,
           let board = model.boards.first(where: { $0.id == id }) {
            t = "Tissue | \(board.name)"
        } else {
            t = "Tissue"
        }
        DispatchQueue.main.async {
            NSApp.windows.first?.title = t
        }
        #endif
    }
}


#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    let model: DrawingModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.delegate = context.coordinator
            window.contentMinSize = NSSize(width: 800, height: 560)
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
