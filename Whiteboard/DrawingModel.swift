import Observation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

nonisolated struct Stroke: Identifiable, Codable, Sendable {
    var id = UUID()
    var points: [CGPoint]
    let color: CodableColor
    let lineWidth: CGFloat
    let isEraser: Bool
    let presetIndex: Int
    let isCatmullRom: Bool
    let isSharpie: Bool

    init(
        id: UUID = UUID(),
        points: [CGPoint],
        color: Color,
        lineWidth: CGFloat,
        isEraser: Bool,
        presetIndex: Int = -1,
        isCatmullRom: Bool = false,
        isSharpie: Bool = false
    ) {
        self.id = id
        self.points = points
        self.color = CodableColor(color)
        self.lineWidth = lineWidth
        self.isEraser = isEraser
        self.presetIndex = presetIndex
        self.isCatmullRom = isCatmullRom
        self.isSharpie = isSharpie
    }

    enum CodingKeys: String, CodingKey {
        case id, points, color, lineWidth, isEraser, presetIndex, isCatmullRom, isSharpie
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        points = try c.decode([CGPoint].self, forKey: .points)
        color = try c.decode(CodableColor.self, forKey: .color)
        lineWidth = try c.decode(CGFloat.self, forKey: .lineWidth)
        isEraser = try c.decode(Bool.self, forKey: .isEraser)
        presetIndex = try c.decodeIfPresent(Int.self, forKey: .presetIndex) ?? -1
        isCatmullRom = try c.decodeIfPresent(Bool.self, forKey: .isCatmullRom) ?? false
        isSharpie = try c.decodeIfPresent(Bool.self, forKey: .isSharpie) ?? false
    }

    var uiColor: Color { color.color }

    @MainActor
    func displayColor(for model: DrawingModel) -> Color {
        StrokeRenderer.resolveDisplayColor(
            for: self,
            penPresets: model.penPresets,
            sharpiePresets: model.sharpiePresets
        )
    }
}

nonisolated struct CodableColor: Codable, Equatable, Sendable {
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
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.r = Double(r); self.g = Double(g); self.b = Double(b); self.a = Double(a)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

nonisolated struct PlacedImage: Identifiable, Codable, Sendable {
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

nonisolated struct CodablePoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

enum Tool: String, CaseIterable {
    case pen, sharpie, eraser, select
}

enum CanvasBackground: String, CaseIterable {
    case none, grid, dots, ruled
}

struct AppSettings {
    var canvasBackground: CanvasBackground = .grid
    var revealSettingsOnSingleTap: Bool = true
    #if os(macOS)
    var pencilOnly: Bool = false
    #else
    var pencilOnly: Bool = true
    #endif
    var isDarkMode: Bool = false {
        didSet {
            #if os(macOS)
            NSApp?.appearance = isDarkMode ? NSAppearance(named: .darkAqua) : nil
            #endif
        }
    }
}

struct PenSettings {
    var lightColor: Color = .black
    var darkColor: Color = .white
    var thickness: CGFloat = 2
    let widthOptions: [CGFloat] = [2, 2.5, 3, 3.5, 4]
    var lightPresets: [Color] = [
        Color(red: 0.05, green: 0.05, blue: 0.05),
        Color(red: 0.95, green: 0.0, blue: 0.1),
        Color(red: 1.0, green: 0.45, blue: 0.0),
        Color(red: 1.0, green: 0.8, blue: 0.0),
        Color(red: 0.0, green: 0.7, blue: 0.15),
        Color(red: 0.0, green: 0.35, blue: 1.0),
        Color(red: 0.55, green: 0.15, blue: 1.0),
        Color(red: 0.6, green: 0.35, blue: 0.1),
    ]
    var darkPresets: [Color] = [
        Color(red: 1.0, green: 1.0, blue: 1.0),
        Color(red: 1.0, green: 0.3, blue: 0.3),
        Color(red: 1.0, green: 0.6, blue: 0.15),
        Color(red: 1.0, green: 0.9, blue: 0.25),
        Color(red: 0.3, green: 1.0, blue: 0.45),
        Color(red: 0.3, green: 0.6, blue: 1.0),
        Color(red: 0.7, green: 0.4, blue: 1.0),
        Color(red: 1.0, green: 0.4, blue: 0.7),
    ]
}

struct SharpieSettings {
    var lightColor: Color = .black
    var darkColor: Color = .white
    var thickness: CGFloat = 2
    let widthOptions: [CGFloat] = [2, 2.5, 3, 3.5, 4]
    var lightPresets: [Color] = [
        Color(red: 0.05, green: 0.05, blue: 0.05),
        Color(red: 0.95, green: 0.0, blue: 0.1),
        Color(red: 1.0, green: 0.45, blue: 0.0),
        Color(red: 1.0, green: 0.8, blue: 0.0),
        Color(red: 0.0, green: 0.7, blue: 0.15),
        Color(red: 0.0, green: 0.35, blue: 1.0),
        Color(red: 0.55, green: 0.15, blue: 1.0),
        Color(red: 0.6, green: 0.35, blue: 0.1),
    ]
    var darkPresets: [Color] = [
        Color(red: 1.0, green: 1.0, blue: 1.0),
        Color(red: 1.0, green: 0.3, blue: 0.3),
        Color(red: 1.0, green: 0.6, blue: 0.15),
        Color(red: 1.0, green: 0.9, blue: 0.25),
        Color(red: 0.3, green: 1.0, blue: 0.45),
        Color(red: 0.3, green: 0.6, blue: 1.0),
        Color(red: 0.7, green: 0.4, blue: 1.0),
        Color(red: 1.0, green: 0.4, blue: 0.7),
    ]
}

enum EraserMode: String, CaseIterable {
    case partial = "Partial"
    case full = "Full Stroke"
}

enum EraseTarget: String, CaseIterable {
    case all = "All"
    case pen = "Pen"
    case sharpie = "Sharpie"
}

struct EraserSettings {
    var mode: EraserMode = .full
    var size: CGFloat = 10
    var eraseTarget: EraseTarget = .all
}

@Observable
final class DrawingModel {
    var strokes: [Stroke] = [] {
        didSet { committedRevision &+= 1 }
    }
    var placedImages: [PlacedImage] = [] {
        didSet { committedRevision &+= 1 }
    }
    var currentTool: Tool = .pen {
        didSet { scheduleSettingsSave() }
    }
    var canUndo: Bool = false
    var canRedo: Bool = false

    var penPresetIndex: Int = 0 {
        didSet { scheduleSettingsSave() }
    }
    var sharpiePresetIndex: Int = 0 {
        didSet { scheduleSettingsSave() }
    }
    var penSettings = PenSettings() {
        didSet { scheduleSettingsSave() }
    }
    var sharpieSettings = SharpieSettings() {
        didSet { scheduleSettingsSave() }
    }
    var eraserSettings = EraserSettings() {
        didSet { scheduleSettingsSave() }
    }
    var appSettings = AppSettings() {
        didSet { scheduleSettingsSave() }
    }

    var recentFiles: [URL] = []
    var boards: [BoardMeta] = []
    var folders: [BoardFolder] = []
    var trashedBoards: [TrashEntry] = []
    var currentBoardId: String?

    var selectionLasso: [CGPoint] = []
    var selectionBoundary: [CGPoint] = []
    var selectedStrokeIds: Set<UUID> = []
    var selectedImageIds: Set<UUID> = []

    var pendingAction: PendingAction?
    var showDeleteMenu: Bool = false
    var deleteMenuLocation: CGPoint = .zero
    var showClearConfirmation: Bool = false
    var isToolbarVisible: Bool = true
    var showWelcome: Bool = true
    var needsRecenter: Bool = false
    var welcomeFolderName: String?
    var lastErrorMessage: String?

    /// Bumped whenever committed strokes or placed images change so the canvas
    /// backing store knows when to re-bake (or incrementally append).
    private(set) var committedRevision: Int = 0
    /// Bumped when background thumbnail generation finishes so WelcomeView refreshes.
    private(set) var thumbnailRevision: Int = 0

    @ObservationIgnored var currentStroke: Stroke?
    @ObservationIgnored var previousTool: Tool = .pen
    @ObservationIgnored var lastCanvasTapLocation: CGPoint = .zero
    @ObservationIgnored var imageCache: [UUID: PlatformImage] = [:]
    @ObservationIgnored let spatialGrid = SpatialHashGrid(cellSize: 256)

    @ObservationIgnored var openFileURL: URL? {
        didSet {
            if let url = openFileURL { addRecent(url) }
        }
    }

    @ObservationIgnored let store: BoardStore
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var history = CanvasHistory(maxSnapshots: 100)
    @ObservationIgnored private var isInitializing = true

    @ObservationIgnored private let recentKey = "recentFiles"
    @ObservationIgnored private let maxRecent = 5
    @ObservationIgnored private let defaultsKey = "savedDefaults"

    @ObservationIgnored private var settingsSaveWorkItem: DispatchWorkItem?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private var pendingAutoSaveBoardId: String?

    // Async thumbnail cache + in-flight deduplication
    @ObservationIgnored private let thumbnailCache = NSCache<NSString, PlatformImage>()
    @ObservationIgnored private var thumbnailKeys: Set<String> = []
    @ObservationIgnored private var inFlightThumbnails: Set<String> = []
    @ObservationIgnored private let thumbnailQueue = DispatchQueue(label: "com.whiteboard.thumbnails", qos: .userInitiated)

    // Move / Resize state
    @ObservationIgnored var isMoving: Bool = false
    @ObservationIgnored var isResizing: Bool = false
    @ObservationIgnored var resizeCorner: Int = 0  // 0=topLeft, 1=topRight, 2=bottomRight, 3=bottomLeft
    @ObservationIgnored var resizeImageId: UUID?
    @ObservationIgnored var resizeStartRect: CGRect = .zero
    @ObservationIgnored var lastMovePoint: CGPoint = .zero
    @ObservationIgnored private var moveSnapshotTaken: Bool = false

    /// Minimum canvas-space squared distance between consecutive raw stroke points.
    @ObservationIgnored private let minStrokePointDistanceSq: CGFloat = 1.25 * 1.25

    enum PendingAction: Equatable {
        case open
        case export(ExportFormat)
        case importImage
    }

    enum ExportFormat: String { case png, pdf }

    init(store: BoardStore = BoardStore(), userDefaults: UserDefaults = .standard) {
        self.store = store
        self.userDefaults = userDefaults
        thumbnailCache.countLimit = 128

        loadDefaults()
        loadRecents()
        loadBoards()
        isInitializing = false
    }

    private func scheduleSettingsSave() {
        guard !isInitializing else { return }
        settingsSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveDefaults()
        }
        settingsSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func reportError(_ message: String) {
        if Thread.isMainThread {
            lastErrorMessage = message
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.lastErrorMessage = message
            }
        }
    }

    // MARK: - Recents

    private func loadRecents() {
        guard let data = userDefaults.data(forKey: recentKey) else { return }
        if let paths = try? JSONDecoder().decode([String].self, from: data) {
            recentFiles = paths.map { URL(fileURLWithPath: $0) }
            return
        }
        if let urls = (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSURL.self], from: data)) as? [URL] {
            recentFiles = urls
        }
    }

    private func saveRecents() {
        let paths = recentFiles.map(\.path)
        if let data = try? JSONEncoder().encode(paths) {
            userDefaults.set(data, forKey: recentKey)
        }
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

    struct SettingsSnapshot: Codable {
        let penLightColor: CodableColor
        let penDarkColor: CodableColor
        let penThickness: CGFloat
        let sharpieLightColor: CodableColor?
        let sharpieDarkColor: CodableColor?
        let sharpieThickness: CGFloat?
        let eraserSize: CGFloat
        let eraserMode: String
        let eraseTarget: String?
        let canvasBg: String
        let isDarkMode: Bool
        let revealSettingsOnSingleTap: Bool
        let pencilOnly: Bool?
        let penPresetIndex: Int?
        let sharpiePresetIndex: Int?
        let currentTool: String

        enum CodingKeys: String, CodingKey {
            case penLightColor, penDarkColor, penThickness,
                 sharpieLightColor, sharpieDarkColor, sharpieThickness,
                 eraserSize, eraserMode, eraseTarget, canvasBg, isDarkMode, revealSettingsOnSingleTap, pencilOnly,
                 penPresetIndex, sharpiePresetIndex, currentTool
        }

        init(
            penLightColor: CodableColor, penDarkColor: CodableColor, penThickness: CGFloat,
            sharpieLightColor: CodableColor?, sharpieDarkColor: CodableColor?, sharpieThickness: CGFloat?,
            eraserSize: CGFloat, eraserMode: String, eraseTarget: String?, canvasBg: String,
            isDarkMode: Bool, revealSettingsOnSingleTap: Bool, pencilOnly: Bool?,
            penPresetIndex: Int?, sharpiePresetIndex: Int?, currentTool: String
        ) {
            self.penLightColor = penLightColor
            self.penDarkColor = penDarkColor
            self.penThickness = penThickness
            self.sharpieLightColor = sharpieLightColor
            self.sharpieDarkColor = sharpieDarkColor
            self.sharpieThickness = sharpieThickness
            self.eraserSize = eraserSize
            self.eraserMode = eraserMode
            self.eraseTarget = eraseTarget
            self.canvasBg = canvasBg
            self.isDarkMode = isDarkMode
            self.revealSettingsOnSingleTap = revealSettingsOnSingleTap
            self.pencilOnly = pencilOnly
            self.penPresetIndex = penPresetIndex
            self.sharpiePresetIndex = sharpiePresetIndex
            self.currentTool = currentTool
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            penLightColor = try c.decode(CodableColor.self, forKey: .penLightColor)
            penDarkColor = try c.decode(CodableColor.self, forKey: .penDarkColor)
            penThickness = try c.decode(CGFloat.self, forKey: .penThickness)
            sharpieLightColor = try c.decodeIfPresent(CodableColor.self, forKey: .sharpieLightColor)
            sharpieDarkColor = try c.decodeIfPresent(CodableColor.self, forKey: .sharpieDarkColor)
            sharpieThickness = try c.decodeIfPresent(CGFloat.self, forKey: .sharpieThickness)
            eraserSize = try c.decode(CGFloat.self, forKey: .eraserSize)
            eraserMode = try c.decode(String.self, forKey: .eraserMode)
            eraseTarget = try c.decodeIfPresent(String.self, forKey: .eraseTarget)
            canvasBg = try c.decode(String.self, forKey: .canvasBg)
            isDarkMode = try c.decode(Bool.self, forKey: .isDarkMode)
            revealSettingsOnSingleTap = try c.decodeIfPresent(Bool.self, forKey: .revealSettingsOnSingleTap) ?? true
            pencilOnly = try c.decodeIfPresent(Bool.self, forKey: .pencilOnly)
            penPresetIndex = try c.decodeIfPresent(Int.self, forKey: .penPresetIndex)
            sharpiePresetIndex = try c.decodeIfPresent(Int.self, forKey: .sharpiePresetIndex)
            currentTool = try c.decodeIfPresent(String.self, forKey: .currentTool) ?? Tool.pen.rawValue
        }
    }

    func saveDefaults() {
        let s = SettingsSnapshot(
            penLightColor: CodableColor(penSettings.lightColor),
            penDarkColor: CodableColor(penSettings.darkColor),
            penThickness: penSettings.thickness,
            sharpieLightColor: CodableColor(sharpieSettings.lightColor),
            sharpieDarkColor: CodableColor(sharpieSettings.darkColor),
            sharpieThickness: sharpieSettings.thickness,
            eraserSize: eraserSettings.size,
            eraserMode: eraserSettings.mode.rawValue,
            eraseTarget: eraserSettings.eraseTarget.rawValue,
            canvasBg: appSettings.canvasBackground.rawValue,
            isDarkMode: appSettings.isDarkMode,
            revealSettingsOnSingleTap: appSettings.revealSettingsOnSingleTap,
            pencilOnly: appSettings.pencilOnly,
            penPresetIndex: penPresetIndex,
            sharpiePresetIndex: sharpiePresetIndex,
            currentTool: currentTool.rawValue
        )
        if let data = try? JSONEncoder().encode(s) {
            userDefaults.set(data, forKey: defaultsKey)
        }
    }

    func loadDefaults() {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(SettingsSnapshot.self, from: data) else { return }
        penSettings.lightColor = s.penLightColor.color
        penSettings.darkColor = s.penDarkColor.color
        penSettings.thickness = s.penThickness
        if let sl = s.sharpieLightColor { sharpieSettings.lightColor = sl.color }
        if let sd = s.sharpieDarkColor { sharpieSettings.darkColor = sd.color }
        if let st = s.sharpieThickness { sharpieSettings.thickness = st }
        eraserSettings.size = s.eraserSize
        eraserSettings.mode = EraserMode(rawValue: s.eraserMode) ?? .full
        if let et = s.eraseTarget { eraserSettings.eraseTarget = EraseTarget(rawValue: et) ?? .all }
        appSettings.canvasBackground = CanvasBackground(rawValue: s.canvasBg) ?? .grid
        appSettings.isDarkMode = s.isDarkMode
        appSettings.revealSettingsOnSingleTap = s.revealSettingsOnSingleTap
        if let po = s.pencilOnly { appSettings.pencilOnly = po }
        if let pIdx = s.penPresetIndex, penSettings.lightPresets.indices.contains(pIdx) {
            penPresetIndex = pIdx
        } else {
            let target = appSettings.isDarkMode ? s.penDarkColor : s.penLightColor
            penPresetIndex = closestPresetIndex(to: target, in: penPresets)
        }
        if let sIdx = s.sharpiePresetIndex, sharpieSettings.lightPresets.indices.contains(sIdx) {
            sharpiePresetIndex = sIdx
        } else if let sc = appSettings.isDarkMode ? s.sharpieDarkColor : s.sharpieLightColor {
            sharpiePresetIndex = closestPresetIndex(to: sc, in: sharpiePresets)
        }
        currentTool = Tool(rawValue: s.currentTool) ?? .pen
    }

    private func closestPresetIndex(to target: CodableColor, in candidates: [Color]) -> Int {
        var bestIdx = 0
        var bestDist = Double.infinity
        for (j, c) in candidates.enumerated() {
            let pc = CodableColor(c)
            let d = (target.r - pc.r) * (target.r - pc.r) + (target.g - pc.g) * (target.g - pc.g) + (target.b - pc.b) * (target.b - pc.b)
            if d < bestDist { bestDist = d; bestIdx = j }
        }
        return bestIdx
    }

    func resetToFactory() {
        userDefaults.removeObject(forKey: defaultsKey)
        penSettings = PenSettings()
        sharpieSettings = SharpieSettings()
        eraserSettings = EraserSettings()
        appSettings = AppSettings()
        currentTool = .pen
        previousTool = .pen
        penPresetIndex = 0
        sharpiePresetIndex = 0
    }

    var hasDefaults: Bool {
        userDefaults.data(forKey: defaultsKey) != nil
    }

    // MARK: - Board Storage

    func loadBoards() {
        do {
            let index = try store.loadIndex()
            boards = index.boards
            folders = index.folders
        } catch {
            boards = []
            folders = []
            reportError(error.localizedDescription)
        }
    }

    private func saveBoards() {
        do {
            try store.saveIndex(BoardIndex(boards: boards, folders: folders))
        } catch {
            reportError(error.localizedDescription)
        }
    }

    func createBoard(name: String, folderId: String? = nil) {
        flushAutoSave()
        let id = String(UUID().uuidString.prefix(8).lowercased())
        let meta = BoardMeta(id: id, name: name, created: Date(), modified: Date())
        boards.insert(meta, at: 0)
        if let fid = folderId, let idx = folders.firstIndex(where: { $0.id == fid }) {
            folders[idx].boardIds.insert(id, at: 0)
        }
        saveBoards()
        currentBoardId = meta.id
        openFileURL = store.boardURL(for: meta.id)
        resetCanvasState()
        do {
            try store.saveBoardSync(id: meta.id, saveData: SaveData(strokes: [], placedImages: []))
        } catch {
            reportError(error.localizedDescription)
        }
    }

    func renameBoard(id: String, to newName: String) {
        guard let idx = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[idx].name = newName
        boards[idx].modified = Date()
        saveBoards()
    }

    // MARK: - Folders

    func createFolder(name: String) {
        let id = String(UUID().uuidString.prefix(8).lowercased())
        folders.append(BoardFolder(id: id, name: name, boardIds: []))
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

    // MARK: - Trash & Restore

    func loadTrash() {
        trashedBoards = store.cleanTrash()
    }

    func trashBoard(id: String, name: String) {
        if currentBoardId == id {
            cancelPendingAutoSave()
            currentBoardId = nil
        }
        do {
            trashedBoards = try store.trashBoard(id: id, name: name)
        } catch {
            reportError(error.localizedDescription)
            return
        }
        boards.removeAll { $0.id == id }
        for fi in folders.indices { folders[fi].boardIds.removeAll { $0 == id } }
        invalidateThumbnail(for: id)
        saveBoards()
    }

    @discardableResult
    func restoreBoard(id: String) -> Bool {
        let newId = String(UUID().uuidString.prefix(8).lowercased())
        do {
            let restored = try store.restoreBoard(id: id, newBoardId: newId)
            let now = Date()
            let meta = BoardMeta(id: newId, name: restored.name, created: now, modified: now)
            boards.insert(meta, at: 0)
            saveBoards()
            trashedBoards = restored.remainingTrash
            invalidateThumbnail(for: newId)
            return true
        } catch {
            reportError(error.localizedDescription)
            return false
        }
    }

    func loadBoard(id: String) {
        flushAutoSave()
        do {
            let save = try store.loadBoard(id: id)
            resetCanvasState()
            strokes = save.strokes
            placedImages = save.placedImages
            currentBoardId = id
            openFileURL = store.boardURL(for: id)
            migratePresetIndices()
            spatialGrid.rebuild(with: strokes)
            updateUndoRedo()
        } catch {
            reportError(error.localizedDescription)
        }
    }

    func openBoardByID(_ id: String) {
        loadBoard(id: id)
    }

    // MARK: - Auto-save

    private func cancelPendingAutoSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        pendingAutoSaveBoardId = nil
    }

    private func scheduleAutoSave() {
        guard let boardId = currentBoardId else { return }
        saveWorkItem?.cancel()
        pendingAutoSaveBoardId = boardId
        let item = DispatchWorkItem { [weak self] in
            self?.performAutoSave(for: boardId)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func performAutoSave(for boardId: String) {
        guard currentBoardId == boardId else { return }
        saveWorkItem = nil
        pendingAutoSaveBoardId = nil

        let snapshot = SaveData(strokes: strokes, placedImages: placedImages)
        invalidateThumbnail(for: boardId)
        if let idx = boards.firstIndex(where: { $0.id == boardId }) {
            boards[idx].modified = Date()
            saveBoards()
        }

        store.saveBoardAsync(id: boardId, saveData: snapshot) { [weak self] result in
            if case .failure(let error) = result {
                self?.reportError(error.localizedDescription)
            }
        }
    }

    func flushAutoSave(drainBackgroundQueue: Bool = false) {
        let boardId = pendingAutoSaveBoardId ?? (saveWorkItem != nil ? currentBoardId : nil)
        saveWorkItem?.cancel()
        saveWorkItem = nil
        pendingAutoSaveBoardId = nil

        if let boardId, currentBoardId == boardId {
            let snapshot = SaveData(strokes: strokes, placedImages: placedImages)
            invalidateThumbnail(for: boardId)
            if let idx = boards.firstIndex(where: { $0.id == boardId }) {
                boards[idx].modified = Date()
                saveBoards()
            }
            do {
                try store.saveBoardSync(id: boardId, saveData: snapshot)
            } catch {
                reportError(error.localizedDescription)
            }
        }
        if drainBackgroundQueue {
            store.drainPendingWrites()
        }
    }

    // MARK: - Theme-aware colors (always synchronized with preset indices)

    var penPresets: [Color] { appSettings.isDarkMode ? penSettings.darkPresets : penSettings.lightPresets }
    var sharpiePresets: [Color] { appSettings.isDarkMode ? sharpieSettings.darkPresets : sharpieSettings.lightPresets }

    var penColor: Color {
        if penPresets.indices.contains(penPresetIndex) {
            return penPresets[penPresetIndex]
        }
        return appSettings.isDarkMode ? penSettings.darkColor : penSettings.lightColor
    }

    var sharpieColor: Color {
        if sharpiePresets.indices.contains(sharpiePresetIndex) {
            return sharpiePresets[sharpiePresetIndex]
        }
        return appSettings.isDarkMode ? sharpieSettings.darkColor : sharpieSettings.lightColor
    }

    func selectPenPreset(_ index: Int) {
        guard penSettings.lightPresets.indices.contains(index),
              penSettings.darkPresets.indices.contains(index) else { return }
        penPresetIndex = index
        penSettings.lightColor = penSettings.lightPresets[index]
        penSettings.darkColor = penSettings.darkPresets[index]
    }

    func selectSharpiePreset(_ index: Int) {
        guard sharpieSettings.lightPresets.indices.contains(index),
              sharpieSettings.darkPresets.indices.contains(index) else { return }
        sharpiePresetIndex = index
        sharpieSettings.lightColor = sharpieSettings.lightPresets[index]
        sharpieSettings.darkColor = sharpieSettings.darkPresets[index]
    }

    // MARK: - History Helpers

    private func makeSnapshot() -> CanvasSnapshot {
        CanvasSnapshot(
            strokes: strokes,
            placedImages: placedImages,
            selectedStrokeIds: selectedStrokeIds,
            selectedImageIds: selectedImageIds,
            selectionBoundary: selectionBoundary
        )
    }

    private func saveState() {
        history.push(makeSnapshot())
        updateUndoRedo()
        scheduleAutoSave()
    }

    private func updateUndoRedo() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    private func resetCanvasState() {
        strokes.removeAll()
        placedImages.removeAll()
        imageCache.removeAll()
        spatialGrid.invalidate()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedImageIds.removeAll()
        selectionLasso.removeAll()
        selectionBoundary.removeAll()
        isMoving = false
        isResizing = false
        resizeImageId = nil
        moveSnapshotTaken = false
        history.clear()
        updateUndoRedo()
    }

    // MARK: - Strokes

    func beginStroke(at point: CGPoint, isEraser: Bool) {
        let isSharpie = currentTool == .sharpie
        let pIdx: Int
        if isEraser { pIdx = -1 }
        else if isSharpie { pIdx = sharpiePresetIndex }
        else { pIdx = penPresetIndex }
        currentStroke = Stroke(
            points: [point],
            color: isEraser ? .white : isSharpie ? sharpieColor : penColor,
            lineWidth: isEraser ? eraserSettings.size : isSharpie ? sharpieSettings.thickness : penSettings.thickness,
            isEraser: isEraser,
            presetIndex: pIdx,
            isCatmullRom: !isEraser,
            isSharpie: isSharpie
        )
    }

    func addPoint(_ point: CGPoint) {
        guard let last = currentStroke?.points.last else {
            currentStroke?.points.append(point)
            return
        }
        // Filter duplicate / sub-pixel jitter points in canvas space.
        if GeometryEngine.distanceSquared(last, point) < minStrokePointDistanceSq {
            return
        }
        currentStroke?.points.append(point)
    }

    func endStroke() {
        guard let stroke = currentStroke else { return }
        currentStroke = nil

        if stroke.isEraser {
            let updated = GeometryEngine.erase(
                strokes: strokes,
                with: stroke,
                mode: eraserSettings.mode,
                target: eraserSettings.eraseTarget,
                spatialGrid: spatialGrid
            )
            if updated.count != strokes.count || !zip(updated, strokes).allSatisfy({ $0.id == $1.id && $0.points.count == $1.points.count }) {
                saveState()
                strokes = updated
                spatialGrid.rebuild(with: strokes)
                updateUndoRedo()
                scheduleAutoSave()
            }
            return
        }

        guard stroke.points.count >= 2 else { return }
        saveState()
        strokes.append(stroke)
        spatialGrid.sync(with: strokes)
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Lasso Selection

    func beginLasso(at point: CGPoint) {
        selectionLasso = [point]
    }

    func addLassoPoint(_ point: CGPoint) {
        if let last = selectionLasso.last, GeometryEngine.distanceSquared(last, point) < 25 { return }
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
        selectedImageIds.removeAll()

        spatialGrid.sync(with: strokes)
        let candidateIndices = spatialGrid.queryIndices(in: path.boundingBoxOfPath)
        for idx in candidateIndices {
            let stroke = strokes[idx]
            guard !stroke.isEraser else { continue }
            for p in stroke.points where path.contains(p) {
                selectedStrokeIds.insert(stroke.id)
                break
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

    // MARK: - Move & Resize Selection

    func isPointOnSelectedItem(_ point: CGPoint) -> Bool {
        let thresholdSq: CGFloat = 15 * 15
        for s in strokes where selectedStrokeIds.contains(s.id) {
            guard s.points.count >= 2 else { continue }
            for i in 0..<(s.points.count - 1) {
                if GeometryEngine.pointSegmentDistanceSquared(point, s.points[i], s.points[i + 1]) < thresholdSq {
                    return true
                }
            }
        }
        for img in placedImages where selectedImageIds.contains(img.id) {
            if CGRect(origin: img.cgPosition, size: img.cgSize).contains(point) {
                return true
            }
        }
        return false
    }

    func hitTestImage(_ point: CGPoint) -> UUID? {
        for img in placedImages.reversed() {
            if CGRect(origin: img.cgPosition, size: img.cgSize).contains(point) {
                return img.id
            }
        }
        return nil
    }

    func isPointInSelectionBoundary(_ point: CGPoint) -> Bool {
        GeometryEngine.pointInPolygon(point, selectionBoundary)
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
        if let hit = hitTestResizeHandle(point) {
            isResizing = true
            resizeCorner = hit.corner
            resizeImageId = hit.imgId
            lastMovePoint = point
            moveSnapshotTaken = false
            if let img = placedImages.first(where: { $0.id == hit.imgId }) {
                resizeStartRect = CGRect(origin: img.cgPosition, size: img.cgSize)
            }
            return
        }
        if !selectionBoundary.isEmpty && GeometryEngine.pointInPolygon(point, selectionBoundary) {
            isMoving = true
            lastMovePoint = point
            moveSnapshotTaken = false
            return
        }
        guard isPointOnSelectedItem(point) else {
            selectedStrokeIds.removeAll()
            selectedImageIds.removeAll()
            selectionBoundary.removeAll()
            beginLasso(at: point)
            return
        }
        isMoving = true
        lastMovePoint = point
        moveSnapshotTaken = false
    }

    func commitMove() {
        let didMutate = moveSnapshotTaken
        isResizing = false
        isMoving = false
        resizeImageId = nil
        moveSnapshotTaken = false
        if didMutate {
            spatialGrid.rebuild(with: strokes)
            updateUndoRedo()
            scheduleAutoSave()
        }
    }

    func moveSelected(by offset: CGSize) {
        guard offset != .zero else { return }

        if isResizing {
            guard let imgId = resizeImageId,
                  let newRect = GeometryEngine.resizedRect(start: resizeStartRect, corner: resizeCorner, offset: offset) else {
                return
            }
            if !moveSnapshotTaken {
                saveState()
                moveSnapshotTaken = true
            }
            placedImages = placedImages.map { img in
                guard img.id == imgId else { return img }
                return PlacedImage(id: img.id, position: newRect.origin, size: newRect.size, imageData: img.imageData)
            }
            resizeStartRect = newRect
            return
        }

        guard isMoving else { return }
        if !moveSnapshotTaken {
            saveState()
            moveSnapshotTaken = true
        }
        strokes = strokes.map { s in
            guard selectedStrokeIds.contains(s.id) else { return s }
            return Stroke(
                id: s.id,
                points: s.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) },
                color: s.uiColor,
                lineWidth: s.lineWidth,
                isEraser: s.isEraser,
                presetIndex: s.presetIndex,
                isCatmullRom: s.isCatmullRom,
                isSharpie: s.isSharpie
            )
        }
        placedImages = placedImages.map { img in
            guard selectedImageIds.contains(img.id) else { return img }
            return PlacedImage(
                id: img.id,
                position: CGPoint(x: img.cgPosition.x + offset.width, y: img.cgPosition.y + offset.height),
                size: img.cgSize,
                imageData: img.imageData
            )
        }
        if !selectionBoundary.isEmpty {
            selectionBoundary = selectionBoundary.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }

    func smoothCatmullRom(_ points: [CGPoint]) -> [CGPoint] {
        GeometryEngine.smoothCatmullRom(points)
    }

    func deleteSelected() {
        guard !selectedStrokeIds.isEmpty || !selectedImageIds.isEmpty || !selectionBoundary.isEmpty else { return }
        saveState()
        if !selectedStrokeIds.isEmpty || !selectedImageIds.isEmpty {
            strokes = strokes.filter { !selectedStrokeIds.contains($0.id) }
            for id in selectedImageIds { imageCache.removeValue(forKey: id) }
            placedImages = placedImages.filter { !selectedImageIds.contains($0.id) }
            selectedStrokeIds.removeAll()
            selectedImageIds.removeAll()
        }
        selectionBoundary.removeAll()
        spatialGrid.rebuild(with: strokes)
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Copy / Paste

    func copySelected() {
        guard !selectedStrokeIds.isEmpty || !selectedImageIds.isEmpty else { return }
        let copiedStrokes = try? JSONEncoder().encode(strokes.filter { selectedStrokeIds.contains($0.id) })
        let copiedImages = try? JSONEncoder().encode(placedImages.filter { selectedImageIds.contains($0.id) })
        let copiedBoundary = try? JSONEncoder().encode(selectionBoundary)

        #if os(iOS)
        let data: [String: Any] = [
            "strokes": copiedStrokes ?? Data(),
            "images": copiedImages ?? Data(),
            "boundary": copiedBoundary ?? Data(),
        ]
        UIPasteboard.general.items = [data]
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        let stringData: [String: String] = [
            "strokes": (copiedStrokes ?? Data()).base64EncodedString(),
            "images": (copiedImages ?? Data()).base64EncodedString(),
            "boundary": (copiedBoundary ?? Data()).base64EncodedString(),
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
        let imagesData = item["images"] as? Data ?? Data()
        let boundaryData = item["boundary"] as? Data ?? Data()
        #else
        guard let json = NSPasteboard.general.data(forType: .string),
              let item = try? JSONSerialization.jsonObject(with: json) as? [String: String] else { return }
        let strokesData = Data(base64Encoded: item["strokes"] ?? "") ?? Data()
        let imagesData = Data(base64Encoded: item["images"] ?? "") ?? Data()
        let boundaryData = Data(base64Encoded: item["boundary"] ?? "") ?? Data()
        #endif

        let decodedStrokes = (try? JSONDecoder().decode([Stroke].self, from: strokesData)) ?? []
        let decodedImages = (try? JSONDecoder().decode([PlacedImage].self, from: imagesData)) ?? []
        guard !decodedStrokes.isEmpty || !decodedImages.isEmpty else { return }

        saveState()

        let pasteOrigin = lastCanvasTapLocation == .zero ? CGPoint(x: 100, y: 100) : lastCanvasTapLocation
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        for s in decodedStrokes {
            for p in s.points {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
            }
        }
        for img in decodedImages {
            minX = min(minX, img.cgPosition.x)
            minY = min(minY, img.cgPosition.y)
        }
        let dx = minX.isFinite ? pasteOrigin.x - minX : 0
        let dy = minY.isFinite ? pasteOrigin.y - minY : 0

        var pastedStrokeIds = Set<UUID>()
        var pastedImageIds = Set<UUID>()

        for s in decodedStrokes {
            let newPoints = s.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            let newStroke = Stroke(
                points: newPoints,
                color: s.uiColor,
                lineWidth: s.lineWidth,
                isEraser: false,
                presetIndex: s.presetIndex,
                isCatmullRom: s.isCatmullRom,
                isSharpie: s.isSharpie
            )
            pastedStrokeIds.insert(newStroke.id)
            strokes.append(newStroke)
        }
        for img in decodedImages {
            let newPos = CGPoint(x: img.cgPosition.x + dx, y: img.cgPosition.y + dy)
            let newImg = PlacedImage(position: newPos, size: img.cgSize, imageData: img.imageData)
            pastedImageIds.insert(newImg.id)
            placedImages.append(newImg)
        }
        selectedStrokeIds = pastedStrokeIds
        selectedImageIds = pastedImageIds
        if let boundary = try? JSONDecoder().decode([CGPoint].self, from: boundaryData), !boundary.isEmpty {
            selectionBoundary = boundary.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        } else {
            selectionBoundary.removeAll()
        }
        spatialGrid.rebuild(with: strokes)
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Images

    func addImage(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            reportError("Could not read image file \(url.lastPathComponent).")
            return
        }
        #if os(iOS)
        guard let uiImg = UIImage(data: data), uiImg.size.width > 0, uiImg.size.height > 0 else {
            reportError("Unsupported or empty image file.")
            return
        }
        let originalSize = uiImg.size
        #else
        guard let nsImg = NSImage(data: data), nsImg.size.width > 0, nsImg.size.height > 0 else {
            reportError("Unsupported or empty image file.")
            return
        }
        let originalSize = nsImg.size
        #endif

        let maxWidth: CGFloat = 400
        let width = min(originalSize.width, maxWidth)
        let aspect = originalSize.height / originalSize.width
        let finalSize = CGSize(width: width, height: max(1, width * aspect))

        let resizedData: Data = {
            #if os(iOS)
            let renderer = UIGraphicsImageRenderer(size: finalSize)
            let resized = renderer.image { _ in
                uiImg.draw(in: CGRect(origin: .zero, size: finalSize))
            }
            return resized.pngData() ?? data
            #else
            let targetSize = NSSize(width: finalSize.width, height: finalSize.height)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(targetSize.width.rounded()),
                pixelsHigh: Int(targetSize.height.rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return data }
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                nsImg.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep.representation(using: .png, properties: [:]) ?? data
            #endif
        }()

        let pos = lastCanvasTapLocation == .zero ? CGPoint(x: 100, y: 100) : lastCanvasTapLocation
        saveState()
        let img = PlacedImage(position: pos, size: finalSize, imageData: resizedData)
        placedImages.append(img)
        selectTool(.select)
        selectedImageIds = [img.id]
        selectedStrokeIds.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
        scheduleAutoSave()
    }

    func resizeSelectedImages(by factor: CGFloat) {
        guard !selectedImageIds.isEmpty, factor > 0, factor.isFinite else { return }
        saveState()
        placedImages = placedImages.map { img in
            guard selectedImageIds.contains(img.id) else { return img }
            let newW = max(10, img.cgSize.width * factor)
            let newH = max(10, img.cgSize.height * factor)
            return PlacedImage(id: img.id, position: img.cgPosition, size: CGSize(width: newW, height: newH), imageData: img.imageData)
        }
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Tool, Undo, Redo, Clear

    func selectTool(_ tool: Tool) {
        currentTool = tool
        if tool != .select {
            selectedStrokeIds.removeAll()
            selectedImageIds.removeAll()
            selectionBoundary.removeAll()
        }
        showDeleteMenu = false
        showClearConfirmation = false
    }

    func undo() {
        guard let prev = history.undo(current: makeSnapshot()) else { return }
        strokes = prev.strokes
        placedImages = prev.placedImages
        selectedStrokeIds = prev.selectedStrokeIds
        selectedImageIds = prev.selectedImageIds
        selectionBoundary = prev.selectionBoundary
        spatialGrid.rebuild(with: strokes)
        pruneImageCache()
        updateUndoRedo()
        scheduleAutoSave()
    }

    func redo() {
        guard let next = history.redo(current: makeSnapshot()) else { return }
        strokes = next.strokes
        placedImages = next.placedImages
        selectedStrokeIds = next.selectedStrokeIds
        selectedImageIds = next.selectedImageIds
        selectionBoundary = next.selectionBoundary
        spatialGrid.rebuild(with: strokes)
        pruneImageCache()
        updateUndoRedo()
        scheduleAutoSave()
    }

    private func pruneImageCache() {
        let activeIds = Set(placedImages.map(\.id))
        imageCache = imageCache.filter { activeIds.contains($0.key) }
    }

    func clear() {
        saveState()
        strokes.removeAll()
        placedImages.removeAll()
        imageCache.removeAll()
        spatialGrid.invalidate()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedImageIds.removeAll()
        selectionLasso.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Save / Load / Export

    /// Portable JSON `.wb` export payload (always embeds images for single-file sharing).
    func saveData() -> Data? {
        let data = SaveData(strokes: strokes, placedImages: placedImages)
        return try? JSONEncoder().encode(data)
    }

    func loadData(_ data: Data) {
        do {
            let save = try JSONDecoder().decode(SaveData.self, from: data)
            saveState()
            strokes = save.strokes
            placedImages = save.placedImages
            imageCache.removeAll()
            migratePresetIndices()
            spatialGrid.rebuild(with: strokes)
            updateUndoRedo()
        } catch {
            reportError("Failed to open file: \(error.localizedDescription)")
        }
    }

    func migratePresetIndices() {
        let penCandidates = appSettings.isDarkMode ? penSettings.darkPresets : penSettings.lightPresets
        let sharpieCandidates = appSettings.isDarkMode ? sharpieSettings.darkPresets : sharpieSettings.lightPresets

        for i in strokes.indices where strokes[i].presetIndex == -1 && !strokes[i].isEraser {
            let s = strokes[i]
            let candidates = s.isSharpie ? sharpieCandidates : penCandidates
            let tr = s.color.r, tg = s.color.g, tb = s.color.b
            var bestIdx = -1
            var bestDist = Double.infinity

            for (j, c) in candidates.enumerated() {
                let pc = CodableColor(c)
                let d = (tr - pc.r) * (tr - pc.r) + (tg - pc.g) * (tg - pc.g) + (tb - pc.b) * (tb - pc.b)
                if d < bestDist { bestDist = d; bestIdx = j }
            }
            if bestIdx >= 0 {
                strokes[i] = Stroke(
                    id: s.id,
                    points: s.points,
                    color: s.uiColor,
                    lineWidth: s.lineWidth,
                    isEraser: s.isEraser,
                    presetIndex: bestIdx,
                    isCatmullRom: s.isCatmullRom,
                    isSharpie: s.isSharpie
                )
            }
        }
    }

    func save() {
        guard let url = openFileURL else { return }
        let shouldStop = url.startAccessingSecurityScopedResource()
        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = saveData() else {
            reportError("Failed to encode board data.")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            reportError("Failed to save file: \(error.localizedDescription)")
        }
    }

    // MARK: - Menu command helpers

    func openCmd() { pendingAction = .open }
    func closeBoard() {
        flushAutoSave()
        showWelcome = true
    }
    func exportPNG() { pendingAction = .export(.png) }
    func exportPDF() { pendingAction = .export(.pdf) }

    func canvasBoundingRect(padding: CGFloat = 40) -> (size: CGSize, offset: CGPoint) {
        guard let box = GeometryEngine.boundingBox(of: strokes, images: placedImages, padding: padding) else {
            return (CGSize(width: 1000, height: 1000), .zero)
        }
        return (box.size, box.origin)
    }

    func pngData(size: CGSize, offset: CGPoint = .zero, scale: CGFloat = 3) -> Data? {
        StrokeRenderer.pngData(
            strokes: strokes,
            placedImages: placedImages,
            penPresets: penPresets,
            sharpiePresets: sharpiePresets,
            isDarkMode: appSettings.isDarkMode,
            size: size,
            offset: offset,
            scale: scale
        )
    }

    func pngData(forBoardId id: String) -> Data? {
        let save: SaveData
        if id == currentBoardId {
            save = SaveData(strokes: strokes, placedImages: placedImages)
        } else if let loaded = store.loadBoardData(id: id) {
            save = loaded
        } else {
            return nil
        }
        guard let box = GeometryEngine.boundingBox(of: save.strokes, images: save.placedImages, padding: 40) else {
            return nil
        }
        return StrokeRenderer.pngData(
            strokes: save.strokes,
            placedImages: save.placedImages,
            penPresets: penPresets,
            sharpiePresets: sharpiePresets,
            isDarkMode: appSettings.isDarkMode,
            size: box.size,
            offset: box.origin,
            scale: 3
        )
    }

    func pdfData(size: CGSize, offset: CGPoint = .zero) -> Data? {
        StrokeRenderer.pdfData(
            strokes: strokes,
            placedImages: placedImages,
            penPresets: penPresets,
            sharpiePresets: sharpiePresets,
            isDarkMode: appSettings.isDarkMode,
            size: size,
            offset: offset
        )
    }

    // MARK: - Persistent Disk + Memory Async Thumbnails

    func thumbnail(for boardId: String, size: CGSize = CGSize(width: 240, height: 320)) -> PlatformImage? {
        let isDark = appSettings.isDarkMode
        let key = "\(boardId)|\(isDark ? 1 : 0)|\(Int(size.width))x\(Int(size.height))"
        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }
        guard !inFlightThumbnails.contains(key) else { return nil }
        inFlightThumbnails.insert(key)

        let penP = penPresets
        let sharpieP = sharpiePresets
        let inMemorySave: SaveData? = (boardId == currentBoardId)
            ? SaveData(strokes: strokes, placedImages: placedImages)
            : nil
        let boardStore = self.store
        let renderSize = CGSize(width: 240, height: 320)

        thumbnailQueue.async { [weak self] in
            var rendered: PlatformImage?

            // 1. Fast path: load pre-rendered PNG thumbnail directly from disk
            if inMemorySave == nil,
               let diskData = boardStore.loadDiskThumbnail(for: boardId, isDark: isDark),
               let img = PlatformImage(data: diskData) {
                rendered = img
            } else {
                // 2. Render from board data and persist PNG thumbnail to disk
                let save = inMemorySave ?? boardStore.loadBoardData(id: boardId)
                if let save, (!save.strokes.isEmpty || !save.placedImages.isEmpty) {
                    rendered = StrokeRenderer.renderThumbnail(
                        strokes: save.strokes,
                        placedImages: save.placedImages,
                        penPresets: penP,
                        sharpiePresets: sharpieP,
                        isDarkMode: isDark,
                        size: renderSize
                    )
                    if let rendered, let png = StrokeRenderer.encodeThumbnailPNG(rendered) {
                        boardStore.saveDiskThumbnail(for: boardId, isDark: isDark, pngData: png)
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlightThumbnails.remove(key)
                if let rendered {
                    self.thumbnailCache.setObject(rendered, forKey: key as NSString)
                    self.thumbnailKeys.insert(key)
                    self.thumbnailRevision &+= 1
                }
            }
        }
        return nil
    }

    func invalidateThumbnail(for boardId: String) {
        let prefix = "\(boardId)|"
        for key in thumbnailKeys where key.hasPrefix(prefix) {
            thumbnailCache.removeObject(forKey: key as NSString)
        }
        thumbnailKeys = thumbnailKeys.filter { !$0.hasPrefix(prefix) }
        inFlightThumbnails = inFlightThumbnails.filter { !$0.hasPrefix(prefix) }
        store.invalidateDiskThumbnails(for: boardId)
    }
}
