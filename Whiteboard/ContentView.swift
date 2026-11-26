import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(DrawingModel.self) var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var hoveredTool: String?
    @State private var settingsTool: Tool?
    @State private var lastTapTime: Date = .distantPast
    @State private var showSettings: Bool = false
    @State private var showImporter = false
    @State private var showingExporter = false
    @State private var showHelp = false
    @State private var showSettingsSidebar = false
    @State private var windowHeight: CGFloat = 700
    @State private var exportFormat: ExportFormat = .wb
    @State private var exportData: Data?
    @State private var exportName = "Untitled"
    @State private var exportType: UTType = .data

    enum ExportFormat: String { case wb, png, pdf }

    private var canvasWindowTitle: String {
        if let id = model.currentBoardId,
           let board = model.boards.first(where: { $0.id == id }) {
            return "Tissue | \(board.name)"
        }
        return "Tissue"
    }

    var body: some View {
        @Bindable var model = model
        let content = Group {
            if model.showWelcome {
                WelcomeView(model: model, onStart: { model.showWelcome = false })
            } else {
                ZStack {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { windowHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in windowHeight = h }
                    }
                    .allowsHitTesting(false)

                    #if os(iOS)
                    CanvasView(model: model, onBeginDraw: { showSettings = false })
                        .ignoresSafeArea()
                        .onPencilDoubleTap { _ in
                            model.toggleEraserFromPencil()
                        }
                        .onPencilSqueeze { phase in
                            if case .ended = phase, !model.showAbout {
                                model.cycleToolFromPencil()
                            }
                        }
                    #else
                    CanvasView(model: model, onBeginDraw: { showSettings = false })
                        .ignoresSafeArea()
                    #endif

                    VStack(spacing: 0) {
                        #if compiler(>=6.2)
                        if #available(macOS 26.0, iOS 26.0, *) {
                            GlassEffectContainer(spacing: 10) {
                                VStack(spacing: 6) {
                                    if model.isToolbarVisible { toolbar }
                                    if model.isToolbarVisible, let tool = settingsTool, tool != .select {
                                        ToolSettingsView(model: model, tool: tool)
                                            .onTapGesture { }
                                    }
                                }
                            }
                        } else {
                            if model.isToolbarVisible { toolbar }
                            if model.isToolbarVisible, let tool = settingsTool, tool != .select {
                                ToolSettingsView(model: model, tool: tool)
                                    .padding(.top, 6)
                                    .onTapGesture { }
                            }
                        }
                        #else
                        if model.isToolbarVisible { toolbar }
                        if model.isToolbarVisible, let tool = settingsTool, tool != .select {
                            ToolSettingsView(model: model, tool: tool)
                                .padding(.top, 6)
                                .onTapGesture { }
                        }
                        #endif
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
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .liquidGlassSurface(cornerRadius: 20)
                                .padding(12)
                        }
                        .ignoresSafeArea()
                        .transition(.move(edge: .trailing))
                        .animation(.easeOut(duration: 0.25), value: showSettingsSidebar)
                    }
                    #endif

                    if model.showDeleteMenu {
                        HStack(spacing: 4) {
                            if model.selectedStrokeIds.isEmpty && model.selectedImageIds.isEmpty {
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
                        .liquidGlassCapsule()
                        .position(model.deleteMenuLocation)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .onTapGesture { }  // prevent pass-through
                    }
                }
                .navigationTitle(canvasWindowTitle)
            }
        }

        return content
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .statusBarHidden()
            #endif
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    model.flushAutoSave()
                }
            }
            .onChange(of: model.pendingAction) { _, newValue in
                guard let newValue else { return }
                switch newValue {
                case .open, .importImage:
                    showImporter = true
                case .export(let format):
                    exportFormat = format == .png ? .png : .pdf
                    exportAction()
                }
                model.pendingAction = nil
            }
            #if os(iOS)
            .background(shortcutButtons)
            #endif
            .fileExporter(isPresented: $showingExporter, document: ExportDocument(data: exportData ?? Data()), contentType: exportType, defaultFilename: exportName) { result in
                if case .failure(let error) = result {
                    model.lastErrorMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url):
                    let shouldStop = url.startAccessingSecurityScopedResource()
                    defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                    let ext = url.pathExtension.lowercased()
                    if ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "heic" || ext == "gif" {
                        model.addImage(url: url)
                    } else {
                        do {
                            let data = try Data(contentsOf: url)
                            model.loadData(data)
                            model.openFileURL = url
                        } catch {
                            model.lastErrorMessage = "Could not open file: \(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    model.lastErrorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $model.showAbout) { AboutView() }
            .animation(.easeOut(duration: 0.15), value: model.showDeleteMenu)
            .confirmationDialog("Clear Canvas?", isPresented: $model.showClearConfirmation, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { model.clear() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all strokes and images.")
            }
            .alert("Error", isPresented: Binding(
                get: { model.lastErrorMessage != nil },
                set: { if !$0 { model.lastErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.lastErrorMessage = nil }
            } message: {
                Text(model.lastErrorMessage ?? "")
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
        case .sharpie: return model.sharpieColor
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 38, minHeight: 36)
                .background(bg)
                .foregroundColor(fg)
                .clipShape(Capsule())
        }
        .onHover { hovering in
            hoveredTool = hovering ? systemName : nil
        }
        .pointingHand()
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
            toolButton(systemName: "pencil", tool: .sharpie)
            toolButton(systemName: "drop.fill", tool: .fill)
            toolButton(systemName: "eraser", tool: .eraser)
            toolButton(systemName: "cursorarrow.click", tool: .select)

            Divider()
                .frame(height: 24)

            Button(action: { model.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minWidth: 38, minHeight: 36)
                    .background(hoveredTool == "undo" ? Color.primary.opacity(0.12) : .clear)
                    .foregroundColor(model.canUndo ? .primary : .secondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .onHover { hovering in
                hoveredTool = hovering ? "undo" : nil
            }
            .pointingHand()

            Button(action: { model.redo() }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minWidth: 38, minHeight: 36)
                    .background(hoveredTool == "redo" ? Color.primary.opacity(0.12) : .clear)
                    .foregroundColor(model.canRedo ? .primary : .secondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.canRedo)
            .onHover { hovering in
                hoveredTool = hovering ? "redo" : nil
            }
            .pointingHand()

            Button(action: { model.closeBoard() }) {
                Image(systemName: "house")
                    .font(.title3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minWidth: 38, minHeight: 36)
                    .background(hoveredTool == "home" ? Color.primary.opacity(0.12) : .clear)
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredTool = hovering ? "home" : nil
            }
            .pointingHand()

            Divider()
                .frame(height: 24)

            settingsMenu
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlassCapsule()
        .padding(.top, 12)
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
        @Bindable var model = model
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsGroup(title: nil, items: [
                        ("arrow.uturn.backward", "Undo", { model.undo() }, !model.canUndo),
                        ("arrow.uturn.forward", "Redo", { model.redo() }, !model.canRedo),
                        ("trash", model.selectedStrokeIds.isEmpty && model.selectedImageIds.isEmpty ? "Clear Canvas" : "Delete", { model.selectedStrokeIds.isEmpty && model.selectedImageIds.isEmpty ? (model.showClearConfirmation = true) : model.deleteSelected() }, model.strokes.isEmpty && model.placedImages.isEmpty),
                        ("doc.on.doc", "Copy", { model.copySelected() }, model.selectedStrokeIds.isEmpty && model.selectedImageIds.isEmpty),
                        ("doc.on.clipboard", "Paste", { model.paste() }, false),
                        ("photo", "Import Image", { showImporter = true }, false),
                        ("viewfinder", "Center", { model.needsRecenter = true }, false),
                        ("house", "Home", { model.closeBoard() }, false),
                    ])

                    Divider().padding(.horizontal)

                    settingsGroup(title: "Appearance", items: [])

                    Button(action: {
                        model.appSettings.isDarkMode.toggle()
                        showSettingsSidebar = false
                    }) {
                        HStack {
                            Image(systemName: model.appSettings.isDarkMode ? "sun.max.fill" : "moon.fill")
                                .frame(width: 24)
                            Text(model.appSettings.isDarkMode ? "Light Mode" : "Dark Mode")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.primary)

                    Toggle(isOn: $model.appSettings.revealSettingsOnSingleTap) {
                        Label("Reveal Options on Single Tap", systemImage: model.appSettings.revealSettingsOnSingleTap ? "hand.tap.fill" : "hand.tap")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Toggle(isOn: $model.appSettings.pencilOnly) {
                        Label("Draw with Apple Pencil Only", systemImage: "applepencil")
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
                        ("info.circle", "About Tissue Box", { model.showAbout = true }, false),
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
        let maxPopoverHeight = max(200, windowHeight - 110)
        let hasSelection = !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty
        let isEmptyCanvas = model.strokes.isEmpty && model.placedImages.isEmpty && model.fills.isEmpty
        let cols = [GridItem(.fixed(38), spacing: 6), GridItem(.fixed(38), spacing: 6), GridItem(.fixed(38), spacing: 6), GridItem(.fixed(38), spacing: 6)]

        #if os(iOS)
        let popoverArrowEdge: Edge = .top
        #else
        let popoverArrowEdge: Edge = .bottom
        #endif

        return Button(action: { showSettings.toggle() }) {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 38, minHeight: 36)
                .background(hoveredTool == "settings" || showSettings ? Color.primary.opacity(0.12) : .clear)
                .foregroundColor(.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("More")
        .onHover { hovering in
            hoveredTool = hovering ? "settings" : nil
        }
        .pointingHand()
        .popover(isPresented: $showSettings, attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrowEdge) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    // Actions
                    LazyVGrid(columns: cols, spacing: 6) {
                        popoverIcon("arrow.uturn.backward", tooltip: "Undo", disabled: !model.canUndo) {
                            model.undo()
                        }
                        popoverIcon("arrow.uturn.forward", tooltip: "Redo", disabled: !model.canRedo) {
                            model.redo()
                        }
                        popoverIcon(
                            "trash",
                            tooltip: hasSelection ? "Delete Selected" : "Clear Tissue",
                            role: .destructive,
                            disabled: isEmptyCanvas
                        ) {
                            showSettings = false
                            if hasSelection { model.deleteSelected() } else { model.showClearConfirmation = true }
                        }
                        popoverIcon("doc.on.doc", tooltip: "Copy", disabled: !hasSelection) {
                            model.copySelected(); showSettings = false
                        }
                        popoverIcon("doc.on.clipboard", tooltip: "Paste") {
                            model.paste(); showSettings = false
                        }
                        popoverIcon("photo", tooltip: "Import Image") {
                            showSettings = false; showImporter = true
                        }
                        popoverIcon("viewfinder", tooltip: "Center Canvas") {
                            model.needsRecenter = true; showSettings = false
                        }
                        popoverIcon("house", tooltip: "Home") {
                            showSettings = false; model.closeBoard()
                        }
                    }

                    Divider()

                    // Appearance & Background
                    LazyVGrid(columns: cols, spacing: 6) {
                        popoverIcon(
                            model.appSettings.isDarkMode ? "sun.max.fill" : "moon.fill",
                            tooltip: model.appSettings.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode"
                        ) {
                            model.appSettings.isDarkMode.toggle()
                        }
                        popoverIcon(
                            model.appSettings.revealSettingsOnSingleTap ? "hand.tap.fill" : "hand.tap",
                            tooltip: "Show Options on Single Tap",
                            isActive: model.appSettings.revealSettingsOnSingleTap
                        ) {
                            model.appSettings.revealSettingsOnSingleTap.toggle()
                        }
                        popoverIcon(
                            "applepencil",
                            tooltip: "Draw with Apple Pencil Only",
                            isActive: model.appSettings.pencilOnly
                        ) {
                            model.appSettings.pencilOnly.toggle()
                        }
                        popoverIcon("bookmark", tooltip: "Save Current as Defaults") {
                            model.saveDefaults(); showSettings = false
                        }

                        ForEach(CanvasBackground.allCases, id: \.self) { bg in
                            popoverIcon(
                                iconName(bg),
                                tooltip: "\(bg.rawValue.capitalized) Background",
                                isActive: model.appSettings.canvasBackground == bg
                            ) {
                                model.appSettings.canvasBackground = bg
                            }
                        }
                    }

                    Divider()

                    // Export, Defaults & Info
                    LazyVGrid(columns: cols, spacing: 6) {
                        popoverIcon("square.and.arrow.down", tooltip: "Save .wb") {
                            showSettings = false; exportFormat = .wb; exportAction()
                        }
                        popoverIcon("photo.badge.arrow.down", tooltip: "Export PNG") {
                            showSettings = false; exportFormat = .png; exportAction()
                        }
                        popoverIcon("doc.richtext", tooltip: "Export PDF") {
                            showSettings = false; exportFormat = .pdf; exportAction()
                        }
                        popoverIcon("folder", tooltip: "Open .wb File…") {
                            showSettings = false; showImporter = true
                        }
                        if model.hasDefaults {
                            popoverIcon("bookmark.fill", tooltip: "Restore Defaults") {
                                model.loadDefaults(); showSettings = false
                            }
                            popoverIcon("arrow.counterclockwise", tooltip: "Reset to Factory Defaults") {
                                model.resetToFactory(); showSettings = false
                            }
                        }
                        popoverIcon("questionmark.circle", tooltip: "Help & Shortcuts") {
                            showSettings = false; showHelp = true
                        }
                        popoverIcon("info.circle", tooltip: "About Tissue Box") {
                            showSettings = false; model.showAbout = true
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: maxPopoverHeight)
            .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        }
    }

    private func popoverIcon(
        _ icon: String,
        tooltip: String,
        isActive: Bool = false,
        role: ButtonRole? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 36, height: 34)
                .background(
                    isActive ? Color.accentColor :
                    Color.primary.opacity(0.06)
                )
                .foregroundColor(
                    disabled ? .secondary.opacity(0.45) :
                    isActive ? .white :
                    role == .destructive ? .red : .primary
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(tooltip)
        .pointingHand()
    }

    private func exportAction() {
        let (size, offset) = model.canvasBoundingRect()
        let baseName = model.currentBoardId.flatMap { id in model.boards.first(where: { $0.id == id })?.name } ?? "Untitled"
        switch exportFormat {
        case .wb:
            exportData = model.saveData()
            exportType = ExportDocument.wbType
            exportName = baseName
        case .png:
            exportData = model.pngData(size: size, offset: offset, scale: 4)
            exportType = .png
            exportName = baseName + ".png"
        case .pdf:
            exportData = model.pdfData(size: size, offset: offset)
            exportType = .pdf
            exportName = baseName + ".pdf"
        }
        guard exportData != nil else {
            model.lastErrorMessage = "Failed to generate export data."
            return
        }
        showingExporter = true
    }
}

extension View {
    /// Applies native Apple Liquid Glass on macOS 26+ / iOS 26+, with a refined
    /// translucent material fallback on earlier OS versions and toolchains.
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat = 14) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        }
        #else
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        #endif
    }

    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        #else
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        #endif
    }

    @ViewBuilder
    func liquidGlassInteractiveCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
        #else
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        #endif
    }

    @ViewBuilder
    func liquidGlassProminentButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }

    @ViewBuilder
    func liquidGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }
}

