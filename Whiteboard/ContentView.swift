import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ContentView: View {
    @Environment(DrawingModel.self) var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var hoveredTool: String?
    @State private var settingsTool: Tool?
    @State private var lastTapTime: Date = .distantPast
    @State private var showSettings: Bool = false
    @State private var showScenes: Bool = false
    @State private var isCustomizingToolbar: Bool = false
    @State private var toolbarDropTargeted: Bool = false
    @State private var trayDropTargeted: Bool = false
    @State private var renamingSceneId: UUID?
    @State private var renameSceneText: String = ""
    @State private var showImporter = false
    @State private var showImageImporter = false
    #if os(iOS)
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    #endif
    @State private var showingExporter = false
    @State private var showHelp = false
    @State private var showSettingsSidebar = false
    @State private var windowHeight: CGFloat = 700
    @State private var showRenameTissue = false
    @State private var renameTissueText = ""
    @State private var showZoomPill = false
    @State private var zoomHideWorkItem: DispatchWorkItem?
    @State private var exportFormat: ExportFormat = .wb
    @State private var exportData: Data?
    @State private var exportName = "Untitled"
    @State private var exportType: UTType = .data

    enum ExportFormat: String { case wb, png, pdf, scenesPDF }

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
                    CanvasView(model: model, onBeginDraw: { showSettings = false; showScenes = false; isCustomizingToolbar = false })
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
                    CanvasView(model: model, onBeginDraw: { showSettings = false; showScenes = false; isCustomizingToolbar = false })
                        .ignoresSafeArea()
                    #endif

                    dockedToolbarOverlay

                    // Transient Zoom Indicator + Fit-to-Content pill (bottom-trailing)
                    if showZoomPill && model.isToolbarVisible {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                zoomIndicatorPill
                                    .padding(.trailing, 16)
                                    .padding(.bottom, model.appSettings.toolbarDockEdge == .bottom ? 76 : 16)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
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
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                    handleImageDrop(providers: providers)
                }
            }
        }

        return content
            .preferredColorScheme(model.appSettings.isDarkMode ? .dark : .light)
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
                case .open:
                    showImporter = true
                case .importImage:
                    showImageImporter = true
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
                    if let utType = UTType(filenameExtension: url.pathExtension), utType.conforms(to: .image) {
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
            .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for (idx, url) in urls.enumerated() {
                        let shouldStop = url.startAccessingSecurityScopedResource()
                        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                        model.addImage(url: url, staggerIndex: idx)
                    }
                case .failure(let error):
                    model.lastErrorMessage = "Image import failed: \(error.localizedDescription)"
                }
            }
            #if os(iOS)
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images)
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                let toLoad = items
                selectedPhotoItems = []
                Task { @MainActor in
                    for (idx, item) in toLoad.enumerated() {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            model.addImage(data: data, staggerIndex: idx)
                        }
                    }
                }
            }
            #endif
            .sheet(isPresented: $showHelp) {
                HelpView()
                    .preferredColorScheme(model.appSettings.isDarkMode ? .dark : .light)
            }
            .sheet(isPresented: $model.showAbout) {
                AboutView()
                    .preferredColorScheme(model.appSettings.isDarkMode ? .dark : .light)
            }
            .animation(.easeOut(duration: 0.15), value: model.showDeleteMenu)
            .confirmationDialog("Clear Canvas?", isPresented: $model.showClearConfirmation, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { model.clear() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all strokes and images.")
            }
            .onChange(of: model.zoomDisplayScale) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) { showZoomPill = true }
                zoomHideWorkItem?.cancel()
                let item = DispatchWorkItem {
                    withAnimation(.easeOut(duration: 0.25)) { showZoomPill = false }
                }
                zoomHideWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
            }
            .alert("Rename Tissue", isPresented: $showRenameTissue) {
                TextField("Tissue name", text: $renameTissueText)
                Button("Rename") {
                    let trimmed = renameTissueText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let id = model.currentBoardId {
                        model.renameBoard(id: id, to: trimmed)
                    }
                }
                Button("Cancel", role: .cancel) { }
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
            Button("") { showImageImporter = true }
                .keyboardShortcut("i", modifiers: .command)
            Button("") { model.addScene() }
                .keyboardShortcut("x", modifiers: .shift)
            Button("") { model.goToPreviousScene() }
                .keyboardShortcut(",", modifiers: [])
            Button("") { model.goToNextScene() }
                .keyboardShortcut(".", modifiers: [])
            Button("") {
                let prior = model.currentTool
                model.selectTool(.eraser)
                switch prior {
                case .pen: model.eraserSettings.eraseTarget = .pen
                case .sharpie: model.eraserSettings.eraseTarget = .sharpie
                case .fill: model.eraserSettings.eraseTarget = .fill
                default: model.eraserSettings.eraseTarget = .all
                }
            }
            .keyboardShortcut("e", modifiers: [])
            Button("") {
                if model.currentTool == .eraser { model.eraserSettings.eraseTarget = .all }
            }
            .keyboardShortcut("0", modifiers: [])
            Button("") {
                if model.currentTool == .eraser { model.eraserSettings.eraseTarget = .pen }
            }
            .keyboardShortcut("1", modifiers: [])
            Button("") {
                if model.currentTool == .eraser { model.eraserSettings.eraseTarget = .sharpie }
            }
            .keyboardShortcut("2", modifiers: [])
            Button("") {
                if model.currentTool == .eraser { model.eraserSettings.eraseTarget = .fill }
            }
            .keyboardShortcut("3", modifiers: [])
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

    #if os(iOS)
    private let toolbarBtnMinW: CGFloat = 46
    private let toolbarBtnMinH: CGFloat = 44
    private let toolbarIconFont: Font = .title2
    private let toolbarNavBtnW: CGFloat = 34
    private let toolbarDividerH: CGFloat = 30
    private let toolbarPadH: CGFloat = 14
    private let toolbarPadV: CGFloat = 8
    private let toolbarSpacing: CGFloat = 10
    #else
    private let toolbarBtnMinW: CGFloat = 38
    private let toolbarBtnMinH: CGFloat = 36
    private let toolbarIconFont: Font = .title3
    private let toolbarNavBtnW: CGFloat = 26
    private let toolbarDividerH: CGFloat = 24
    private let toolbarPadH: CGFloat = 10
    private let toolbarPadV: CGFloat = 6
    private let toolbarSpacing: CGFloat = 8
    #endif

    private func toolButton(systemName: String, tool: Tool) -> some View {
        let isSelected = model.currentTool == tool
        let isHovered = hoveredTool == systemName
        let bg: Color = isSelected ? toolColor(tool) : isHovered ? Color.primary.opacity(0.12) : .clear
        let fg: Color = isSelected ? contrastingColor(for: bg) : isHovered ? .primary : .secondary
        return Button(action: {}) {
            Image(systemName: systemName)
                .font(toolbarIconFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: toolbarBtnMinW, minHeight: toolbarBtnMinH)
                .background(bg)
                .foregroundColor(fg)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .scaleEffect(isHovered ? 1.07 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .pencilHoverEffect()
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

    private var hasActiveSelection: Bool {
        !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty
    }

    @ViewBuilder
    private var dockedToolbarOverlay: some View {
        let edge = model.appSettings.toolbarDockEdge
        let secondaryPanel: some View = Group {
            if model.isToolbarVisible && isCustomizingToolbar {
                customizeToolbarTray
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if model.isToolbarVisible && model.currentTool == .select && hasActiveSelection {
                selectionActionPill
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if model.isToolbarVisible, let tool = settingsTool, tool != .select && tool != .laser {
                ToolSettingsView(model: model, tool: tool)
                    .onTapGesture { }
            }
        }

        switch edge {
        case .top:
            VStack(spacing: 6) {
                if model.isToolbarVisible { toolbar }
                secondaryPanel
                Spacer()
            }
            .padding(.top, 12)
        case .bottom:
            VStack(spacing: 6) {
                Spacer()
                secondaryPanel
                if model.isToolbarVisible { toolbar }
            }
            .padding(.bottom, 14)
        case .left:
            HStack(alignment: .center, spacing: 8) {
                if model.isToolbarVisible { toolbar }
                VStack {
                    secondaryPanel
                    Spacer()
                }
                .padding(.top, 12)
                Spacer()
            }
            .padding(.leading, 12)
        case .right:
            HStack(alignment: .center, spacing: 8) {
                Spacer()
                VStack {
                    secondaryPanel
                    Spacer()
                }
                .padding(.top, 12)
                if model.isToolbarVisible { toolbar }
            }
            .padding(.trailing, 12)
        }
    }

    private var zoomIndicatorPill: some View {
        HStack(spacing: 6) {
            Button(action: { model.needsResetZoom = true }) {
                Text("\(Int((model.zoomDisplayScale * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Reset Zoom to 100%")
            .pointingHand()

            Divider().frame(height: 16)

            Button(action: { model.needsFitToContent = true }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Fit All Content")
            .pointingHand()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .liquidGlassCapsule()
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
    }

    private var selectionActionPill: some View {
        HStack(spacing: 6) {
            Button(action: { model.copySelected() }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Copy Selection")
            .pointingHand()
            .pencilHoverEffect()

            Button(action: { model.duplicateSelected() }) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Duplicate Selection")
            .pointingHand()
            .pencilHoverEffect()

            if !model.selectedStrokeIds.isEmpty || !model.selectedFillIds.isEmpty {
                Divider().frame(height: 18)
                HStack(spacing: 4) {
                    ForEach(Array(model.penPresets.prefix(6).enumerated()), id: \.offset) { idx, color in
                        Button(action: { model.recolorSelected(to: color, presetIndex: idx) }) {
                            Circle()
                                .fill(color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.75))
                                .frame(width: 22, height: 22)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Recolor Selection")
                        .pointingHand()
                        .pencilHoverEffect()
                    }
                }
            }

            Divider().frame(height: 18)

            Button(action: { model.transformSelected(scale: 0.85, rotation: 0) }) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Shrink Selection")
            .pointingHand()
            .pencilHoverEffect()

            Button(action: { model.transformSelected(scale: 1.15, rotation: 0) }) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Enlarge Selection")
            .pointingHand()
            .pencilHoverEffect()

            Button(action: { model.transformSelected(scale: 1.0, rotation: .pi / 12) }) {
                Image(systemName: "rotate.right")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Rotate Selection 15°")
            .pointingHand()
            .pencilHoverEffect()

            Divider().frame(height: 18)

            Button(role: .destructive, action: { model.deleteSelected() }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(width: 28, height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Delete Selection")
            .pointingHand()
            .pencilHoverEffect()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlassCapsule()
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        .onTapGesture { }
    }

    private var toolbar: some View {
        let isVertical = model.appSettings.toolbarDockEdge.isVertical
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: toolbarSpacing))
            : AnyLayout(HStackLayout(spacing: toolbarSpacing))

        return layout {
            ForEach(model.pinnedToolbarItems) { item in
                if isCustomizingToolbar {
                    customizingToolbarChip(for: item)
                } else {
                    toolbarItemView(for: item)
                }
            }

            if !model.pinnedToolbarItems.isEmpty {
                Divider()
                    .frame(width: isVertical ? toolbarDividerH : nil, height: isVertical ? nil : toolbarDividerH)
            }

            if isCustomizingToolbar {
                Button("Done") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isCustomizingToolbar = false
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: toolbarBtnMinH)
                .background(Color.accentColor)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .buttonStyle(.plain)
                .pointingHand()
                .pencilHoverEffect()
            } else {
                settingsMenu
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isVertical ? toolbarPadV : toolbarPadH)
        .padding(.vertical, isVertical ? toolbarPadH : toolbarPadV)
        .liquidGlassCapsule()
        .overlay(
            Capsule()
                .stroke(
                    isCustomizingToolbar ? (toolbarDropTargeted ? Color.accentColor : Color.accentColor.opacity(0.4)) : Color.clear,
                    lineWidth: toolbarDropTargeted ? 2 : 1
                )
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard isCustomizingToolbar, let raw = payloads.first, let item = ToolbarItemID(rawValue: raw) else {
                return false
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                model.pinToolbarItem(item, before: nil)
            }
            return true
        } isTargeted: { targeted in
            toolbarDropTargeted = targeted
        }
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
    }

    @ViewBuilder
    private func toolbarItemView(for item: ToolbarItemID) -> some View {
        if let tool = item.associatedTool {
            toolButton(systemName: item.systemImage, tool: tool)
        } else if item == .scenes {
            scenesToolbarGroup
        } else {
            actionToolbarButton(for: item)
        }
    }

    private var scenesToolbarGroup: some View {
        HStack(spacing: 2) {
            Button(action: { model.goToPreviousScene() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: toolbarNavBtnW > 30 ? 15 : 13, weight: .semibold))
                    .frame(width: toolbarNavBtnW, height: toolbarBtnMinH)
                    .background(hoveredTool == "prevScene" ? Color.primary.opacity(0.14) : .clear)
                    .foregroundColor(model.scenes.isEmpty ? .secondary.opacity(0.45) : .primary)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .scaleEffect(hoveredTool == "prevScene" ? 1.07 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: hoveredTool == "prevScene")
                    .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .disabled(model.scenes.isEmpty)
            .help("Previous Scene")
            .onHover { hovering in hoveredTool = hovering ? "prevScene" : nil }
            .pointingHand()

            scenesMenu

            Button(action: { model.goToNextScene() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: toolbarNavBtnW > 30 ? 15 : 13, weight: .semibold))
                    .frame(width: toolbarNavBtnW, height: toolbarBtnMinH)
                    .background(hoveredTool == "nextScene" ? Color.primary.opacity(0.14) : .clear)
                    .foregroundColor(model.scenes.isEmpty ? .secondary.opacity(0.45) : .primary)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .scaleEffect(hoveredTool == "nextScene" ? 1.07 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: hoveredTool == "nextScene")
                    .pencilHoverEffect()
            }
            .buttonStyle(.plain)
            .disabled(model.scenes.isEmpty)
            .help("Next Scene")
            .onHover { hovering in hoveredTool = hovering ? "nextScene" : nil }
            .pointingHand()
        }
    }

    private func actionToolbarButton(for item: ToolbarItemID) -> some View {
        let isHovered = hoveredTool == item.rawValue
        let isActive = isToolbarItemActive(item)
        let isDisabled = isToolbarItemDisabled(item)
        let isDestructive = item == .clear

        return Button(action: { performToolbarAction(for: item) }) {
            Image(systemName: dynamicIcon(for: item))
                .font(toolbarIconFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: toolbarBtnMinW, minHeight: toolbarBtnMinH)
                .background(
                    isActive ? Color.accentColor :
                    isHovered ? Color.primary.opacity(0.14) : .clear
                )
                .foregroundColor(
                    isDisabled ? .secondary.opacity(0.45) :
                    isActive ? .white :
                    isDestructive ? .red : .primary
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
                .scaleEffect(isHovered ? 1.07 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .pencilHoverEffect()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(dynamicTooltip(for: item))
        .onHover { hovering in
            hoveredTool = hovering ? item.rawValue : nil
        }
        .pointingHand()
    }

    private func customizingToolbarChip(for item: ToolbarItemID) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: dynamicIcon(for: item))
                .font(toolbarIconFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: toolbarBtnMinW, minHeight: toolbarBtnMinH)
                .background(Color.primary.opacity(0.10))
                .foregroundColor(.primary)
                .clipShape(Capsule())
                .contentShape(Capsule())

            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    model.unpinToolbarItem(item)
                }
            }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, .red)
            }
            .buttonStyle(.plain)
            .offset(x: 3, y: -3)
            .help("Move \(item.title) to More")
            .pointingHand()
        }
        .help("Drag to reorder or drop in tray below to move to More")
        .draggable(item.rawValue)
        .dropDestination(for: String.self) { payloads, _ in
            guard let raw = payloads.first, let dropped = ToolbarItemID(rawValue: raw) else { return false }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                model.pinToolbarItem(dropped, before: item)
            }
            return true
        }
    }

    private var customizeToolbarTray: some View {
        let cols = [GridItem(.adaptive(minimum: 58, maximum: 68), spacing: 8)]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Customize Toolbar", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: cycleToolbarDockEdge) {
                    Label(model.appSettings.toolbarDockEdge.rawValue, systemImage: "dock.rectangle")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Dock Toolbar: Top / Bottom / Left / Right")
                .pointingHand()

                Button("Reset") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        model.resetToolbarLayout()
                        model.appSettings.toolbarDockEdge = .top
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .pointingHand()
            }

            Text("Drag icons onto the toolbar above to add or reorder · Drag icons down here to move to More")
                .font(.caption2)
                .foregroundColor(.secondary)

            if model.unpinnedToolbarItems.isEmpty {
                Text("All tools are pinned to the toolbar. Drag any icon down here to unpin it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(model.unpinnedToolbarItems) { item in
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    model.pinToolbarItem(item, before: nil)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: dynamicIcon(for: item))
                                        .font(.system(size: 16))
                                        .frame(width: 38, height: 34)
                                        .background(Color.primary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(item.title)
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .pencilHoverEffect()
                            }
                            .buttonStyle(.plain)
                            .help("Drag or tap to add \(item.title) to toolbar")
                            .pointingHand()
                            .draggable(item.rawValue)
                        }
                    }
                }
                .frame(maxHeight: min(220, max(120, windowHeight - 220)))
            }
        }
        .padding(14)
        .frame(width: 360)
        .liquidGlassSurface(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(trayDropTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard let raw = payloads.first, let dropped = ToolbarItemID(rawValue: raw) else { return false }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                model.unpinToolbarItem(dropped)
            }
            return true
        } isTargeted: { targeted in
            trayDropTargeted = targeted
        }
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        .onTapGesture { }
    }

    private func cycleToolbarDockEdge() {
        let edges = ToolbarDockEdge.allCases
        if let idx = edges.firstIndex(of: model.appSettings.toolbarDockEdge) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                model.appSettings.toolbarDockEdge = edges[(idx + 1) % edges.count]
            }
        }
    }

    private func dynamicIcon(for item: ToolbarItemID) -> String {
        switch item {
        case .darkMode:
            return model.appSettings.isDarkMode ? "sun.max.fill" : "moon.fill"
        case .warmPaper:
            return model.appSettings.isWarmPaper ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .singleTapOptions:
            return model.appSettings.revealSettingsOnSingleTap ? "hand.tap.fill" : "hand.tap"
        default:
            return item.systemImage
        }
    }

    private func dynamicTooltip(for item: ToolbarItemID) -> String {
        let hasSelection = !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty
        switch item {
        case .clear: return hasSelection ? "Delete Selected" : "Clear Tissue"
        case .darkMode: return model.appSettings.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode"
        case .warmPaper: return model.appSettings.isWarmPaper ? "Switch to Crisp White Paper" : "Switch to Warm Café Napkin Paper"
        case .renameTissue: return "Rename Tissue"
        case .fitContent: return "Fit All Content"
        case .laser: return "Laser Pointer (L)"
        case .singleTapOptions: return "Show Options on Single Tap"
        case .pencilOnly: return "Draw with Apple Pencil Only"
        case .importPhoto: return "Import from Photos"
        case .importImage: return "Import Image File…"
        case .openFile: return "Open .wb File…"
        case .help: return "Help & Shortcuts"
        case .about: return "About Tissue Box"
        default: return item.title
        }
    }

    private func isToolbarItemActive(_ item: ToolbarItemID) -> Bool {
        if let tool = item.associatedTool {
            return model.currentTool == tool
        }
        switch item {
        case .warmPaper: return model.appSettings.isWarmPaper && !model.appSettings.isDarkMode
        case .singleTapOptions: return model.appSettings.revealSettingsOnSingleTap
        case .pencilOnly: return model.appSettings.pencilOnly
        default: return false
        }
    }

    private func isToolbarItemDisabled(_ item: ToolbarItemID) -> Bool {
        let hasSelection = !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty
        let isEmptyCanvas = model.strokes.isEmpty && model.placedImages.isEmpty && model.fills.isEmpty
        switch item {
        case .undo: return !model.canUndo
        case .redo: return !model.canRedo
        case .clear: return isEmptyCanvas
        case .copy: return !hasSelection
        case .renameTissue: return model.currentBoardId == nil
        default: return false
        }
    }

    private func performToolbarAction(for item: ToolbarItemID, closePopover: Bool = false) {
        let hasSelection = !model.selectedStrokeIds.isEmpty || !model.selectedImageIds.isEmpty || !model.selectedFillIds.isEmpty
        switch item {
        case .pen, .sharpie, .fill, .eraser, .select, .laser:
            if let tool = item.associatedTool {
                model.selectTool(tool)
                settingsTool = (model.appSettings.revealSettingsOnSingleTap && tool != .laser && tool != .select) ? tool : nil
            }
            if closePopover { showSettings = false }
        case .scenes:
            if closePopover { showSettings = false }
            showScenes.toggle()
        case .home:
            if closePopover { showSettings = false }
            model.closeBoard()
        case .undo:
            model.undo()
        case .redo:
            model.redo()
        case .clear:
            if closePopover { showSettings = false }
            if hasSelection { model.deleteSelected() } else { model.showClearConfirmation = true }
        case .copy:
            model.copySelected()
            if closePopover { showSettings = false }
        case .paste:
            model.paste()
            if closePopover { showSettings = false }
        case .importPhoto:
            if closePopover { showSettings = false }
            #if os(iOS)
            showPhotosPicker = true
            #endif
        case .importImage:
            if closePopover { showSettings = false }
            showImageImporter = true
        case .center:
            model.needsRecenter = true
            if closePopover { showSettings = false }
        case .fitContent:
            model.needsFitToContent = true
            if closePopover { showSettings = false }
        case .darkMode:
            model.appSettings.isDarkMode.toggle()
        case .warmPaper:
            if model.appSettings.isDarkMode { model.appSettings.isDarkMode = false }
            model.appSettings.isWarmPaper.toggle()
        case .renameTissue:
            if closePopover { showSettings = false }
            if let id = model.currentBoardId,
               let board = model.boards.first(where: { $0.id == id }) {
                renameTissueText = board.name
                showRenameTissue = true
            }
        case .singleTapOptions:
            model.appSettings.revealSettingsOnSingleTap.toggle()
        case .pencilOnly:
            model.appSettings.pencilOnly.toggle()
        case .exportWB:
            if closePopover { showSettings = false }
            exportFormat = .wb; exportAction()
        case .exportPNG:
            if closePopover { showSettings = false }
            exportFormat = .png; exportAction()
        case .exportPDF:
            if closePopover { showSettings = false }
            exportFormat = .pdf; exportAction()
        case .openFile:
            if closePopover { showSettings = false }
            showImporter = true
        case .help:
            if closePopover { showSettings = false }
            showHelp = true
        case .about:
            if closePopover { showSettings = false }
            model.showAbout = true
        }
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

    // MARK: - Scenes Popover & Floating Navigator

    private var scenesMenu: some View {
        #if os(iOS)
        let popoverArrowEdge: Edge = .top
        #else
        let popoverArrowEdge: Edge = .bottom
        #endif
        let maxPopoverHeight = max(220, windowHeight - 130)

        return Button(action: {
            showSettings = false
            showScenes.toggle()
        }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "rectangle.stack")
                    .font(toolbarIconFont)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minWidth: toolbarBtnMinW, minHeight: toolbarBtnMinH)
                    .background(hoveredTool == "scenes" || showScenes ? Color.primary.opacity(0.14) : .clear)
                    .foregroundColor(showScenes ? .accentColor : .primary)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .scaleEffect(hoveredTool == "scenes" ? 1.07 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: hoveredTool == "scenes")
                    .pencilHoverEffect()

                if !model.scenes.isEmpty {
                    Text("\(model.scenes.count)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .offset(x: 2, y: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Scenes")
        .onHover { hovering in
            hoveredTool = hovering ? "scenes" : nil
        }
        .pointingHand()
        .popover(isPresented: $showScenes, attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrowEdge) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Text("Scenes")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !model.scenes.isEmpty {
                        Button(action: {
                            showScenes = false
                            exportFormat = .scenesPDF
                            exportAction()
                        }) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 26, height: 24)
                                .background(Color.primary.opacity(0.08))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Export Scenes as Multi-Page PDF")
                        .pointingHand()
                    }
                    Button(action: { model.addScene() }) {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.16))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Save Current View as Scene")
                    .pointingHand()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().opacity(0.45)

                if model.scenes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("No Scenes Yet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Bookmark regions of your tissue to jump between ideas like slides.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: { model.addScene() }) {
                            Label("Add Current View", systemImage: "plus")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .liquidGlassProminentButton()
                        .pointingHand()
                        .padding(.top, 2)
                    }
                    .padding(16)
                } else {
                    let listHeight = min(CGFloat(model.scenes.count) * 48 + 12, maxPopoverHeight - 50)
                    List {
                        ForEach(Array(model.scenes.enumerated()), id: \.element.id) { index, scene in
                            sceneRow(scene: scene, index: index)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        model.deleteScene(id: scene.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        renameSceneText = scene.name
                                        renamingSceneId = scene.id
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(.accentColor)
                                }
                        }
                        .onMove { source, destination in
                            model.moveScenes(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: max(56, listHeight))
                }
            }
            .frame(width: 240)
            .preferredColorScheme(model.appSettings.isDarkMode ? .dark : .light)
            .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        }
    }

    private func sceneRow(scene: CanvasScene, index: Int) -> some View {
        let _ = model.sceneThumbnailRevision
        let thumb = model.sceneThumbnail(for: scene)
        let isActive = model.activeSceneId == scene.id
        return HStack(spacing: 8) {
            // Lazy mini-thumbnail preview (rendered off-main-thread only when popover opens)
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumb {
                        #if os(macOS)
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        #else
                        Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        #endif
                    } else {
                        Color.primary.opacity(0.06)
                    }
                }
                .frame(width: 44, height: 33)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isActive ? 1.5 : 0.5)
                )

                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isActive ? Color.accentColor : Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(2)
            }

            if renamingSceneId == scene.id {
                TextField("Scene name", text: $renameSceneText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        model.renameScene(id: scene.id, to: renameSceneText)
                        renamingSceneId = nil
                    }
            } else {
                Button(action: {
                    model.goToScene(scene)
                    showScenes = false
                }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scene.name)
                            .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("\(Int((scene.cgScale * 100).rounded()))%")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
            }

            Menu {
                Button {
                    model.updateSceneToCurrentView(id: scene.id)
                } label: {
                    Label("Update to Current View", systemImage: "viewfinder")
                }
                Button {
                    renameSceneText = scene.name
                    renamingSceneId = scene.id
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                if index > 0 {
                    Button {
                        model.moveScene(id: scene.id, direction: -1)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                }
                if index < model.scenes.count - 1 {
                    Button {
                        model.moveScene(id: scene.id, direction: 1)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    model.deleteScene(id: scene.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .pointingHand()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
    }

    private var settingsMenu: some View {
        let maxPopoverHeight = max(200, windowHeight - 110)
        let cols = [GridItem(.fixed(38), spacing: 6), GridItem(.fixed(38), spacing: 6), GridItem(.fixed(38), spacing: 6), GridItem(.fixed(38), spacing: 6)]

        #if os(iOS)
        let popoverArrowEdge: Edge = .top
        #else
        let popoverArrowEdge: Edge = .bottom
        #endif

        return Button(action: { showSettings.toggle() }) {
            Image(systemName: "line.3.horizontal")
                .font(toolbarIconFont)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: toolbarBtnMinW, minHeight: toolbarBtnMinH)
                .background(hoveredTool == "settings" || showSettings ? Color.primary.opacity(0.14) : .clear)
                .foregroundColor(.primary)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .scaleEffect(hoveredTool == "settings" ? 1.07 : 1.0)
                .animation(.easeOut(duration: 0.12), value: hoveredTool == "settings")
                .pencilHoverEffect()
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
                    // Unpinned tools & actions
                    if !model.unpinnedToolbarItems.isEmpty {
                        LazyVGrid(columns: cols, spacing: 6) {
                            ForEach(model.unpinnedToolbarItems) { item in
                                popoverIcon(
                                    dynamicIcon(for: item),
                                    tooltip: dynamicTooltip(for: item),
                                    isActive: isToolbarItemActive(item),
                                    role: item == .clear ? .destructive : nil,
                                    disabled: isToolbarItemDisabled(item)
                                ) {
                                    performToolbarAction(for: item, closePopover: true)
                                }
                            }
                        }

                        Divider()
                    }

                    // Canvas Background
                    LazyVGrid(columns: cols, spacing: 6) {
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

                    // Defaults & Customize Toolbar
                    LazyVGrid(columns: cols, spacing: 6) {
                        popoverIcon("slider.horizontal.3", tooltip: "Customize Toolbar…") {
                            showSettings = false
                            settingsTool = nil
                            withAnimation(.easeOut(duration: 0.18)) {
                                isCustomizingToolbar = true
                            }
                        }
                        popoverIcon("bookmark", tooltip: "Save Current as Defaults") {
                            model.saveDefaults(); showSettings = false
                        }
                        if model.hasDefaults {
                            popoverIcon("bookmark.fill", tooltip: "Restore Defaults") {
                                model.loadDefaults(); showSettings = false
                            }
                            popoverIcon("arrow.counterclockwise", tooltip: "Reset to Factory Defaults") {
                                model.resetToFactory(); showSettings = false
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: maxPopoverHeight)
            .preferredColorScheme(model.appSettings.isDarkMode ? .dark : .light)
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
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .pencilHoverEffect()
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(tooltip)
        .pointingHand()
    }

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for (idx, provider) in providers.enumerated() {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        model.addImage(data: data, staggerIndex: idx)
                    }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { fileURL, _ in
                    guard let fileURL,
                          let utType = UTType(filenameExtension: fileURL.pathExtension),
                          utType.conforms(to: .image) else { return }
                    Task { @MainActor in
                        let shouldStop = fileURL.startAccessingSecurityScopedResource()
                        defer { if shouldStop { fileURL.stopAccessingSecurityScopedResource() } }
                        model.addImage(url: fileURL, staggerIndex: idx)
                    }
                }
            }
        }
        return accepted
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
        case .scenesPDF:
            exportData = model.scenesPDFData()
            exportType = .pdf
            exportName = baseName + "-Scenes.pdf"
        }
        guard exportData != nil else {
            model.lastErrorMessage = "Failed to generate export data."
            return
        }
        showingExporter = true
    }
}

extension View {
    /// Applies native iPadOS Apple Pencil / pointer hover highlight when available.
    @ViewBuilder
    func pencilHoverEffect() -> some View {
        #if os(iOS)
        self.hoverEffect(.highlight)
        #else
        self
        #endif
    }

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

