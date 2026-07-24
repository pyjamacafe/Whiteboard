import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @ObservedObject var model: DrawingModel
    @State private var showImporter = false
    @State private var showNewName = false
    @State private var showNewFolder = false
    @State private var newName = ""
    @State private var newFolderName = ""
    @State private var renamingId: String?
    @State private var renameText = ""
    @State private var hoveredBoard: String?
    @State private var deleteBoardId: String?
    @State private var deleteBoardName: String = ""
    @State private var showDeleteAlert = false
    @State private var showRenameFolder = false
    @State private var renameFolderId: String?
    @State private var renameFolderText = ""
    @State private var selectedFolder: String?
    @State private var hoveredButton: String?
    @State private var hoveredFolder: String?
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 200)
                .background(Color.primary.opacity(0.05))

            Divider()

            // Main content
            mainContent
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(model.appSettings.isDarkMode ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color(.windowBackgroundColor))
        #else
        .background(model.appSettings.isDarkMode ? Color(red: 28/255, green: 28/255, blue: 30/255) : Color(.systemBackground))
        #endif
        .foregroundColor(model.appSettings.isDarkMode ? .white : .primary)
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        .accentColor(model.appSettings.isDarkMode ? Color(red: 0.5, green: 0.8, blue: 1.0) : nil)
        .onAppear { model.loadTrash() }
        .onChange(of: selectedFolder) { _, newValue in
            model.welcomeFolderName = newValue.flatMap { id in model.folders.first(where: { $0.id == id })?.name }
        }
        .alert("New Doodle", isPresented: $showNewName) {
            TextField("Doodle name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.createBoard(name: name); newName = ""; onStart() }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: { Text("Enter a name for the new doodle") }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.createFolder(name: name); newFolderName = "" }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: { Text("Enter a name for the folder") }
        .alert("Rename Folder", isPresented: $showRenameFolder) {
            TextField("Folder name", text: $renameFolderText)
            Button("Rename") {
                let name = renameFolderText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let id = renameFolderId { model.renameFolder(id: id, to: name) }
                renameFolderId = nil
            }
            Button("Cancel", role: .cancel) { renameFolderId = nil }
        } message: { Text("Enter a new name for the folder") }
        .alert("Delete Doodle", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = deleteBoardId { model.trashBoard(id: id, name: deleteBoardName) }
            }
            Button("Cancel", role: .cancel) { deleteBoardId = nil }
        } message: {
            Text("\"\(deleteBoardName)\" will be moved to trash and permanently deleted after 30 days.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Folders").font(.headline).foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.top, 16)

            // "All Doodles" item
            Button(action: { selectedFolder = nil }) {
                HStack {
                    Image(systemName: "tray.full").frame(width: 20)
                    Text("All Doodles").font(.body)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hoveredFolder == nil ? (selectedFolder == nil ? Color.accentColor.opacity(0.15) : Color.clear) : Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveredFolder = $0 ? "" : nil }
            .pointingHand()

            // Folders
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.folders) { folder in
                        Button(action: { selectedFolder = folder.id }) {
                            HStack {
                                Image(systemName: "folder.fill").foregroundColor(.accentColor).frame(width: 20)
                                Text(folder.name).font(.body).lineLimit(1)
                                Spacer()
                                Text("\(model.boardIdsInFolder(folder.id).count)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedFolder == folder.id ? Color.accentColor.opacity(0.15) :
                                hoveredFolder == folder.id ? Color.accentColor.opacity(0.12) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveredFolder = $0 ? folder.id : nil }
                        .pointingHand()
                        .contextMenu {
                            Button("Rename") { renameFolderId = folder.id; renameFolderText = folder.name; showRenameFolder = true }
                            Button("Delete", role: .destructive) { model.deleteFolder(id: folder.id) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Main content

    @AppStorage("viewMode") private var viewMode: ViewMode = .list

    enum ViewMode: String, CaseIterable { case list, thumbnails }

    private var mainContent: some View {
        VStack(spacing: 12) {
            // Logo + Title row (centered)
            VStack(spacing: 8) {
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                Text("Doodles")
                    .font(.system(size: 42, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

            // Buttons row
            HStack(spacing: 6) {
                Button(action: { showNewName = true }) {
                    Label("New", systemImage: "plus.square")
                        .font(.system(size: 12))
                        .frame(minWidth: 56, minHeight: 26)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHand()
                .brightness(hoveredButton == "new" ? -0.15 : 0)
                .onHover { hoveredButton = $0 ? "new" : nil }

                Button(action: { model.pendingAction = .open }) {
                    Label("Open", systemImage: "folder")
                        .font(.system(size: 12))
                        .frame(minWidth: 56, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHand()
                .brightness(hoveredButton == "open" ? -0.15 : 0)
                .onHover { hoveredButton = $0 ? "open" : nil }

                Button(action: { showNewFolder = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .frame(minWidth: 26, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHand()
                .brightness(hoveredButton == "newfolder" ? -0.15 : 0)
                .onHover { hoveredButton = $0 ? "newfolder" : nil }

                Spacer()

                Button(action: { model.appSettings.isDarkMode.toggle() }) {
                    Image(systemName: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 12))
                        .frame(minWidth: 26, minHeight: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHand()
                .brightness(hoveredButton == "theme" ? -0.15 : 0)
                .onHover { hoveredButton = $0 ? "theme" : nil }

                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.thumbnails)
                }
                .pickerStyle(.segmented)
                .frame(width: 80, height: 26)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Board list / thumbnails
            ScrollView {
                let displayBoards = selectedFolder == nil ? model.boards : model.boards.filter { model.boardIdsInFolder(selectedFolder!).contains($0.id) }
                let items = Array(displayBoards.prefix(10))

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Text("No doodles yet").foregroundColor(.secondary).padding(.top, 40)
                        Text("Create a new doodle or open an existing one")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else if viewMode == .thumbnails {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240))], spacing: 16) {
                        ForEach(items) { board in
                            thumbnailCell(board)
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 2) {
                        ForEach(items) { board in
                            boardRow(board)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if !model.trashedBoards.isEmpty {
                    Divider().padding(.vertical, 8).padding(.horizontal, viewMode == .thumbnails ? 24 : 20)
                    Text("Recently Deleted").font(.headline).foregroundColor(.secondary)
                        .padding(.horizontal, viewMode == .thumbnails ? 24 : 20)

                    ForEach(model.trashedBoards.prefix(5), id: \.id) { entry in
                        HStack {
                            Text(entry.name).font(.body).foregroundColor(.secondary)
                            Spacer()
                            Text(entry.deletedAt, style: .relative).font(.caption).foregroundColor(.secondary)
                            Button("Restore") {
                                if model.restoreBoard(id: entry.id) { model.loadTrash() }
                            }
                            .buttonStyle(.plain).font(.caption).foregroundColor(.accentColor).pointingHand()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, viewMode == .thumbnails ? 24 : 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Thumbnail cell

    private func thumbnailCell(_ board: DrawingModel.BoardMeta) -> some View {
        let img = model.thumbnail(for: board.id)
        let isHovered = hoveredBoard == board.id
        return VStack(spacing: 8) {
            Group {
                if let img = img {
                    #if os(macOS)
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fill)
                    #else
                    Image(uiImage: img)
                        .resizable().aspectRatio(contentMode: .fill)
                    #endif
                } else {
                    Image(systemName: "doc.text")
                        .font(.largeTitle).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.75, contentMode: .fill)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(isHovered ? 0.15 : 0), radius: isHovered ? 8 : 0, y: isHovered ? 4 : 0)
            .scaleEffect(isHovered ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onTapGesture { model.loadBoard(id: board.id); onStart() }

            Text(board.name).font(.caption).lineLimit(1)
            Text(board.modified.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(maxWidth: 200)
        .onHover { hovering in
            hoveredBoard = hovering ? board.id : nil
            #if os(macOS)
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            #endif
        }
    }

    // MARK: - Board row

    @ViewBuilder
    private func boardRow(_ board: DrawingModel.BoardMeta) -> some View {
        HStack {
            if renamingId == board.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { finishRename(board.id) }
                Button("Save") { finishRename(board.id) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                VStack(alignment: .leading) {
                    Text(board.name).font(.body)
                    Text(board.modified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { model.loadBoard(id: board.id); onStart() }
                .pointingHand()
                .onHover { hoveredBoard = $0 ? board.id : nil }

                Spacer()

                Menu {
                    ForEach(model.folders) { f in
                        Button(f.name) { model.moveBoard(boardId: board.id, toFolder: f.id) }
                    }
                    Button("No folder") { model.moveBoard(boardId: board.id, toFolder: nil) }
                } label: { Image(systemName: "folder.badge.plus").font(.caption) }
                .menuStyle(.borderlessButton)
                .help("Move to folder")

                Button(action: { startRename(board) }) { Image(systemName: "pencil").font(.caption) }
                    .buttonStyle(.plain).help("Rename").pointingHand()

                Button(action: { confirmDelete(board) }) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.plain).help("Delete").pointingHand()
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(hoveredBoard == board.id ? Color.accentColor.opacity(0.12) : Color.clear))
    }

    // MARK: - Helpers

    private func finishRename(_ id: String) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { model.renameBoard(id: id, to: name) }
        renamingId = nil
    }

    private func confirmDelete(_ board: DrawingModel.BoardMeta) {
        deleteBoardId = board.id; deleteBoardName = board.name; showDeleteAlert = true
    }

    private func startRename(_ board: DrawingModel.BoardMeta) {
        renamingId = board.id; renameText = board.name
    }
}

extension View {
    @ViewBuilder
    func pointingHand() -> some View {
        #if os(macOS)
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        #else
        self
        #endif
    }
}


