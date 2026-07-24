import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject var model: DrawingModel
    @State private var hoveredTool: String?
    @State private var settingsTool: Tool?
    @State private var lastTapTime: Date = .distantPast
    @State private var showSettings: Bool = false
    @State private var showImporter = false
    @State private var showingExporter = false
    @State private var showHelp = false
    @State private var exportFormat: ExportFormat = .wb
    @State private var exportData: Data?
    @State private var exportName = "Untitled"
    @State private var exportType: UTType = .data

    enum ExportFormat: String { case wb, png, pdf }

    var body: some View {
        Group {
            if model.showWelcome {
                WelcomeView(model: model, onStart: { model.showWelcome = false })
            } else {
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
                Spacer()
            }
        }
    }
}
        .onTapGesture { settingsTool = nil }
        .onChange(of: model.pendingAction) { _, newValue in
            guard let newValue else { return }
            if newValue == .open { showImporter = true }
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
            Button("") { showImporter = true }
                .keyboardShortcut("o", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
        )
        .background(
            Button("") { model.closeBoard() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
        )
        .fileExporter(isPresented: $showingExporter, document: ExportDocument(data: exportData ?? Data()), contentType: exportType, defaultFilename: exportName) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.init(filenameExtension: "wb")!, .data]) { result in
            if case .success(let url) = result {
                let shouldStop = url.startAccessingSecurityScopedResource()
                defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    model.loadData(data)
                    model.openFileURL = url
                }
            }
        }
        .sheet(isPresented: $showHelp) { HelpView() }
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
            #if os(macOS)
            if hovering || settingsTool == tool { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            #endif
        }
        .onChange(of: settingsTool) { _, newValue in
            #if os(macOS)
            if newValue == tool { NSCursor.pointingHand.set() }
            #endif
        }
        .highPriorityGesture(
            TapGesture().onEnded {
                let now = Date()
                if now.timeIntervalSince(lastTapTime) < 0.3 {
                    settingsTool = settingsTool == tool ? nil : tool
                    showSettings = false
                    lastTapTime = .distantPast
                } else {
                    lastTapTime = now
                    model.selectTool(tool)
                    settingsTool = nil
                    showSettings = false
                }
            }
        )
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

            settingsMenu
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(model.appSettings.isDarkMode ? Color(red: 44/255, green: 44/255, blue: 46/255) : Color(.sRGB, red: 0.97, green: 0.97, blue: 0.97, opacity: 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
        .padding(.top, 12)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
    }

    private func iconName(_ bg: CanvasBackground) -> String {
        switch bg {
        case .none: return "rectangle"
        case .grid: return "grid"
        case .dots: return "circle.grid.2x2"
        case .ruled: return "line.horizontal.3"
        }
    }

    private var settingsMenu: some View {
        Menu {
            Section {
                Button(action: { model.undo() }) { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button(action: { model.redo() }) { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                Button(action: { model.deleteSelected() }) { Label("Delete Selected", systemImage: "trash") }
                    .disabled(model.strokes.isEmpty && model.fillRegions.isEmpty)
                Button(action: { model.needsRecenter = true }) { Label("Center", systemImage: "viewfinder") }
                Button(action: { model.showWelcome = true }) { Label("Home", systemImage: "house") }
            }

            Divider()

            Section("Appearance") {
                Toggle(isOn: $model.appSettings.isDarkMode) {
                    Label(model.appSettings.isDarkMode ? "Dark Mode" : "Light Mode", systemImage: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                }

                Picker("Background", selection: $model.appSettings.canvasBackground) {
                    ForEach(CanvasBackground.allCases, id: \.self) { bg in
                        Label(bg.rawValue.capitalized, systemImage: iconName(bg)).tag(bg)
                    }
                }
            }

            Section("Defaults") {
                Button(action: { model.saveDefaults() }) { Label("Save Current as Defaults", systemImage: "bookmark") }
                if model.hasDefaults {
                    Button(action: { model.loadDefaults() }) { Label("Restore Defaults", systemImage: "bookmark.fill") }
                    Button(action: { model.resetToFactory() }) { Label("Reset to Factory", systemImage: "arrow.counterclockwise") }
                }
            }

            Section("Export") {
                Button(action: { exportFormat = .wb; exportAction() }) { Label("Save", systemImage: "square.and.arrow.down") }
                Button(action: { exportFormat = .png; exportAction() }) { Label("Export PNG", systemImage: "photo") }
                Button(action: { exportFormat = .pdf; exportAction() }) { Label("Export PDF", systemImage: "doc.richtext") }
                Button(action: { showImporter = true }) { Label("Open", systemImage: "folder") }
            }

            Section {
                Button(action: { showHelp = true }) { Label("Help", systemImage: "questionmark.circle") }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func exportAction() {
        let (size, offset) = canvasRect()
        switch exportFormat {
        case .wb:
            exportData = model.saveData()
            exportType = .init(filenameExtension: "wb") ?? .data
            exportName = model.currentBoardId.flatMap { id in model.boards.first(where: { $0.id == id })?.name } ?? "Untitled"
        case .png:
            exportData = model.pngData(size: size, offset: offset, scale: 4)
            exportType = .png
            exportName = (model.currentBoardId.flatMap { id in model.boards.first(where: { $0.id == id })?.name } ?? "Untitled") + ".png"
        case .pdf:
            exportData = model.pdfData(size: size, offset: offset)
            exportType = .pdf
            exportName = (model.currentBoardId.flatMap { id in model.boards.first(where: { $0.id == id })?.name } ?? "Untitled") + ".pdf"
        }
        showingExporter = true
    }

    private func canvasRect() -> (size: CGSize, offset: CGPoint) {
        var minX: CGFloat = .greatestFiniteMagnitude, maxX: CGFloat = 0
        var minY: CGFloat = .greatestFiniteMagnitude, maxY: CGFloat = 0
        var hasContent = false
        for s in model.strokes {
            for p in s.points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
                hasContent = true
            }
        }
        for r in model.fillRegions {
            let box = r.cgPath.boundingBox
            if !box.isNull {
                minX = min(minX, box.minX); maxX = max(maxX, box.maxX)
                minY = min(minY, box.minY); maxY = max(maxY, box.maxY)
                hasContent = true
            }
        }
        guard hasContent else { return (CGSize(width: 1000, height: 1000), .zero) }
        let pad: CGFloat = 40
        return (
            CGSize(width: maxX - minX + pad * 2, height: maxY - minY + pad * 2),
            CGPoint(x: minX - pad, y: minY - pad)
        )
    }
}
