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
    case pen, sharpie, fill, eraser, select
}

/// Every configurable item that can live on either the floating canvas toolbar
/// or inside the More menu.
nonisolated enum ToolbarItemID: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case pen
    case sharpie
    case fill
    case eraser
    case select
    case scenes
    case home
    case undo
    case redo
    case clear
    case copy
    case paste
    case importPhoto
    case importImage
    case center
    case darkMode
    case singleTapOptions
    case pencilOnly
    case exportWB
    case exportPNG
    case exportPDF
    case openFile
    case help
    case about

    var id: String { rawValue }

    static let defaultPinned: [ToolbarItemID] = [
        .pen, .sharpie, .fill, .eraser, .select, .scenes, .home
    ]

    static var platformCases: [ToolbarItemID] {
        #if os(iOS)
        return allCases
        #else
        return allCases.filter { $0 != .importPhoto }
        #endif
    }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .sharpie: return "Sharpie"
        case .fill: return "Fill"
        case .eraser: return "Eraser"
        case .select: return "Select"
        case .scenes: return "Scenes"
        case .home: return "Home"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .clear: return "Clear / Delete"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .importPhoto: return "Photos"
        case .importImage: return "Import Image"
        case .center: return "Center Canvas"
        case .darkMode: return "Theme"
        case .singleTapOptions: return "Single-Tap Options"
        case .pencilOnly: return "Pencil Only"
        case .exportWB: return "Save .wb"
        case .exportPNG: return "Export PNG"
        case .exportPDF: return "Export PDF"
        case .openFile: return "Open .wb"
        case .help: return "Help"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .sharpie: return "pencil"
        case .fill: return "drop.fill"
        case .eraser: return "eraser"
        case .select: return "cursorarrow.click"
        case .scenes: return "rectangle.stack"
        case .home: return "house"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .clear: return "trash"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .importPhoto: return "photo.on.rectangle"
        case .importImage: return "photo"
        case .center: return "viewfinder"
        case .darkMode: return "moon.fill"
        case .singleTapOptions: return "hand.tap"
        case .pencilOnly: return "applepencil"
        case .exportWB: return "square.and.arrow.down"
        case .exportPNG: return "photo.badge.arrow.down"
        case .exportPDF: return "doc.richtext"
        case .openFile: return "folder"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        }
    }

    var associatedTool: Tool? {
        switch self {
        case .pen: return .pen
        case .sharpie: return .sharpie
        case .fill: return .fill
        case .eraser: return .eraser
        case .select: return .select
        default: return nil
        }
    }
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

enum FillOverlapMode: String, CaseIterable {
    case replace = "Replace"
    case blend = "Blend"
}

struct FillSettings {
    var lightColor: Color = Color(red: 0.0, green: 0.35, blue: 1.0)
    var darkColor: Color = Color(red: 0.3, green: 0.6, blue: 1.0)
    var opacity: Double = 0.25
    let opacityOptions: [Double] = [0.25, 0.5, 0.75, 1.0]
    var gapTolerance: CGFloat = 2.5
    var overlapMode: FillOverlapMode = .replace
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
    case fill = "Fill"
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
    var fills: [FillShape] = [] {
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
    var fillPresetIndex: Int = 5 {
        didSet { scheduleSettingsSave() }
    }
    var penSettings = PenSettings() {
        didSet { scheduleSettingsSave() }
    }
    var sharpieSettings = SharpieSettings() {
        didSet { scheduleSettingsSave() }
    }
    var fillSettings = FillSettings() {
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
    var scenes: [CanvasScene] = []
    var activeSceneId: UUID?
    var pendingSceneNavigation: CanvasScene?

    var selectionLasso: [CGPoint] = []
    var selectionBoundary: [CGPoint] = []
    var selectedStrokeIds: Set<UUID> = []
    var selectedImageIds: Set<UUID> = []
    var selectedFillIds: Set<UUID> = []

    var pendingAction: PendingAction?
    var showDeleteMenu: Bool = false
    var deleteMenuLocation: CGPoint = .zero
    var showClearConfirmation: Bool = false
    var showAbout: Bool = false
    var isToolbarVisible: Bool = true
    var showWelcome: Bool = true
    var needsRecenter: Bool = false
    var welcomeFolderName: String?
    var lastErrorMessage: String?
    var pinnedToolbarItems: [ToolbarItemID] = ToolbarItemID.defaultPinned

    /// Bumped whenever committed strokes or placed images change so the canvas
    /// backing store knows when to re-bake (or incrementally append).
    private(set) var committedRevision: Int = 0
    /// Bumped when background thumbnail generation finishes so WelcomeView refreshes.
    private(set) var thumbnailRevision: Int = 0

    @ObservationIgnored var currentStroke: Stroke?
    @ObservationIgnored var previousTool: Tool = .pen
    @ObservationIgnored var lastCanvasTapLocation: CGPoint = .zero
    @ObservationIgnored var currentViewportCenter: CGPoint = .zero
    @ObservationIgnored var currentViewportScale: CGFloat = 1.0
    @ObservationIgnored var needsDefaultSceneCapture: Bool = false
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
    @ObservationIgnored private let toolbarLayoutKey = "pinnedToolbarItems"

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
        loadToolbarLayout()
        loadRecents()
        loadBoards()
        isInitializing = false
    }

    // MARK: - Configurable Toolbar Layout

    var unpinnedToolbarItems: [ToolbarItemID] {
        let pinnedSet = Set(pinnedToolbarItems)
        return ToolbarItemID.platformCases.filter { !pinnedSet.contains($0) }
    }

    private func loadToolbarLayout() {
        guard let data = userDefaults.data(forKey: toolbarLayoutKey),
              let decoded = try? JSONDecoder().decode([ToolbarItemID].self, from: data) else {
            pinnedToolbarItems = ToolbarItemID.defaultPinned
            return
        }
        let valid = Set(ToolbarItemID.platformCases)
        var seen = Set<ToolbarItemID>()
        let filtered = decoded.filter { valid.contains($0) && seen.insert($0).inserted }
        pinnedToolbarItems = filtered
    }

    private func saveToolbarLayout() {
        if let data = try? JSONEncoder().encode(pinnedToolbarItems) {
            userDefaults.set(data, forKey: toolbarLayoutKey)
        }
    }

    func pinToolbarItem(_ item: ToolbarItemID, before target: ToolbarItemID? = nil) {
        guard ToolbarItemID.platformCases.contains(item) else { return }
        if item == target { return }
        pinnedToolbarItems.removeAll { $0 == item }
        if let target, let idx = pinnedToolbarItems.firstIndex(of: target) {
            pinnedToolbarItems.insert(item, at: idx)
        } else {
            pinnedToolbarItems.append(item)
        }
        saveToolbarLayout()
    }

    func unpinToolbarItem(_ item: ToolbarItemID) {
        pinnedToolbarItems.removeAll { $0 == item }
        saveToolbarLayout()
    }

    func resetToolbarLayout() {
        pinnedToolbarItems = ToolbarItemID.defaultPinned
        saveToolbarLayout()
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
        fillSettings = FillSettings()
        eraserSettings = EraserSettings()
        appSettings = AppSettings()
        currentTool = .pen
        previousTool = .pen
        penPresetIndex = 0
        sharpiePresetIndex = 0
        fillPresetIndex = 5
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
        let defaultScene = CanvasScene(name: "Scene 1", center: currentViewportCenter, scale: 1.0)
        scenes = [defaultScene]
        activeSceneId = defaultScene.id
        needsDefaultSceneCapture = true
        do {
            try store.saveBoardSync(id: meta.id, saveData: SaveData(strokes: [], placedImages: [], fills: [], scenes: scenes))
        } catch {
            reportError(error.localizedDescription)
        }
    }

    /// Creates a new board immediately with a unique default name (no modal prompt).
    @discardableResult
    func createQuickBoard(folderId: String? = nil) -> String {
        let base = "Untitled Tissue"
        let existingNames = Set(boards.map(\.name))
        var candidate = base
        var n = 2
        while existingNames.contains(candidate) {
            candidate = "\(base) \(n)"
            n += 1
        }
        createBoard(name: candidate, folderId: folderId)
        return currentBoardId ?? ""
    }

    func folderName(forBoardId boardId: String) -> String? {
        folders.first(where: { $0.boardIds.contains(boardId) })?.name
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

    func permanentlyDeleteTrashedBoard(id: String) {
        trashedBoards = store.permanentlyDeleteTrash(id: id)
    }

    func emptyTrash() {
        trashedBoards = store.emptyTrash()
    }

    func loadBoard(id: String) {
        flushAutoSave()
        do {
            let save = try store.loadBoard(id: id)
            resetCanvasState()
            strokes = save.strokes
            placedImages = save.placedImages
            fills = save.fills
            scenes = save.scenes
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

        let snapshot = SaveData(strokes: strokes, placedImages: placedImages, fills: fills, scenes: scenes)
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
            let snapshot = SaveData(strokes: strokes, placedImages: placedImages, fills: fills, scenes: scenes)
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
    var fillPresets: [Color] { appSettings.isDarkMode ? fillSettings.darkPresets : fillSettings.lightPresets }

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

    var fillColor: Color {
        if fillPresets.indices.contains(fillPresetIndex) {
            return fillPresets[fillPresetIndex]
        }
        return appSettings.isDarkMode ? fillSettings.darkColor : fillSettings.lightColor
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

    func selectFillPreset(_ index: Int) {
        guard fillSettings.lightPresets.indices.contains(index),
              fillSettings.darkPresets.indices.contains(index) else { return }
        fillPresetIndex = index
        fillSettings.lightColor = fillSettings.lightPresets[index]
        fillSettings.darkColor = fillSettings.darkPresets[index]
    }

    // MARK: - Flood Fill

    /// Flood-fills the nearest enclosed region bounded by pen/sharpie strokes around `point`.
    /// Returns `true` if a closed region was found and filled, `false` if open/unbounded.
    @discardableResult
    func floodFill(at point: CGPoint) -> Bool {
        guard let contours = FloodFillEngine.computeContours(
            at: point,
            strokes: strokes,
            gapTolerance: fillSettings.gapTolerance
        ) else {
            return false
        }
        saveState()
        let shape = FillShape(
            contours: contours,
            color: fillColor,
            opacity: fillSettings.opacity,
            presetIndex: fillPresetIndex
        )
        if fillSettings.overlapMode == .replace {
            let newBox = shape.boundingBox()
            let expandedNewBox = newBox.insetBy(dx: -8, dy: -8)
            fills.removeAll { existing in
                let oldBox = existing.boundingBox()
                guard !oldBox.isNull, oldBox.intersects(newBox) else { return false }
                guard existing.makeCGPath().contains(point, using: .evenOdd) else { return false }
                if expandedNewBox.contains(oldBox) { return true }
                let inter = oldBox.intersection(newBox)
                let interArea = max(0, inter.width) * max(0, inter.height)
                let unionArea = oldBox.width * oldBox.height + newBox.width * newBox.height - interArea
                return unionArea > 0 && (interArea / unionArea) > 0.7
            }
        }
        fills.append(shape)
        updateUndoRedo()
        scheduleAutoSave()
        return true
    }

    // MARK: - History Helpers

    private func makeSnapshot() -> CanvasSnapshot {
        CanvasSnapshot(
            strokes: strokes,
            placedImages: placedImages,
            fills: fills,
            selectedStrokeIds: selectedStrokeIds,
            selectedImageIds: selectedImageIds,
            selectedFillIds: selectedFillIds,
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
        fills.removeAll()
        scenes.removeAll()
        activeSceneId = nil
        pendingSceneNavigation = nil
        needsDefaultSceneCapture = false
        imageCache.removeAll()
        spatialGrid.invalidate()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedImageIds.removeAll()
        selectedFillIds.removeAll()
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
            let updatedStrokes: [Stroke]
            if eraserSettings.eraseTarget == .fill {
                updatedStrokes = strokes
            } else {
                updatedStrokes = GeometryEngine.erase(
                    strokes: strokes,
                    with: stroke,
                    mode: eraserSettings.mode,
                    target: eraserSettings.eraseTarget,
                    spatialGrid: spatialGrid
                )
            }
            let updatedFills: [FillShape]
            if (eraserSettings.eraseTarget == .all || eraserSettings.eraseTarget == .fill) && !fills.isEmpty {
                updatedFills = fills.filter { fill in
                    let path = fill.makeCGPath()
                    return !stroke.points.contains { path.contains($0, using: .evenOdd) }
                }
            } else {
                updatedFills = fills
            }

            let strokesChanged = updatedStrokes.count != strokes.count
                || !zip(updatedStrokes, strokes).allSatisfy({ $0.id == $1.id && $0.points.count == $1.points.count })
            let fillsChanged = updatedFills.count != fills.count
            if strokesChanged || fillsChanged {
                saveState()
                strokes = updatedStrokes
                fills = updatedFills
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
        selectedFillIds.removeAll()

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

        for fill in fills {
            let box = fill.boundingBox()
            guard !box.isNull else { continue }
            let center = CGPoint(x: box.midX, y: box.midY)
            if path.contains(center) || fill.contours.first?.contains(where: { path.contains($0) }) == true {
                selectedFillIds.insert(fill.id)
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
        for fill in fills where selectedFillIds.contains(fill.id) {
            if fill.makeCGPath().contains(point, using: .evenOdd) {
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
            selectedFillIds.removeAll()
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
        if !selectedFillIds.isEmpty {
            fills = fills.map { fill in
                guard selectedFillIds.contains(fill.id) else { return fill }
                let shifted = fill.contours.map { loop in
                    loop.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
                }
                return FillShape(id: fill.id, contours: shifted, color: fill.uiColor, opacity: fill.opacity, presetIndex: fill.presetIndex)
            }
        }
        if !selectionBoundary.isEmpty {
            selectionBoundary = selectionBoundary.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }

    func smoothCatmullRom(_ points: [CGPoint]) -> [CGPoint] {
        GeometryEngine.smoothCatmullRom(points)
    }

    func deleteSelected() {
        guard !selectedStrokeIds.isEmpty || !selectedImageIds.isEmpty || !selectedFillIds.isEmpty || !selectionBoundary.isEmpty else { return }
        saveState()
        if !selectedStrokeIds.isEmpty || !selectedImageIds.isEmpty || !selectedFillIds.isEmpty {
            strokes = strokes.filter { !selectedStrokeIds.contains($0.id) }
            for id in selectedImageIds { imageCache.removeValue(forKey: id) }
            placedImages = placedImages.filter { !selectedImageIds.contains($0.id) }
            fills = fills.filter { !selectedFillIds.contains($0.id) }
            selectedStrokeIds.removeAll()
            selectedImageIds.removeAll()
            selectedFillIds.removeAll()
        }
        selectionBoundary.removeAll()
        spatialGrid.rebuild(with: strokes)
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Copy / Paste

    func copySelected() {
        guard !selectedStrokeIds.isEmpty || !selectedImageIds.isEmpty || !selectedFillIds.isEmpty else { return }
        let copiedStrokes = try? JSONEncoder().encode(strokes.filter { selectedStrokeIds.contains($0.id) })
        let copiedImages = try? JSONEncoder().encode(placedImages.filter { selectedImageIds.contains($0.id) })
        let copiedFills = try? JSONEncoder().encode(fills.filter { selectedFillIds.contains($0.id) })
        let copiedBoundary = try? JSONEncoder().encode(selectionBoundary)

        #if os(iOS)
        let data: [String: Any] = [
            "strokes": copiedStrokes ?? Data(),
            "images": copiedImages ?? Data(),
            "fills": copiedFills ?? Data(),
            "boundary": copiedBoundary ?? Data(),
        ]
        UIPasteboard.general.items = [data]
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        let stringData: [String: String] = [
            "strokes": (copiedStrokes ?? Data()).base64EncodedString(),
            "images": (copiedImages ?? Data()).base64EncodedString(),
            "fills": (copiedFills ?? Data()).base64EncodedString(),
            "boundary": (copiedBoundary ?? Data()).base64EncodedString(),
        ]
        if let json = try? JSONSerialization.data(withJSONObject: stringData, options: .fragmentsAllowed) {
            pb.setData(json, forType: .string)
        }
        #endif
    }

    func paste() {
        #if os(iOS)
        let item = UIPasteboard.general.items.first
        let strokesData = item?["strokes"] as? Data ?? Data()
        let imagesData = item?["images"] as? Data ?? Data()
        let fillsData = item?["fills"] as? Data ?? Data()
        let boundaryData = item?["boundary"] as? Data ?? Data()
        #else
        var strokesData = Data()
        var imagesData = Data()
        var fillsData = Data()
        var boundaryData = Data()
        if let json = NSPasteboard.general.data(forType: .string),
           let item = try? JSONSerialization.jsonObject(with: json) as? [String: String] {
            strokesData = Data(base64Encoded: item["strokes"] ?? "") ?? Data()
            imagesData = Data(base64Encoded: item["images"] ?? "") ?? Data()
            fillsData = Data(base64Encoded: item["fills"] ?? "") ?? Data()
            boundaryData = Data(base64Encoded: item["boundary"] ?? "") ?? Data()
        }
        #endif

        let decodedStrokes = (try? JSONDecoder().decode([Stroke].self, from: strokesData)) ?? []
        let decodedImages = (try? JSONDecoder().decode([PlacedImage].self, from: imagesData)) ?? []
        let decodedFills = (try? JSONDecoder().decode([FillShape].self, from: fillsData)) ?? []
        guard !decodedStrokes.isEmpty || !decodedImages.isEmpty || !decodedFills.isEmpty else {
            // Fall back to pasting a standard system clipboard image (screenshots, Safari, Photos, Preview)
            pasteSystemClipboardImage()
            return
        }

        saveState()

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
        for fill in decodedFills {
            let box = fill.boundingBox()
            if !box.isNull {
                minX = min(minX, box.minX)
                minY = min(minY, box.minY)
            }
        }

        // If the user hasn't tapped elsewhere since copying, offset slightly (+24, +24)
        // so the pasted copy is clearly separated from the original selection.
        let dx: CGFloat
        let dy: CGFloat
        if lastCanvasTapLocation == .zero || (!selectionBoundary.isEmpty && GeometryEngine.pointInPolygon(lastCanvasTapLocation, selectionBoundary)) {
            dx = 24
            dy = 24
        } else {
            dx = minX.isFinite ? lastCanvasTapLocation.x - minX : 0
            dy = minY.isFinite ? lastCanvasTapLocation.y - minY : 0
        }

        var pastedStrokeIds = Set<UUID>()
        var pastedImageIds = Set<UUID>()
        var pastedFillIds = Set<UUID>()

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
        for fill in decodedFills {
            let shiftedContours = fill.contours.map { loop in
                loop.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
            let newFill = FillShape(
                contours: shiftedContours,
                color: fill.uiColor,
                opacity: fill.opacity,
                presetIndex: fill.presetIndex
            )
            pastedFillIds.insert(newFill.id)
            fills.append(newFill)
        }

        // Replace selection exclusively with the newly pasted items so dragging moves ONLY the paste.
        selectedStrokeIds = pastedStrokeIds
        selectedImageIds = pastedImageIds
        selectedFillIds = pastedFillIds
        if let boundary = try? JSONDecoder().decode([CGPoint].self, from: boundaryData), !boundary.isEmpty {
            selectionBoundary = boundary.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        } else {
            selectionBoundary.removeAll()
        }
        currentTool = .select
        spatialGrid.rebuild(with: strokes)
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Images

    @discardableResult
    private func pasteSystemClipboardImage() -> Bool {
        #if os(iOS)
        if let img = UIPasteboard.general.image,
           let data = img.pngData() ?? img.jpegData(compressionQuality: 0.85) {
            return addImage(data: data)
        }
        return false
        #else
        let pb = NSPasteboard.general
        if let pngData = pb.data(forType: .png) {
            return addImage(data: pngData)
        }
        if let tiffData = pb.data(forType: .tiff) {
            return addImage(data: tiffData)
        }
        if let nsImg = NSImage(pasteboard: pb), let tiff = nsImg.tiffRepresentation {
            return addImage(data: tiff)
        }
        return false
        #endif
    }

    @discardableResult
    func addImage(url: URL, at centerPoint: CGPoint? = nil, staggerIndex: Int = 0) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            reportError("Could not read image file \(url.lastPathComponent).")
            return false
        }
        return addImage(data: data, at: centerPoint, staggerIndex: staggerIndex)
    }

    /// Imports an image from raw `Data` (PNG, JPEG, HEIC, WebP, TIFF, GIF, BMP, etc.),
    /// preserving Retina sharpness (up to 1200 px long edge), using JPEG for opaque photos
    /// and PNG for transparent images, and centering it in the current viewport.
    @discardableResult
    func addImage(data: Data, at centerPoint: CGPoint? = nil, staggerIndex: Int = 0) -> Bool {
        let maxVisualDimension: CGFloat = 400
        let maxPixelDimension: CGFloat = 1200

        #if os(iOS)
        guard let uiImg = UIImage(data: data), uiImg.size.width > 0, uiImg.size.height > 0 else {
            reportError("Unsupported or empty image file.")
            return false
        }
        let rawPixelW = uiImg.size.width * uiImg.scale
        let rawPixelH = uiImg.size.height * uiImg.scale
        let visualScale = min(1.0, maxVisualDimension / max(uiImg.size.width, uiImg.size.height))
        let finalSize = CGSize(
            width: max(1, (uiImg.size.width * visualScale).rounded()),
            height: max(1, (uiImg.size.height * visualScale).rounded())
        )
        let pixelScale = min(1.0, maxPixelDimension / max(rawPixelW, rawPixelH))
        let pixelSize = CGSize(
            width: max(1, (rawPixelW * pixelScale).rounded()),
            height: max(1, (rawPixelH * pixelScale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let hasAlpha: Bool = {
            guard let info = uiImg.cgImage?.alphaInfo else { return true }
            return info == .first || info == .last || info == .premultipliedFirst || info == .premultipliedLast
        }()
        format.opaque = !hasAlpha
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let normalized = renderer.image { _ in
            uiImg.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        let encodedData: Data = hasAlpha
            ? (normalized.pngData() ?? data)
            : (normalized.jpegData(compressionQuality: 0.85) ?? normalized.pngData() ?? data)
        #else
        guard let nsImg = NSImage(data: data) else {
            reportError("Unsupported or empty image file.")
            return false
        }
        var proposed = NSRect(origin: .zero, size: nsImg.size)
        guard let cgImg = nsImg.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              cgImg.width > 0, cgImg.height > 0 else {
            reportError("Unsupported or empty image file.")
            return false
        }
        let rawPixelW = CGFloat(cgImg.width)
        let rawPixelH = CGFloat(cgImg.height)
        let visualScale = min(1.0, maxVisualDimension / max(rawPixelW, rawPixelH))
        let finalSize = CGSize(
            width: max(1, (rawPixelW * visualScale).rounded()),
            height: max(1, (rawPixelH * visualScale).rounded())
        )
        let pixelScale = min(1.0, maxPixelDimension / max(rawPixelW, rawPixelH))
        let pxW = max(1, Int((rawPixelW * pixelScale).rounded()))
        let pxH = max(1, Int((rawPixelH * pixelScale).rounded()))
        let alphaInfo = cgImg.alphaInfo
        let hasAlpha = alphaInfo == .first || alphaInfo == .last || alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast

        let encodedData: Data = {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pxW,
                pixelsHigh: pxH,
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
                ctx.imageInterpolation = .high
                nsImg.draw(
                    in: NSRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)),
                    from: NSRect(origin: .zero, size: nsImg.size),
                    operation: .copy,
                    fraction: 1
                )
            }
            NSGraphicsContext.restoreGraphicsState()
            if hasAlpha {
                return rep.representation(using: .png, properties: [:]) ?? data
            }
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                ?? rep.representation(using: .png, properties: [:])
                ?? data
        }()
        #endif

        let stagger = CGFloat(staggerIndex) * 24
        let anchor = centerPoint ?? currentViewportCenter
        let pos = CGPoint(
            x: anchor.x - finalSize.width / 2 + stagger,
            y: anchor.y - finalSize.height / 2 + stagger
        )
        saveState()
        let img = PlacedImage(position: pos, size: finalSize, imageData: encodedData)
        placedImages.append(img)
        selectTool(.select)
        selectedImageIds = [img.id]
        selectedStrokeIds.removeAll()
        selectedFillIds.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
        scheduleAutoSave()
        return true
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
        if tool != currentTool {
            previousTool = currentTool
        }
        currentTool = tool
        if tool != .select {
            selectedStrokeIds.removeAll()
            selectedImageIds.removeAll()
            selectedFillIds.removeAll()
            selectionBoundary.removeAll()
        }
        showDeleteMenu = false
        showClearConfirmation = false
    }

    /// Toggles between the Eraser and the previously active tool (used by Apple Pencil
    /// double-tap on iPadOS and over macOS Sidecar).
    func toggleEraserFromPencil() {
        if currentTool == .eraser {
            let target = previousTool == .eraser ? .pen : previousTool
            selectTool(target)
        } else {
            let prior = currentTool
            selectTool(.eraser)
            switch prior {
            case .pen: eraserSettings.eraseTarget = .pen
            case .sharpie: eraserSettings.eraseTarget = .sharpie
            case .fill: eraserSettings.eraseTarget = .fill
            default: eraserSettings.eraseTarget = .all
            }
        }
    }

    /// Cycles through drawing/selection tools (Pen → Sharpie → Fill → Select → Pen),
    /// used by Apple Pencil Pro squeeze on iPadOS and macOS Sidecar.
    func cycleToolFromPencil() {
        let order: [Tool] = [.pen, .sharpie, .fill, .select]
        if let idx = order.firstIndex(of: currentTool) {
            selectTool(order[(idx + 1) % order.count])
        } else {
            selectTool(.pen)
        }
    }

    func undo() {
        guard let prev = history.undo(current: makeSnapshot()) else { return }
        strokes = prev.strokes
        placedImages = prev.placedImages
        fills = prev.fills
        selectedStrokeIds = prev.selectedStrokeIds
        selectedImageIds = prev.selectedImageIds
        selectedFillIds = prev.selectedFillIds
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
        fills = next.fills
        selectedStrokeIds = next.selectedStrokeIds
        selectedImageIds = next.selectedImageIds
        selectedFillIds = next.selectedFillIds
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
        fills.removeAll()
        imageCache.removeAll()
        spatialGrid.invalidate()
        currentStroke = nil
        selectedStrokeIds.removeAll()
        selectedImageIds.removeAll()
        selectedFillIds.removeAll()
        selectionLasso.removeAll()
        selectionBoundary.removeAll()
        updateUndoRedo()
        scheduleAutoSave()
    }

    // MARK: - Scenes (Viewport Bookmarks)

    /// Called by `CanvasView` once the initial layout size is known for a newly created tissue,
    /// locking the default "Scene 1" to the exact initial viewport center and scale.
    func captureDefaultSceneIfNeeded() {
        guard needsDefaultSceneCapture, !scenes.isEmpty else { return }
        needsDefaultSceneCapture = false
        scenes[0].centerX = Double(currentViewportCenter.x)
        scenes[0].centerY = Double(currentViewportCenter.y)
        scenes[0].scale = Double(max(currentViewportScale, 0.1))
        scheduleAutoSave()
    }

    @discardableResult
    func addScene(name: String? = nil) -> CanvasScene {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmed?.isEmpty == false) ? trimmed! : "Scene \(scenes.count + 1)"
        let scene = CanvasScene(
            name: title,
            center: currentViewportCenter,
            scale: max(currentViewportScale, 0.1)
        )
        scenes.append(scene)
        activeSceneId = scene.id
        scheduleAutoSave()
        return scene
    }

    func goToScene(_ scene: CanvasScene) {
        activeSceneId = scene.id
        pendingSceneNavigation = scene
    }

    func goToNextScene() {
        guard !scenes.isEmpty else { return }
        if let activeId = activeSceneId,
           let idx = scenes.firstIndex(where: { $0.id == activeId }) {
            let next = scenes[(idx + 1) % scenes.count]
            goToScene(next)
        } else {
            goToScene(scenes[0])
        }
    }

    func goToPreviousScene() {
        guard !scenes.isEmpty else { return }
        if let activeId = activeSceneId,
           let idx = scenes.firstIndex(where: { $0.id == activeId }) {
            let prev = scenes[(idx - 1 + scenes.count) % scenes.count]
            goToScene(prev)
        } else {
            goToScene(scenes[scenes.count - 1])
        }
    }

    func updateSceneToCurrentView(id: UUID) {
        guard let idx = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[idx].centerX = Double(currentViewportCenter.x)
        scenes[idx].centerY = Double(currentViewportCenter.y)
        scenes[idx].scale = Double(max(currentViewportScale, 0.1))
        activeSceneId = id
        scheduleAutoSave()
    }

    func renameScene(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[idx].name = trimmed
        scheduleAutoSave()
    }

    func deleteScene(id: UUID) {
        scenes.removeAll { $0.id == id }
        if activeSceneId == id {
            activeSceneId = nil
        }
        scheduleAutoSave()
    }

    func moveScene(id: UUID, direction: Int) {
        guard let idx = scenes.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + direction
        guard target >= 0 && target < scenes.count else { return }
        let item = scenes.remove(at: idx)
        scenes.insert(item, at: target)
        scheduleAutoSave()
    }

    func moveScenes(fromOffsets source: IndexSet, toOffset destination: Int) {
        scenes.move(fromOffsets: source, toOffset: destination)
        scheduleAutoSave()
    }

    // MARK: - Save / Load / Export

    /// Portable JSON `.wb` export payload (always embeds images for single-file sharing).
    func saveData() -> Data? {
        let data = SaveData(strokes: strokes, placedImages: placedImages, fills: fills, scenes: scenes)
        return try? JSONEncoder().encode(data)
    }

    func loadData(_ data: Data) {
        do {
            let save = try JSONDecoder().decode(SaveData.self, from: data)
            saveState()
            strokes = save.strokes
            placedImages = save.placedImages
            fills = save.fills
            scenes = save.scenes
            activeSceneId = nil
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
        guard let box = GeometryEngine.boundingBox(of: strokes, images: placedImages, fills: fills, padding: padding) else {
            return (CGSize(width: 1000, height: 1000), .zero)
        }
        return (box.size, box.origin)
    }

    func pngData(size: CGSize, offset: CGPoint = .zero, scale: CGFloat = 3) -> Data? {
        StrokeRenderer.pngData(
            strokes: strokes,
            placedImages: placedImages,
            fills: fills,
            penPresets: penPresets,
            sharpiePresets: sharpiePresets,
            fillPresets: fillPresets,
            isDarkMode: appSettings.isDarkMode,
            size: size,
            offset: offset,
            scale: scale
        )
    }

    func pngData(forBoardId id: String) -> Data? {
        let save: SaveData
        if id == currentBoardId {
            save = SaveData(strokes: strokes, placedImages: placedImages, fills: fills)
        } else if let loaded = store.loadBoardData(id: id) {
            save = loaded
        } else {
            return nil
        }
        guard let box = GeometryEngine.boundingBox(of: save.strokes, images: save.placedImages, fills: save.fills, padding: 40) else {
            return nil
        }
        return StrokeRenderer.pngData(
            strokes: save.strokes,
            placedImages: save.placedImages,
            fills: save.fills,
            penPresets: penPresets,
            sharpiePresets: sharpiePresets,
            fillPresets: fillPresets,
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
            fills: fills,
            penPresets: penPresets,
            sharpiePresets: sharpiePresets,
            fillPresets: fillPresets,
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
        let fillP = fillPresets
        let inMemorySave: SaveData? = (boardId == currentBoardId)
            ? SaveData(strokes: strokes, placedImages: placedImages, fills: fills)
            : nil
        let boardStore = self.store
        let renderSize = CGSize(width: 320, height: 240)

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
                if let save, (!save.strokes.isEmpty || !save.placedImages.isEmpty || !save.fills.isEmpty) {
                    rendered = StrokeRenderer.renderThumbnail(
                        strokes: save.strokes,
                        placedImages: save.placedImages,
                        fills: save.fills,
                        penPresets: penP,
                        sharpiePresets: sharpieP,
                        fillPresets: fillP,
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
