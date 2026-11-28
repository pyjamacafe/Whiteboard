import CoreGraphics
import SwiftUI
import XCTest
@testable import Whiteboard

@MainActor
final class WhiteboardTests: XCTestCase {

    private var tempDir: URL!
    private var store: BoardStore!
    private var defaultsSuiteName: String!
    private var testDefaults: UserDefaults!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhiteboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = BoardStore(baseDirectory: tempDir)
        defaultsSuiteName = "com.whiteboard.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        if let defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }
    }

    // MARK: - GeometryEngine Tests

    func testMakeCGPathHandlesTwoPointCatmullRomStroke() {
        let stroke = Stroke(
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 80)],
            color: .black,
            lineWidth: 3,
            isEraser: false,
            presetIndex: 0,
            isCatmullRom: true
        )
        let path = GeometryEngine.makeCGPath(for: stroke)
        XCTAssertNotNil(path)
        XCTAssertFalse(path!.isEmpty)
    }

    func testBoundingBoxSupportsNegativeCoordinatesAndPlacedImages() {
        let negStroke = Stroke(
            points: [CGPoint(x: -200, y: -150), CGPoint(x: -50, y: -25)],
            color: .black,
            lineWidth: 4,
            isEraser: false
        )
        let img = PlacedImage(
            position: CGPoint(x: -300, y: -250),
            size: CGSize(width: 40, height: 30),
            imageData: Data([0x00])
        )

        let box = GeometryEngine.boundingBox(of: [negStroke], images: [img], padding: 10)
        XCTAssertNotNil(box)
        XCTAssertEqual(box!.minX, -310, accuracy: 0.01)
        XCTAssertEqual(box!.minY, -260, accuracy: 0.01)
        XCTAssertEqual(box!.maxX, -38, accuracy: 0.01) // -50 + halfWidth(2) + padding(10)
        XCTAssertEqual(box!.maxY, -13, accuracy: 0.01) // -25 + halfWidth(2) + padding(10)

        // Image-only board still produces a valid bounding box
        let imgOnlyBox = GeometryEngine.boundingBox(of: [], images: [img], padding: 0)
        XCTAssertNotNil(imgOnlyBox)
        XCTAssertEqual(imgOnlyBox!.width, 40, accuracy: 0.01)
        XCTAssertEqual(imgOnlyBox!.height, 30, accuracy: 0.01)
    }

    func testResizedRectGuardsAgainstZeroDimensions() {
        XCTAssertNil(GeometryEngine.resizedRect(start: .zero, corner: 2, offset: CGSize(width: 10, height: 10)))
        XCTAssertNil(GeometryEngine.resizedRect(start: CGRect(x: 0, y: 0, width: 100, height: 0), corner: 2, offset: CGSize(width: 10, height: 10)))

        let valid = GeometryEngine.resizedRect(
            start: CGRect(x: 0, y: 0, width: 100, height: 50),
            corner: 2,
            offset: CGSize(width: 20, height: 5)
        )
        XCTAssertNotNil(valid)
        XCTAssertEqual(valid!.width, 120, accuracy: 0.01)
        XCTAssertEqual(valid!.height, 60, accuracy: 0.01) // aspect ratio preserved (2:1)
    }

    func testEraseFullStrokeDetectsSparseCrossingSegments() {
        // Long horizontal pen stroke with only 2 endpoints
        let penStroke = Stroke(
            points: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)],
            color: .black,
            lineWidth: 2,
            isEraser: false,
            isSharpie: false
        )
        let sharpieStroke = Stroke(
            points: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)],
            color: .red,
            lineWidth: 4,
            isEraser: false,
            isSharpie: true
        )
        // Vertical eraser crossing at x = 100 (far from both endpoints!)
        let eraser = Stroke(
            points: [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)],
            color: .white,
            lineWidth: 10,
            isEraser: true
        )

        let afterPenErase = GeometryEngine.erase(
            strokes: [penStroke, sharpieStroke],
            with: eraser,
            mode: .full,
            target: .pen
        )
        XCTAssertEqual(afterPenErase.count, 1)
        XCTAssertTrue(afterPenErase[0].isSharpie)
    }

    func testErasePartialSplitsStroke() {
        let penStroke = Stroke(
            points: (0...10).map { CGPoint(x: CGFloat($0) * 10, y: 0) },
            color: .black,
            lineWidth: 2,
            isEraser: false
        )
        let eraser = Stroke(
            points: [CGPoint(x: 50, y: -10), CGPoint(x: 50, y: 10)],
            color: .white,
            lineWidth: 12,
            isEraser: true
        )

        let result = GeometryEngine.erase(strokes: [penStroke], with: eraser, mode: .partial, target: .all)
        XCTAssertEqual(result.count, 2, "Stroke should be split into two segments around x=50")
    }

    // MARK: - CanvasHistory Tests

    func testCanvasHistoryEnforcesMaxSnapshotsAndRestoresImages() {
        var history = CanvasHistory(maxSnapshots: 3)
        let img = PlacedImage(position: CGPoint(x: 10, y: 10), size: CGSize(width: 50, height: 50), imageData: Data([1, 2, 3]))

        for i in 0..<5 {
            history.push(CanvasSnapshot(
                strokes: [Stroke(points: [CGPoint(x: CGFloat(i), y: 0), CGPoint(x: CGFloat(i + 1), y: 0)], color: .black, lineWidth: 2, isEraser: false)],
                placedImages: i == 4 ? [img] : [],
                selectedStrokeIds: [],
                selectedImageIds: [],
                selectionBoundary: []
            ))
        }

        XCTAssertEqual(history.undoStack.count, 3)

        let current = CanvasSnapshot(strokes: [], placedImages: [], selectedStrokeIds: [], selectedImageIds: [], selectionBoundary: [])
        let restored = history.undo(current: current)
        XCTAssertEqual(restored?.placedImages.count, 1)
        XCTAssertEqual(restored?.placedImages.first?.id, img.id)
    }

    // MARK: - BoardStore Tests

    func testBoardStoreCorruptedIndexIsBackedUpAndThrows() throws {
        try Data("not valid json".utf8).write(to: store.indexURL)
        XCTAssertThrowsError(try store.loadIndex()) { error in
            guard case BoardStoreError.corruptedIndex(let backupURL, _) = error else {
                XCTFail("Expected corruptedIndex error, got \(error)")
                return
            }
            XCTAssertNotNil(backupURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL!.path))
        }
    }

    func testBoardStoreTrashCleanupAndRestore() throws {
        let stroke = Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)], color: .black, lineWidth: 2, isEraser: false)
        let img = PlacedImage(position: CGPoint(x: 5, y: 5), size: CGSize(width: 20, height: 20), imageData: Data([9, 8, 7]))
        try store.saveBoardSync(id: "board1", saveData: SaveData(strokes: [stroke], placedImages: [img]))

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let trashed = try store.trashBoard(id: "board1", name: "My Board", now: t0)
        XCTAssertEqual(trashed.count, 1)
        XCTAssertNotNil(trashed[0].fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.boardURL(for: "board1").path))

        // Restore into a new board ID and verify both strokes and placedImages survive
        let restored = try store.restoreBoard(id: "board1", newBoardId: "board2")
        XCTAssertEqual(restored.name, "My Board")
        XCTAssertEqual(restored.saveData.strokes.count, 1)
        XCTAssertEqual(restored.saveData.placedImages.count, 1)
        XCTAssertTrue(restored.remainingTrash.isEmpty)

        // Trash board2 and verify 31-day cleanup removes the file from .trash/
        let trashed2 = try store.trashBoard(id: "board2", name: "My Board", now: t0)
        let fileName = try XCTUnwrap(trashed2.first?.fileName)
        let trashedFileURL = store.trashDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedFileURL.path))

        let t31 = t0.addingTimeInterval(31 * 24 * 3600)
        let afterClean = store.cleanTrash(now: t31)
        XCTAssertTrue(afterClean.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashedFileURL.path))
    }

    // MARK: - DrawingModel Integration Tests

    func testLoadBoardClearsUndoStackAndFlushesPreviousBoard() throws {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.createBoard(name: "Board A")
        let boardAId = try XCTUnwrap(model.currentBoardId)

        model.beginStroke(at: CGPoint(x: 0, y: 0), isEraser: false)
        model.addPoint(CGPoint(x: 100, y: 100))
        model.endStroke()
        XCTAssertEqual(model.strokes.count, 1)
        XCTAssertTrue(model.canUndo)

        // Immediately create & switch to Board B without waiting for 0.5s debounce
        model.createBoard(name: "Board B")
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.strokes.isEmpty)

        // Board A's stroke must have been flushed to disk before switching
        let savedA = try store.loadBoard(id: boardAId)
        XCTAssertEqual(savedA.strokes.count, 1)

        // Loading Board A must NOT push Board B onto undoStack
        model.loadBoard(id: boardAId)
        XCTAssertEqual(model.strokes.count, 1)
        XCTAssertFalse(model.canUndo)
    }

    func testMoveUndoRevertsToPreMovePosition() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.beginStroke(at: CGPoint(x: 10, y: 10), isEraser: false)
        model.addPoint(CGPoint(x: 50, y: 10))
        model.endStroke()
        let strokeId = model.strokes[0].id

        model.selectedStrokeIds = [strokeId]
        model.beginMove(at: CGPoint(x: 20, y: 10))
        model.moveSelected(by: CGSize(width: 100, height: 50))
        model.commitMove()

        XCTAssertEqual(model.strokes[0].points[0].x, 110, accuracy: 0.01)
        XCTAssertEqual(model.strokes[0].points[0].y, 60, accuracy: 0.01)

        // A single undo must revert directly to the pre-move position
        model.undo()
        XCTAssertEqual(model.strokes[0].points[0].x, 10, accuracy: 0.01)
        XCTAssertEqual(model.strokes[0].points[0].y, 10, accuracy: 0.01)
    }

    func testExportPNGAndPDFProduceValidData() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.beginStroke(at: CGPoint(x: -50, y: -50), isEraser: false)
        model.addPoint(CGPoint(x: 50, y: 50))
        model.endStroke()

        let (size, offset) = model.canvasBoundingRect()
        let png = model.pngData(size: size, offset: offset, scale: 2)
        let pdf = model.pdfData(size: size, offset: offset)

        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 100)
        XCTAssertNotNil(pdf)
        XCTAssertGreaterThan(pdf?.count ?? 0, 100)
    }

    func testMigrateLegacyPresetIndices() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.appSettings.isDarkMode = false
        let redPreset = model.penSettings.lightPresets[1]
        model.strokes = [
            Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)], color: redPreset, lineWidth: 2, isEraser: false, presetIndex: -1)
        ]

        model.migratePresetIndices()
        XCTAssertEqual(model.strokes[0].presetIndex, 1)
    }

    // MARK: - Performance & Storage Optimization Tests

    func testSpatialHashGridQueryAndIncrementalSync() {
        let grid = SpatialHashGrid(cellSize: 100)
        let s1 = Stroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], color: .black, lineWidth: 2, isEraser: false)
        let s2 = Stroke(points: [CGPoint(x: 1000, y: 1000), CGPoint(x: 1050, y: 1050)], color: .black, lineWidth: 2, isEraser: false)
        var strokes = [s1, s2]
        grid.sync(with: strokes)

        XCTAssertEqual(grid.queryIndices(in: CGRect(x: 0, y: 0, width: 100, height: 100)), [0])
        XCTAssertEqual(grid.queryIndices(in: CGRect(x: 950, y: 950, width: 150, height: 150)), [1])

        // Incremental single-stroke append
        let s3 = Stroke(points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)], color: .red, lineWidth: 2, isEraser: false)
        strokes.append(s3)
        grid.sync(with: strokes)
        XCTAssertEqual(grid.queryIndices(in: CGRect(x: 0, y: 0, width: 100, height: 100)), [0, 2])
    }

    func testRDPSimplificationReducesCollinearPoints() {
        // 50 collinear points along y = 0, then a sharp corner to (500, 100)
        var pts = (0..<50).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        pts.append(CGPoint(x: 490, y: 100))

        let simplified = GeometryEngine.simplifyRDP(pts, tolerance: 0.3)
        XCTAssertEqual(simplified.count, 3)
        XCTAssertEqual(simplified.first, pts.first)
        XCTAssertEqual(simplified.last, pts.last)
    }

    func testBoardStoreBinaryAssetRoundTripAndLegacyJSONCompat() throws {
        // 1. Binary plist + external image asset round-trip
        let stroke = Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 40)], color: .blue, lineWidth: 3, isEraser: false)
        let imgData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let img = PlacedImage(position: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 60), imageData: imgData)

        try store.saveBoardSync(id: "bin1", saveData: SaveData(strokes: [stroke], placedImages: [img]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(for: img.id).path))

        let loaded = try store.loadBoard(id: "bin1")
        XCTAssertEqual(loaded.strokes.count, 1)
        XCTAssertEqual(loaded.placedImages.count, 1)
        XCTAssertEqual(loaded.placedImages[0].imageData, imgData)

        // 2. Legacy JSON `.wb` file written directly still decodes cleanly
        let legacyJSON = try JSONEncoder().encode(SaveData(strokes: [stroke], placedImages: [img]))
        try legacyJSON.write(to: store.boardURL(for: "legacy1"), options: .atomic)
        let loadedLegacy = try store.loadBoard(id: "legacy1")
        XCTAssertEqual(loadedLegacy.strokes.count, 1)
        XCTAssertEqual(loadedLegacy.placedImages.count, 1)
    }

    func testBoardStoreDiskThumbnails() {
        let fakePNG = Data([1, 2, 3, 4])
        XCTAssertNil(store.loadDiskThumbnail(for: "b1", isDark: false))
        store.saveDiskThumbnail(for: "b1", isDark: false, pngData: fakePNG)
        XCTAssertEqual(store.loadDiskThumbnail(for: "b1", isDark: false), fakePNG)

        store.invalidateDiskThumbnails(for: "b1")
        XCTAssertNil(store.loadDiskThumbnail(for: "b1", isDark: false))
    }

    func testStrokePathCacheCachesAndInvalidatesOnMove() {
        let cache = StrokePathCache()
        let stroke = Stroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: true)
        let entry1 = cache.entry(for: stroke)
        XCTAssertNotNil(entry1)

        // Same stroke returns cached entry
        let entry2 = cache.entry(for: stroke)
        XCTAssertEqual(entry1?.bounds, entry2?.bounds)

        // Moved stroke (same ID, shifted points) invalidates and updates bounds
        let moved = Stroke(id: stroke.id, points: [CGPoint(x: 210, y: 210), CGPoint(x: 300, y: 300)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: true)
        let entry3 = cache.entry(for: moved)
        XCTAssertNotNil(entry3)
        XCTAssertNotEqual(entry1?.bounds, entry3?.bounds)
    }

    func testAddPointFiltersSubPixelDuplicates() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.beginStroke(at: CGPoint(x: 10, y: 10), isEraser: false)
        model.addPoint(CGPoint(x: 10.2, y: 10.2)) // too close, filtered
        model.addPoint(CGPoint(x: 10.5, y: 10.5)) // still too close, filtered
        model.addPoint(CGPoint(x: 20, y: 20))     // kept
        XCTAssertEqual(model.currentStroke?.points.count, 2)
    }

    func testToolHighlightColorAlwaysMatchesStrokeDisplayColor() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.selectPenPreset(5) // Blue
        model.beginStroke(at: CGPoint(x: 0, y: 0), isEraser: false)
        model.addPoint(CGPoint(x: 20, y: 20))
        model.endStroke()

        XCTAssertEqual(CodableColor(model.penColor), CodableColor(model.strokes[0].displayColor(for: model)))

        // Toggle Dark Mode — highlight and stroke must remain identical
        model.appSettings.isDarkMode = true
        XCTAssertEqual(CodableColor(model.penColor), CodableColor(model.strokes[0].displayColor(for: model)))

        // Persist and reload defaults in a new model instance
        model.saveDefaults()
        let reloaded = DrawingModel(store: store, userDefaults: testDefaults)
        XCTAssertEqual(reloaded.penPresetIndex, 5)
        XCTAssertEqual(CodableColor(reloaded.penColor), CodableColor(reloaded.penPresets[5]))
    }

    func testQuickBoardCreationAndPermanentTrashDelete() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.createFolder(name: "Work")
        let folderId = model.folders[0].id

        let id1 = model.createQuickBoard(folderId: folderId)
        let id2 = model.createQuickBoard(folderId: folderId)

        XCTAssertEqual(model.boards.first(where: { $0.id == id1 })?.name, "Untitled Tissue")
        XCTAssertEqual(model.boards.first(where: { $0.id == id2 })?.name, "Untitled Tissue 2")
        XCTAssertEqual(model.folderName(forBoardId: id1), "Work")

        model.trashBoard(id: id1, name: "Untitled Tissue")
        model.trashBoard(id: id2, name: "Untitled Tissue 2")
        XCTAssertEqual(model.trashedBoards.count, 2)

        model.permanentlyDeleteTrashedBoard(id: id1)
        XCTAssertEqual(model.trashedBoards.count, 1)

        model.emptyTrash()
        XCTAssertTrue(model.trashedBoards.isEmpty)
    }

    // MARK: - Flood Fill (Option #2) Tests

    private func makeBoxStroke(rect: CGRect, closed: Bool = true, gap: CGFloat = 0) -> Stroke {
        var pts: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        if closed {
            pts.append(CGPoint(x: rect.minX, y: rect.minY + gap))
        }
        return Stroke(points: pts, color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false)
    }

    func testFloodFillEnclosedSquareSucceedsAndOpenShapeAborts() {
        let closedBox = makeBoxStroke(rect: CGRect(x: 0, y: 0, width: 100, height: 100), closed: true)
        let contours = FloodFillEngine.computeContours(at: CGPoint(x: 50, y: 50), strokes: [closedBox], gapTolerance: 0)
        XCTAssertNotNil(contours)
        XCTAssertEqual(contours?.count, 1)

        let shape = FillShape(contours: contours!, color: .blue, opacity: 0.5, presetIndex: 5)
        let path = shape.makeCGPath()
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50), using: .evenOdd))
        XCTAssertFalse(path.contains(CGPoint(x: 150, y: 150), using: .evenOdd))

        // Sharp 4-edge rectangle must fill all four corners without cutting corner triangles
        let rectEdges = [
            Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
            Stroke(points: [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
            Stroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
            Stroke(points: [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
        ]
        let rectContours = FloodFillEngine.computeContours(at: CGPoint(x: 50, y: 50), strokes: rectEdges, gapTolerance: 2.5)
        XCTAssertNotNil(rectContours)
        let rectPath = FillShape(contours: rectContours!, color: .blue).makeCGPath()
        XCTAssertTrue(rectPath.contains(CGPoint(x: 2, y: 2), using: .evenOdd), "Top-left corner should be filled")
        XCTAssertTrue(rectPath.contains(CGPoint(x: 98, y: 2), using: .evenOdd), "Top-right corner should be filled")
        XCTAssertTrue(rectPath.contains(CGPoint(x: 98, y: 98), using: .evenOdd), "Bottom-right corner should be filled")
        XCTAssertTrue(rectPath.contains(CGPoint(x: 2, y: 98), using: .evenOdd), "Bottom-left corner should be filled")

        // Open shape (missing left edge) must abort with nil (no bleeding!)
        let openBox = makeBoxStroke(rect: CGRect(x: 0, y: 0, width: 100, height: 100), closed: false)
        XCTAssertNil(FloodFillEngine.computeContours(at: CGPoint(x: 50, y: 50), strokes: [openBox], gapTolerance: 2.5))
    }

    func testFloodFillPreservesInteriorHoleWithEvenOddRule() {
        let outer = makeBoxStroke(rect: CGRect(x: 0, y: 0, width: 120, height: 120), closed: true)
        let inner = makeBoxStroke(rect: CGRect(x: 40, y: 40, width: 40, height: 40), closed: true)

        // Tap inside the ring (between outer and inner)
        let contours = FloodFillEngine.computeContours(at: CGPoint(x: 20, y: 60), strokes: [outer, inner], gapTolerance: 0)
        XCTAssertNotNil(contours)
        XCTAssertEqual(contours?.count, 2, "Ring fill should produce outer contour + inner hole contour")

        let path = FillShape(contours: contours!, color: .red).makeCGPath()
        XCTAssertTrue(path.contains(CGPoint(x: 20, y: 60), using: .evenOdd), "Ring interior should be filled")
        XCTAssertFalse(path.contains(CGPoint(x: 60, y: 60), using: .evenOdd), "Center hole should remain unfilled")
    }

    func testFloodFillGapToleranceAndPersistenceAndUndo() throws {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.createBoard(name: "Fill Test")
        let boardId = try XCTUnwrap(model.currentBoardId)

        // Small 4pt gap at top-left corner
        let gappedBox = makeBoxStroke(rect: CGRect(x: 0, y: 0, width: 100, height: 100), closed: true, gap: 4)
        model.strokes = [gappedBox]

        // Strict mode (gapTolerance = 0) should refuse to bleed through the 4pt gap
        model.fillSettings.gapTolerance = 0
        XCTAssertFalse(model.floodFill(at: CGPoint(x: 50, y: 50)))

        // Auto mode (gapTolerance = 2.5 => 5pt closing) should fill cleanly
        model.fillSettings.gapTolerance = 2.5
        XCTAssertTrue(model.floodFill(at: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(model.fills.count, 1)

        // Persist and reload from BoardStore
        model.flushAutoSave()
        let loaded = try store.loadBoard(id: boardId)
        XCTAssertEqual(loaded.fills.count, 1)

        // Undo removes the fill, Redo restores it
        model.undo()
        XCTAssertTrue(model.fills.isEmpty)
        model.redo()
        XCTAssertEqual(model.fills.count, 1)

        // Replace mode (default): refilling the same region replaces the prior fill
        model.fillSettings.overlapMode = .replace
        model.selectFillPreset(1) // Red
        XCTAssertTrue(model.floodFill(at: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(model.fills.count, 1, "Replace mode should replace the existing fill in that region")
        XCTAssertEqual(model.fills[0].presetIndex, 1)

        // Blend mode: refilling the same region layers a new fill on top
        model.fillSettings.overlapMode = .blend
        model.selectFillPreset(4) // Green
        XCTAssertTrue(model.floodFill(at: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(model.fills.count, 2, "Blend mode should keep both fills layered")
    }

    func testPencilDoubleTapTogglesEraserAndRestoresPreviousTool() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)

        // Pen -> Eraser (targets .pen) -> Pen
        model.selectTool(.pen)
        model.toggleEraserFromPencil()
        XCTAssertEqual(model.currentTool, .eraser)
        XCTAssertEqual(model.eraserSettings.eraseTarget, .pen)
        model.toggleEraserFromPencil()
        XCTAssertEqual(model.currentTool, .pen)

        // Sharpie -> Eraser (targets .sharpie) -> Sharpie
        model.selectTool(.sharpie)
        model.toggleEraserFromPencil()
        XCTAssertEqual(model.currentTool, .eraser)
        XCTAssertEqual(model.eraserSettings.eraseTarget, .sharpie)
        model.toggleEraserFromPencil()
        XCTAssertEqual(model.currentTool, .sharpie)

        // Fill -> Eraser (targets .fill) -> Fill
        model.selectTool(.fill)
        model.toggleEraserFromPencil()
        XCTAssertEqual(model.currentTool, .eraser)
        XCTAssertEqual(model.eraserSettings.eraseTarget, .fill)
        model.toggleEraserFromPencil()
        XCTAssertEqual(model.currentTool, .fill)

        // Squeeze cycles Pen -> Sharpie -> Fill -> Select -> Pen (and Eraser -> Pen)
        model.selectTool(.pen)
        model.cycleToolFromPencil()
        XCTAssertEqual(model.currentTool, .sharpie)
        model.cycleToolFromPencil()
        XCTAssertEqual(model.currentTool, .fill)
        model.cycleToolFromPencil()
        XCTAssertEqual(model.currentTool, .select)
        model.cycleToolFromPencil()
        XCTAssertEqual(model.currentTool, .pen)

        model.selectTool(.eraser)
        model.cycleToolFromPencil()
        XCTAssertEqual(model.currentTool, .pen)
    }

    func testScenesCRUDNavigationAndPersistence() throws {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.createBoard(name: "Scenes Test")
        let boardId = try XCTUnwrap(model.currentBoardId)

        // New tissue automatically starts with Scene 1 capturing the default canvas view
        XCTAssertEqual(model.scenes.count, 1)
        let s1 = model.scenes[0]
        XCTAssertEqual(s1.name, "Scene 1")
        XCTAssertEqual(model.activeSceneId, s1.id)
        model.currentViewportCenter = CGPoint(x: 500, y: 350)
        model.currentViewportScale = 1.0
        model.captureDefaultSceneIfNeeded()
        XCTAssertEqual(model.scenes[0].center.x, 500, accuracy: 0.01)
        XCTAssertEqual(model.scenes[0].center.y, 350, accuracy: 0.01)

        model.currentViewportCenter = CGPoint(x: 800, y: -300)
        model.currentViewportScale = 0.75
        let s2 = model.addScene(name: "Architecture")
        XCTAssertEqual(s2.name, "Architecture")
        XCTAssertEqual(model.scenes.count, 2)
        XCTAssertEqual(model.activeSceneId, s2.id)

        // Navigation wraps around cleanly
        model.goToNextScene()
        XCTAssertEqual(model.activeSceneId, s1.id)
        XCTAssertEqual(model.pendingSceneNavigation?.id, s1.id)
        model.goToPreviousScene()
        XCTAssertEqual(model.activeSceneId, s2.id)

        // Rename, update viewport, and reorder
        model.renameScene(id: s1.id, to: "Intro")
        XCTAssertEqual(model.scenes[0].name, "Intro")
        model.currentViewportCenter = CGPoint(x: 42, y: 84)
        model.updateSceneToCurrentView(id: s1.id)
        XCTAssertEqual(model.scenes[0].center.x, 42, accuracy: 0.01)
        model.moveScene(id: s2.id, direction: -1)
        XCTAssertEqual(model.scenes[0].id, s2.id)
        model.moveScenes(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(model.scenes[0].id, s1.id)
        model.moveScenes(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(model.scenes[0].id, s2.id)

        // Persist and reload from disk
        model.flushAutoSave()
        let loaded = try store.loadBoard(id: boardId)
        XCTAssertEqual(loaded.scenes.count, 2)
        XCTAssertEqual(loaded.scenes[0].name, "Architecture")
        XCTAssertEqual(loaded.scenes[1].name, "Intro")

        // Delete
        model.deleteScene(id: s2.id)
        XCTAssertEqual(model.scenes.count, 1)
    }

    func testEraserFillTargetErasesOnlyFillsAndNotStrokes() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        let rectEdges = [
            Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
            Stroke(points: [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
            Stroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
            Stroke(points: [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)], color: .black, lineWidth: 2, isEraser: false, isCatmullRom: false),
        ]
        model.strokes = rectEdges
        XCTAssertTrue(model.floodFill(at: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(model.fills.count, 1)

        // Erase across both the fill and the border strokes with target = .fill
        model.eraserSettings.eraseTarget = .fill
        model.beginStroke(at: CGPoint(x: 0, y: 50), isEraser: true)
        model.addPoint(CGPoint(x: 50, y: 50))
        model.addPoint(CGPoint(x: 100, y: 50))
        model.endStroke()

        XCTAssertTrue(model.fills.isEmpty, "Fill target should erase the touched fill")
        XCTAssertEqual(model.strokes.count, 4, "Fill target must leave pen/sharpie strokes untouched")
    }

    func testCopyPasteLassoMovesOnlyPastedItems() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        let origStroke = Stroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)], color: .black, lineWidth: 2, isEraser: false)
        let origFill = FillShape(contours: [[CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 10), CGPoint(x: 40, y: 40), CGPoint(x: 10, y: 40)]], color: .blue)
        model.strokes = [origStroke]
        model.fills = [origFill]
        model.selectedStrokeIds = [origStroke.id]
        model.selectedFillIds = [origFill.id]
        model.selectionBoundary = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 0, y: 50)]
        model.lastCanvasTapLocation = CGPoint(x: 25, y: 25)

        model.copySelected()
        model.paste()

        XCTAssertEqual(model.strokes.count, 2)
        XCTAssertEqual(model.fills.count, 2)
        // Original IDs must NOT remain selected
        XCTAssertFalse(model.selectedStrokeIds.contains(origStroke.id))
        XCTAssertFalse(model.selectedFillIds.contains(origFill.id))

        // Dragging the pasted selection must move ONLY the pasted copy, leaving originals at (10, 10)
        model.beginMove(at: CGPoint(x: 40, y: 40))
        model.moveSelected(by: CGSize(width: 200, height: 100))
        model.commitMove()

        let stillOrigStroke = model.strokes.first(where: { $0.id == origStroke.id })!
        let stillOrigFill = model.fills.first(where: { $0.id == origFill.id })!
        XCTAssertEqual(stillOrigStroke.points[0].x, 10, accuracy: 0.01)
        XCTAssertEqual(stillOrigFill.contours[0][0].x, 10, accuracy: 0.01)

        let pastedStroke = model.strokes.first(where: { $0.id != origStroke.id })!
        let pastedFill = model.fills.first(where: { $0.id != origFill.id })!
        XCTAssertEqual(pastedStroke.points[0].x, 234, accuracy: 0.01) // 10 + 24 + 200
        XCTAssertEqual(pastedFill.contours[0][0].x, 234, accuracy: 0.01)
    }

    private func makeTestPNGData(width: Int, height: Int, opaque: Bool = false) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImg = ctx.makeImage()!
        let rep = NSBitmapImageRep(cgImage: cgImg)
        return rep.representation(using: .png, properties: [:])!
    }

    func testAddImagePreservesRetinaResolutionCentersInViewportAndClearsFillSelection() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.currentViewportCenter = CGPoint(x: 1500, y: -600)
        model.selectedFillIds = [UUID()]

        // 2000x1000 image -> visual size 400x200, stored pixel resolution 1200x600 (Retina-sharp)
        let pngData = makeTestPNGData(width: 2000, height: 1000, opaque: false)
        XCTAssertTrue(model.addImage(data: pngData))
        XCTAssertEqual(model.placedImages.count, 1)

        let placed = model.placedImages[0]
        XCTAssertEqual(placed.cgSize.width, 400, accuracy: 1)
        XCTAssertEqual(placed.cgSize.height, 200, accuracy: 1)
        // Centered on currentViewportCenter (1500, -600) -> origin (1300, -700)
        XCTAssertEqual(placed.cgPosition.x, 1300, accuracy: 1)
        XCTAssertEqual(placed.cgPosition.y, -700, accuracy: 1)
        // Stored pixels should be 1200x600 (not blurry 400x200)
        let decoded = NSBitmapImageRep(data: placed.imageData)
        XCTAssertEqual(decoded?.pixelsWide, 1200)
        XCTAssertEqual(decoded?.pixelsHigh, 600)
        // Stale fill selection must be cleared
        XCTAssertTrue(model.selectedFillIds.isEmpty)
        XCTAssertEqual(model.selectedImageIds, [placed.id])
    }

    func testPasteSystemClipboardImage() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        let pngData = makeTestPNGData(width: 300, height: 200, opaque: true)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)

        model.paste()
        XCTAssertEqual(model.placedImages.count, 1)
        XCTAssertEqual(model.placedImages[0].cgSize.width, 300, accuracy: 1)
        XCTAssertEqual(model.placedImages[0].cgSize.height, 200, accuracy: 1)
    }

    func testConfigurableToolbarPinReorderUnpinAndPersistence() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        XCTAssertEqual(model.pinnedToolbarItems, ToolbarItemID.defaultPinned)
        XCTAssertTrue(model.unpinnedToolbarItems.contains(.undo))

        // Pin Undo before Home
        model.pinToolbarItem(.undo, before: .home)
        XCTAssertTrue(model.pinnedToolbarItems.contains(.undo))
        XCTAssertFalse(model.unpinnedToolbarItems.contains(.undo))
        let undoIdx = model.pinnedToolbarItems.firstIndex(of: .undo)!
        let homeIdx = model.pinnedToolbarItems.firstIndex(of: .home)!
        XCTAssertLessThan(undoIdx, homeIdx)

        // Unpin Sharpie -> moves to unpinned list
        model.unpinToolbarItem(.sharpie)
        XCTAssertFalse(model.pinnedToolbarItems.contains(.sharpie))
        XCTAssertTrue(model.unpinnedToolbarItems.contains(.sharpie))

        // Persists across reload
        let reloaded = DrawingModel(store: store, userDefaults: testDefaults)
        XCTAssertEqual(reloaded.pinnedToolbarItems, model.pinnedToolbarItems)

        // Reset restores defaults
        reloaded.resetToolbarLayout()
        XCTAssertEqual(reloaded.pinnedToolbarItems, ToolbarItemID.defaultPinned)
    }

    func testShapeRecognitionSnapsLineCircleAndRectangle() {
        // Straight-ish line
        let linePts = (0...10).map { i in CGPoint(x: CGFloat(i) * 15, y: sin(CGFloat(i)) * 1.5) }
        let snappedLine = GeometryEngine.recognizeShape(from: linePts)
        XCTAssertNotNil(snappedLine)
        XCTAssertEqual(snappedLine?.first?.x ?? -1, 0, accuracy: 0.1)
        XCTAssertEqual(snappedLine?.last?.x ?? -1, 150, accuracy: 0.1)

        // Circle
        let circlePts = (0...32).map { i -> CGPoint in
            let a = (CGFloat(i) / 32.0) * .pi * 2
            return CGPoint(x: 100 + cos(a) * 50, y: 100 + sin(a) * 50)
        }
        let snappedCircle = GeometryEngine.recognizeShape(from: circlePts)
        XCTAssertNotNil(snappedCircle)
        XCTAssertEqual(snappedCircle?.count, 65)

        // Rectangle
        var rectPts: [CGPoint] = []
        for i in 0..<10 { rectPts.append(CGPoint(x: CGFloat(i) * 10, y: 0)) }
        for i in 0..<10 { rectPts.append(CGPoint(x: 100, y: CGFloat(i) * 8)) }
        for i in 0..<10 { rectPts.append(CGPoint(x: 100 - CGFloat(i) * 10, y: 80)) }
        for i in 0...10 { rectPts.append(CGPoint(x: 0, y: 80 - CGFloat(i) * 8)) }
        let snappedRect = GeometryEngine.recognizeShape(from: rectPts)
        XCTAssertNotNil(snappedRect)
    }

    func testDuplicateRecolorTransformPinAndScenesPDFExport() throws {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.createBoard(name: "Deck")
        let boardId = try XCTUnwrap(model.currentBoardId)

        // Pin/favorite board
        model.togglePinBoard(id: boardId)
        XCTAssertTrue(model.boards.first(where: { $0.id == boardId })?.isPinned == true)

        // Stroke + selection duplicate, recolor, transform
        model.beginStroke(at: CGPoint(x: 0, y: 0), isEraser: false)
        model.addPoint(CGPoint(x: 100, y: 0))
        model.endStroke()
        let origId = model.strokes[0].id
        model.selectedStrokeIds = [origId]

        model.duplicateSelected()
        XCTAssertEqual(model.strokes.count, 2)
        XCTAssertFalse(model.selectedStrokeIds.contains(origId))

        model.recolorSelected(to: .red, presetIndex: 1)
        let dupStroke = model.strokes.first(where: { $0.id != origId })!
        XCTAssertEqual(dupStroke.presetIndex, 1)

        let beforeWidth = abs(dupStroke.points.last!.x - dupStroke.points.first!.x)
        model.transformSelected(scale: 1.5, rotation: 0)
        let scaledDup = model.strokes.first(where: { $0.id != origId })!
        let afterWidth = abs(scaledDup.points.last!.x - scaledDup.points.first!.x)
        XCTAssertEqual(afterWidth, beforeWidth * 1.5, accuracy: 0.5)

        // Multi-page Scenes PDF export
        model.addScene(name: "Slide 2")
        let pdf = model.scenesPDFData()
        XCTAssertNotNil(pdf)
        XCTAssertGreaterThan(pdf?.count ?? 0, 200)
    }

    func testRotationAngleSnappingCardinalAndStep() {
        // Light cardinal snap within 4° of 0°, 90°, -90°, 180°
        let near90 = (90.0 - 2.5) * .pi / 180.0
        let snap90 = GeometryEngine.snapRotationAngle(near90, snapToStep: false)
        XCTAssertTrue(snap90.snapped)
        XCTAssertEqual(snap90.angle, .pi / 2, accuracy: 1e-5)

        let nearZero = (3.0) * .pi / 180.0
        let snap0 = GeometryEngine.snapRotationAngle(nearZero, snapToStep: false)
        XCTAssertTrue(snap0.snapped)
        XCTAssertEqual(snap0.angle, 0, accuracy: 1e-5)

        // Outside cardinal threshold should not snap when Shift is not held
        let freeAngle = 37.0 * .pi / 180.0
        let unsnapped = GeometryEngine.snapRotationAngle(freeAngle, snapToStep: false)
        XCTAssertFalse(unsnapped.snapped)
        XCTAssertEqual(unsnapped.angle, freeAngle, accuracy: 1e-5)

        // Shift-snap locks to nearest 15°
        let stepSnapped = GeometryEngine.snapRotationAngle(37.0 * .pi / 180.0, snapToStep: true)
        XCTAssertTrue(stepSnapped.snapped)
        XCTAssertEqual(stepSnapped.angle, 30.0 * .pi / 180.0, accuracy: 1e-5)
    }

    func testRotationHandleDragAndResetForStrokesAndPlacedImages() throws {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.currentTool = .select

        // 1) Stroke drag-rotation via handle + single undo + reset
        let s = Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], color: .black, lineWidth: 2, isEraser: false)
        model.strokes = [s]
        model.selectedStrokeIds = [s.id]
        XCTAssertFalse(model.canResetSelectionRotation)

        let geom = try XCTUnwrap(model.rotationHandleGeometry(scale: 1.0))
        XCTAssertTrue(model.hitTestRotateHandle(geom.handleCenter, scale: 1.0))
        XCTAssertFalse(model.hitTestRotateHandle(CGPoint(x: 500, y: 500), scale: 1.0))

        // Drag handle 90° clockwise (from north (50, -28) to east (50 + 28, 0))
        model.beginRotate(at: geom.handleCenter, scale: 1.0)
        XCTAssertTrue(model.isRotating)
        model.updateRotate(to: CGPoint(x: geom.pivot.x + 15, y: geom.pivot.y - 25), snapTo15Degrees: false)
        model.updateRotate(to: CGPoint(x: geom.pivot.x + 28, y: geom.pivot.y), snapTo15Degrees: false)
        model.commitRotate()

        XCTAssertFalse(model.isRotating)
        XCTAssertTrue(model.canResetSelectionRotation)
        XCTAssertEqual(model.selectionRotationAngle, .pi / 2, accuracy: 1e-4)
        XCTAssertEqual(model.activeRotationLabel, "90°")
        // Horizontal segment (0,0)-(100,0) rotated +90° around (50,0) -> vertical (50,-50)-(50,50)
        XCTAssertEqual(model.strokes[0].points[0].x, 50, accuracy: 0.1)
        XCTAssertEqual(model.strokes[0].points[0].y, -50, accuracy: 0.1)
        XCTAssertEqual(model.strokes[0].points[1].x, 50, accuracy: 0.1)
        XCTAssertEqual(model.strokes[0].points[1].y, 50, accuracy: 0.1)

        // Reset Rotation brings stroke back to horizontal (0,0)-(100,0)
        model.resetSelectionRotation()
        XCTAssertFalse(model.canResetSelectionRotation)
        XCTAssertEqual(model.strokes[0].points[0].x, 0, accuracy: 0.1)
        XCTAssertEqual(model.strokes[0].points[0].y, 0, accuracy: 0.1)
        XCTAssertEqual(model.strokes[0].points[1].x, 100, accuracy: 0.1)
        XCTAssertEqual(model.strokes[0].points[1].y, 0, accuracy: 0.1)

        // Undo reverts Reset Rotation (back to 90°), second undo reverts the whole handle drag in 1 step
        model.undo()
        XCTAssertEqual(model.strokes[0].points[0].x, 50, accuracy: 0.1)
        model.undo()
        XCTAssertEqual(model.strokes[0].points[0].x, 0, accuracy: 0.1)

        // 2) PlacedImage rotation via handle, persistence across re-select, rotated corner hit-test, and BoardStore round-trip
        model.clearSelection()
        let imgData = makeTestPNGData(width: 80, height: 40, opaque: true)
        let img = PlacedImage(position: CGPoint(x: 100, y: 100), size: CGSize(width: 80, height: 40), imageData: imgData)
        model.placedImages = [img]
        model.selectedImageIds = [img.id]

        let imgGeom = try XCTUnwrap(model.rotationHandleGeometry(scale: 1.0))
        model.beginRotate(at: imgGeom.handleCenter, scale: 1.0)
        // Drag 45° clockwise with Shift-snap
        let targetPt = CGPoint(x: imgGeom.pivot.x + 40, y: imgGeom.pivot.y - 40)
        model.updateRotate(to: targetPt, snapTo15Degrees: true)
        model.commitRotate()

        XCTAssertEqual(model.placedImages[0].rotation, .pi / 4, accuracy: 1e-4)
        // Rotated corner hit-test should hit the rotated top-left corner
        let rotatedCorners = model.placedImages[0].rotatedCorners()
        let cornerHit = model.hitTestResizeHandle(rotatedCorners[0], scale: 1.0)
        XCTAssertEqual(cornerHit?.imgId, img.id)
        XCTAssertEqual(cornerHit?.corner, 0)

        // Persist through BoardStore binary plist and verify rotation survives
        try store.saveBoardSync(id: "rot_board", saveData: SaveData(strokes: [], placedImages: model.placedImages))
        let reloaded = try store.loadBoard(id: "rot_board")
        XCTAssertEqual(reloaded.placedImages.count, 1)
        XCTAssertEqual(reloaded.placedImages[0].rotation, .pi / 4, accuracy: 1e-4)

        // Deselect and re-select: Reset Rotation should STILL be enabled for rotated image
        model.clearSelection()
        model.selectedImageIds = [img.id]
        XCTAssertTrue(model.canResetSelectionRotation)
        XCTAssertEqual(model.activeRotationLabel, "45°")
        model.resetSelectionRotation()
        XCTAssertEqual(model.placedImages[0].rotation, 0, accuracy: 1e-5)
        XCTAssertFalse(model.canResetSelectionRotation)
    }

    func testLassoTapToSelectElementsAndClearSelection() {
        let model = DrawingModel(store: store, userDefaults: testDefaults)
        model.currentTool = .select

        let pen = Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0)], color: .black, lineWidth: 2, isEraser: false, isSharpie: false)
        let sharpie = Stroke(points: [CGPoint(x: 0, y: 100), CGPoint(x: 80, y: 100)], color: .orange, lineWidth: 3, isEraser: false, isSharpie: true)
        let fill = FillShape(
            contours: [[CGPoint(x: 200, y: 0), CGPoint(x: 280, y: 0), CGPoint(x: 280, y: 80), CGPoint(x: 200, y: 80)]],
            color: .blue,
            opacity: 0.5
        )
        model.strokes = [pen, sharpie]
        model.fills = [fill]

        // Tap on pen stroke via beginLasso + endLasso (no drag) selects just pen
        model.beginLasso(at: CGPoint(x: 40, y: 2))
        model.endLasso(scale: 1.0)
        XCTAssertEqual(model.selectedStrokeIds, [pen.id])
        XCTAssertTrue(model.selectedFillIds.isEmpty)
        XCTAssertFalse(model.selectionBoundary.isEmpty)

        // Tap on sharpie stroke selects just sharpie
        XCTAssertTrue(model.selectElement(at: CGPoint(x: 40, y: 100), scale: 1.0))
        XCTAssertEqual(model.selectedStrokeIds, [sharpie.id])
        XCTAssertFalse(model.selectionBoundary.isEmpty)

        // Tap inside fill selects just fill
        XCTAssertTrue(model.selectElement(at: CGPoint(x: 240, y: 40), scale: 1.0))
        XCTAssertEqual(model.selectedFillIds, [fill.id])
        XCTAssertTrue(model.selectedStrokeIds.isEmpty)
        XCTAssertFalse(model.selectionBoundary.isEmpty)

        // Escape / clearLassoSelection clears active selection while staying in .select tool
        model.clearLassoSelection()
        XCTAssertEqual(model.currentTool, .select)
        XCTAssertFalse(model.hasAnySelectionOrLasso)

        // Tap in free area selects nothing
        model.beginLasso(at: CGPoint(x: 500, y: 500))
        model.endLasso(scale: 1.0)
        XCTAssertFalse(model.hasAnySelectionOrLasso)

        // Dragging a lasso around empty space leaves no stale boundary
        model.beginLasso(at: CGPoint(x: 450, y: 450))
        model.addLassoPoint(CGPoint(x: 550, y: 450))
        model.addLassoPoint(CGPoint(x: 550, y: 550))
        model.addLassoPoint(CGPoint(x: 450, y: 550))
        model.endLasso(scale: 1.0)
        XCTAssertTrue(model.selectionBoundary.isEmpty)
    }
}
