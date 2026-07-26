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
    @State private var showSettingsSidebar = false
    @State private var exportFormat: ExportFormat = .wb
    @State private var exportData: Data?
    @State private var exportName = "Untitled"
    @State private var exportType: UTType = .data

    enum ExportFormat: String { case wb, png, pdf }

    var body: some View {
        let content = Group {
            if model.showWelcome {
                WelcomeView(model: model, onStart: { model.showWelcome = false })
            } else {
                ZStack {
                    CanvasView(model: model, onBeginDraw: { showSettings = false })
                        .ignoresSafeArea()
                        .pencilSqueezeToolbar(model: model)

                    VStack(spacing: 0) {
                        if model.isToolbarVisible { toolbar }
                        if model.isToolbarVisible, let tool = settingsTool, tool != .select {
                            ToolSettingsView(model: model, tool: tool)
                                .padding(.top, 4)
                                .onTapGesture { }
                        }
                        Spacer()
                    }

                    #if os(iOS) && !targetEnvironment(macCatalyst)
                    if showSettingsSidebar {
                        HStack(spacing: 0) {
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture { showSettingsSidebar = false }
                            settingsSidebarContent
                                .frame(width: 300)
                                .background(.thickMaterial)
                        }
                        .ignoresSafeArea()
                        .transition(.move(edge: .trailing))
                        .animation(.easeOut(duration: 0.25), value: showSettingsSidebar)
                    }
                    #endif

                    if model.showDeleteMenu {
                        HStack(spacing: 4) {
                            if model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty {
                                // Nothing selected — offer Paste
                                Button(action: { model.paste(); model.showDeleteMenu = false }) {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                        .font(.callout)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Something selected — offer Copy and Delete
                                Button(action: { model.copySelected(); model.showDeleteMenu = false }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.callout)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if !model.selectedImageIds.isEmpty {
                                    Button(action: { model.resizeSelectedImages(by: 0.8); model.showDeleteMenu = false }) {
                                        Image(systemName: "minus.magnifyingglass")
                                            .font(.callout)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { model.resizeSelectedImages(by: 1.25); model.showDeleteMenu = false }) {
                                        Image(systemName: "plus.magnifyingglass")
                                            .font(.callout)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(role: .destructive) {
                                    model.deleteSelected()
                                    model.showDeleteMenu = false
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .font(.callout)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(.thickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                        .position(model.deleteMenuLocation)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .onTapGesture { }  // prevent pass-through
                    }
                }
            }
        }

        return content
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .statusBarHidden()
            #endif
            .onChange(of: model.pendingAction) { _, newValue in
                guard let newValue else { return }
                if newValue == .open { showImporter = true }
                if newValue == .importImage { showImporter = true }
                model.pendingAction = nil
            }
            .background(shortcutButtons)
            .fileExporter(isPresented: $showingExporter, document: ExportDocument(data: exportData ?? Data()), contentType: exportType, defaultFilename: exportName) { _ in }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result {
                    let shouldStop = url.startAccessingSecurityScopedResource()
                    defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                    // Check if it's an image or a .wb file
                    let ext = url.pathExtension.lowercased()
                    if ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "heic" || ext == "gif" {
                        model.addImage(url: url)
                    } else {
                        if let data = try? Data(contentsOf: url) {
                            model.loadData(data)
                            model.openFileURL = url
                        }
                    }
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .animation(.easeOut(duration: 0.15), value: model.showDeleteMenu)
            .confirmationDialog("Clear Canvas?", isPresented: $model.showClearConfirmation, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { model.clear() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all strokes, fills, and laser annotations.")
            }
    }

    private var shortcutButtons: some View {
        VStack(spacing: 0) {
            Button("") { model.isToolbarVisible.toggle() }
                .keyboardShortcut(.tab, modifiers: [])
            Button("") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("") { model.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { model.copySelected() }
                .keyboardShortcut("c", modifiers: .command)
            Button("") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
            Button("") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
            Button("") { showImporter = true }
                .keyboardShortcut("o", modifiers: .command)
            Button("") { model.closeBoard() }
                .keyboardShortcut("w", modifiers: .command)
            Button("") { showImporter = true }
                .keyboardShortcut("i", modifiers: .command)
        }
        .hidden()
        .frame(width: 0, height: 0)
    }
    private func toolColor(_ tool: Tool) -> Color {
        switch tool {
        case .pen: return model.penColor
        case .highlighter: return model.hlColor
        case .fill: return model.fillColor
        case .laser: return model.appSettings.isDarkMode ? Color.white : Color.black
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
                if model.appSettings.revealSettingsOnSingleTap {
                    if now.timeIntervalSince(lastTapTime) < 0.3 {
                        settingsTool = settingsTool == tool ? nil : tool
                        showSettings = false
                        lastTapTime = .distantPast
                        model.selectTool(tool)
                    } else {
                        lastTapTime = now
                        model.selectTool(tool)
                        settingsTool = tool
                        showSettings = false
                    }
                } else {
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

            toolButton(systemName: "laser.burst", tool: .laser)

            Divider()
                .frame(height: 24)

            Button(action: { model.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(hoveredTool == "undo" ? Color.primary.opacity(0.12) : .clear)
                    .foregroundColor(model.canUndo ? .primary : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .onHover { hovering in
                hoveredTool = hovering ? "undo" : nil
                #if os(macOS)
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                #endif
            }

            Button(action: { model.redo() }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(hoveredTool == "redo" ? Color.primary.opacity(0.12) : .clear)
                    .foregroundColor(model.canRedo ? .primary : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!model.canRedo)
            .onHover { hovering in
                hoveredTool = hovering ? "redo" : nil
                #if os(macOS)
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                #endif
            }

            Button(action: { model.showWelcome = true }) {
                Image(systemName: "house")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(hoveredTool == "home" ? Color.primary.opacity(0.12) : .clear)
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredTool = hovering ? "home" : nil
                #if os(macOS)
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                #endif
            }

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

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private var settingsSidebarContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsGroup(title: nil, items: [
                        ("arrow.uturn.backward", "Undo", { model.undo() }, !model.canUndo),
                        ("arrow.uturn.forward", "Redo", { model.redo() }, !model.canRedo),
                        ("trash", model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty ? "Clear Canvas" : "Delete", { model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty ? (model.showClearConfirmation = true) : model.deleteSelected() }, model.strokes.isEmpty && model.fillRegions.isEmpty && model.placedImages.isEmpty),
                        ("doc.on.doc", "Copy", { model.copySelected() }, model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty),
                        ("doc.on.clipboard", "Paste", { model.paste() }, false),
                        ("photo", "Import Image", { showImporter = true }, false),
                        ("viewfinder", "Center", { model.needsRecenter = true }, false),
                        ("house", "Home", { model.showWelcome = true }, false),
                    ])

                    Divider().padding(.horizontal)

                    settingsGroup(title: "Appearance", items: [])

                    Toggle(isOn: $model.appSettings.isDarkMode) {
                        Label(model.appSettings.isDarkMode ? "Dark Mode" : "Light Mode", systemImage: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .onTapGesture { showSettingsSidebar = false }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Toggle(isOn: $model.appSettings.revealSettingsOnSingleTap) {
                        Label("Reveal Options on Single Tap", systemImage: model.appSettings.revealSettingsOnSingleTap ? "hand.tap.fill" : "hand.tap")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Picker("Background", selection: $model.appSettings.canvasBackground) {
                        ForEach(CanvasBackground.allCases, id: \.self) { bg in
                            Label(bg.rawValue.capitalized, systemImage: iconName(bg)).tag(bg)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider().padding(.horizontal)

                    settingsGroup(title: "Defaults", items: [
                        ("bookmark", "Save Current as Defaults", { model.saveDefaults() }, false),
                    ])
                    if model.hasDefaults {
                        settingsGroup(title: nil, items: [
                            ("bookmark.fill", "Restore Defaults", { model.loadDefaults() }, false),
                            ("arrow.counterclockwise", "Reset to Factory", { model.resetToFactory() }, false),
                        ])
                    }

                    Divider().padding(.horizontal)

                    settingsGroup(title: "Export", items: [
                        ("square.and.arrow.down", "Save", { exportFormat = .wb; exportAction() }, false),
                        ("photo", "Export PNG", { exportFormat = .png; exportAction() }, false),
                        ("doc.richtext", "Export PDF", { exportFormat = .pdf; exportAction() }, false),
                        ("folder", "Open", { showImporter = true }, false),
                    ])

                    Divider().padding(.horizontal)

                    settingsGroup(title: nil, items: [
                        ("questionmark.circle", "Help", { showHelp = true }, false),
                    ])
                }
                .padding()
                .padding(.bottom, 60)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettingsSidebar = false }
                }
            }
        }
    }

    private func settingsGroup(title: String?, items: [(icon: String, label: String, action: () -> Void, disabled: Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                Text(title)
                    .font(.caption).foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button(action: {
                    item.action()
                    hideSidebarOnAction(item.label)
                }) {
                    HStack {
                        Image(systemName: item.icon)
                            .frame(width: 24)
                        Text(item.label)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .disabled(item.disabled)
                .foregroundColor(item.disabled ? .secondary : .primary)
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                        .padding(.horizontal, 2)
                        .opacity(0)
                )
            }
        }
    }

    private func hideSidebarOnAction(_ label: String) {
        // Don't hide for Undo/Redo/Delete since they don't change context
        if label == "Home" || label.hasPrefix("Export") || label == "Save" || label == "Open" || label == "Help" || label == "Save Current as Defaults" || label == "Restore Defaults" || label == "Reset to Factory" || label == "Center" || label == "Dark Mode" {
            showSettingsSidebar = false
        }
    }
    #endif

    private var settingsMenu: some View {
        let content = Group {
            Section {
                Button(action: { model.undo() }) { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button(action: { model.redo() }) { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                Button(action: { model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty ? (model.showClearConfirmation = true) : model.deleteSelected() }) {
                    Label(model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty ? "Clear Canvas" : "Delete", systemImage: "trash")
                }
                .disabled(model.strokes.isEmpty && model.fillRegions.isEmpty && model.placedImages.isEmpty)
                Button(action: { model.copySelected() }) { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.selectedStrokeIds.isEmpty && model.selectedFillIds.isEmpty && model.selectedImageIds.isEmpty)
                Button(action: { model.paste() }) { Label("Paste", systemImage: "doc.on.clipboard") }
                Button(action: { showImporter = true }) { Label("Import Image", systemImage: "photo") }
                Button(action: { model.needsRecenter = true }) { Label("Center", systemImage: "viewfinder") }
                Button(action: { model.showWelcome = true }) { Label("Home", systemImage: "house") }
            }

            Divider()

            Section("Appearance") {
                Toggle(isOn: $model.appSettings.isDarkMode) {
                    Label(model.appSettings.isDarkMode ? "Dark Mode" : "Light Mode", systemImage: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                }

                Toggle(isOn: $model.appSettings.revealSettingsOnSingleTap) {
                    Label("Show Options on Single Tap", systemImage: model.appSettings.revealSettingsOnSingleTap ? "hand.tap.fill" : "hand.tap")
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
        }

        let label = Image(systemName: "line.3.horizontal")
            .font(.title3)
            .frame(width: 32, height: 32)
            .background(hoveredTool == "settings" ? Color.primary.opacity(0.12) : .clear)
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering in
                hoveredTool = hovering ? "settings" : nil
                #if os(macOS)
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                #endif
            }

        return Menu(content: { content }, label: { label })
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

extension View {
    @ViewBuilder
    func pencilSqueezeToolbar(model: DrawingModel) -> some View {
        #if os(iOS)
        if #available(iOS 17.5, *) {
            self.onPencilSqueeze { phase in
                if case .ended = phase {
                    model.isToolbarVisible.toggle()
                }
            }
        } else { self }
        #else
        self
        #endif
    }
}

