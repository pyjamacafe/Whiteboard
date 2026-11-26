import Foundation

/// A bookmarked viewport region ("Scene") on the infinite canvas, stored as the
/// canvas-space center point and zoom scale so it frames the same area across
/// different screen sizes (Mac and iPad).
nonisolated struct CanvasScene: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var centerX: Double
    var centerY: Double
    var scale: Double

    init(id: UUID = UUID(), name: String, center: CGPoint, scale: CGFloat) {
        self.id = id
        self.name = name
        self.centerX = Double(center.x)
        self.centerY = Double(center.y)
        self.scale = Double(scale)
    }

    var center: CGPoint {
        CGPoint(x: centerX, y: centerY)
    }

    var cgScale: CGFloat {
        CGFloat(scale)
    }
}

/// Portable serialized contents of a `.wb` board file (JSON-compatible for export/import).
nonisolated struct SaveData: Codable, Sendable {
    let strokes: [Stroke]
    let placedImages: [PlacedImage]
    let fills: [FillShape]
    let scenes: [CanvasScene]

    enum CodingKeys: String, CodingKey {
        case strokes, placedImages, fills, scenes
    }

    init(strokes: [Stroke], placedImages: [PlacedImage], fills: [FillShape] = [], scenes: [CanvasScene] = []) {
        self.strokes = strokes
        self.placedImages = placedImages
        self.fills = fills
        self.scenes = scenes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokes = try c.decode([Stroke].self, forKey: .strokes)
        placedImages = try c.decodeIfPresent([PlacedImage].self, forKey: .placedImages) ?? []
        fills = try c.decodeIfPresent([FillShape].self, forKey: .fills) ?? []
        scenes = try c.decodeIfPresent([CanvasScene].self, forKey: .scenes) ?? []
    }
}

/// Fast internal on-disk representation: binary plist + external image asset refs
/// so auto-save never re-encodes megabytes of base64 image data on every stroke.
private nonisolated struct StoredImageRef: Codable, Sendable {
    let id: UUID
    let position: CodablePoint
    let size: CodablePoint
}

private nonisolated struct BinaryBoardData: Codable, Sendable {
    let version: Int
    let strokes: [Stroke]
    let imageRefs: [StoredImageRef]
    let fills: [FillShape]
    let scenes: [CanvasScene]

    enum CodingKeys: String, CodingKey {
        case version, strokes, imageRefs, fills, scenes
    }

    init(version: Int, strokes: [Stroke], imageRefs: [StoredImageRef], fills: [FillShape] = [], scenes: [CanvasScene] = []) {
        self.version = version
        self.strokes = strokes
        self.imageRefs = imageRefs
        self.fills = fills
        self.scenes = scenes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        strokes = try c.decode([Stroke].self, forKey: .strokes)
        imageRefs = try c.decode([StoredImageRef].self, forKey: .imageRefs)
        fills = try c.decodeIfPresent([FillShape].self, forKey: .fills) ?? []
        scenes = try c.decodeIfPresent([CanvasScene].self, forKey: .scenes) ?? []
    }
}

nonisolated struct BoardMeta: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var created: Date
    var modified: Date
}

nonisolated struct BoardFolder: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var boardIds: [String]
}

nonisolated struct BoardIndex: Codable, Equatable, Sendable {
    var boards: [BoardMeta]
    var folders: [BoardFolder]
}

nonisolated struct TrashEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let deletedAt: Date
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, deletedAt, fileName
    }

    init(id: String, name: String, deletedAt: Date, fileName: String? = nil) {
        self.id = id
        self.name = name
        self.deletedAt = deletedAt
        self.fileName = fileName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        deletedAt = try c.decode(Date.self, forKey: .deletedAt)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
    }
}

enum BoardStoreError: LocalizedError {
    case directoryUnavailable
    case corruptedIndex(backupURL: URL?, underlying: Error)
    case boardNotFound(String)
    case trashEntryNotFound(String)
    case ioFailure(String, Error)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return "Could not access the application boards directory."
        case .corruptedIndex(let backup, _):
            if let backup {
                return "The board index was unreadable and was backed up to \(backup.lastPathComponent)."
            }
            return "The board index could not be read."
        case .boardNotFound(let id):
            return "Board \(id) could not be found on disk."
        case .trashEntryNotFound(let id):
            return "Trashed board \(id) could not be found."
        case .ioFailure(let context, let error):
            return "\(context): \(error.localizedDescription)"
        }
    }
}

/// Manages atomic disk I/O for boards, external image assets, disk thumbnails,
/// folders, and the 30-day trash directory.
/// Explicitly `nonisolated` so background `ioQueue` and `thumbnailQueue` work
/// never contends with or deadlocks against `@MainActor`.
nonisolated final class BoardStore: @unchecked Sendable {
    let baseDirectory: URL
    private let fileManager: FileManager
    private let ioQueue = DispatchQueue(label: "com.whiteboard.boardstore.io", qos: .utility)

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = Self.defaultBoardsDirectory(fileManager: fileManager)
        }
        ensureDirectoryExists(self.baseDirectory)
    }

    static func defaultBoardsDirectory(fileManager: FileManager = .default) -> URL {
        #if os(macOS)
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        #else
        let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        #endif
        return root.appendingPathComponent("com.whiteboard.boards", isDirectory: true)
    }

    var indexURL: URL { baseDirectory.appendingPathComponent("boards.json") }
    var trashDirectory: URL { baseDirectory.appendingPathComponent(".trash", isDirectory: true) }
    var trashIndexURL: URL { trashDirectory.appendingPathComponent("trash_index.json") }
    var assetsDirectory: URL { baseDirectory.appendingPathComponent(".assets", isDirectory: true) }
    var thumbsDirectory: URL { baseDirectory.appendingPathComponent(".thumbs", isDirectory: true) }

    func boardURL(for id: String) -> URL {
        baseDirectory.appendingPathComponent("\(id).wb")
    }

    func assetURL(for imageId: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(imageId.uuidString).img")
    }

    func thumbnailURL(for boardId: String, isDark: Bool) -> URL {
        thumbsDirectory.appendingPathComponent("\(boardId)_\(isDark ? "dark" : "light").png")
    }

    private func ensureDirectoryExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Index

    func loadIndex() throws -> BoardIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return BoardIndex(boards: [], folders: [])
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode(BoardIndex.self, from: data)
            return BoardIndex(
                boards: decoded.boards.sorted { $0.modified > $1.modified },
                folders: decoded.folders
            )
        } catch {
            let backupName = "boards.json.corrupt.\(Int(Date().timeIntervalSince1970))"
            let backupURL = baseDirectory.appendingPathComponent(backupName)
            var savedBackup: URL?
            if (try? fileManager.copyItem(at: indexURL, to: backupURL)) != nil {
                savedBackup = backupURL
            }
            throw BoardStoreError.corruptedIndex(backupURL: savedBackup, underlying: error)
        }
    }

    func saveIndex(_ index: BoardIndex) throws {
        ensureDirectoryExists(baseDirectory)
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            throw BoardStoreError.ioFailure("Failed to save board index", error)
        }
    }

    // MARK: - Board Files (Fast Binary Plist + External Assets, Legacy JSON compatible)

    private static let binaryPlistMagic = Data("bplist00".utf8)

    private func decodeBoardData(_ data: Data) throws -> SaveData {
        if data.starts(with: Self.binaryPlistMagic) {
            let binary = try PropertyListDecoder().decode(BinaryBoardData.self, from: data)
            var images: [PlacedImage] = []
            images.reserveCapacity(binary.imageRefs.count)
            for ref in binary.imageRefs {
                let url = assetURL(for: ref.id)
                if let imgData = try? Data(contentsOf: url) {
                    images.append(PlacedImage(
                        id: ref.id,
                        position: ref.position.cgPoint,
                        size: CGSize(width: ref.size.x, height: ref.size.y),
                        imageData: imgData
                    ))
                }
            }
            return SaveData(strokes: binary.strokes, placedImages: images, fills: binary.fills, scenes: binary.scenes)
        }
        return try JSONDecoder().decode(SaveData.self, from: data)
    }

    private func encodeBoardData(_ saveData: SaveData) throws -> Data {
        if !saveData.placedImages.isEmpty {
            ensureDirectoryExists(assetsDirectory)
            for img in saveData.placedImages {
                let url = assetURL(for: img.id)
                if !fileManager.fileExists(atPath: url.path) {
                    try img.imageData.write(to: url, options: .atomic)
                }
            }
        }
        let refs = saveData.placedImages.map {
            StoredImageRef(id: $0.id, position: $0.position, size: $0.size)
        }
        let payload = BinaryBoardData(version: 4, strokes: saveData.strokes, imageRefs: refs, fills: saveData.fills, scenes: saveData.scenes)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(payload)
    }

    func loadBoard(id: String) throws -> SaveData {
        let url = boardURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BoardStoreError.boardNotFound(id)
        }
        do {
            let data = try Data(contentsOf: url)
            return try decodeBoardData(data)
        } catch {
            throw BoardStoreError.ioFailure("Failed to open board", error)
        }
    }

    func loadBoardData(id: String) -> SaveData? {
        try? loadBoard(id: id)
    }

    func saveBoardSync(id: String, saveData: SaveData) throws {
        ensureDirectoryExists(baseDirectory)
        let url = boardURL(for: id)
        do {
            let data = try encodeBoardData(saveData)
            try data.write(to: url, options: .atomic)
        } catch {
            throw BoardStoreError.ioFailure("Failed to save board", error)
        }
    }

    func saveBoardAsync(id: String, saveData: SaveData, completion: @escaping (Result<Void, Error>) -> Void) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.saveBoardSync(id: id, saveData: saveData)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func drainPendingWrites() {
        ioQueue.sync {}
    }

    // MARK: - Persistent Disk Thumbnails

    func loadDiskThumbnail(for boardId: String, isDark: Bool) -> Data? {
        let url = thumbnailURL(for: boardId, isDark: isDark)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func saveDiskThumbnail(for boardId: String, isDark: Bool, pngData: Data) {
        ensureDirectoryExists(thumbsDirectory)
        let url = thumbnailURL(for: boardId, isDark: isDark)
        try? pngData.write(to: url, options: .atomic)
    }

    func invalidateDiskThumbnails(for boardId: String) {
        try? fileManager.removeItem(at: thumbnailURL(for: boardId, isDark: false))
        try? fileManager.removeItem(at: thumbnailURL(for: boardId, isDark: true))
    }

    // MARK: - Trash

    func loadTrash() -> [TrashEntry] {
        guard fileManager.fileExists(atPath: trashIndexURL.path),
              let data = try? Data(contentsOf: trashIndexURL),
              let list = try? JSONDecoder().decode([TrashEntry].self, from: data) else {
            return []
        }
        return list.sorted { $0.deletedAt > $1.deletedAt }
    }

    private func saveTrashIndex(_ entries: [TrashEntry]) throws {
        ensureDirectoryExists(trashDirectory)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: trashIndexURL, options: .atomic)
    }

    func trashBoard(id: String, name: String, now: Date = Date()) throws -> [TrashEntry] {
        ensureDirectoryExists(trashDirectory)
        let fileName = "\(id)_\(Int64(now.timeIntervalSince1970 * 1000)).wb"
        let src = boardURL(for: id)
        let dst = trashDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: src.path) {
            if fileManager.fileExists(atPath: dst.path) {
                try? fileManager.removeItem(at: dst)
            }
            do {
                try fileManager.moveItem(at: src, to: dst)
            } catch {
                throw BoardStoreError.ioFailure("Failed to move board to trash", error)
            }
        }
        invalidateDiskThumbnails(for: id)

        var entries = loadTrash()
        entries.append(TrashEntry(id: id, name: name, deletedAt: now, fileName: fileName))
        do {
            try saveTrashIndex(entries)
        } catch {
            throw BoardStoreError.ioFailure("Failed to update trash index", error)
        }
        return cleanTrash(now: now)
    }

    @discardableResult
    func cleanTrash(now: Date = Date(), retentionDays: TimeInterval = 30) -> [TrashEntry] {
        let entries = loadTrash()
        let cutoff = now.addingTimeInterval(-retentionDays * 24 * 3600)
        var remaining: [TrashEntry] = []
        let dirFiles = (try? fileManager.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil)) ?? []

        for entry in entries {
            if entry.deletedAt <= cutoff {
                if let fileName = entry.fileName {
                    try? fileManager.removeItem(at: trashDirectory.appendingPathComponent(fileName))
                } else {
                    for file in dirFiles where file.lastPathComponent.hasPrefix("\(entry.id)_") {
                        try? fileManager.removeItem(at: file)
                    }
                }
            } else {
                remaining.append(entry)
            }
        }

        if remaining.count != entries.count {
            try? saveTrashIndex(remaining)
        }
        return remaining.sorted { $0.deletedAt > $1.deletedAt }
    }

    func restoreBoard(id: String, newBoardId: String) throws -> (name: String, saveData: SaveData, remainingTrash: [TrashEntry]) {
        var entries = loadTrash()
        let entry = entries.first(where: { $0.id == id })

        let src: URL?
        if let fileName = entry?.fileName {
            let candidate = trashDirectory.appendingPathComponent(fileName)
            src = fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        } else {
            let files = (try? fileManager.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil)) ?? []
            src = files.first { $0.lastPathComponent.hasPrefix("\(id)_") }
        }

        guard let sourceURL = src else {
            throw BoardStoreError.trashEntryNotFound(id)
        }

        let data: Data
        let decoded: SaveData
        do {
            data = try Data(contentsOf: sourceURL)
            decoded = try decodeBoardData(data)
            ensureDirectoryExists(baseDirectory)
            try data.write(to: boardURL(for: newBoardId), options: .atomic)
        } catch {
            throw BoardStoreError.ioFailure("Failed to restore board", error)
        }

        try? fileManager.removeItem(at: sourceURL)
        entries.removeAll { $0.id == id }
        try? saveTrashIndex(entries)

        let name = entry?.name ?? "Restored Board"
        return (name, decoded, entries.sorted { $0.deletedAt > $1.deletedAt })
    }

    /// Permanently deletes a single trashed board from disk and `trash_index.json`.
    @discardableResult
    func permanentlyDeleteTrash(id: String) -> [TrashEntry] {
        var entries = loadTrash()
        if let entry = entries.first(where: { $0.id == id }) {
            if let fileName = entry.fileName {
                try? fileManager.removeItem(at: trashDirectory.appendingPathComponent(fileName))
            } else {
                let files = (try? fileManager.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil)) ?? []
                for file in files where file.lastPathComponent.hasPrefix("\(id)_") {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        entries.removeAll { $0.id == id }
        try? saveTrashIndex(entries)
        return entries.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Permanently deletes all trashed boards and clears `trash_index.json`.
    @discardableResult
    func emptyTrash() -> [TrashEntry] {
        let files = (try? fileManager.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "wb" {
            try? fileManager.removeItem(at: file)
        }
        try? saveTrashIndex([])
        return []
    }
}
