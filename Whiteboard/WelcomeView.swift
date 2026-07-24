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
                .padding(.horizontal, 12).padding(.top, 16)

            // "All Doodles" item
            Button(action: { selectedFolder = nil }) {
                HStack {
                    Image(systemName: "tray.full").frame(width: 20)
                    Text("All Doodles").font(.body)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selectedFolder == nil ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

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
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selectedFolder == folder.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename") { renameFolderId = folder.id; renameFolderText = folder.name; showRenameFolder = true }
                            Button("Delete", role: .destructive) { model.deleteFolder(id: folder.id) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Main content

    @State private var viewMode: ViewMode = .list

    enum ViewMode: String, CaseIterable { case list, thumbnails }

    private var mainContent: some View {
        VStack(spacing: 12) {
            // Logo row
            HStack {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.top, 24).padding(.horizontal, 24)

            // Title row
            HStack {
                Text("Doodles")
                    .font(.largeTitle).bold()
                Spacer()
            }
            .padding(.horizontal, 24)

            // Buttons row
            HStack(spacing: 8) {
                Button(action: { showNewName = true }) {
                    Label("New", systemImage: "plus.square")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)

                Button(action: { model.pendingAction = .open }) {
                    Label("Open", systemImage: "folder")
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button(action: { showNewFolder = true }) {
                    Image(systemName: "folder.badge.plus").font(.title3)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Spacer()

                Button(action: { model.appSettings.isDarkMode.toggle() }) {
                    Image(systemName: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.thumbnails)
                }
                .pickerStyle(.segmented).frame(width: 88)
            }
            .padding(.horizontal, 24)

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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200))], spacing: 12) {
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
                            .buttonStyle(.plain).font(.caption).foregroundColor(.accentColor)
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
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .aspectRatio(1.4, contentMode: .fit)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.largeTitle).foregroundColor(.secondary)
                )
                .onTapGesture { model.loadBoard(id: board.id); onStart() }

            Text(board.name).font(.caption).lineLimit(1)
            Text(board.modified.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(maxWidth: 200)
        .onHover { hoveredBoard = $0 ? board.id : nil }
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
                    .buttonStyle(.plain).help("Rename")

                Button(action: { confirmDelete(board) }) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.plain).help("Delete")
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(hoveredBoard == board.id ? Color.accentColor.opacity(0.12) : Color.clear))
    }

    // MARK: - Helpers

    private func confirmDelete(_ board: DrawingModel.BoardMeta) {
        deleteBoardId = board.id; deleteBoardName = board.name; showDeleteAlert = true
    }

    private func startRename(_ board: DrawingModel.BoardMeta) {
        renamingId = board.id; renameText = board.name
    }

    private func finishRename(_ id: String) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { model.renameBoard(id: id, to: name) }
        renamingId = nil
    }
}
