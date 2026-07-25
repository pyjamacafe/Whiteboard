import Combine
import SwiftUI
import UniformTypeIdentifiers
import os
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

struct Stroke: Identifiable, Codable {
    var id = UUID()
    var points: [CGPoint]
    let color: CodableColor
    let lineWidth: CGFloat
    let isEraser: Bool
    let isHighlighter: Bool
    let presetIndex: Int  // -1 = absolute color, 0+ = preset index for theme lookup

    init(id: UUID = UUID(), points: [CGPoint], color: Color, lineWidth: CGFloat, isEraser: Bool, isHighlighter: Bool, presetIndex: Int = -1) {
        self.id = id
        self.points = points
        self.color = CodableColor(color)
        self.lineWidth = lineWidth
        self.isEraser = isEraser
        self.isHighlighter = isHighlighter
        self.presetIndex = presetIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, points, color, lineWidth, isEraser, isHighlighter, presetIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        points = try c.decode([CGPoint].self, forKey: .points)
        color = try c.decode(CodableColor.self, forKey: .color)
        lineWidth = try c.decode(CGFloat.self, forKey: .lineWidth)
        isEraser = try c.decode(Bool.self, forKey: .isEraser)
        isHighlighter = try c.decode(Bool.self, forKey: .isHighlighter)
        presetIndex = try c.decodeIfPresent(Int.self, forKey: .presetIndex) ?? -1
    }

    var uiColor: Color { color.color }

    func displayColor(for model: DrawingModel) -> Color {
        guard presetIndex >= 0 else { return color.color }  // absolute color, no theme lookup
        if isHighlighter {
            guard presetIndex < model.hlPresets.count else { return color.color }
            return model.hlPresets[presetIndex]
        } else {
            guard presetIndex < model.penPresets.count else { return color.color }
            return model.penPresets[presetIndex]
        }
    }
}

struct CodableColor: Codable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(_ color: Color) {
        #if os(iOS)
        let c = UIColor(color)
        #else
        let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(iOS)
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        self.r = Double(r); self.g = Double(g); self.b = Double(b); self.a = Double(a)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

struct FillRegion: Identifiable, Codable {
    var id = UUID()
    let path: CodablePath
    let color: CodableColor
    let presetIndex: Int

    enum CodingKeys: String, CodingKey {
        case id, path, color, presetIndex
    }

    init(id: UUID = UUID(), path: CGPath, color: Color, presetIndex: Int = -1) {
        self.id = id
        self.path = CodablePath(path)
        self.color = CodableColor(color)
        self.presetIndex = presetIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(CodablePath.self, forKey: .path)
        color = try c.decode(CodableColor.self, forKey: .color)
        presetIndex = try c.decodeIfPresent(Int.self, forKey: .presetIndex) ?? -1
    }

    var uiColor: Color { color.color }
    var cgPath: CGPath { path.cgPath }

    func displayColor(for model: DrawingModel) -> Color {
        guard presetIndex >= 0 else { return color.color }
        guard presetIndex < model.fillPresets.count else { return color.color }
        let preset = model.fillPresets[presetIndex]
        let stored = color.color
        #if os(iOS)
        let c = UIColor(stored)
        #else
        let c = NSColor(stored).usingColorSpace(.sRGB) ?? NSColor.black
        #endif
        var a: CGFloat = 0
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return preset.opacity(a)
    }
}

struct CodablePath: Codable {
    let points: [CodablePoint]

    init(_ path: CGPath) {
        var pts: [CodablePoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: pts.append(CodablePoint(e.points[0]))
            case .addLineToPoint: pts.append(CodablePoint(e.points[0]))
            case .addQuadCurveToPoint: pts.append(CodablePoint(e.points[0])); pts.append(CodablePoint(e.points[1]))
            case .addCurveToPoint: pts.append(CodablePoint(e.points[0])); pts.append(CodablePoint(e.points[1])); pts.append(CodablePoint(e.points[2]))
            case .closeSubpath: break
            @unknown default: break
            }
        }
        self.points = pts
    }

    var cgPath: CGPath {
        let raw = points.map(\.cgPoint)
        guard raw.count >= 2 else { return CGMutablePath() }
        let path = CGMutablePath()
        path.move(to: raw[0])
        for i in 1..<raw.count {
            path.addLine(to: raw[i])
        }
        path.closeSubpath()
        return path
    }
}

struct CodablePoint: Codable {
    let x: Double
    let y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

enum Tool: String, CaseIterable {
    case pen, eraser, fill, select, highlighter, laser
}

enum LaserMode: String, CaseIterable {
    case point = "Pointer Only"
    case tail = "Pointer with Tail"
}

struct LaserSettings {
    var mode: LaserMode = .point
    var tailFade: Double = 1.0
    var color: Color = .red
    var size: CGFloat = 6
}

enum CanvasBackground: String, CaseIterable {
    case none, grid, dots, ruled
}

struct AppSettings {
    var canvasBackground: CanvasBackground = .grid
    var isDarkMode: Bool = false {
        didSet {
            #if os(macOS)
            NSApp.appearance = isDarkMode ? NSAppearance(named: .darkAqua) : nil
            #endif
        }
    }
}

struct PenSettings {
    var lightColor: Color = .black
    var darkColor: Color = .white
    var thickness: CGFloat = 2
    var smoothness: CGFloat = 1
    var lightPresets: [Color] = [.black, .red, .orange, .yellow, .green, .blue, .purple, .brown]
    var darkPresets: [Color] = [
        Color(red: 0.96, green: 0.96, blue: 0.96),
        Color(red: 1.0, green: 0.6, blue: 0.6),
        Color(red: 1.0, green: 0.75, blue: 0.5),
        Color(red: 0.9, green: 0.9, blue: 0.5),
        Color(red: 0.6, green: 0.9, blue: 0.6),
        Color(red: 0.5, green: 0.8, blue: 1.0),
        Color(red: 0.75, green: 0.6, blue: 1.0),
        Color(red: 1.0, green: 0.6, blue: 0.8),
    ]
}

struct FillSettings {
    var lightColor: Color = .red
    var darkColor: Color = .red
    var opacity: Double = 0.25
    var lightPresets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint]
    var darkPresets: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple, .pink, .mint]
}

enum EraserMode: String, CaseIterable {
    case partial = "Partial"
    case full = "Full Stroke"
}

struct EraserSettings {
    var mode: EraserMode = .full
    var size: CGFloat = 20
}

struct HighlighterSettings {
    var lightColor: Color = .yellow
    var darkColor: Color = .yellow
    var thickness: CGFloat = 15
    var opacity: Double = 0.3
    var lightPresets: [Color] = [.yellow, .green, .cyan, .orange, .pink, .purple, .red, .blue]
    var darkPresets: [Color] = [.yellow, .green, .cyan, .orange, .pink, .purple, .red, .blue]
}

typealias CanvasSnapshot = (strokes: [Stroke], fillRegions: [FillRegion], selectedStrokeIds: Set<UUID>, selectedFillIds: Set<UUID>)

class DrawingModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var fillRegions: [FillRegion] = []
    @Published var currentTool: Tool = .pen
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    var currentStroke: Stroke?
    var previousTool: Tool = .pen
    @Published var penPresetIndex: Int = 0
    @Published var fillPresetIndex: Int = 0
    @Published var hlPresetIndex: Int = 0
    @Published var penSettings = PenSettings()
    @Published var fillSettings = FillSettings()
    @Published var eraserSettings = EraserSettings()
    @Published var highlighterSettings = HighlighterSettings()
    @Published var laserSettings = LaserSettings()
    @Published var appSettings = AppSettings()
    var openFileURL: URL? {
        didSet {
            if let url = openFileURL { addRecent(url) }
        }
    }

    @Published var recentFiles: [URL] = []

    private let recentKey = "recentFiles"
    private let maxRecent = 5

    init() {
        loadRecents()
        loadBoards()
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentKey) else { return }
        let urls = (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSURL.self], from: data)) as? [URL] ?? []
        recentFiles = urls
    }

    private func saveRecents() {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: recentFiles, requiringSecureCoding: false)
        UserDefaults.standard.set(data, forKey: recentKey)
    }

    private func addRecent(_ url: URL) {
        var files = recentFiles
        files.removeAll { $0.path == url.path }
        files.insert(url, at: 0)
        if files.count > maxRecent { files = Array(files.prefix(maxRecent)) }
        recentFiles = files
        saveRecents()
    }

    // MARK: - Default Settings

    private let defaultsKey = "savedDefaults"

    struct SettingsSnapshot: Codable {
        let penLightColor: CodableColor
        let penDarkColor: CodableColor
        let penThickness: CGFloat
        let penSmoothness: CGFloat
        let fillLightColor: CodableColor
        let fillDarkColor: CodableColor
        let fillOpacity: Double
        let hlLightColor: CodableColor
        let hlDarkColor: CodableColor
        let hlThickness: CGFloat
        let hlOpacity: Double
        let eraserSize: CGFloat
        let eraserMode: String
        let canvasBg: String
        let isDarkMode: Bool
    }

    func saveDefaults() {
        let s = SettingsSnapshot(
            penLightColor: CodableColor(penSettings.lightColor),
            penDarkColor: CodableColor(penSettings.darkColor),
            penThickness: penSettings.thickness,
            penSmoothness: penSettings.smoothness,
            fillLightColor: CodableColor(fillSettings.lightColor),
            fillDarkColor: CodableColor(fillSettings.darkColor),
            fillOpacity: fillSettings.opacity,
            hlLightColor: CodableColor(highlighterSettings.lightColor),
            hlDarkColor: CodableColor(highlighterSettings.darkColor),
            hlThickness: highlighterSettings.thickness,
            hlOpacity: highlighterSettings.opacity,
            eraserSize: eraserSettings.size,
            eraserMode: eraserSettings.mode.rawValue,
            canvasBg: appSettings.canvasBackground.rawValue,
            isDarkMode: appSettings.isDarkMode
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func loadDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(SettingsSnapshot.self, from: data) else { return }
        penSettings.lightColor = s.penLightColor.color
        penSettings.darkColor = s.penDarkColor.color
        penSettings.thickness = s.penThickness
        penSettings.smoothness = s.penSmoothness
        fillSettings.lightColor = s.fillLightColor.color
        fillSettings.darkColor = s.fillDarkColor.color
        fillSettings.opacity = s.fillOpacity
        highlighterSettings.lightColor = s.hlLightColor.color
        highlighterSettings.darkColor = s.hlDarkColor.color
        highlighterSettings.thickness = s.hlThickness
        highlighterSettings.opacity = s.hlOpacity
        eraserSettings.size = s.eraserSize
        eraserSettings.mode = EraserMode(rawValue: s.eraserMode) ?? .partial
        appSettings.canvasBackground = CanvasBackground(rawValue: s.canvasBg) ?? .grid
        appSettings.isDarkMode = s.isDarkMode
    }

    func resetToFactory() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        penSettings = PenSettings()
        fillSettings = FillSettings()
        highlighterSettings = HighlighterSettings()
        laserSettings = LaserSettings()
        eraserSettings = EraserSettings()
        appSettings = AppSettings()
    }

    var hasDefaults: Bool {
        UserDefaults.standard.data(forKey: defaultsKey) != nil
    }

    // MARK: - Board Storage

    private var boardsDir: URL {
        let fm = FileManager.default
        #if os(macOS)
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #else
        let appSupport = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
        let dir = appSupport.appendingPathComponent("com.whiteboard.boards")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL { boardsDir.appendingPathComponent("boards.json") }

    struct BoardMeta: Codable, Identifiable {
        var id: String
        var name: String
        var created: Date
        var modified: Date
    }

    @Published var boards: [BoardMeta] = []
    @Published var folders: [BoardFolder] = []
    @Published var currentBoardId: String?

    struct BoardFolder: Codable, Identifiable {
        var id: String
        var name: String
        var boardIds: [String]
    }

    func loadBoards() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode(BoardIndex.self, from: data) else {
            boards = []; folders = []; return
        }
        boards = list.boards.sorted { $0.modified > $1.modified }
        folders = list.folders
    }

    private struct BoardIndex: Codable {
        var boards: [BoardMeta]
        var folders: [BoardFolder]
    }

    private func saveBoards() {
        let index = BoardIndex(boards: boards, folders: folders)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func createBoard(name: String, folderId: String? = nil) {
        let id = UUID().uuidString.prefix(8).lowercased()
        let meta = BoardMeta(id: String(id), name: name, created: Date(), modified: Date())
        boards.insert(meta, at: 0)
        if let fid = folderId, let idx = folders.firstIndex(where: { $0.id == fid }) {
            folders[idx].boardIds.insert(String(id), at: 0)
        }
        saveBoards()
        currentBoardId = meta.id
        openFileURL = boardURL(for: meta.id)
        clear()
    }

    func renameBoard(id: String, to newName: String) {
        guard let idx = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[idx].name = newName
        boards[idx].modified = Date()
        saveBoards()
    }

    // MARK: - Folders

    func createFolder(name: String) {
        let id = UUID().uuidString.prefix(8).lowercased()
        folders.append(BoardFolder(id: String(id), name: name, boardIds: []))
        saveBoards()
    }

    func renameFolder(id: String, to newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = newName
        saveBoards()
    }

    func deleteFolder(id: String) {
        folders.removeAll { $0.id == id }
        saveBoards()
    }

    func moveBoard(boardId: String, toFolder folderId: String?) {
        for fi in folders.indices { folders[fi].boardIds.removeAll { $0 == boardId } }
        if let fid = folderId, let idx = folders.firstIndex(where: { $0.id == fid }) {
            folders[idx].boardIds.append(boardId)
        }
        saveBoards()
    }

    func boardIdsInFolder(_ folderId: String) -> [String] {
        folders.first(where: { $0.id == folderId })?.boardIds ?? []
    }

    func deleteBoard(id: String) {
        let src = boardURL(for: id)
        let trashDir = boardsDir.appendingPathComponent(".trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let dst = trashDir.appendingPathComponent("\(id)_\(Date().timeIntervalSince1970).wb")
        try? FileManager.default.moveItem(at: src, to: dst)
        boards.removeAll { $0.id == id }
        for fi in folders.indices { folders[fi].boardIds.removeAll { $0 == id } }
        saveBoards()
        if currentBoardId == id { currentBoardId = nil }
        cleanTrash()
    }

    func restoreBoard(id: String) -> Bool {
        let trashDir = boardsDir.appendingPathComponent(".trash", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil) else { return false }
        let match = files.first { $0.lastPathComponent.hasPrefix("\(id)_") }
        guard let src = match else { return false }
        guard let data = try? Data(contentsOf: src) else { return false }
        // Extract original name from the board index (or use a fallback)
        let indexURL = trashDir.appendingPathComponent("trash_index.json")
        var trashIndex: [TrashEntry] = (try? JSONDecoder().decode([TrashEntry].self, from: Data(contentsOf: indexURL))) ?? []
        let entry = trashIndex.first(where: { $0.id == id })
        let name = entry?.name ?? "Restored Board"
        createBoard(name: name)
        if let current = currentBoardId {
            let dst = boardURL(for: current)
            try? data.write(to: dst, options: .atomic)
            loadBoard(id: current)
            // Reload from the written file
            if let reload = try? Data(contentsOf: dst),
               let saved = try? JSONDecoder().decode(SaveData.self, from: reload) {
                strokes = saved.strokes
                fillRegions = saved.fillRegions
            }
        }
        try? FileManager.default.removeItem(at: src)
        trashIndex.removeAll { $0.id == id }
        if let updated = try? JSONEncoder().encode(trashIndex) { try? updated.write(to: indexURL) }
        return true
    }

    struct TrashEntry: Codable {
        let id: String
        let name: String
        let deletedAt: Date
    }

    @Published var trashedBoards: [TrashEntry] = []

    func loadTrash() {
        let trashDir = boardsDir.appendingPathComponent(".trash", isDirectory: true)
        let indexURL = trashDir.appendingPathComponent("trash_index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([TrashEntry].self, from: data) else {
            trashedBoards = []; return
        }
        trashedBoards = list.sorted { $0.deletedAt > $1.deletedAt }
    }

    private func cleanTrash() {
        let trashDir = boardsDir.appendingPathComponent(".trash", isDirectory: true)
        let indexURL = trashDir.appendingPathComponent("trash_index.json")
        let index: [TrashEntry] = (try? JSONDecoder().decode([TrashEntry].self, from: Data(contentsOf: indexURL))) ?? []
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let remaining = index.filter { $0.deletedAt > cutoff }
        // Remove files older than 30 days
        for entry in index where entry.deletedAt <= cutoff {
            let file = trashDir.appendingPathComponent("\(entry.id)_\(entry.deletedAt.timeIntervalSince1970).wb")
            try? FileManager.default.removeItem(at: file)
        }
        if remaining.count != index.count {
            if let data = try? JSONEncoder().encode(remaining) { try? data.write(to: indexURL) }
        }
        loadTrash()
    }

    func trashBoard(id: String, name: String) {
        let entry = TrashEntry(id: id, name: name, deletedAt: Date())
        let trashDir = boardsDir.appendingPathComponent(".trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let indexURL = trashDir.appendingPathComponent("trash_index.json")
        var index: [TrashEntry] = (try? JSONDecoder().decode([TrashEntry].self, from: Data(contentsOf: indexURL))) ?? []
        index.append(entry)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL) }
        deleteBoard(id: id)
    }

    func loadBoard(id: String) {
        let url = boardURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let save = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        saveState()
        strokes = save.strokes
        fillRegions = save.fillRegions
        currentBoardId = id
        openFileURL = url
        updateUndoRedo()
    }

    private func boardURL(for id: String) -> URL {
        boardsDir.appendingPathComponent("\(id).wb")
    }

    func openBoardByID(_ id: String) {
        loadBoard(id: id)
    }

    // MARK: - Auto-save

    private var saveWorkItem: DispatchWorkItem?

    private func scheduleAutoSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.performAutoSave() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func performAutoSave() {
        guard let id = currentBoardId, let data = saveData() else { return }
        try? data.write(to: boardURL(for: id), options: .atomic)
        if let idx = boards.firstIndex(where: { $0.id == id }) {
            boards[idx].modified = Date()
            saveBoards()
        }
    }

    // Theme-aware colors
    var penColor: Color { appSettings.isDarkMode ? penSettings.darkColor : penSettings.lightColor }
    var penPresets: [Color] { appSettings.isDarkMode ? penSettings.darkPresets : penSettings.lightPresets }
    var fillColor: Color { appSettings.isDarkMode ? fillSettings.darkColor : fillSettings.lightColor }
    var fillPresets: [Color] { appSettings.isDarkMode ? fillSettings.darkPresets : fillSettings.lightPresets }
    var hlColor: Color { appSettings.isDarkMode ? highlighterSettings.darkColor : highlighterSettings.lightColor }
    var hlPresets: [Color] { appSettings.isDarkMode ? highlighterSettings.darkPresets : highlighterSettings.lightPresets }
    @Published var selectionLasso: [CGPoint] = []
    @Published var selectionBoundary: [CGPoint] = []
    @Published var selectedStrokeIds: Set<UUID> = []
    @Published var selectedFillIds: Set<UUID> = []
    @Published var fillLassoPoints: [CGPoint] = []
    var laserTail: [(point: CGPoint, time: Date)] = []
    var laserPointer: CGPoint?
    var laserTailFadeStart: Date?
    var laserTailFading: Bool { laserTailFadeStart != nil }

    private var undoStack: [CanvasSnapshot] = []
    private var redoStack: [CanvasSnapshot] = []

    private func saveState() {
        undoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds))
        redoStack.removeAll()
        canUndo = true
        canRedo = false
        scheduleAutoSave()
    }

    private func updateUndoRedo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func beginStroke(at point: CGPoint, isEraser: Bool) {
        let isHighlight = currentTool == .highlighter
        let pIdx: Int
        if isEraser { pIdx = -1 }
        else if isHighlight { pIdx = hlPresetIndex }
        else { pIdx = penPresetIndex }
        currentStroke = Stroke(
            points: [point],
            color: isEraser ? .white : isHighlight ? hlColor : penColor,
            lineWidth: isEraser ? eraserSettings.size : isHighlight ? highlighterSettings.thickness : penSettings.thickness,
            isEraser: isEraser,
            isHighlighter: isHighlight,
            presetIndex: pIdx
        )
    }

    func addPoint(_ point: CGPoint) {
        currentStroke?.points.append(point)
    }

    func endStroke() {
        guard let stroke = currentStroke else { currentStroke = nil; return }
        currentStroke = nil

        saveState()

        if stroke.isEraser {
            erase(stroke)
            return
        } else if stroke.points.count >= 2 {
            var finalStroke = stroke
            if penSettings.smoothness > 1 && !stroke.isEraser && stroke.lineWidth < 10 {
                let eps = (penSettings.smoothness - 1) * 0.05
                let simplified = simplify(stroke.points, epsilon: eps)
                if simplified.count >= 2 {
                    finalStroke = Stroke(id: stroke.id, points: simplified, color: stroke.uiColor, lineWidth: stroke.lineWidth, isEraser: false, isHighlighter: stroke.isHighlighter)
                }
            }
            strokes.append(finalStroke)
        }
        updateUndoRedo()
    }

    // MARK: - Lasso Selection

    func beginLasso(at point: CGPoint) {
        selectionLasso = [point]
    }

    func addLassoPoint(_ point: CGPoint) {
        selectionLasso.append(point)
    }

    func endLasso() {
        guard selectionLasso.count >= 3 else { selectionLasso = []; return }

        saveState()

        let path = CGMutablePath()
        path.move(to: selectionLasso[0])
        for i in 1..<selectionLasso.count {
            path.addLine(to: selectionLasso[i])
        }
        path.closeSubpath()

        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()

        for stroke in strokes where !stroke.isEraser {
            for p in stroke.points {
                if path.contains(p) {
                    selectedStrokeIds.insert(stroke.id)
                    break
                }
            }
        }

        for region in fillRegions {
            let box = region.cgPath.boundingBox
            let center = CGPoint(x: box.midX, y: box.midY)
            if path.contains(center) || path.contains(box.origin) {
                selectedFillIds.insert(region.id)
            }
        }

        selectionBoundary = selectionLasso
        selectionLasso = []
        updateUndoRedo()
    }

    // MARK: - Fill Lasso

    func beginFillLasso(at point: CGPoint) {
        fillLassoPoints = [point]
    }

    func addFillLassoPoint(_ point: CGPoint) {
        if let last = fillLassoPoints.last, last.distance(to: point) < 1 { return }
        fillLassoPoints.append(point)
    }

    func endFillLasso() {
        let pts = fillLassoPoints
        fillLassoPoints = []
        os_log("[fillLasso] endFillLasso pts=%d", type: .debug, pts.count)
        guard !pts.isEmpty else { os_log("[fillLasso] empty pts", type: .debug); return }

        if pts.count == 1 {
            os_log("[fillLasso] single-point tap → performFill", type: .debug)
            performFill(at: pts[0])
            return
        }

        var totalDist: CGFloat = 0
        for i in 1..<pts.count { totalDist += pts[i - 1].distance(to: pts[i]) }
        os_log("[fillLasso] multi-point tap totalDist=%.2f", type: .debug, totalDist)

        if totalDist < 15 {
            os_log("[fillLasso] short motion treat as tap → performFill", type: .debug)
            performFill(at: pts.last!)
            return
        }

        os_log("[fillLasso] long stroke → closed-figure fill pts=%d totalDist=%.1f", type: .debug, pts.count, totalDist)
        saveState()

        // Build the lasso path
        let lassoPath = CGMutablePath()
        lassoPath.move(to: pts[0])
        for i in 1..<pts.count { lassoPath.addLine(to: pts[i]) }
        lassoPath.closeSubpath()

        // Try to find a stroke-bounded enclosure within the lasso.
        // Use the centroid of the lasso as the fill tap point.
        let centroid = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(x: centroid.x / CGFloat(pts.count), y: centroid.y / CGFloat(pts.count))
        var fillPath: CGPath = lassoPath
        if let enclosure = FloodFill.fillPath(at: center, strokes: strokes) {
            // Use the DCEL-found enclosure (bounded by strokes)
            fillPath = enclosure
        }

        let region = FillRegion(path: fillPath, color: fillColor.opacity(fillSettings.opacity), presetIndex: fillPresetIndex)
        fillRegions.append(region)
        updateUndoRedo()
    }

    // MARK: - Move Selection

    var isMoving: Bool = false
    var lastMovePoint: CGPoint = .zero
    private var moveDidChange: Bool = false

    func isPointOnSelectedItem(_ point: CGPoint) -> Bool {
        let threshold: CGFloat = 15
        for s in strokes where selectedStrokeIds.contains(s.id) {
            for i in 0..<s.points.count - 1 {
                let d = pointSegDist(point, s.points[i], s.points[i + 1])
                if d < threshold { return true }
            }
        }
        for r in fillRegions where selectedFillIds.contains(r.id) {
            if r.cgPath.contains(point) { return true }
        }
        return false
    }

    func beginMove(at point: CGPoint) {
        guard isPointOnSelectedItem(point) else {
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectionBoundary.removeAll()
            beginLasso(at: point)
            return
        }
        isMoving = true
        lastMovePoint = point
        moveDidChange = false
    }

    func commitMove() {
        guard isMoving else { return }
        isMoving = false
        if moveDidChange {
            saveState()
            updateUndoRedo()
        }
    }

    func moveSelected(by offset: CGSize) {
        guard isMoving, offset != .zero else { return }
        moveDidChange = true
        strokes = strokes.map { s in
            guard selectedStrokeIds.contains(s.id) else { return s }
            return Stroke(id: s.id, points: s.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) },
                           color: s.uiColor, lineWidth: s.lineWidth, isEraser: s.isEraser, isHighlighter: s.isHighlighter)
        }
        fillRegions = fillRegions.map { r in
            guard selectedFillIds.contains(r.id) else { return r }
            var t = CGAffineTransform(translationX: offset.width, y: offset.height)
            let newPath = r.cgPath.copy(using: &t) ?? r.cgPath
            return FillRegion(id: r.id, path: newPath, color: r.uiColor)
        }
        if !selectionBoundary.isEmpty {
            selectionBoundary = selectionBoundary.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }

    // MARK: - Delete Selected

    private func pointSegDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq != 0 else { return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let px = a.x + t * dx, py = a.y + t * dy
        return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py))
    }

    // MARK: - RDP simplification

    func simplified(_ points: [CGPoint]) -> [CGPoint] {
        guard penSettings.smoothness > 1 else { return points }
        let eps = (penSettings.smoothness - 1) * 0.05
        let result = simplify(points, epsilon: eps)
        return result.count >= 2 ? result : points
    }

    private func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var dmax: CGFloat = 0
        var idx = 0
        for i in 1..<points.count - 1 {
            let d = perpDist(points[i], points[0], points[points.count - 1])
            if d > dmax { dmax = d; idx = i }
        }
        if dmax > epsilon {
            return simplify(Array(points[0...idx]), epsilon: epsilon).dropLast()
                + simplify(Array(points[idx..<points.count]), epsilon: epsilon)
        }
        return [points[0], points[points.count - 1]]
    }

    private func perpDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq != 0 else { return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let px = a.x + t * dx, py = a.y + t * dy
        return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py))
    }

    func deleteSelected() {
        guard !selectedStrokeIds.isEmpty || !selectedFillIds.isEmpty else {
            clear()
            return
        }
        saveState()
        strokes = strokes.filter { !selectedStrokeIds.contains($0.id) }
        fillRegions = fillRegions.filter { !selectedFillIds.contains($0.id) }
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Eraser

    private func erase(_ eraser: Stroke) {
        let threshold = eraser.lineWidth / 2
        let oldStrokes = strokes
        let oldFills = fillRegions

        let hitByEraser: (Stroke) -> Bool = { pen in
            pen.points.contains { pp in
                eraser.points.contains { ep in
                    let dx = pp.x - ep.x, dy = pp.y - ep.y
                    return sqrt(dx * dx + dy * dy) < threshold
                }
            }
        }

        if self.eraserSettings.mode == .full {
            self.strokes = oldStrokes.filter { $0.isEraser || !hitByEraser($0) }
        } else {
            var newStrokes: [Stroke] = []
            for pen in oldStrokes where !pen.isEraser {
                var segment: [CGPoint] = []
                for pp in pen.points {
                    let isErased = eraser.points.contains { ep in
                        let dx = pp.x - ep.x, dy = pp.y - ep.y
                        return sqrt(dx * dx + dy * dy) < threshold
                    }
                    if isErased {
                        if segment.count >= 2 {
                            newStrokes.append(Stroke(points: segment, color: pen.uiColor, lineWidth: pen.lineWidth, isEraser: false, isHighlighter: pen.isHighlighter))
                        }
                        segment = []
                    } else {
                        segment.append(pp)
                    }
                }
                if segment.count >= 2 {
                    newStrokes.append(Stroke(points: segment, color: pen.uiColor, lineWidth: pen.lineWidth, isEraser: false, isHighlighter: pen.isHighlighter))
                }
            }
            self.strokes = newStrokes
        }

        self.fillRegions = oldFills.filter { region in
            for ep in eraser.points {
                if region.cgPath.contains(ep) { return false }
            }
            return true
        }
        self.updateUndoRedo()
        self.scheduleAutoSave()
    }

    // MARK: - Fill

    func performFill(at canvasPoint: CGPoint) {
        os_log("[fillLasso] performFill at (%.1f, %.1f)", type: .debug, canvasPoint.x, canvasPoint.y)
        saveState()
        guard let path = FloodFill.fillPath(at: canvasPoint, strokes: strokes) else {
            os_log("[fillLasso] performFill no path found", type: .debug)
            updateUndoRedo()
            return
        }
        os_log("[fillLasso] performFill got path area=%.1f", type: .debug, abs(path.boundingBox.width * path.boundingBox.height))
        let region = FillRegion(path: path, color: fillColor.opacity(fillSettings.opacity), presetIndex: fillPresetIndex)
        fillRegions.append(region)
        updateUndoRedo()
    }

    func selectTool(_ tool: Tool) {
        currentTool = tool
        if tool != .select {
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectionBoundary.removeAll()
        }
        if tool != .laser {
            laserTail.removeAll()
            laserPointer = nil
        }
        fillLassoPoints = []
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds))
        let prev = undoStack.removeLast()
        strokes = prev.strokes
        fillRegions = prev.fillRegions
        selectedStrokeIds = prev.selectedStrokeIds
        selectedFillIds = prev.selectedFillIds
        updateUndoRedo()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds))
        let next = redoStack.removeLast()
        strokes = next.strokes
        fillRegions = next.fillRegions
        selectedStrokeIds = next.selectedStrokeIds
        selectedFillIds = next.selectedFillIds
        updateUndoRedo()
    }

    func clear() {
        saveState()
        strokes.removeAll()
        fillRegions.removeAll()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectionLasso.removeAll()
        selectionBoundary.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoRedo()
    }

    // MARK: - Save / Load / Export

    private struct SaveData: Codable {
        let strokes: [Stroke]
        let fillRegions: [FillRegion]
    }

    func saveData() -> Data? {
        let data = SaveData(strokes: strokes, fillRegions: fillRegions)
        return try? JSONEncoder().encode(data)
    }

    func loadData(_ data: Data) {
        guard let save = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        saveState()
        strokes = save.strokes
        fillRegions = save.fillRegions
        updateUndoRedo()
    }

    func save() {
        guard let url = openFileURL else { return }
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
        if let data = saveData() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Menu command helpers (triggered by menu bar or keyboard)

    func openCmd() { pendingAction = .open }
    func closeBoard() { showWelcome = true }
    func exportPNG() { pendingAction = .export(.png) }
    func exportPDF() { pendingAction = .export(.pdf) }

    enum PendingAction: Equatable {
        case open
        case export(ExportFormat)
    }

    enum ExportFormat: String { case png, pdf }
    @Published var pendingAction: PendingAction?
    @Published var isToolbarVisible: Bool = true
    @Published var showWelcome: Bool = true
    @Published var needsRecenter: Bool = false
    @Published var welcomeFolderName: String?
    @Published var showRadialMenu: Bool = false
    var radialMenuCenter: CGPoint = .zero

    func pngData(size: CGSize, offset: CGPoint = .zero, scale: CGFloat = 3) -> Data? {
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard w > 0, h > 0, w <= 8192, h <= 8192 else { return nil }

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Map canvas (y-down) → bitmap (CG y-up) so content top-left is at output origin
        ctx.translateBy(x: -offset.x * scale, y: CGFloat(h) + offset.y * scale)
        ctx.scaleBy(x: scale, y: -scale)

        // Render fills
        for r in fillRegions {
            ctx.setFillColor(r.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.beginPath()
            ctx.addPath(r.cgPath)
            ctx.fillPath()
        }

        // Render highlighter strokes as a group with uniform opacity
        let hlOpacity = CGFloat(highlighterSettings.opacity)
        if !strokes.contains(where: \.isHighlighter) == false {
            ctx.saveGState()
            ctx.setAlpha(hlOpacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            renderStrokesForExport(strokes.filter(\.isHighlighter), ctx: ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        // Pen and eraser strokes
        renderStrokesForExport(strokes.filter { !$0.isHighlighter }, ctx: ctx)

        guard let image = ctx.makeImage() else { return nil }
        let cfData = CFDataCreateMutable(nil, 0)
        guard let dest = CGImageDestinationCreateWithData(cfData!, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return cfData! as Data
    }

    private func renderStrokesForExport(_ strokes: [Stroke], ctx: CGContext) {
        for s in strokes { renderStrokeForExport(s, ctx: ctx) }
    }

    private func renderStrokeForExport(_ s: Stroke, ctx: CGContext) {
        guard s.points.count >= 2 else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if s.isEraser {
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(s.lineWidth)
        } else {
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(s.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(s.lineWidth)
        }
        ctx.addLines(between: s.points)
        ctx.strokePath()
        ctx.restoreGState()
    }

    func pdfData(size: CGSize, offset: CGPoint = .zero) -> Data? {
        let rect = CGRect(origin: .zero, size: size)
        let cfData = CFDataCreateMutable(nil, 0)
        guard let consumer = CGDataConsumer(data: cfData!) else { return nil }
        var mediaBox = rect
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        pdf.beginPDFPage(nil)
        renderToContext(pdf, size: size, offset: offset)
        pdf.endPDFPage()
        pdf.closePDF()
        return cfData! as Data
    }

    private func renderToContext(_ ctx: CGContext, size: CGSize, offset: CGPoint = .zero) {
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.translateBy(x: -offset.x, y: size.height + offset.y)
        ctx.scaleBy(x: 1, y: -1)

        for r in fillRegions {
            ctx.setFillColor(r.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.beginPath()
            ctx.addPath(r.cgPath)
            ctx.fillPath()
        }
        let hlOpacity = CGFloat(highlighterSettings.opacity)
        if strokes.contains(where: \.isHighlighter) {
            ctx.saveGState()
            ctx.setAlpha(hlOpacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for s in strokes where s.isHighlighter { renderStrokeForExport(s, ctx: ctx) }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        for s in strokes where !s.isHighlighter { renderStrokeForExport(s, ctx: ctx) }
    }

    // MARK: - Thumbnail

    func thumbnail(for boardId: String, size: CGSize = CGSize(width: 240, height: 320)) -> PlatformImage? {
        // Use in-memory strokes if this is the current board
        if boardId == currentBoardId {
            guard !strokes.isEmpty || !fillRegions.isEmpty else { return nil }
            return renderThumbnail(strokes: strokes, fillRegions: fillRegions, size: size)
        }
        // Otherwise load from disk
        let url = boardURL(for: boardId)
        guard let data = try? Data(contentsOf: url),
              let save = try? JSONDecoder().decode(SaveData.self, from: data) else { return nil }
        return renderThumbnail(strokes: save.strokes, fillRegions: save.fillRegions, size: size)
    }

    private func renderThumbnail(strokes: [Stroke], fillRegions: [FillRegion], size: CGSize) -> PlatformImage? {
        let isDark = appSettings.isDarkMode
        let w = Int(size.width), h = Int(size.height)
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        if isDark {
            ctx.setFillColor(CGColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1))
        } else {
            ctx.setFillColor(gray: 1, alpha: 1)
        }
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        var minX: CGFloat = .greatestFiniteMagnitude, maxX: CGFloat = 0
        var minY: CGFloat = .greatestFiniteMagnitude, maxY: CGFloat = 0
        for s in strokes { for p in s.points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) } }
        for r in fillRegions { let box = r.cgPath.boundingBox; if !box.isNull { minX = min(minX, box.minX); maxX = max(maxX, box.maxX); minY = min(minY, box.minY); maxY = max(maxY, box.maxY) } }
        guard maxX > minX, maxY > minY else { return nil }

        let pad: CGFloat = 10, cw = maxX - minX + pad * 2, ch = maxY - minY + pad * 2
        let sc = min(CGFloat(w) / cw, CGFloat(h) / ch) * 0.9
        let ox = (CGFloat(w) - cw * sc) / 2 - (minX - pad) * sc
        let oy = (CGFloat(h) - ch * sc) / 2 - (minY - pad) * sc

        ctx.translateBy(x: ox, y: oy + CGFloat(h))
        ctx.scaleBy(x: sc, y: -sc)

        for r in fillRegions { ctx.setFillColor(r.uiColor.cgColor ?? CGColor(gray: 0.5, alpha: 1)); ctx.beginPath(); ctx.addPath(r.cgPath); ctx.fillPath() }
        for s in strokes where !s.isEraser {
            ctx.saveGState(); ctx.setLineCap(CGLineCap.round); ctx.setLineJoin(CGLineJoin.round)
            ctx.setStrokeColor(s.uiColor.cgColor ?? CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(max(s.lineWidth, 1))
            ctx.addLines(between: s.points); ctx.strokePath(); ctx.restoreGState()
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}
