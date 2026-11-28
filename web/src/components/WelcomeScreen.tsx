import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { BoardFolder, BoardMeta, TrashEntry } from '../types/model';
import { Icon } from './Icons';
import { ConfirmModal, PromptModal } from './Modals';

type SidebarSection =
  | { kind: 'all' }
  | { kind: 'recents' }
  | { kind: 'trash' }
  | { kind: 'folder'; id: string };

type ViewMode = 'thumbnails' | 'list';
type SortMode = 'modified' | 'created' | 'name';

interface WelcomeScreenProps {
  boards: BoardMeta[];
  folders: BoardFolder[];
  trashedBoards: TrashEntry[];
  thumbnails: Record<string, string>;
  isDarkMode: boolean;
  onToggleDarkMode: () => void;
  onCreateBoard: (folderId?: string) => void;
  onOpenBoard: (id: string) => void;
  onOpenWBFile: () => void;
  onDropWBFile: (file: File) => void;
  onRenameBoard: (id: string, name: string) => void;
  onTogglePinBoard: (id: string) => void;
  onMoveBoardToFolder: (boardId: string, folderId: string | null) => void;
  onExportBoardPNG: (id: string) => void;
  onTrashBoard: (id: string) => void;
  onRestoreTrash: (trashId: string) => void;
  onPermanentDeleteTrash: (trashId: string) => void;
  onEmptyTrash: () => void;
  onCreateFolder: (name: string) => void;
  onRenameFolder: (id: string, name: string) => void;
  onDeleteFolder: (id: string) => void;
  onShowHelp: () => void;
  onShowAbout: () => void;
}

function formatRelativeDate(ts: number): string {
  const diff = Date.now() - ts;
  if (diff < 60_000) return 'Just now';
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return new Date(ts).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

function timeGroupLabel(b: BoardMeta): string {
  if (b.isPinned) return 'Pinned';
  const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const startYesterday = startToday - 86_400_000;
  const startWeek = startToday - 7 * 86_400_000;
  if (b.modified >= startToday) return 'Today';
  if (b.modified >= startYesterday) return 'Yesterday';
  if (b.modified >= startWeek) return 'This Week';
  return 'Earlier';
}

export const WelcomeScreen: React.FC<WelcomeScreenProps> = (props) => {
  const [section, setSection] = useState<SidebarSection>({ kind: 'all' });
  const [viewMode, setViewMode] = useState<ViewMode>(
    () => (localStorage.getItem('tissuebox.viewMode') as ViewMode) || 'thumbnails'
  );
  const [sortMode, setSortMode] = useState<SortMode>(
    () => (localStorage.getItem('tissuebox.sortMode') as SortMode) || 'modified'
  );
  const [searchText, setSearchText] = useState('');
  const [showNewFolder, setShowNewFolder] = useState(false);
  const [renameFolder, setRenameFolder] = useState<BoardFolder | null>(null);
  const [renameBoard, setRenameBoard] = useState<BoardMeta | null>(null);
  const [showEmptyTrashConfirm, setShowEmptyTrashConfirm] = useState(false);
  const [permDeleteEntry, setPermDeleteEntry] = useState<TrashEntry | null>(null);
  const [openMenuBoardId, setOpenMenuBoardId] = useState<string | null>(null);
  const [draggedBoardId, setDraggedBoardId] = useState<string | null>(null);
  const [dropTargetKey, setDropTargetKey] = useState<string | null>(null);
  const [undoToast, setUndoToast] = useState<{ name: string; trashId: string } | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(false);

  const searchRef = useRef<HTMLInputElement>(null);
  const toastTimerRef = useRef<number | null>(null);

  useEffect(() => {
    localStorage.setItem('tissuebox.viewMode', viewMode);
  }, [viewMode]);

  useEffect(() => {
    localStorage.setItem('tissuebox.sortMode', sortMode);
  }, [sortMode]);

  // Welcome keyboard shortcuts (Ctrl/Cmd+N, Ctrl/Cmd+F, Esc)
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === 'n') {
        e.preventDefault();
        props.onCreateBoard(section.kind === 'folder' ? section.id : undefined);
      } else if (mod && e.key.toLowerCase() === 'f') {
        e.preventDefault();
        searchRef.current?.focus();
      } else if (mod && e.key.toLowerCase() === 'o') {
        e.preventDefault();
        props.onOpenWBFile();
      } else if (e.key === 'Escape') {
        if (openMenuBoardId) setOpenMenuBoardId(null);
        else if (searchText) setSearchText('');
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [section, openMenuBoardId, searchText]);

  const recentBoards = useMemo(() => {
    const cutoff = Date.now() - 7 * 86_400_000;
    return props.boards.filter((b) => b.modified >= cutoff);
  }, [props.boards]);

  const filteredBoards = useMemo(() => {
    let list = props.boards;
    if (section.kind === 'recents') {
      list = recentBoards;
    } else if (section.kind === 'folder') {
      const folder = props.folders.find((f) => f.id === section.id);
      const idSet = new Set(folder?.boardIds ?? []);
      list = list.filter((b) => idSet.has(b.id));
    }

    const q = searchText.trim().toLowerCase();
    if (q) {
      list = list.filter((b) => b.name.toLowerCase().includes(q));
    }

    return [...list].sort((a, b) => {
      if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
      if (sortMode === 'name') return a.name.localeCompare(b.name);
      if (sortMode === 'created') return b.created - a.created;
      return b.modified - a.modified;
    });
  }, [props.boards, props.folders, recentBoards, section, searchText, sortMode]);

  const timeGroups = useMemo(() => {
    const order = ['Pinned', 'Today', 'Yesterday', 'This Week', 'Earlier'];
    const map = new Map<string, BoardMeta[]>();
    for (const b of filteredBoards) {
      const g = timeGroupLabel(b);
      const arr = map.get(g) ?? [];
      arr.push(b);
      map.set(g, arr);
    }
    return order.filter((k) => map.has(k)).map((k) => ({ title: k, boards: map.get(k)! }));
  }, [filteredBoards]);

  const sectionTitle =
    section.kind === 'all'
      ? 'All Tissues'
      : section.kind === 'recents'
      ? 'Recents'
      : section.kind === 'trash'
      ? 'Recently Deleted'
      : props.folders.find((f) => f.id === section.id)?.name ?? 'Folder';

  const countLabel =
    section.kind === 'trash'
      ? `${props.trashedBoards.length} ${props.trashedBoards.length === 1 ? 'item' : 'items'} · Kept 30 days`
      : `${filteredBoards.length} ${filteredBoards.length === 1 ? 'tissue' : 'tissues'}`;

  const handleTrashWithToast = (board: BoardMeta) => {
    setOpenMenuBoardId(null);
    props.onTrashBoard(board.id);
    setUndoToast({ name: board.name, trashId: board.id });
    if (toastTimerRef.current !== null) window.clearTimeout(toastTimerRef.current);
    toastTimerRef.current = window.setTimeout(() => setUndoToast(null), 5000);
  };

  return (
    <div
      className="welcome-shell"
      onClick={() => setOpenMenuBoardId(null)}
      onDragOver={(e) => {
        if (Array.from(e.dataTransfer.types).includes('Files')) e.preventDefault();
      }}
      onDrop={(e) => {
        const wb = Array.from(e.dataTransfer.files).find((f) => f.name.toLowerCase().endsWith('.wb'));
        if (wb) {
          e.preventDefault();
          props.onDropWBFile(wb);
        }
      }}
    >
      {/* Sidebar */}
      <aside className={`welcome-sidebar ${sidebarOpen ? 'open' : ''}`}>
        <div className="sidebar-brand">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="Tissue Box" className="sidebar-logo" />
          <span className="sidebar-title">Tissue Box</span>
        </div>

        <div className="sidebar-scroll">
          <div className="sidebar-section-label">Library</div>
          <button
            type="button"
            className={`sidebar-row ${section.kind === 'all' ? 'active' : ''} ${
              dropTargetKey === 'all' ? 'drop-target' : ''
            }`}
            onClick={() => {
              setSection({ kind: 'all' });
              setSidebarOpen(false);
            }}
            onDragOver={(e) => {
              if (draggedBoardId) {
                e.preventDefault();
                setDropTargetKey('all');
              }
            }}
            onDragLeave={() => setDropTargetKey(null)}
            onDrop={() => {
              if (draggedBoardId) props.onMoveBoardToFolder(draggedBoardId, null);
              setDraggedBoardId(null);
              setDropTargetKey(null);
            }}
          >
            <Icon name="thumbnails" size={15} />
            <span className="sidebar-row-label">All Tissues</span>
            <span className="sidebar-count">{props.boards.length}</span>
          </button>

          <button
            type="button"
            className={`sidebar-row ${section.kind === 'recents' ? 'active' : ''}`}
            onClick={() => {
              setSection({ kind: 'recents' });
              setSidebarOpen(false);
            }}
          >
            <Icon name="clock" size={15} />
            <span className="sidebar-row-label">Recents</span>
            <span className="sidebar-count">{recentBoards.length}</span>
          </button>

          <button
            type="button"
            className={`sidebar-row ${section.kind === 'trash' ? 'active' : ''}`}
            onClick={() => {
              setSection({ kind: 'trash' });
              setSidebarOpen(false);
            }}
          >
            <Icon name="trash" size={15} />
            <span className="sidebar-row-label">Recently Deleted</span>
            <span className="sidebar-count">{props.trashedBoards.length}</span>
          </button>

          <div className="sidebar-folders-header">
            <span className="sidebar-section-label">Folders</span>
            <button
              type="button"
              className="mini-icon-btn"
              title="New Folder"
              onClick={() => setShowNewFolder(true)}
            >
              <Icon name="plus" size={13} />
            </button>
          </div>

          {props.folders.length === 0 ? (
            <div className="sidebar-empty-folders">No folders yet</div>
          ) : (
            props.folders.map((folder) => {
              const active = section.kind === 'folder' && section.id === folder.id;
              return (
                <div
                  key={folder.id}
                  className={`sidebar-row folder-row ${active ? 'active' : ''} ${
                    dropTargetKey === folder.id ? 'drop-target' : ''
                  }`}
                  onClick={() => {
                    setSection({ kind: 'folder', id: folder.id });
                    setSidebarOpen(false);
                  }}
                  onDragOver={(e) => {
                    if (draggedBoardId) {
                      e.preventDefault();
                      setDropTargetKey(folder.id);
                    }
                  }}
                  onDragLeave={() => setDropTargetKey(null)}
                  onDrop={() => {
                    if (draggedBoardId) props.onMoveBoardToFolder(draggedBoardId, folder.id);
                    setDraggedBoardId(null);
                    setDropTargetKey(null);
                  }}
                >
                  <Icon name="folder" size={15} className="folder-icon" />
                  <span className="sidebar-row-label">{folder.name}</span>
                  <span className="sidebar-count">{folder.boardIds.length}</span>
                  <div className="folder-hover-actions" onClick={(e) => e.stopPropagation()}>
                    <button
                      type="button"
                      className="row-icon-btn"
                      title="Rename Folder"
                      onClick={() => setRenameFolder(folder)}
                    >
                      <Icon name="rename" size={12} />
                    </button>
                    <button
                      type="button"
                      className="row-icon-btn destructive"
                      title="Delete Folder"
                      onClick={() => {
                        if (active) setSection({ kind: 'all' });
                        props.onDeleteFolder(folder.id);
                      }}
                    >
                      <Icon name="trash" size={12} />
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>

        <div className="sidebar-footer">
          <button type="button" className="sidebar-footer-btn" onClick={props.onShowHelp}>
            <Icon name="help" size={15} />
            <span>Help</span>
          </button>
          <button type="button" className="sidebar-footer-btn" onClick={props.onShowAbout}>
            <Icon name="about" size={15} />
            <span>About</span>
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="welcome-main">
        <header className="welcome-titlebar">
          <div className="titlebar-left">
            <button
              type="button"
              className="mini-icon-btn mobile-menu-btn"
              title="Toggle Sidebar"
              onClick={() => setSidebarOpen((v) => !v)}
            >
              <Icon name="list" size={16} />
            </button>
            <div>
              <h1 className="welcome-heading">{sectionTitle}</h1>
              <div className="welcome-subtitle">{countLabel}</div>
            </div>
          </div>

          <div className="titlebar-actions">
            {section.kind !== 'trash' ? (
              <>
                <div className="search-field">
                  <Icon name="search" size={14} className="muted-icon" />
                  <input
                    ref={searchRef}
                    type="search"
                    placeholder="Search"
                    value={searchText}
                    onChange={(e) => setSearchText(e.target.value)}
                  />
                </div>
                <button
                  type="button"
                  className="primary-pill-btn"
                  title="New Tissue (Ctrl/⌘N)"
                  onClick={() => props.onCreateBoard(section.kind === 'folder' ? section.id : undefined)}
                >
                  <Icon name="plus" size={14} />
                  <span>New Tissue</span>
                </button>
                <button
                  type="button"
                  className="titlebar-icon-btn"
                  title="Open .wb File (Ctrl/⌘O)"
                  onClick={props.onOpenWBFile}
                >
                  <Icon name="openFile" size={16} />
                </button>
                <select
                  className="sort-select"
                  value={sortMode}
                  aria-label="Sort tissues"
                  onChange={(e) => setSortMode(e.target.value as SortMode)}
                >
                  <option value="modified">Date Modified</option>
                  <option value="created">Date Created</option>
                  <option value="name">Name</option>
                </select>
                <button
                  type="button"
                  className="titlebar-icon-btn"
                  title={viewMode === 'thumbnails' ? 'Switch to List View' : 'Switch to Grid View'}
                  onClick={() => setViewMode((v) => (v === 'thumbnails' ? 'list' : 'thumbnails'))}
                >
                  <Icon name={viewMode === 'thumbnails' ? 'list' : 'thumbnails'} size={16} />
                </button>
              </>
            ) : (
              props.trashedBoards.length > 0 && (
                <button
                  type="button"
                  className="danger-pill-btn"
                  onClick={() => setShowEmptyTrashConfirm(true)}
                >
                  <Icon name="trash" size={14} />
                  <span>Empty Trash</span>
                </button>
              )
            )}
            <button
              type="button"
              className="titlebar-icon-btn"
              title={props.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
              onClick={props.onToggleDarkMode}
            >
              <Icon name={props.isDarkMode ? 'sun' : 'moon'} size={16} />
            </button>
          </div>
        </header>

        <div className="welcome-content">
          {section.kind === 'trash' ? (
            props.trashedBoards.length === 0 ? (
              <div className="welcome-empty">
                <Icon name="trash" size={38} className="muted-icon" />
                <h2>Recently Deleted is Empty</h2>
                <p>Deleted tissues stay here for 30 days before permanent removal.</p>
              </div>
            ) : (
              <div className="trash-list">
                {props.trashedBoards.map((entry) => {
                  const daysLeft = Math.max(
                    1,
                    Math.ceil((entry.deletedAt + 30 * 86_400_000 - Date.now()) / 86_400_000)
                  );
                  return (
                    <div key={entry.id} className="trash-row">
                      <div className="trash-meta">
                        <div className="trash-name">{entry.name}</div>
                        <div className="trash-sub">
                          Deleted {formatRelativeDate(entry.deletedAt)} · {daysLeft}d remaining
                        </div>
                      </div>
                      <div className="trash-actions">
                        <button
                          type="button"
                          className="accent-chip-btn"
                          onClick={() => props.onRestoreTrash(entry.id)}
                        >
                          <Icon name="restore" size={13} />
                          <span>Restore</span>
                        </button>
                        <button
                          type="button"
                          className="row-icon-btn destructive"
                          title="Delete Permanently"
                          onClick={() => setPermDeleteEntry(entry)}
                        >
                          <Icon name="trash" size={15} />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )
          ) : filteredBoards.length === 0 ? (
            <div className="welcome-empty">
              <img src={`${import.meta.env.BASE_URL}logo.png`} alt="" className="empty-logo" />
              <h2>{searchText ? 'No Matching Tissues' : 'Start Your First Tissue'}</h2>
              <p>
                {searchText
                  ? `No tissues match "${searchText}".`
                  : 'Sketch ideas like on a café napkin, or drop any .wb file here.'}
              </p>
              <div className="empty-actions">
                {searchText ? (
                  <button type="button" className="secondary-pill-btn" onClick={() => setSearchText('')}>
                    Clear Search
                  </button>
                ) : (
                  <>
                    <button
                      type="button"
                      className="primary-pill-btn"
                      onClick={() =>
                        props.onCreateBoard(section.kind === 'folder' ? section.id : undefined)
                      }
                    >
                      <Icon name="plus" size={14} />
                      <span>New Tissue</span>
                    </button>
                    <button type="button" className="secondary-pill-btn" onClick={props.onOpenWBFile}>
                      <Icon name="openFile" size={14} />
                      <span>Open .wb File</span>
                    </button>
                  </>
                )}
              </div>
            </div>
          ) : viewMode === 'thumbnails' ? (
            <div className="boards-grid">
              {filteredBoards.map((board) => (
                <div
                  key={board.id}
                  className="board-card"
                  draggable
                  onDragStart={() => setDraggedBoardId(board.id)}
                  onDragEnd={() => {
                    setDraggedBoardId(null);
                    setDropTargetKey(null);
                  }}
                  onClick={() => props.onOpenBoard(board.id)}
                >
                  <div className="board-thumb-box">
                    {props.thumbnails[board.id] ? (
                      <img src={props.thumbnails[board.id]} alt={board.name} />
                    ) : (
                      <div className="blank-napkin-preview" />
                    )}
                    {board.isPinned && (
                      <span className="card-pin-badge" title="Pinned">
                        <Icon name="pin" size={11} />
                      </span>
                    )}
                    <button
                      type="button"
                      className="card-menu-trigger"
                      title="Tissue Actions"
                      onClick={(e) => {
                        e.stopPropagation();
                        setOpenMenuBoardId(openMenuBoardId === board.id ? null : board.id);
                      }}
                    >
                      <Icon name="more" size={15} />
                    </button>
                  </div>

                  <div className="board-card-footer">
                    <div className="board-card-name">{board.name}</div>
                    <div className="board-card-date">{formatRelativeDate(board.modified)}</div>
                  </div>

                  {openMenuBoardId === board.id && (
                    <div
                      className="glass-surface card-dropdown"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <button type="button" onClick={() => props.onOpenBoard(board.id)}>
                        <Icon name="externalLink" size={14} /> Open
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          props.onTogglePinBoard(board.id);
                          setOpenMenuBoardId(null);
                        }}
                      >
                        <Icon name={board.isPinned ? 'pinSlash' : 'pin'} size={14} />
                        {board.isPinned ? 'Unpin' : 'Pin to Top'}
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setRenameBoard(board);
                          setOpenMenuBoardId(null);
                        }}
                      >
                        <Icon name="rename" size={14} /> Rename
                      </button>
                      {props.folders.length > 0 && (
                        <div className="dropdown-sub">
                          <span className="dropdown-sub-label">Move to Folder</span>
                          <button
                            type="button"
                            onClick={() => {
                              props.onMoveBoardToFolder(board.id, null);
                              setOpenMenuBoardId(null);
                            }}
                          >
                            All Tissues
                          </button>
                          {props.folders.map((f) => (
                            <button
                              key={f.id}
                              type="button"
                              onClick={() => {
                                props.onMoveBoardToFolder(board.id, f.id);
                                setOpenMenuBoardId(null);
                              }}
                            >
                              {f.name}
                            </button>
                          ))}
                        </div>
                      )}
                      <button
                        type="button"
                        onClick={() => {
                          props.onExportBoardPNG(board.id);
                          setOpenMenuBoardId(null);
                        }}
                      >
                        <Icon name="exportPNG" size={14} /> Export PNG
                      </button>
                      <button
                        type="button"
                        className="destructive"
                        onClick={() => handleTrashWithToast(board)}
                      >
                        <Icon name="trash" size={14} /> Move to Trash
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="boards-list-groups">
              {timeGroups.map((group) => (
                <div key={group.title} className="time-group">
                  <div className="time-group-header">{group.title}</div>
                  {group.boards.map((board) => (
                    <div
                      key={board.id}
                      className="board-list-row"
                      draggable
                      onDragStart={() => setDraggedBoardId(board.id)}
                      onDragEnd={() => {
                        setDraggedBoardId(null);
                        setDropTargetKey(null);
                      }}
                      onClick={() => props.onOpenBoard(board.id)}
                    >
                      <div className="list-mini-thumb">
                        {props.thumbnails[board.id] ? (
                          <img src={props.thumbnails[board.id]} alt="" />
                        ) : (
                          <div className="blank-napkin-preview" />
                        )}
                      </div>
                      <div className="list-board-info">
                        <div className="board-card-name">
                          {board.isPinned && <Icon name="pin" size={12} className="inline-pin" />}
                          {board.name}
                        </div>
                        <div className="board-card-date">{formatRelativeDate(board.modified)}</div>
                      </div>
                      <div className="list-board-actions" onClick={(e) => e.stopPropagation()}>
                        <button
                          type="button"
                          className="row-icon-btn"
                          title={board.isPinned ? 'Unpin' : 'Pin'}
                          onClick={() => props.onTogglePinBoard(board.id)}
                        >
                          <Icon name={board.isPinned ? 'pinSlash' : 'pin'} size={14} />
                        </button>
                        <button
                          type="button"
                          className="row-icon-btn"
                          title="Rename"
                          onClick={() => setRenameBoard(board)}
                        >
                          <Icon name="rename" size={14} />
                        </button>
                        <button
                          type="button"
                          className="row-icon-btn destructive"
                          title="Move to Trash"
                          onClick={() => handleTrashWithToast(board)}
                        >
                          <Icon name="trash" size={14} />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          )}
        </div>

        {undoToast && (
          <div className="glass-capsule undo-toast">
            <span>Moved “{undoToast.name}” to Trash</span>
            <button
              type="button"
              className="accent-chip-btn"
              onClick={() => {
                props.onRestoreTrash(undoToast.trashId);
                setUndoToast(null);
              }}
            >
              Undo
            </button>
          </div>
        )}
      </main>

      {showNewFolder && (
        <PromptModal
          title="New Folder"
          placeholder="Folder name"
          initialValue=""
          submitLabel="Create"
          onSubmit={(name) => {
            props.onCreateFolder(name);
            setShowNewFolder(false);
          }}
          onCancel={() => setShowNewFolder(false)}
        />
      )}

      {renameFolder && (
        <PromptModal
          title="Rename Folder"
          placeholder="Folder name"
          initialValue={renameFolder.name}
          submitLabel="Rename"
          onSubmit={(name) => {
            props.onRenameFolder(renameFolder.id, name);
            setRenameFolder(null);
          }}
          onCancel={() => setRenameFolder(null)}
        />
      )}

      {renameBoard && (
        <PromptModal
          title="Rename Tissue"
          placeholder="Tissue name"
          initialValue={renameBoard.name}
          submitLabel="Rename"
          onSubmit={(name) => {
            props.onRenameBoard(renameBoard.id, name);
            setRenameBoard(null);
          }}
          onCancel={() => setRenameBoard(null)}
        />
      )}

      {showEmptyTrashConfirm && (
        <ConfirmModal
          title="Empty Trash?"
          message={`All ${props.trashedBoards.length} deleted tissues will be permanently removed. This cannot be undone.`}
          confirmLabel="Empty Trash"
          onConfirm={() => {
            props.onEmptyTrash();
            setShowEmptyTrashConfirm(false);
          }}
          onCancel={() => setShowEmptyTrashConfirm(false)}
        />
      )}

      {permDeleteEntry && (
        <ConfirmModal
          title="Delete Permanently?"
          message={`"${permDeleteEntry.name}" will be permanently deleted. This cannot be undone.`}
          confirmLabel="Delete Permanently"
          onConfirm={() => {
            props.onPermanentDeleteTrash(permDeleteEntry.id);
            setPermDeleteEntry(null);
          }}
          onCancel={() => setPermDeleteEntry(null)}
        />
      )}
    </div>
  );
};
