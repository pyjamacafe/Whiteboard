import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct WelcomeView: View {
    var model: DrawingModel
    let onStart: () -> Void

    enum SidebarSelection: Hashable {
        case all
        case recents
        case trash
        case folder(String)
    }

    enum ViewMode: String, CaseIterable { case list, thumbnails }
    enum SortMode: String, CaseIterable {
        case modified = "Date Modified"
        case created = "Date Created"
        case name = "Name"
    }

    private struct TimeGroup: Identifiable {
        let id: String
        let title: String
        let boards: [BoardMeta]
    }

    private struct UndoTrashToast: Equatable {
        let message: String
        let trashedIds: [String]
    }

    @AppStorage("viewMode") private var viewMode: ViewMode = .thumbnails
    @AppStorage("boardSort") private var sortRaw: String = SortMode.modified.rawValue

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selection: SidebarSelection = .all
    @State private var searchText = ""
    @State private var isSearchPresented = false

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showRenameFolder = false
    @State private var renameFolderId: String?
    @State private var renameFolderText = ""

    @State private var renamingId: String?
    @State private var renameText = ""

    @State private var hoveredBoard: String?
    @State private var hoveredSidebar: SidebarSelection?
    @State private var dropTargetedFolder: SidebarSelection?

    @State private var showEmptyTrashAlert = false
    @State private var permanentDeleteEntry: TrashEntry?

    @State private var undoToast: UndoTrashToast?
    @State private var toastDismissTask: DispatchWorkItem?

    @FocusState private var renameFocused: Bool
    @FocusState private var contentFocused: Bool

    private var sortMode: SortMode { SortMode(rawValue: sortRaw) ?? .modified }
    private var isDark: Bool { model.appSettings.isDarkMode }

    private var activeFolderId: String? {
        if case .folder(let id) = selection { return id }
        return nil
    }

    private var sectionTitle: String {
        switch selection {
        case .all: return "All Tissues"
        case .recents: return "Recents"
        case .trash: return "Recently Deleted"
        case .folder(let id):
            return model.folders.first(where: { $0.id == id })?.name ?? "Folder"
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 260)
        } detail: {
            ZStack(alignment: .bottom) {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let toast = undoToast {
                    undoToastView(toast)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            #if os(macOS)
            .background(isDark ? Color(red: 18/255, green: 18/255, blue: 20/255) : Color(.windowBackgroundColor))
            #else
            .background(isDark ? Color.black : Color(.systemBackground))
            #endif
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: undoToast)
            .navigationTitle(sectionTitle)
            #if os(macOS)
            .navigationSubtitle(headerSubtitle)
            #endif
            .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Search")
            .toolbar {
                titlebarToolbarItems
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(isDark ? .white : .primary)
        .colorScheme(isDark ? .dark : .light)
        .accentColor(isDark ? Color(red: 0.45, green: 0.78, blue: 1.0) : nil)
        .onAppear {
            model.loadTrash()
            contentFocused = true
        }
        .onChange(of: selection) { _, newSelection in
            switch newSelection {
            case .folder(let id):
                model.welcomeFolderName = model.folders.first(where: { $0.id == id })?.name
            case .recents:
                model.welcomeFolderName = "Recents"
            case .trash:
                model.welcomeFolderName = "Recently Deleted"
            case .all:
                model.welcomeFolderName = nil
            }
        }
        .background(welcomeKeyboardShortcuts)
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.createFolder(name: name) }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: { Text("Enter a name for the new folder") }
        .alert("Rename Folder", isPresented: $showRenameFolder) {
            TextField("Folder name", text: $renameFolderText)
            Button("Rename") {
                let name = renameFolderText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let id = renameFolderId { model.renameFolder(id: id, to: name) }
                renameFolderId = nil
            }
            Button("Cancel", role: .cancel) { renameFolderId = nil }
        } message: { Text("Enter a new name for the folder") }
        .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(model.trashedBoards.count) deleted tissues will be permanently removed. This cannot be undone.")
        }
        .alert("Delete Permanently?", isPresented: Binding(
            get: { permanentDeleteEntry != nil },
            set: { if !$0 { permanentDeleteEntry = nil } }
        )) {
            Button("Delete Permanently", role: .destructive) {
                if let entry = permanentDeleteEntry {
                    model.permanentlyDeleteTrashedBoard(id: entry.id)
                }
                permanentDeleteEntry = nil
            }
            Button("Cancel", role: .cancel) { permanentDeleteEntry = nil }
        } message: {
            Text("\"\(permanentDeleteEntry?.name ?? "")\" will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Keyboard Shortcuts

    private var welcomeKeyboardShortcuts: some View {
        Group {
            Button("") { createNewBoard() }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { isSearchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { handleEscape() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .hidden()
        .frame(width: 0, height: 0)
    }

    private func handleEscape() {
        if renamingId != nil {
            renamingId = nil
            renameFocused = false
        } else if !searchText.isEmpty || isSearchPresented {
            searchText = ""
            isSearchPresented = false
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App brand header
            HStack(spacing: 10) {
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                Text("Tissue Box")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarSectionLabel("Library")

                    sidebarRow(
                        target: .all,
                        icon: "square.grid.2x2",
                        title: "All Tissues",
                        count: model.boards.count,
                        acceptsDrop: true,
                        onDropBoardIds: { ids in
                            for id in ids { model.moveBoard(boardId: id, toFolder: nil) }
                        }
                    )

                    sidebarRow(
                        target: .recents,
                        icon: "clock",
                        title: "Recents",
                        count: recentBoards.count
                    )

                    sidebarRow(
                        target: .trash,
                        icon: "trash",
                        title: "Recently Deleted",
                        count: model.trashedBoards.count,
                        tint: model.trashedBoards.isEmpty ? nil : .secondary
                    )

                    // Folders header with inline '+' button
                    HStack {
                        sidebarSectionLabel("Folders")
                        Spacer()
                        Button(action: { showNewFolder = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("New Folder")
                        .pointingHand()
                        .padding(.trailing, 8)
                        .padding(.top, 12)
                    }

                    if model.folders.isEmpty {
                        Text("No folders yet")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(model.folders) { folder in
                            sidebarRow(
                                target: .folder(folder.id),
                                icon: "folder.fill",
                                title: folder.name,
                                count: model.boardIdsInFolder(folder.id).count,
                                tint: .accentColor,
                                acceptsDrop: true,
                                onDropBoardIds: { ids in
                                    for id in ids { model.moveBoard(boardId: id, toFolder: folder.id) }
                                }
                            )
                            .contextMenu {
                                Button("Rename") {
                                    renameFolderId = folder.id
                                    renameFolderText = folder.name
                                    showRenameFolder = true
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    if selection == .folder(folder.id) { selection = .all }
                                    model.deleteFolder(id: folder.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
    }

    private func sidebarSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sidebarRow(
        target: SidebarSelection,
        icon: String,
        title: String,
        count: Int,
        tint: Color? = nil,
        acceptsDrop: Bool = false,
        onDropBoardIds: (([String]) -> Void)? = nil
    ) -> some View {
        let isSelected = selection == target
        let isHovered = hoveredSidebar == target
        let isDropTarget = dropTargetedFolder == target

        let row = Button(action: { selection = target }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : (tint ?? .secondary))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isDropTarget ? Color.accentColor.opacity(0.24) :
                        isSelected ? Color.accentColor.opacity(0.14) :
                        isHovered ? Color.primary.opacity(0.06) : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isDropTarget ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isDropTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredSidebar = $0 ? target : nil }
        .pointingHand()

        if acceptsDrop, let onDropBoardIds {
            row.dropDestination(for: String.self) { ids, _ in
                onDropBoardIds(ids)
                return true
            } isTargeted: { targeted in
                dropTargetedFolder = targeted ? target : (dropTargetedFolder == target ? nil : dropTargetedFolder)
            }
        } else {
            row
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            if selection == .trash {
                trashContent
            } else {
                boardsContent
            }
        }
    }

    // MARK: - Unified Titlebar Toolbar

    @ToolbarContentBuilder
    private var titlebarToolbarItems: some ToolbarContent {
        if selection == .trash {
            if !model.trashedBoards.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive, action: { showEmptyTrashAlert = true }) {
                        Label("Empty Trash", systemImage: "trash")
                    }
                    .pointingHand()
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { model.appSettings.isDarkMode.toggle() }) {
                    Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                }
                .help(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
                .pointingHand()
            }
        } else {
            // Order: New (+), Open, Search, Theme toggle, then Sort & View
            ToolbarItem(placement: .automatic) {
                Button(action: createNewBoard) {
                    Image(systemName: "plus")
                }
                .help("New Tissue (⌘N)")
                .pointingHand()
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { model.pendingAction = .open }) {
                    Image(systemName: "folder")
                }
                .help("Open .wb File…")
                .pointingHand()
            }

            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .automatic)
            }
            #endif

            ToolbarItem(placement: .automatic) {
                Button(action: { model.appSettings.isDarkMode.toggle() }) {
                    Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                }
                .help(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
                .pointingHand()
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Button {
                            sortRaw = mode.rawValue
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if sortMode == mode { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort: \(sortMode.rawValue)")
                .pointingHand()
            }

            ToolbarItem(placement: .automatic) {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.thumbnails)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 78)
                .pointingHand()
            }
        }
    }

    private var headerSubtitle: String {
        if selection == .trash {
            let n = model.trashedBoards.count
            return n == 0 ? "No deleted tissues" : "\(n) \(n == 1 ? "item" : "items") · Auto-deleted after 30 days"
        }
        let n = displayedBoards.count
        return "\(n) \(n == 1 ? "tissue" : "tissues")"
    }

    // MARK: - Boards Grid / List

    private var boardsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if displayedBoards.isEmpty {
                    emptyState
                } else if viewMode == .thumbnails {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(displayedBoards) { board in
                            thumbnailCell(board)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if sortMode == .name {
                            VStack(spacing: 4) {
                                ForEach(displayedBoards) { board in
                                    boardRow(board)
                                }
                            }
                        } else {
                            ForEach(groupedBoards) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.bottom, 2)
                                    ForEach(group.boards) { board in
                                        boardRow(board)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .focusable()
        .focused($contentFocused)
        .focusEffectDisabled()
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(_ board: BoardMeta) -> some View {
        let _ = model.thumbnailRevision
        let img = model.thumbnail(for: board.id)
        let isHovered = hoveredBoard == board.id
        let folderBadge = (selection == .all || selection == .recents) ? model.folderName(forBoardId: board.id) : nil

        return VStack(spacing: 0) {
            // Uniform 4:3 preview area — overlay guarantees identical card height for all boards
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        if let img {
                            #if os(macOS)
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                            #else
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                            #endif
                        } else {
                            BlankCanvasPreview(
                                background: model.appSettings.canvasBackground,
                                isDarkMode: isDark,
                                isWarmPaper: model.appSettings.isWarmPaper
                            )
                        }
                    }
                    .clipped()

                if board.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                // Clean overflow menu (revealed on hover on macOS, always subtly visible on iOS)
                #if os(macOS)
                let showMenuButton = isHovered
                #else
                let showMenuButton = true
                #endif

                if showMenuButton && renamingId != board.id {
                    Menu {
                        boardContextMenu(board)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 26, height: 26)
                            .liquidGlassInteractiveCapsule()
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(8)
                    .transition(.opacity)
                }
            }

            Divider().opacity(0.45)

            // Metadata footer
            VStack(alignment: .leading, spacing: 4) {
                if renamingId == board.id {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .focused($renameFocused)
                        .onSubmit { finishRename(board.id) }
                } else {
                    Text(board.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(relativeDate(board.modified))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let folderBadge {
                            folderPill(folderBadge)
                        }
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color(red: 30/255, green: 30/255, blue: 34/255) : Color.white)
                .shadow(
                    color: .black.opacity(isDark ? (isHovered ? 0.45 : 0.22) : (isHovered ? 0.16 : 0.06)),
                    radius: isHovered ? 12 : 4,
                    y: isHovered ? 5 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovered ? Color.primary.opacity(isDark ? 0.24 : 0.18) :
                    Color.primary.opacity(isDark ? 0.12 : 0.08),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture {
            openBoard(board)
        }
        .draggable(board.id)
        .onHover { hovering in
            hoveredBoard = hovering ? board.id : nil
        }
        .pointingHand()
        .contextMenu { boardContextMenu(board) }
    }

    // MARK: - List Row (with Mini Thumbnail & Folder Pill)

    private func boardRow(_ board: BoardMeta) -> some View {
        let _ = model.thumbnailRevision
        let img = model.thumbnail(for: board.id, size: CGSize(width: 120, height: 90))
        let isHovered = hoveredBoard == board.id
        let folderBadge = (selection == .all || selection == .recents) ? model.folderName(forBoardId: board.id) : nil

        return HStack(spacing: 12) {
            // Mini thumbnail (fixed 52×39 container)
            Color.clear
                .frame(width: 52, height: 39)
                .overlay {
                    if let img {
                        #if os(macOS)
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        #else
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                        #endif
                    } else {
                        BlankCanvasPreview(
                            background: model.appSettings.canvasBackground,
                            isDarkMode: isDark,
                            compact: true
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )

            if renamingId == board.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFocused)
                    .onSubmit { finishRename(board.id) }
                Button("Save") { finishRename(board.id) }
                    .liquidGlassProminentButton()
                    .controlSize(.small)
                Button("Cancel") { renamingId = nil; renameFocused = false }
                    .liquidGlassButton()
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if board.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        Text(board.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                    }
                    Text(relativeDate(board.modified))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let folderBadge {
                    folderPill(folderBadge)
                }

                #if os(macOS)
                let showRowMenu = isHovered
                #else
                let showRowMenu = true
                #endif

                if showRowMenu {
                    Menu {
                        boardContextMenu(board)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .pointingHand()
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            openBoard(board)
        }
        .draggable(board.id)
        .onHover { hovering in
            hoveredBoard = hovering ? board.id : nil
        }
        .pointingHand()
        .contextMenu { boardContextMenu(board) }
    }

    private func folderPill(_ name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9))
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.07))
        .clipShape(Capsule())
    }

    // MARK: - Recently Deleted View

    private var trashContent: some View {
        ScrollView {
            if model.trashedBoards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Trash is Empty")
                        .font(.title3.weight(.semibold))
                    Text("Deleted tissues stay here for 30 days before being permanently removed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 90)
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.trashedBoards) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(size: 14, weight: .medium))
                                Text("Deleted \(relativeDate(entry.deletedAt)) · \(daysRemainingText(since: entry.deletedAt))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Restore") {
                                if model.restoreBoard(id: entry.id) {
                                    model.loadTrash()
                                }
                            }
                            .liquidGlassButton()
                            .controlSize(.small)
                            .pointingHand()

                            Button(role: .destructive) {
                                permanentDeleteEntry = entry
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                            }
                            .liquidGlassButton()
                            .controlSize(.small)
                            .help("Delete Permanently")
                            .pointingHand()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isDark ? Color.white.opacity(0.04) : Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    private func daysRemainingText(since deletedAt: Date) -> String {
        let elapsedDays = Int(Date().timeIntervalSince(deletedAt) / (24 * 3600))
        let remaining = max(1, 30 - elapsedDays)
        return "\(remaining) \(remaining == 1 ? "day" : "days") left"
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func boardContextMenu(_ board: BoardMeta) -> some View {
        Button { openBoard(board) } label: { Label("Open", systemImage: "arrow.up.right.square") }
        Button { model.togglePinBoard(id: board.id) } label: {
            Label(board.isPinned ? "Unpin" : "Pin to Top", systemImage: board.isPinned ? "pin.slash" : "pin")
        }
        Button { startRename(board) } label: { Label("Rename", systemImage: "pencil") }
        Menu {
            Button("No Folder") { model.moveBoard(boardId: board.id, toFolder: nil) }
            if !model.folders.isEmpty { Divider() }
            ForEach(model.folders) { folder in
                Button(folder.name) { model.moveBoard(boardId: board.id, toFolder: folder.id) }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        #if os(macOS)
        Button { exportBoards([board.id]) } label: { Label("Export PNG", systemImage: "square.and.arrow.up") }
        #endif
        Divider()
        Button(role: .destructive) { trashBoards([board]) } label: { Label("Move to Trash", systemImage: "trash") }
    }

    // MARK: - Undo Toast

    private func undoToastView(_ toast: UndoTrashToast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
            Button("Undo") {
                toastDismissTask?.cancel()
                for id in toast.trashedIds {
                    model.restoreBoard(id: id)
                }
                model.loadTrash()
                undoToast = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassCapsule()
    }

    private func showUndoToast(message: String, trashedIds: [String]) {
        toastDismissTask?.cancel()
        undoToast = UndoTrashToast(message: message, trashedIds: trashedIds)
        let task = DispatchWorkItem { undoToast = nil }
        toastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: task)
    }

    // MARK: - Empty State

    private var emptyStateIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        switch selection {
        case .folder: return "folder"
        case .recents: return "clock"
        case .all, .trash: return "square.and.pencil"
        }
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty { return "No results for \"\(searchText)\"" }
        switch selection {
        case .folder: return "\(sectionTitle) is empty"
        case .recents: return "No recent tissues"
        case .all, .trash: return "Pull out your first tissue"
        }
    }

    private var emptyStateSubtitle: String {
        if !searchText.isEmpty {
            return selection == .all
                ? "Check the spelling or try a different keyword."
                : "No matches in \(sectionTitle). Try another keyword or search across All Tissues."
        }
        switch selection {
        case .folder:
            return "Create a new tissue here, or drag existing tissues from All Tissues onto \"\(sectionTitle)\" in the sidebar."
        case .recents:
            return "Tissues you open or sketch on will show up here for quick access."
        case .all, .trash:
            return "Sketch ideas quickly like on a café napkin, or open an existing .wb file."
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isDark ? 0.14 : 0.10))
                    .frame(width: 68, height: 68)
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text(emptyStateTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(emptyStateSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 10) {
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Label("Clear Search", systemImage: "xmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .liquidGlassProminentButton()
                    .pointingHand()

                    if selection != .all {
                        Button(action: { selection = .all }) {
                            Text("Search All Tissues")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .liquidGlassButton()
                        .pointingHand()
                    }
                } else {
                    Button(action: createNewBoard) {
                        Label(activeFolderId != nil ? "New Tissue Here" : "New Tissue", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                    }
                    .liquidGlassProminentButton()
                    .pointingHand()

                    if selection == .all {
                        Button(action: { model.pendingAction = .open }) {
                            Label("Open File…", systemImage: "folder")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .liquidGlassButton()
                        .pointingHand()
                    } else {
                        Button(action: { selection = .all }) {
                            Label("Browse All Tissues", systemImage: "square.grid.2x2")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .liquidGlassButton()
                        .pointingHand()
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 96)
    }

    // MARK: - Interactions

    private func createNewBoard() {
        model.createQuickBoard(folderId: activeFolderId)
        onStart()
    }

    private func openBoard(_ board: BoardMeta) {
        model.loadBoard(id: board.id)
        onStart()
    }

    private func trashBoards(_ boardsToTrash: [BoardMeta]) {
        guard !boardsToTrash.isEmpty else { return }
        let ids = boardsToTrash.map(\.id)
        for board in boardsToTrash {
            model.trashBoard(id: board.id, name: board.name)
        }
        let msg = boardsToTrash.count == 1
            ? "Moved \"\(boardsToTrash[0].name)\" to Trash"
            : "Moved \(boardsToTrash.count) tissues to Trash"
        showUndoToast(message: msg, trashedIds: ids)
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
                let safeName = name.replacingOccurrences(of: "/", with: "-")
                let file = dir.appendingPathComponent(safeName).appendingPathExtension("png")
                do {
                    try data.write(to: file, options: .atomic)
                } catch {
                    model.lastErrorMessage = "Failed to export \(name): \(error.localizedDescription)"
                }
            }
        }
    }
    #endif

    // MARK: - Computed Data

    private var recentBoards: [BoardMeta] {
        var seen = Set<String>()
        var result: [BoardMeta] = []
        for url in model.recentFiles {
            let id = url.deletingPathExtension().lastPathComponent
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            if let board = model.boards.first(where: { $0.id == id }) {
                result.append(board)
            }
            if result.count >= 12 { break }
        }
        return result
    }

    private var displayedBoards: [BoardMeta] {
        let base: [BoardMeta]
        switch selection {
        case .all:
            base = model.boards
        case .recents:
            base = recentBoards
        case .folder(let folderId):
            let ids = Set(model.boardIdsInFolder(folderId))
            base = model.boards.filter { ids.contains($0.id) }
        case .trash:
            base = []
        }

        let q = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(q) }
        switch sortMode {
        case .name:
            return filtered.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .created:
            return filtered.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.created > $1.created
            }
        case .modified:
            return filtered.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.modified > $1.modified
            }
        }
    }

    private var groupedBoards: [TimeGroup] {
        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now

        var today: [BoardMeta] = []
        var yesterday: [BoardMeta] = []
        var thisWeek: [BoardMeta] = []
        var earlier: [BoardMeta] = []

        for board in displayedBoards {
            let date = sortMode == .created ? board.created : board.modified
            if cal.isDateInToday(date) {
                today.append(board)
            } else if cal.isDateInYesterday(date) {
                yesterday.append(board)
            } else if date >= weekAgo {
                thisWeek.append(board)
            } else {
                earlier.append(board)
            }
        }

        var groups: [TimeGroup] = []
        if !today.isEmpty { groups.append(TimeGroup(id: "today", title: "Today", boards: today)) }
        if !yesterday.isEmpty { groups.append(TimeGroup(id: "yesterday", title: "Yesterday", boards: yesterday)) }
        if !thisWeek.isEmpty { groups.append(TimeGroup(id: "week", title: "Previous 7 Days", boards: thisWeek)) }
        if !earlier.isEmpty { groups.append(TimeGroup(id: "earlier", title: "Earlier", boards: earlier)) }
        return groups
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today, " + date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday, " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func startRename(_ board: BoardMeta) {
        renamingId = board.id
        renameText = board.name
        DispatchQueue.main.async { renameFocused = true }
    }

    private func finishRename(_ id: String) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { model.renameBoard(id: id, to: name) }
        renamingId = nil
        renameFocused = false
    }
}

// MARK: - Miniature Blank Canvas Preview

/// Renders a subtle miniature paper pattern (grid, dots, ruled, or plain)
/// matching the user's current canvas background & theme for empty boards.
private struct BlankCanvasPreview: View {
    let background: CanvasBackground
    let isDarkMode: Bool
    var isWarmPaper: Bool = false
    var compact: Bool = false

    var body: some View {
        Canvas { context, size in
            let bg = isDarkMode
                ? Color(red: 14/255, green: 14/255, blue: 16/255)
                : (isWarmPaper ? Color(red: 250/255, green: 245/255, blue: 235/255) : Color.white)
            let fg = isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            let spacing: CGFloat = compact ? 8 : 14
            switch background {
            case .none:
                break
            case .grid:
                var path = Path()
                var x = spacing
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y = spacing
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(fg), lineWidth: 0.5)
            case .dots:
                var path = Path()
                let r: CGFloat = compact ? 0.6 : 0.9
                var x = spacing
                while x < size.width {
                    var y = spacing
                    while y < size.height {
                        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                        y += spacing
                    }
                    x += spacing
                }
                context.fill(path, with: .color(fg))
            case .ruled:
                var path = Path()
                var y = spacing
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(fg), lineWidth: 0.5)
            }
        }
    }
}

extension View {
    func pointingHand() -> some View {
        modifier(PointingHandModifier())
    }
}

private struct PointingHandModifier: ViewModifier {
    @State private var isPushed = false

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content
                .onHover { hovering in
                    if hovering && !isPushed {
                        NSCursor.pointingHand.push()
                        isPushed = true
                    } else if !hovering && isPushed {
                        NSCursor.pop()
                        isPushed = false
                    }
                }
                .onDisappear {
                    if isPushed {
                        NSCursor.pop()
                        isPushed = false
                    }
                }
        }
        #else
        content
        #endif
    }
}
