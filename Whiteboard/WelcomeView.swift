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
    @State private var expandedFolders: Set<String> = []
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "pencil.tip")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Whiteboard")
                .font(.largeTitle).bold()

            HStack(spacing: 16) {
                Button(action: { showNewName = true }) {
                    Label("New Board", systemImage: "plus.square")
                        .frame(maxWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { model.pendingAction = .open }) {
                    Label("Open…", systemImage: "folder")
                        .frame(maxWidth: 160, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { showNewFolder = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .help("New Folder")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !model.boards.isEmpty || !model.folders.isEmpty {
                        Text("Boards").font(.headline).padding(.top, 4)
                    }

                    // Folders
                    ForEach(model.folders) { folder in
                        VStack(alignment: .leading, spacing: 2) {
                            Button(action: {
                                if expandedFolders.contains(folder.id) {
                                    expandedFolders.remove(folder.id)
                                } else {
                                    expandedFolders.insert(folder.id)
                                }
                            }) {
                                HStack {
                                    Image(systemName: expandedFolders.contains(folder.id) ? "folder.fill" : "folder")
                                        .foregroundColor(.accentColor)
                                    Text(folder.name).font(.body)
                                    Spacer()
                                    Text("\(model.boardIdsInFolder(folder.id).count)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(action: { startRenameFolder(folder) }) {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive, action: { model.deleteFolder(id: folder.id) }) {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                            }

                            if expandedFolders.contains(folder.id) {
                                let ids = model.boardIdsInFolder(folder.id)
                                let folderBoards = model.boards.filter { ids.contains($0.id) }
                                ForEach(folderBoards) { board in
                                    boardRow(board, folderId: folder.id)
                                }
                                if folderBoards.isEmpty {
                                    Text("Empty folder")
                                        .font(.caption).foregroundColor(.secondary)
                                        .padding(.leading, 32).padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    // Unfiled boards
                    let unfiled = model.boards.filter { b in
                        !model.folders.contains(where: { $0.boardIds.contains(b.id) })
                    }
                    ForEach(unfiled) { board in
                        boardRow(board, folderId: nil)
                    }
                }
                .frame(maxWidth: 380)
            }

            if !model.trashedBoards.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Deleted").font(.headline).padding(.top, 4)
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
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: 380)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.loadTrash() }
        .alert("New Board", isPresented: $showNewName) {
            TextField("Board name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    model.createBoard(name: name)
                    newName = ""; onStart()
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: { Text("Enter a name for the new board") }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    model.createFolder(name: name)
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: { Text("Enter a name for the folder") }
        .alert("Rename Folder", isPresented: $showRenameFolder) {
            TextField("Folder name", text: $renameFolderText)
            Button("Rename") {
                let name = renameFolderText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let id = renameFolderId {
                    model.renameFolder(id: id, to: name)
                }
                renameFolderId = nil
            }
            Button("Cancel", role: .cancel) { renameFolderId = nil }
        } message: { Text("Enter a new name for the folder") }
        .alert("Delete Board", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = deleteBoardId {
                    model.trashBoard(id: id, name: deleteBoardName)
                }
            }
            Button("Cancel", role: .cancel) { deleteBoardId = nil }
        } message: {
            Text("\"\(deleteBoardName)\" will be moved to trash and permanently deleted after 30 days.")
        }
    }

    @ViewBuilder
    private func boardRow(_ board: DrawingModel.BoardMeta, folderId: String?) -> some View {
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
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hoveredBoard == board.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03)))
    }

    private func confirmDelete(_ board: DrawingModel.BoardMeta) {
        deleteBoardId = board.id; deleteBoardName = board.name; showDeleteAlert = true
    }

    private func startRenameFolder(_ folder: DrawingModel.BoardFolder) {
        renameFolderId = folder.id; renameFolderText = folder.name; showRenameFolder = true
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
