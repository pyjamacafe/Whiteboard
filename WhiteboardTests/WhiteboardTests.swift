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
}
