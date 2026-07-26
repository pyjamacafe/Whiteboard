import Combine
import SwiftUI
import UniformTypeIdentifiers
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
    let presetIndex: Int
    let isCatmullRom: Bool

    init(id: UUID = UUID(), points: [CGPoint], color: Color, lineWidth: CGFloat, isEraser: Bool, isHighlighter: Bool, presetIndex: Int = -1, isCatmullRom: Bool = false) {
        self.id = id
        self.points = points
        self.color = CodableColor(color)
        self.lineWidth = lineWidth
        self.isEraser = isEraser
        self.isHighlighter = isHighlighter
        self.presetIndex = presetIndex
        self.isCatmullRom = isCatmullRom
    }

    enum CodingKeys: String, CodingKey {
        case id, points, color, lineWidth, isEraser, isHighlighter, presetIndex, isCatmullRom
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
        isCatmullRom = try c.decodeIfPresent(Bool.self, forKey: .isCatmullRom) ?? false
    }

    var uiColor: Color { color.color }

    func displayColor(for model: DrawingModel) -> Color {
        if presetIndex >= 0 {
            if isHighlighter {
                guard presetIndex < model.hlPresets.count else { return color.color }
                return model.hlPresets[presetIndex]
            } else {
                guard presetIndex < model.penPresets.count else { return color.color }
                return model.penPresets[presetIndex]
            }
        }
        return color.color
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

struct PlacedImage: Identifiable, Codable {
    var id = UUID()
    var position: CodablePoint
    var size: CodablePoint  // stored as (width, height)
    let imageData: Data

    init(id: UUID = UUID(), position: CGPoint, size: CGSize, imageData: Data) {
        self.id = id
        self.position = CodablePoint(position)
        self.size = CodablePoint(CGPoint(x: size.width, y: size.height))
        self.imageData = imageData
    }

    var cgPosition: CGPoint { position.cgPoint }
    var cgSize: CGSize { CGSize(width: size.cgPoint.x, height: size.cgPoint.y) }
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

enum CanvasBackground: String, CaseIterable {
    case none, grid, dots, ruled
}

struct AppSettings {
    var canvasBackground: CanvasBackground = .grid
    var revealSettingsOnSingleTap: Bool = true
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
    let widthOptions: [CGFloat] = [2, 2.5, 3, 3.5, 4]
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
    let opacityOptions: [Double] = [0.10, 0.25, 0.50, 0.75, 1.0]
    var lightPresets: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint]
    var darkPresets: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple, .pink, .mint]
}

enum EraserMode: String, CaseIterable {
    case partial = "Partial"
    case full = "Full Stroke"
}

struct EraserSettings {
    var mode: EraserMode = .full
    var size: CGFloat = 10
}

struct HighlighterSettings {
    var lightColor: Color = .yellow
    var darkColor: Color = .yellow
    var thickness: CGFloat = 10
    let opacity: Double = 0.3
    let thicknessOptions: [CGFloat] = [10, 15, 20, 25, 30]
    var lightPresets: [Color] = [.yellow, .green, .cyan, .orange, .pink, .purple, .red, .blue]
    var darkPresets: [Color] = [.yellow, .green, .cyan, .orange, .pink, .purple, .red, .blue]
}

struct LaserSettings {
    var retainStrokes: Bool = false
    let tailFade: Double = 3.0
    var size: CGFloat = 1.5
}

typealias CanvasSnapshot = (strokes: [Stroke], fillRegions: [FillRegion], selectedStrokeIds: Set<UUID>, selectedFillIds: Set<UUID>, selectedImageIds: Set<UUID>, laserStrokes: [(points: [CGPoint], time: Date, isRetained: Bool)])

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
    @Published var laserSettings = LaserSettings() {
        didSet {
            if !laserSettings.retainStrokes {
                persistentLaserStrokes.removeAll()
            }
        }
    }
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
        let fillLightColor: CodableColor
        let fillDarkColor: CodableColor
        let fillOpacity: Double
        let hlLightColor: CodableColor
        let hlDarkColor: CodableColor
        let hlThickness: CGFloat
        let eraserSize: CGFloat
        let eraserMode: String
        let canvasBg: String
        let isDarkMode: Bool
        let revealSettingsOnSingleTap: Bool

        enum CodingKeys: String, CodingKey {
            case penLightColor, penDarkColor, penThickness,
                 fillLightColor, fillDarkColor, fillOpacity,
                 hlLightColor, hlDarkColor, hlThickness,
                 eraserSize, eraserMode, canvasBg, isDarkMode, revealSettingsOnSingleTap
        }

        init(penLightColor: CodableColor, penDarkColor: CodableColor, penThickness: CGFloat,
             fillLightColor: CodableColor, fillDarkColor: CodableColor, fillOpacity: Double,
             hlLightColor: CodableColor, hlDarkColor: CodableColor, hlThickness: CGFloat,
             eraserSize: CGFloat, eraserMode: String, canvasBg: String, isDarkMode: Bool, revealSettingsOnSingleTap: Bool) {
            self.penLightColor = penLightColor
            self.penDarkColor = penDarkColor
            self.penThickness = penThickness
            self.fillLightColor = fillLightColor
            self.fillDarkColor = fillDarkColor
            self.fillOpacity = fillOpacity
            self.hlLightColor = hlLightColor
            self.hlDarkColor = hlDarkColor
            self.hlThickness = hlThickness
            self.eraserSize = eraserSize
            self.eraserMode = eraserMode
            self.canvasBg = canvasBg
            self.isDarkMode = isDarkMode
            self.revealSettingsOnSingleTap = revealSettingsOnSingleTap
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            penLightColor = try c.decode(CodableColor.self, forKey: .penLightColor)
            penDarkColor = try c.decode(CodableColor.self, forKey: .penDarkColor)
            penThickness = try c.decode(CGFloat.self, forKey: .penThickness)
            fillLightColor = try c.decode(CodableColor.self, forKey: .fillLightColor)
            fillDarkColor = try c.decode(CodableColor.self, forKey: .fillDarkColor)
            fillOpacity = try c.decode(Double.self, forKey: .fillOpacity)
            hlLightColor = try c.decode(CodableColor.self, forKey: .hlLightColor)
            hlDarkColor = try c.decode(CodableColor.self, forKey: .hlDarkColor)
            hlThickness = try c.decode(CGFloat.self, forKey: .hlThickness)
            eraserSize = try c.decode(CGFloat.self, forKey: .eraserSize)
            eraserMode = try c.decode(String.self, forKey: .eraserMode)
            canvasBg = try c.decode(String.self, forKey: .canvasBg)
            isDarkMode = try c.decode(Bool.self, forKey: .isDarkMode)
            revealSettingsOnSingleTap = try c.decodeIfPresent(Bool.self, forKey: .revealSettingsOnSingleTap) ?? true
        }
    }

    func saveDefaults() {
        let s = SettingsSnapshot(
            penLightColor: CodableColor(penSettings.lightColor),
            penDarkColor: CodableColor(penSettings.darkColor),
            penThickness: penSettings.thickness,
            fillLightColor: CodableColor(fillSettings.lightColor),
            fillDarkColor: CodableColor(fillSettings.darkColor),
            fillOpacity: fillSettings.opacity,
            hlLightColor: CodableColor(highlighterSettings.lightColor),
            hlDarkColor: CodableColor(highlighterSettings.darkColor),
            hlThickness: highlighterSettings.thickness,
            eraserSize: eraserSettings.size,
            eraserMode: eraserSettings.mode.rawValue,
            canvasBg: appSettings.canvasBackground.rawValue,
            isDarkMode: appSettings.isDarkMode,
            revealSettingsOnSingleTap: appSettings.revealSettingsOnSingleTap
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
        fillSettings.lightColor = s.fillLightColor.color
        fillSettings.darkColor = s.fillDarkColor.color
        fillSettings.opacity = s.fillOpacity
        highlighterSettings.lightColor = s.hlLightColor.color
        highlighterSettings.darkColor = s.hlDarkColor.color
        highlighterSettings.thickness = s.hlThickness
        eraserSettings.size = s.eraserSize
        eraserSettings.mode = EraserMode(rawValue: s.eraserMode) ?? .partial
        appSettings.canvasBackground = CanvasBackground(rawValue: s.canvasBg) ?? .grid
        appSettings.isDarkMode = s.isDarkMode
        appSettings.revealSettingsOnSingleTap = s.revealSettingsOnSingleTap
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
        placedImages = save.placedImages
        imageCache.removeAll()
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
    @Published var selectedImageIds: Set<UUID> = []
    @Published var placedImages: [PlacedImage] = []
    var imageCache: [UUID: Any] = [:]  // UIImage on iOS, NSImage on macOS
    @Published var fillLassoPoints: [CGPoint] = []
    var laserTail: [(point: CGPoint, time: Date)] = []
    var laserPointer: CGPoint?
    var laserTailFadeStart: Date?
    var persistentLaserStrokes: [(points: [CGPoint], time: Date, isRetained: Bool)] = []
    var lastCanvasTapLocation: CGPoint = .zero
    var laserTailFading: Bool { laserTailFadeStart != nil }

    private var undoStack: [CanvasSnapshot] = []
    private var redoStack: [CanvasSnapshot] = []

    private func saveState() {
        undoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds, selectedImageIds, persistentLaserStrokes))
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
            presetIndex: pIdx,
            isCatmullRom: !isEraser && !isHighlight
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
            strokes.append(stroke)
        }
        updateUndoRedo()
    }

    // MARK: - Lasso Selection

    func beginLasso(at point: CGPoint) {
        selectionLasso = [point]
    }

    func addLassoPoint(_ point: CGPoint) {
        // Skip if too close to the last point (avoids accidental lassos from stationary taps)
        if let last = selectionLasso.last, last.distance(to: point) < 5 { return }
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
        selectedImageIds.removeAll()

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

        for img in placedImages {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if path.contains(center) || path.contains(rect.origin) {
                selectedImageIds.insert(img.id)
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

        // Single-point or short motion: on macOS this is a click (tap),
        // on iOS double-tap gesture handles bucket fill instead.
        #if os(macOS)
        if pts.count == 1 {
            performFill(at: pts[0])
            return
        }
        var totalDist: CGFloat = 0
        for i in 1..<pts.count { totalDist += pts[i - 1].distance(to: pts[i]) }
        if totalDist < 15 {
            performFill(at: pts.last!)
            return
        }
        #else
        guard pts.count >= 2 else { return }
        var totalDist: CGFloat = 0
        for i in 1..<pts.count { totalDist += pts[i - 1].distance(to: pts[i]) }
        guard totalDist >= 15 else { return }
        #endif

        saveState()

        // Build the lasso path and find stroke-bounded enclosures inside it.
        let lassoPath = CGMutablePath()
        lassoPath.move(to: pts[0])
        for i in 1..<pts.count { lassoPath.addLine(to: pts[i]) }
        lassoPath.closeSubpath()

        // Get all DCEL enclosures, filter to those whose centroid is inside
        // the lasso, and pick the smallest one.
        let lassoBox = lassoPath.boundingBox
        let allEnclosures = FloodFill.detectEnclosures(canvasPoint: CGPoint(x: lassoBox.midX, y: lassoBox.midY), strokes: strokes)
        var fillPath: CGPath = lassoPath
        var bestArea: CGFloat = 0
        for enc in allEnclosures {
            let ebox = enc.boundingBox
            guard !ebox.isNull else { continue }
            guard lassoBox.intersects(ebox) else { continue }
            let eCentroid = CGPoint(x: ebox.midX, y: ebox.midY)
            #if os(iOS)
            guard UIBezierPath(cgPath: lassoPath).contains(eCentroid) else { continue }
            #else
            guard lassoPath.contains(eCentroid, using: .winding) else { continue }
            #endif
            let area = abs(ebox.width * ebox.height)
            if area > bestArea {
                bestArea = area
                fillPath = enc
            }
        }

        let region = FillRegion(path: fillPath, color: fillColor.opacity(fillSettings.opacity), presetIndex: fillPresetIndex)
        fillRegions.append(region)
        updateUndoRedo()
    }

    // MARK: - Move Selection

    var isMoving: Bool = false
    var isResizing: Bool = false
    var resizeCorner: Int = 0  // 0=topLeft, 1=topRight, 2=bottomRight, 3=bottomLeft
    var resizeImageId: UUID?
    var resizeStartRect: CGRect = .zero
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
        for img in placedImages where selectedImageIds.contains(img.id) {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            if rect.contains(point) { return true }
        }
        return false
    }

    func hitTestImage(_ point: CGPoint) -> UUID? {
        for img in placedImages {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            if rect.contains(point) { return img.id }
        }
        return nil
    }

    func isPointInSelectionBoundary(_ point: CGPoint) -> Bool {
        pointInPolygon(point, selectionBoundary)
    }

    func hitTestResizeHandle(_ point: CGPoint) -> (imgId: UUID, corner: Int)? {
        let handleSize: CGFloat = 20
        for img in placedImages where selectedImageIds.contains(img.id) {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            let handles: [(CGPoint, Int)] = [
                (CGPoint(x: rect.minX, y: rect.minY), 0),
                (CGPoint(x: rect.maxX, y: rect.minY), 1),
                (CGPoint(x: rect.maxX, y: rect.maxY), 2),
                (CGPoint(x: rect.minX, y: rect.maxY), 3),
            ]
            for (pos, corner) in handles {
                let hRect = CGRect(x: pos.x - handleSize / 2, y: pos.y - handleSize / 2, width: handleSize, height: handleSize)
                if hRect.contains(point) { return (img.id, corner) }
            }
        }
        return nil
    }

    func beginMove(at point: CGPoint) {
        // Check for resize handle hit on a selected image
        if let hit = hitTestResizeHandle(point) {
            isResizing = true
            resizeCorner = hit.corner
            resizeImageId = hit.imgId
            lastMovePoint = point
            moveDidChange = false
            if let img = placedImages.first(where: { $0.id == hit.imgId }) {
                resizeStartRect = CGRect(origin: img.cgPosition, size: img.cgSize)
            }
            return
        }
        // If there's a selection boundary and the tap is inside it, treat as move
        if !selectionBoundary.isEmpty && pointInPolygon(point, selectionBoundary) {
            isMoving = true
            lastMovePoint = point
            moveDidChange = false
            return
        }
        guard isPointOnSelectedItem(point) else {
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectionBoundary.removeAll()
            beginLasso(at: point)
            return
        }
        // Automatically include fill regions whose bounding box overlaps
        // with the selected strokes, so fills move with their boundary strokes.
        if !selectedStrokeIds.isEmpty {
            var strokeBox = CGRect.null
            for s in strokes where selectedStrokeIds.contains(s.id) {
                for p in s.points {
                    strokeBox = strokeBox.isEmpty ? CGRect(origin: p, size: .zero) : strokeBox.union(CGRect(origin: p, size: .zero))
                }
            }
            for r in fillRegions where !selectedFillIds.contains(r.id) {
                if strokeBox.intersects(r.cgPath.boundingBox) {
                    selectedFillIds.insert(r.id)
                }
            }
        }
        isMoving = true
        lastMovePoint = point
        moveDidChange = false
    }

    func commitMove() {
        if isResizing {
            isResizing = false
            if moveDidChange {
                saveState()
                updateUndoRedo()
            }
            return
        }
        guard isMoving else { return }
        isMoving = false
        if moveDidChange {
            saveState()
            updateUndoRedo()
        }
    }

    func moveSelected(by offset: CGSize) {
        if isResizing {
            guard let imgId = resizeImageId, offset != .zero else { return }
            moveDidChange = true
            let start = resizeStartRect
            let aspect = start.width / start.height
            var newRect = start
            // Lock aspect ratio: size changes driven by the larger drag axis
            let dragX = abs(offset.width) >= abs(offset.height)
            switch resizeCorner {
            case 0: // top-left
                if dragX {
                    let newW = max(10, start.width - offset.width)
                    let newH = newW / aspect
                    newRect = CGRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
                } else {
                    let newH = max(10, start.height - offset.height)
                    let newW = newH * aspect
                    newRect = CGRect(x: start.maxX - newW, y: start.maxY - newH, width: newW, height: newH)
                }
            case 1: // top-right
                if dragX {
                    let newW = max(10, start.width + offset.width)
                    let newH = newW / aspect
                    newRect = CGRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
                } else {
                    let newH = max(10, start.height - offset.height)
                    let newW = newH * aspect
                    newRect = CGRect(x: start.minX, y: start.maxY - newH, width: newW, height: newH)
                }
            case 2: // bottom-right
                if dragX {
                    let newW = max(10, start.width + offset.width)
                    let newH = newW / aspect
                    newRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
                } else {
                    let newH = max(10, start.height + offset.height)
                    let newW = newH * aspect
                    newRect = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
                }
            case 3: // bottom-left
                if dragX {
                    let newW = max(10, start.width - offset.width)
                    let newH = newW / aspect
                    newRect = CGRect(x: start.maxX - newW, y: start.minY, width: newW, height: newH)
                } else {
                    let newH = max(10, start.height + offset.height)
                    let newW = newH * aspect
                    newRect = CGRect(x: start.maxX - newW, y: start.minY, width: newW, height: newH)
                }
            default: break
            }
            if newRect.width >= 10 && newRect.height >= 10 {
                placedImages = placedImages.map { img in
                    guard img.id == imgId else { return img }
                    return PlacedImage(id: img.id, position: newRect.origin, size: newRect.size, imageData: img.imageData)
                }
                resizeStartRect = newRect
            }
            return
        }
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
        placedImages = placedImages.map { img in
            guard selectedImageIds.contains(img.id) else { return img }
            return PlacedImage(id: img.id, position: CGPoint(x: img.cgPosition.x + offset.width, y: img.cgPosition.y + offset.height), size: img.cgSize, imageData: img.imageData)
        }
        if !selectionBoundary.isEmpty {
            selectionBoundary = selectionBoundary.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }

    // MARK: - Delete Selected

    func pointInPolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    private func pointSegDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq != 0 else { return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let px = a.x + t * dx, py = a.y + t * dy
        return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py))
    }

    func smoothCatmullRom(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        // Gaussian-weighted moving average (window radius 2)
        let gaussWeights: [CGFloat] = [0.061, 0.242, 0.394, 0.242, 0.061]
        var smoothed = points
        for i in 0..<points.count {
            var sx: CGFloat = 0, sy: CGFloat = 0, sw: CGFloat = 0
            for w in -2...2 {
                let idx = i + w
                guard idx >= 0, idx < points.count else { continue }
                let weight = gaussWeights[w + 2]
                sx += points[idx].x * weight
                sy += points[idx].y * weight
                sw += weight
            }
            if sw > 0 {
                smoothed[i] = CGPoint(x: sx / sw, y: sy / sw)
            }
        }

        // Catmull-Rom to cubic Bezier
        // For each segment [p1, p2] with neighbors p0, p3:
        //   cp1 = p1 + (p2 - p0) / 6
        //   cp2 = p2 - (p3 - p1) / 6
        var result: [CGPoint] = [smoothed[0]]
        for i in 0..<smoothed.count - 1 {
            let p0 = i > 0 ? smoothed[i - 1] : smoothed[i]
            let p1 = smoothed[i]
            let p2 = smoothed[i + 1]
            let p3 = i + 2 < smoothed.count ? smoothed[i + 2] : smoothed[i + 1]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            result.append(cp1)
            result.append(cp2)
            result.append(p2)
        }
        return result
    }

    func deleteSelected() {
        saveState()
        if !selectedStrokeIds.isEmpty || !selectedFillIds.isEmpty || !selectedImageIds.isEmpty {
            strokes = strokes.filter { !selectedStrokeIds.contains($0.id) }
            fillRegions = fillRegions.filter { !selectedFillIds.contains($0.id) }
            for id in selectedImageIds { imageCache.removeValue(forKey: id) }
            placedImages = placedImages.filter { !selectedImageIds.contains($0.id) }
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectedImageIds.removeAll()
        }
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

    // MARK: - Copy / Paste

    func copySelected() {
        guard !selectedStrokeIds.isEmpty || !selectedFillIds.isEmpty || !selectedImageIds.isEmpty else { return }
        let copiedStrokes = try? JSONEncoder().encode(strokes.filter { selectedStrokeIds.contains($0.id) })
        let copiedFills = try? JSONEncoder().encode(fillRegions.filter { selectedFillIds.contains($0.id) })
        let copiedImages = try? JSONEncoder().encode(placedImages.filter { selectedImageIds.contains($0.id) })
        let data: [String: Any] = [
            "strokes": copiedStrokes ?? Data(),
            "fills": copiedFills ?? Data(),
            "images": copiedImages ?? Data(),
            "boundary": (try? JSONEncoder().encode(selectionBoundary)) ?? Data(),
        ]
        #if os(iOS)
        UIPasteboard.general.items = [data as [String: Any]]
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        // Convert Data values to base64 strings for JSONSerialization compatibility
        let stringData: [String: String] = [
            "strokes": (copiedStrokes ?? Data()).base64EncodedString(),
            "fills": (copiedFills ?? Data()).base64EncodedString(),
            "images": (copiedImages ?? Data()).base64EncodedString(),
            "boundary": ((try? JSONEncoder().encode(selectionBoundary)) ?? Data()).base64EncodedString(),
        ]
        if let json = try? JSONSerialization.data(withJSONObject: stringData, options: .fragmentsAllowed) {
            pb.setData(json, forType: .string)
        }
        #endif
    }

    func paste() {
        #if os(iOS)
        guard let item = UIPasteboard.general.items.first else { return }
        let strokesData = item["strokes"] as? Data ?? Data()
        let fillsData = item["fills"] as? Data ?? Data()
        let imagesData = item["images"] as? Data ?? Data()
        let boundaryData = item["boundary"] as? Data ?? Data()
        #else
        guard let json = NSPasteboard.general.data(forType: .string),
              let item = try? JSONSerialization.jsonObject(with: json) as? [String: String] else { return }
        let strokesData = Data(base64Encoded: item["strokes"] ?? "") ?? Data()
        let fillsData = Data(base64Encoded: item["fills"] ?? "") ?? Data()
        let imagesData = Data(base64Encoded: item["images"] ?? "") ?? Data()
        let boundaryData = Data(base64Encoded: item["boundary"] ?? "") ?? Data()
        #endif

        saveState()

        // Compute offset to paste at the last tap location
        let pasteOrigin = lastCanvasTapLocation == .zero ? CGPoint(x: 100, y: 100) : lastCanvasTapLocation

        // Compute unified bounding box of all pasted content
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        if let pastedStrokes2 = try? JSONDecoder().decode([Stroke].self, from: strokesData) {
            for s in pastedStrokes2 {
                for p in s.points {
                    if p.x < minX { minX = p.x }
                    if p.y < minY { minY = p.y }
                }
            }
        }
        if let pastedFills2 = try? JSONDecoder().decode([FillRegion].self, from: fillsData) {
            for r in pastedFills2 {
                let box = r.cgPath.boundingBox
                if box.minX < minX { minX = box.minX }
                if box.minY < minY { minY = box.minY }
            }
        }
        if let pastedImages2 = try? JSONDecoder().decode([PlacedImage].self, from: imagesData) {
            for img in pastedImages2 {
                if img.cgPosition.x < minX { minX = img.cgPosition.x }
                if img.cgPosition.y < minY { minY = img.cgPosition.y }
            }
        }
        let dx = (minX == .infinity) ? 0 : pasteOrigin.x - minX
        let dy = (minY == .infinity) ? 0 : pasteOrigin.y - minY

        var pastedStrokeIds = Set<UUID>()
        var pastedFillIds = Set<UUID>()
        var pastedImageIds = Set<UUID>()

        if let pastedStrokes = try? JSONDecoder().decode([Stroke].self, from: strokesData) {
            for s in pastedStrokes {
                let newPoints = s.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                let newStroke = Stroke(points: newPoints, color: s.uiColor, lineWidth: s.lineWidth, isEraser: false, isHighlighter: s.isHighlighter, presetIndex: s.presetIndex, isCatmullRom: s.isCatmullRom)
                pastedStrokeIds.insert(newStroke.id)
                strokes.append(newStroke)
            }
        }
        if let pastedFills = try? JSONDecoder().decode([FillRegion].self, from: fillsData) {
            for r in pastedFills {
                var t = CGAffineTransform(translationX: dx, y: dy)
                let newPath = r.cgPath.copy(using: &t) ?? r.cgPath
                let newFill = FillRegion(path: newPath, color: r.uiColor, presetIndex: r.presetIndex)
                pastedFillIds.insert(newFill.id)
                fillRegions.append(newFill)
            }
        }
        if let pastedImages = try? JSONDecoder().decode([PlacedImage].self, from: imagesData) {
            for img in pastedImages {
                let newPos = CGPoint(x: img.cgPosition.x + dx, y: img.cgPosition.y + dy)
                let newImg = PlacedImage(position: newPos, size: img.cgSize, imageData: img.imageData)
                pastedImageIds.insert(newImg.id)
                placedImages.append(newImg)
            }
        }
        // Select pasted items so they can be moved immediately
        selectedStrokeIds = pastedStrokeIds
        selectedFillIds = pastedFillIds
        selectedImageIds = pastedImageIds
        // Restore selection boundary from copied boundary polygon
        if let boundary = try? JSONDecoder().decode([CGPoint].self, from: boundaryData), !boundary.isEmpty {
            selectionBoundary = boundary.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        } else {
            selectionBoundary.removeAll()
        }
    }

    func addImage(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        #if os(iOS)
        guard let uiImg = UIImage(data: data) else { return }
        let originalSize = uiImg.size
        #else
        guard let nsImg = NSImage(data: data) else { return }
        let originalSize = nsImg.size
        #endif
        let maxWidth: CGFloat = 400
        let aspect = originalSize.height / originalSize.width
        let finalSize = CGSize(width: min(originalSize.width, maxWidth), height: min(originalSize.width, maxWidth) * aspect)
        // Resize image data to display size so rendering is fast
        let resizedData: Data = {
            #if os(iOS)
            let s = UIScreen.main.scale
            UIGraphicsBeginImageContextWithOptions(finalSize, false, s)
            uiImg.draw(in: CGRect(origin: .zero, size: finalSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resized?.pngData() ?? data
            #else
            let resized = NSImage(size: finalSize)
            resized.lockFocus()
            nsImg.draw(in: NSRect(origin: .zero, size: finalSize), from: NSRect(origin: .zero, size: nsImg.size), operation: .copy, fraction: 1)
            resized.unlockFocus()
            if let tiffData = resized.tiffRepresentation {
                let bitmap = NSBitmapImageRep(data: tiffData)
                if let pngData = bitmap?.representation(using: .png, properties: [:]) { return pngData }
            }
            return data
            #endif
        }()
        let pos = lastCanvasTapLocation == .zero ? CGPoint(x: 100, y: 100) : lastCanvasTapLocation
        saveState()
        let img = PlacedImage(position: pos, size: finalSize, imageData: resizedData)
        placedImages.append(img)
        // Auto-select the newly imported image and switch to selection tool
        selectTool(.select)
        selectedImageIds = [img.id]
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
    }

    func resizeSelectedImages(by factor: CGFloat) {
        guard !selectedImageIds.isEmpty else { return }
        saveState()
        placedImages = placedImages.map { img in
            guard selectedImageIds.contains(img.id) else { return img }
            return PlacedImage(id: img.id, position: img.cgPosition, size: CGSize(width: img.cgSize.width * factor, height: img.cgSize.height * factor), imageData: img.imageData)
        }
        updateUndoRedo()
    }

    // MARK: - Fill

    func performFill(at canvasPoint: CGPoint) {
        saveState()
        guard let path = FloodFill.fillPath(at: canvasPoint, strokes: strokes) else {
            updateUndoRedo()
            return
        }
        let region = FillRegion(path: path, color: fillColor.opacity(fillSettings.opacity), presetIndex: fillPresetIndex)
        fillRegions.append(region)
        updateUndoRedo()
    }

    func selectTool(_ tool: Tool) {
        currentTool = tool
        if tool != .select {
            selectedStrokeIds.removeAll()
            selectedFillIds.removeAll()
            selectedImageIds.removeAll()
            selectionBoundary.removeAll()
        }
        if tool != .laser {
            if !laserSettings.retainStrokes {
                persistentLaserStrokes.removeAll()
            }
            laserTail.removeAll()
            laserPointer = nil
            laserTailFadeStart = nil
        }
        fillLassoPoints = []
        showDeleteMenu = false
        showClearConfirmation = false
        needsDelete = false
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds, selectedImageIds, persistentLaserStrokes))
        let prev = undoStack.removeLast()
        strokes = prev.strokes
        fillRegions = prev.fillRegions
        selectedStrokeIds = prev.selectedStrokeIds
        selectedFillIds = prev.selectedFillIds
        selectedImageIds = prev.selectedImageIds
        persistentLaserStrokes = prev.laserStrokes
        updateUndoRedo()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append((strokes, fillRegions, selectedStrokeIds, selectedFillIds, selectedImageIds, persistentLaserStrokes))
        let next = redoStack.removeLast()
        strokes = next.strokes
        fillRegions = next.fillRegions
        selectedStrokeIds = next.selectedStrokeIds
        selectedFillIds = next.selectedFillIds
        selectedImageIds = next.selectedImageIds
        persistentLaserStrokes = next.laserStrokes
        updateUndoRedo()
    }

    func clear() {
        saveState()
        strokes.removeAll()
        fillRegions.removeAll()
        placedImages.removeAll()
        imageCache.removeAll()
        persistentLaserStrokes.removeAll()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectedImageIds.removeAll()
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
        let placedImages: [PlacedImage]

        enum CodingKeys: String, CodingKey {
            case strokes, fillRegions, placedImages
        }

        init(strokes: [Stroke], fillRegions: [FillRegion], placedImages: [PlacedImage]) {
            self.strokes = strokes
            self.fillRegions = fillRegions
            self.placedImages = placedImages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            strokes = try c.decode([Stroke].self, forKey: .strokes)
            fillRegions = try c.decode([FillRegion].self, forKey: .fillRegions)
            placedImages = try c.decodeIfPresent([PlacedImage].self, forKey: .placedImages) ?? []
        }
    }

    func saveData() -> Data? {
        let data = SaveData(strokes: strokes, fillRegions: fillRegions, placedImages: placedImages)
        return try? JSONEncoder().encode(data)
    }

    func loadData(_ data: Data) {
        do {
            let save = try JSONDecoder().decode(SaveData.self, from: data)
            saveState()
            strokes = save.strokes
            fillRegions = save.fillRegions
            placedImages = save.placedImages
            imageCache.removeAll()
            migratePresetIndices()
            updateUndoRedo()
        } catch {
            print("[loadData] error: \(error)")
        }
    }

    private func migratePresetIndices() {
        let penPresets = appSettings.isDarkMode ? penSettings.darkPresets : penSettings.lightPresets
        let hlPresets = appSettings.isDarkMode ? highlighterSettings.darkPresets : highlighterSettings.lightPresets
        for i in strokes.indices where strokes[i].presetIndex == -1 && !strokes[i].isEraser {
            let s = strokes[i]
            let candidates = s.isHighlighter ? hlPresets : penPresets
            #if os(iOS)
            let target = UIColor(s.color.color)
            #else
            guard let target = NSColor(s.color.color).usingColorSpace(.sRGB) else { continue }
            #endif
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
            target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            var bestIdx = -1
            var bestDist = CGFloat.infinity
            for (j, c) in candidates.enumerated() {
                #if os(iOS)
                let pc = UIColor(c)
                #else
                guard let pc = NSColor(c).usingColorSpace(.sRGB) else { continue }
                #endif
                var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0, pa: CGFloat = 0
                pc.getRed(&pr, green: &pg, blue: &pb, alpha: &pa)
                let d = (tr - pr) * (tr - pr) + (tg - pg) * (tg - pg) + (tb - pb) * (tb - pb)
                if d < bestDist { bestDist = d; bestIdx = j }
            }
            if bestIdx >= 0 {
                strokes[i] = Stroke(id: s.id, points: s.points, color: s.uiColor, lineWidth: s.lineWidth, isEraser: s.isEraser, isHighlighter: s.isHighlighter, presetIndex: bestIdx, isCatmullRom: s.isCatmullRom)
            }
        }
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
        case importImage
    }

    enum ExportFormat: String { case png, pdf }
    @Published var pendingAction: PendingAction?
    @Published var showDeleteMenu: Bool = false
    @Published var deleteMenuLocation: CGPoint = .zero
    @Published var needsDelete: Bool = false
    @Published var showClearConfirmation: Bool = false
    @Published var isToolbarVisible: Bool = true
    @Published var showWelcome: Bool = true
    @Published var needsRecenter: Bool = false
    @Published var welcomeFolderName: String?

    func pngData(size: CGSize, offset: CGPoint = .zero, scale: CGFloat = 3) -> Data? {
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard w > 0, h > 0, w <= 8192, h <= 8192 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // No background fill — PNG exports with transparent background.
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

        // Render placed images
        for img in placedImages {
            let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
            #if os(iOS)
            if let uiImg = UIImage(data: img.imageData) {
                uiImg.draw(in: rect)
            }
            #endif
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
