import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @ObservedObject var model: DrawingModel
    @State private var showImporter = false
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pencil.tip")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Whiteboard")
                .font(.largeTitle).bold()

            Text("Start a new board or open an existing one")
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: { onStart() }) {
                    Label("New Board", systemImage: "plus.square")
                        .frame(maxWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showImporter = true }) {
                    Label("Open…", systemImage: "folder")
                        .frame(maxWidth: 160, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            if !model.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent").font(.headline).padding(.top, 8)

                    ForEach(Array(model.recentFiles.prefix(5)), id: \.path) { url in
                        Button(action: {
                            let shouldStop = url.startAccessingSecurityScopedResource()
                            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url) {
                                model.loadData(data)
                                model.openFileURL = url
                                onStart()
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc").foregroundColor(.secondary)
                                Text(url.lastPathComponent).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 320)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.init(filenameExtension: "wb")!, .data]) { result in
            if case .success(let url) = result {
                let shouldStop = url.startAccessingSecurityScopedResource()
                defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    model.loadData(data)
                    model.openFileURL = url
                    onStart()
                }
            }
        }
    }
}
