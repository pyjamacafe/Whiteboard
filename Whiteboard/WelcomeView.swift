import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct WelcomeView: View {
    @ObservedObject var model: DrawingModel
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
    @State private var hoveredFolder: String?
    @State private var searchText = ""
    @State private var selectedBoardIds: Set<String> = []
    @State private var showBulkDeleteAlert = false
    @FocusState private var listFocused: Bool
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 220)
                .background(Color.primary.opacity(0.05))

            Divider()

            // Main content
            mainContent
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(model.appSettings.isDarkMode ? Color.black : Color(.windowBackgroundColor))
        #else
        .background(model.appSettings.isDarkMode ? Color.black : Color(.systemBackground))
        #endif
        .foregroundColor(model.appSettings.isDarkMode ? .white : .primary)
        .colorScheme(model.appSettings.isDarkMode ? .dark : .light)
        .accentColor(model.appSettings.isDarkMode ? Color(red: 0.5, green: 0.8, blue: 1.0) : nil)
        .onAppear {
            model.loadTrash()
            listFocused = true
        }
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
        .alert(bulkDeleteTitle, isPresented: $showBulkDeleteAlert) {
            Button("Delete", role: .destructive) { trashSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("They will be moved to trash and permanently deleted after 30 days.")
        }
    }

    private var bulkDeleteTitle: String {
        selectedBoardIds.count == 1 ? "Delete Doodle?" : "Delete \(selectedBoardIds.count) Doodles?"
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Folders").font(.headline).foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.top, 16)

            // "All Doodles" item (drop target to remove a board from a folder)
            Button(action: { selectedFolder = nil }) {
                HStack {
                    Image(systemName: "tray.full").frame(width: 20)
                    Text("All Doodles").font(.body)
                    Spacer()
                    Text("\(model.boards.count)").font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    selectedFolder == nil ? Color.accentColor.opacity(0.15) :
                    hoveredFolder == "" ? Color.accentColor.opacity(0.12) : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveredFolder = $0 ? "" : nil }
            .pointingHand()
            .dropDestination(for: String.self) { ids, _ in
                for id in ids { model.moveBoard(boardId: id, toFolder: nil) }
                return true
            }

            // Folders
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.folders) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 8)
    }

    private func folderRow(_ folder: DrawingModel.BoardFolder) -> some View {
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
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { model.moveBoard(boardId: id, toFolder: folder.id) }
            return true
        }
        .contextMenu {
            Button("Rename") { renameFolderId = folder.id; renameFolderText = folder.name; showRenameFolder = true }
            Button("Delete", role: .destructive) { model.deleteFolder(id: folder.id) }
        }
    }

    // MARK: - Main content

    @AppStorage("viewMode") private var viewMode: ViewMode = .list
    @AppStorage("boardSort") private var sortRaw: String = SortMode.modified.rawValue

    enum ViewMode: String, CaseIterable { case list, thumbnails }
    enum SortMode: String, CaseIterable {
        case modified = "Date Modified"
        case created = "Date Created"
        case name = "Name"
    }

    private var sortMode: SortMode { SortMode(rawValue: sortRaw) ?? .modified }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header

            // Bulk-selection action bar
            if !selectedBoardIds.isEmpty {
                bulkActionBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Recents
                    if !recentBoards.isEmpty {
                        sectionHeader("Recents")
                        recentStrip
                            .padding(.bottom, 16)
                    }

                    sectionHeader(selectedFolder == nil ? "All Doodles" : (model.folders.first(where: { $0.id == selectedFolder })?.name ?? "Doodles"))

                    if displayedBoards.isEmpty {
                        emptyState
                    } else if viewMode == .thumbnails {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260))], spacing: 20) {
                            ForEach(displayedBoards) { board in
                                thumbnailCell(board)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(displayedBoards) { board in
                                boardRow(board)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                    }

                    if !model.trashedBoards.isEmpty {
                        Divider().padding(.vertical, 12).padding(.horizontal, viewMode == .thumbnails ? 28 : 24)
                        Text("Recently Deleted").font(.headline).foregroundColor(.secondary)
                            .padding(.horizontal, viewMode == .thumbnails ? 28 : 24)

                        ForEach(model.trashedBoards, id: \.id) { entry in
                            HStack {
                                Text(entry.name).font(.body).foregroundColor(.secondary)
                                Spacer()
                                Text(relativeDate(entry.deletedAt)).font(.caption).foregroundColor(.secondary)
                                Button("Restore") {
                                    if model.restoreBoard(id: entry.id) { model.loadTrash() }
                                }
                                .buttonStyle(.plain).font(.caption).foregroundColor(.accentColor).pointingHand()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, viewMode == .thumbnails ? 28 : 24)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            #if os(macOS)
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .onKeyPress(.return) { openSelected(); return .handled }
            .onKeyPress(.delete) { if !selectedBoardIds.isEmpty { showBulkDeleteAlert = true }; return .handled }
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image("logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                    Text("Doodles").font(.system(size: 24, weight: .bold))
                }

                Spacer()

                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search doodles", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Sort
                Menu {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) { sortRaw = mode.rawValue }
                    }
                } label: {
                    Label(sortMode.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort")
                .pointingHand()

                // Theme
                Button(action: { model.appSettings.isDarkMode.toggle() }) {
                    Image(systemName: model.appSettings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .help(model.appSettings.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
                .pointingHand()

                // View mode
                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.thumbnails)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }

            // Actions
            HStack(spacing: 12) {
                Button(action: { showNewName = true }) {
                    Label("New Doodle", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .pointingHand()

                Button(action: { model.pendingAction = .open }) {
                    Label("Open", systemImage: "folder")
                        .font(.system(size: 14))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .pointingHand()

                Button(action: { showNewFolder = true }) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 14))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .pointingHand()

                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.secondary)
            .padding(.horizontal, viewMode == .thumbnails ? 28 : 24)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Recents

    private var recentBoards: [DrawingModel.BoardMeta] {
        var seen = Set<String>()
        var result: [DrawingModel.BoardMeta] = []
        for url in model.recentFiles {
            let id = url.deletingPathExtension().lastPathComponent
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            if let board = model.boards.first(where: { $0.id == id }) {
                result.append(board)
            }
            if result.count >= 5 { break }
        }
        return result
    }

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(recentBoards) { board in
                    recentCell(board)
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private func recentCell(_ board: DrawingModel.BoardMeta) -> some View {
        let img = model.thumbnail(for: board.id, size: CGSize(width: 160, height: 120))
        return VStack(spacing: 4) {
            Group {
                if let img = img {
                    #if os(macOS)
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    #else
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    #endif
                } else {
                    Image(systemName: "doc.text").foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 80)
            .background(Color.primary.opacity(0.06))
            .clipped()

            Text(board.name).font(.caption).lineLimit(1)
        }
        .frame(width: 120)
        .contentShape(Rectangle())
        .onTapGesture { openBoard(board) }
        .pointingHand()
        .onHover { hoveredBoard = $0 ? board.id : nil }
    }

    // MARK: - Bulk actions

    private var bulkActionBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedBoardIds.count) selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            // Move to folder
            Menu {
                Button("No folder") { moveSelected(toFolder: nil) }
                ForEach(model.folders) { folder in
                    Button(folder.name) { moveSelected(toFolder: folder.id) }
                }
            } label: {
                Label("Move", systemImage: "folder")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            #if os(macOS)
            Button(action: { exportBoards(Array(selectedBoardIds)) }) {
                Label("Export PNG", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            #endif

            Button(role: .destructive, action: { showBulkDeleteAlert = true }) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Clear") { selectedBoardIds.removeAll() }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHand()
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No doodles yet" : "No matches for \"\(searchText)\"")
                .font(.title3.weight(.medium))
            Text(searchText.isEmpty ? "Create your first doodle or open an existing one" : "Try a different search")
                .font(.caption)
                .foregroundColor(.secondary)
            if searchText.isEmpty {
                Button(action: { showNewName = true }) {
                    Label("New Doodle", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Thumbnail cell

    private func thumbnailCell(_ board: DrawingModel.BoardMeta) -> some View {
        let img = model.thumbnail(for: board.id)
        let isHovered = hoveredBoard == board.id
        let isSelected = selectedBoardIds.contains(board.id)
        return VStack(spacing: 0) {
            // Thumbnail
            Group {
                if let img = img {
                    #if os(macOS)
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    #else
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                    #endif
                } else {
                    Image(systemName: "doc.text").font(.largeTitle).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .aspectRatio(4/3, contentMode: .fill)
            .background(Color.primary.opacity(0.06))
            .clipped()

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if renamingId == board.id {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { finishRename(board.id) }
                } else {
                    Text(board.name).font(.caption).lineLimit(1)
                    Text(relativeDate(board.modified))
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }

                HStack(spacing: 6) {
                    Button(action: { startRename(board) }) { Image(systemName: "pencil").font(.caption2) }
                        .buttonStyle(.plain).pointingHand()
                    #if os(macOS)
                    Button(action: { exportBoards([board.id]) }) { Image(systemName: "square.and.arrow.up").font(.caption2) }
                        .buttonStyle(.plain).pointingHand()
                    #endif
                    Spacer()
                    Button(action: { confirmDelete(board) }) { Image(systemName: "trash").font(.caption2) }
                        .buttonStyle(.plain).pointingHand()
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1))
        .shadow(color: .black.opacity(isHovered ? 0.12 : 0.04), radius: isHovered ? 8 : 3, y: isHovered ? 4 : 1)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture { handleSelect(board) }
        .onTapGesture(count: 2) { openBoard(board) }
        .draggable(board.id)
        .onHover { hovering in
            hoveredBoard = hovering ? board.id : nil
            #if os(macOS)
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            #endif
        }
        .contextMenu { boardContextMenu(board) }
    }

    // MARK: - Board row

    @ViewBuilder
    private func boardRow(_ board: DrawingModel.BoardMeta) -> some View {
        let isSelected = selectedBoardIds.contains(board.id)
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
                    Text(relativeDate(board.modified))
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleSelect(board) }
                .onTapGesture(count: 2) { openBoard(board) }
                .pointingHand()
                .onHover { hoveredBoard = $0 ? board.id : nil }

                Spacer()

                Button(action: { startRename(board) }) { Image(systemName: "pencil").font(.caption) }
                    .buttonStyle(.plain).help("Rename").pointingHand()

                #if os(macOS)
                Button(action: { exportBoards([board.id]) }) { Image(systemName: "square.and.arrow.up").font(.caption) }
                    .buttonStyle(.plain).help("Export PNG").pointingHand()
                #endif

                Button(action: { confirmDelete(board) }) { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.plain).help("Delete").pointingHand()
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.18) : (hoveredBoard == board.id ? Color.accentColor.opacity(0.12) : Color.clear)))
        .contentShape(Rectangle())
        .draggable(board.id)
        .contextMenu { boardContextMenu(board) }
    }

    @ViewBuilder
    private func boardContextMenu(_ board: DrawingModel.BoardMeta) -> some View {
        Button("Open") { openBoard(board) }
        Button("Rename") { startRename(board) }
        Menu("Move to Folder") {
            Button("No folder") { model.moveBoard(boardId: board.id, toFolder: nil) }
            ForEach(model.folders) { folder in
                Button(folder.name) { model.moveBoard(boardId: board.id, toFolder: folder.id) }
            }
        }
        #if os(macOS)
        Button("Export PNG") { exportBoards([board.id]) }
        #endif
        Divider()
        Button("Delete", role: .destructive) { confirmDelete(board) }
    }

    // MARK: - Interaction

    private func handleSelect(_ board: DrawingModel.BoardMeta) {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedBoardIds.contains(board.id) { selectedBoardIds.remove(board.id) }
            else { selectedBoardIds.insert(board.id) }
        } else if flags.contains(.shift) {
            selectedBoardIds.insert(board.id)
        } else {
            selectedBoardIds = [board.id]
        }
        #else
        if selectedBoardIds.contains(board.id) {
            selectedBoardIds = selectedBoardIds.count > 1 ? [board.id] : []
        } else {
            selectedBoardIds = [board.id]
        }
        #endif
    }

    private func openBoard(_ board: DrawingModel.BoardMeta) {
        model.loadBoard(id: board.id)
        onStart()
    }

    private func moveSelection(_ delta: Int) {
        guard !displayedBoards.isEmpty else { return }
        let current: Int?
        if let sel = selectedBoardIds.first {
            current = displayedBoards.firstIndex { $0.id == sel }
        } else {
            current = nil
        }
        let next: Int
        if let idx = current {
            next = min(max(idx + delta, 0), displayedBoards.count - 1)
        } else {
            next = delta > 0 ? 0 : displayedBoards.count - 1
        }
        selectedBoardIds = [displayedBoards[next].id]
    }

    private func openSelected() {
        if let sel = selectedBoardIds.first, let board = displayedBoards.first(where: { $0.id == sel }) {
            openBoard(board)
        }
    }

    private func moveSelected(toFolder folderId: String?) {
        for id in selectedBoardIds { model.moveBoard(boardId: id, toFolder: folderId) }
        selectedBoardIds.removeAll()
    }

    private func trashSelected() {
        for id in selectedBoardIds {
            if let board = model.boards.first(where: { $0.id == id }) {
                model.trashBoard(id: id, name: board.name)
            }
        }
        selectedBoardIds.removeAll()
    }

    #if os(macOS)
    private func exportBoards(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        if panel.runModal() == .OK, let dir = panel.url {
            for id in ids {
                guard let name = model.boards.first(where: { $0.id == id })?.name,
                      let data = model.pngData(forBoardId: id) else { continue }
                let file = dir.appendingPathComponent(name).appendingPathExtension("png")
                try? data.write(to: file)
            }
        }
    }
    #endif

    // MARK: - Computed boards

    private var displayedBoards: [DrawingModel.BoardMeta] {
        let base: [DrawingModel.BoardMeta]
        if let folder = selectedFolder {
            let ids = Set(model.boardIdsInFolder(folder))
            base = model.boards.filter { ids.contains($0.id) }
        } else {
            base = model.boards
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(q) }
        switch sortMode {
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .created: return filtered.sorted { $0.created > $1.created }
        case .modified: return filtered.sorted { $0.modified > $1.modified }
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

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
