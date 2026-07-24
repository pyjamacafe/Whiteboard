import SwiftUI
import UniformTypeIdentifiers

struct SettingsPopupView: View {
    @ObservedObject var model: DrawingModel
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportData: Data?
    @State private var exportName = "Untitled"
    @State private var exportType: UTType = .data

    enum ExportFormat: String, CaseIterable {
        case wb = "Whiteboard"
        case png = "PNG"
        case pdf = "PDF"
    }

    @State private var exportFormat: ExportFormat = .wb

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            HStack(spacing: 8) {
                Button(action: { model.undo() }) { Image(systemName: "arrow.uturn.backward").font(.title3).frame(width: 32, height: 32) }
                    .disabled(!model.canUndo)
                Button(action: { model.redo() }) { Image(systemName: "arrow.uturn.forward").font(.title3).frame(width: 32, height: 32) }
                    .disabled(!model.canRedo)
                Button(action: { model.deleteSelected() }) { Image(systemName: "trash").font(.title3).frame(width: 32, height: 32) }
                    .disabled(model.strokes.isEmpty && model.fillRegions.isEmpty)
                Button(action: { model.needsRecenter = true }) { Image(systemName: "viewfinder").font(.title3).frame(width: 32, height: 32) }
                Spacer()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Divider()

            Toggle(isOn: $model.appSettings.isDarkMode) {
                HStack {
                    Image(systemName: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .frame(width: 20)
                    Text("Dark Mode")
                }
            }
            .toggleStyle(.switch)

            Divider()

            Text("Canvas Background").font(.subheadline).foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(CanvasBackground.allCases, id: \.self) { bg in
                    let isSelected = model.appSettings.canvasBackground == bg
                    Button(action: { model.appSettings.canvasBackground = bg }) {
                        Image(systemName: iconName(for: bg))
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                            .foregroundColor(isSelected ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Group {
                    Button(action: saveFile) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(model.openFileURL != nil ? Color.accentColor : Color.primary.opacity(0.08))
                            .foregroundColor(model.openFileURL != nil ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .help(model.openFileURL != nil ? "Save" : "Save As…")

                    Button(action: { exportFormat = .png; prepareExport() }) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .help("Export PNG")

                    Button(action: { exportFormat = .pdf; prepareExport() }) {
                        Image(systemName: "doc.richtext")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .help("Export PDF")
                }
                .disabled(model.strokes.isEmpty && model.fillRegions.isEmpty)
                .buttonStyle(.plain)

                Spacer()

                Button(action: { showingImporter = true }) {
                    Image(systemName: "folder")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.08))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Open .wb")
            }
        }
        .padding(14)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .frame(maxWidth: 260)
        .fileExporter(isPresented: $showingExporter, document: ExportDocument(data: exportData ?? Data()), contentType: exportType, defaultFilename: exportName) { _ in }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.init(filenameExtension: "wb")!, .data]) { result in
            if case .success(let url) = result {
                let shouldStop = url.startAccessingSecurityScopedResource()
                defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    model.loadData(data)
                    model.openFileURL = url
                }
            }
        }
    }

    private func saveFile() {
        if model.openFileURL != nil {
            model.save()
        } else {
            exportFormat = .wb
            prepareExport()
        }
    }

    private func prepareExport() {
        let (size, offset) = canvasRect()
        switch exportFormat {
        case .wb:
            exportData = model.saveData()
            exportType = .init(filenameExtension: "wb") ?? .data
            exportName = "Untitled.wb"
        case .png:
            exportData = model.pngData(size: size, offset: offset, scale: 4)
            exportType = .png
            exportName = "Untitled.png"
        case .pdf:
            exportData = model.pdfData(size: size, offset: offset)
            exportType = .pdf
            exportName = "Untitled.pdf"
        }
        showingExporter = exportData != nil
    }

    private func canvasRect() -> (size: CGSize, offset: CGPoint) {
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = 0
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

    private func iconName(for bg: CanvasBackground) -> String {
        switch bg {
        case .none: return "rectangle"
        case .grid: return "grid"
        case .dots: return "circle.grid.2x2"
        case .ruled: return "line.horizontal.3"
        }
    }
}

struct ExportDocument: FileDocument {
    let data: Data

    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.data, .png, .pdf, .init(filenameExtension: "wb")!] }

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
