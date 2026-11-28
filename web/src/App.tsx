import React, { useCallback, useEffect, useRef, useState } from 'react';
import { CanvasStage } from './components/CanvasStage';
import { Icon } from './components/Icons';
import { AboutModal, ConfirmModal, HelpModal, PromptModal } from './components/Modals';
import { ScenesPopover } from './components/ScenesPopover';
import { QuickSelectionMenu, SelectionPill } from './components/SelectionPill';
import { Toolbar } from './components/Toolbar';
import { ToolSettingsPill } from './components/ToolSettingsPill';
import { WelcomeScreen } from './components/WelcomeScreen';
import { downloadBlob, exportCanvasPDFBytes, exportScenesPDFBytes } from './engine/pdfExport';
import { renderBoardThumbnailDataUrl, renderPNGBlob } from './engine/renderer';
import { decodeWBJson, encodeWBJson } from './engine/wbCodec';
import { boardStore } from './store/boardStore';
import { drawingStore, useDrawingState } from './store/drawingStore';
import {
  generateId,
  type BoardFolder,
  type BoardMeta,
  type SaveData,
  type Tool,
  type TrashEntry,
} from './types/model';

export const App: React.FC = () => {
  const state = useDrawingState();

  // Library state
  const [showWelcome, setShowWelcome] = useState(true);
  const [boards, setBoards] = useState<BoardMeta[]>([]);
  const [folders, setFolders] = useState<BoardFolder[]>([]);
  const [trashedBoards, setTrashedBoards] = useState<TrashEntry[]>([]);
  const [currentBoardId, setCurrentBoardId] = useState<string | null>(null);
  const [thumbnails, setThumbnails] = useState<Record<string, string>>({});

  // Canvas overlay & modal state
  const [settingsTool, setSettingsTool] = useState<Tool | null>(null);
  const [showScenes, setShowScenes] = useState(false);
  const [showMore, setShowMore] = useState(false);
  const [isCustomizing, setIsCustomizing] = useState(false);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [showRenameTissue, setShowRenameTissue] = useState(false);
  const [showHelp, setShowHelp] = useState(false);
  const [showAbout, setShowAbout] = useState(false);
  const [showZoomPill, setShowZoomPill] = useState(false);

  const zoomHideTimer = useRef<number | null>(null);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const wbInputRef = useRef<HTMLInputElement>(null);
  const currentBoardIdRef = useRef<string | null>(null);
  currentBoardIdRef.current = currentBoardId;

  const boardsRef = useRef(boards);
  boardsRef.current = boards;
  const foldersRef = useRef(folders);
  foldersRef.current = folders;

  const currentBoardName =
    boards.find((b) => b.id === currentBoardId)?.name ?? 'Tissue';

  // Sync document title
  useEffect(() => {
    document.title = showWelcome ? 'Tissue Box' : `Tissue | ${currentBoardName}`;
  }, [showWelcome, currentBoardName]);

  // Initial library load from IndexedDB
  useEffect(() => {
    (async () => {
      const idx = await boardStore.loadIndex();
      setBoards(idx.boards);
      setFolders(idx.folders);
      const trash = await boardStore.loadTrash();
      setTrashedBoards(trash);
    })();
  }, []);

  // Load/generate thumbnails whenever welcome screen or theme changes
  useEffect(() => {
    if (!showWelcome || boards.length === 0) return;
    let cancelled = false;
    (async () => {
      const next: Record<string, string> = {};
      for (const b of boards) {
        const cached = await boardStore.loadThumbnail(b.id, state.appSettings.isDarkMode);
        if (cached) {
          next[b.id] = cached;
          continue;
        }
        const data = await boardStore.loadBoard(b.id);
        if (!data) continue;
        const url = await renderBoardThumbnailDataUrl({
          strokes: data.strokes,
          placedImages: data.placedImages,
          fills: data.fills,
          shapes: data.shapes ?? [],
          textLabels: data.textLabels ?? [],
          penPresets: drawingStore.penPresets,
          sharpiePresets: drawingStore.sharpiePresets,
          fillPresets: drawingStore.fillPresets,
          shapePresets: drawingStore.shapePresets,
          textPresets: drawingStore.textPresets,
          isDarkMode: state.appSettings.isDarkMode,
          isWarmPaper: state.appSettings.isWarmPaper,
        });
        if (url) {
          await boardStore.saveThumbnail(b.id, state.appSettings.isDarkMode, url);
          next[b.id] = url;
        }
      }
      if (!cancelled) setThumbnails(next);
    })();
    return () => {
      cancelled = true;
    };
  }, [showWelcome, boards, state.appSettings.isDarkMode, state.appSettings.isWarmPaper]);

  // Persist index helper
  const persistIndex = useCallback(async (nextBoards: BoardMeta[], nextFolders: BoardFolder[]) => {
    setBoards(nextBoards);
    setFolders(nextFolders);
    await boardStore.saveIndex({ boards: nextBoards, folders: nextFolders });
  }, []);

  // Wire auto-save hook to IndexedDB
  useEffect(() => {
    drawingStore.setAutoSaveHook((data: SaveData) => {
      const id = currentBoardIdRef.current;
      if (!id) return;
      const now = Date.now();
      boardStore.saveBoard(id, data).then(() => boardStore.invalidateThumbnails(id));
      const updated = boardsRef.current
        .map((b) => (b.id === id ? { ...b, modified: now } : b))
        .sort((a, b) => b.modified - a.modified);
      persistIndex(updated, foldersRef.current);
    });
    return () => drawingStore.setAutoSaveHook(null);
  }, [persistIndex]);

  // Flush auto-save before tab unload
  useEffect(() => {
    const onBeforeUnload = () => drawingStore.flushAutoSave();
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, []);

  // Transient Zoom Indicator Pill
  useEffect(() => {
    if (showWelcome) return;
    setShowZoomPill(true);
    if (zoomHideTimer.current !== null) window.clearTimeout(zoomHideTimer.current);
    zoomHideTimer.current = window.setTimeout(() => setShowZoomPill(false), 2000);
    return () => {
      if (zoomHideTimer.current !== null) window.clearTimeout(zoomHideTimer.current);
    };
  }, [state.zoomDisplayScale, showWelcome]);

  // MARK: - Board CRUD

  const createBoard = async (folderId?: string, initialData?: SaveData, customName?: string) => {
    const now = Date.now();
    const id = generateId();
    const defaultName =
      customName?.trim() ||
      `Tissue ${boardsRef.current.length + 1}`;
    const meta: BoardMeta = { id, name: defaultName, created: now, modified: now, isPinned: false };
    const defaultScene = {
      id: generateId(),
      name: 'Scene 1',
      centerX: 0,
      centerY: 0,
      scale: 1,
    };
    const saveData: SaveData = initialData ?? {
      strokes: [],
      placedImages: [],
      fills: [],
      shapes: [],
      textLabels: [],
      scenes: [defaultScene],
    };

    await boardStore.saveBoard(id, saveData);
    const nextBoards = [meta, ...boardsRef.current];
    const nextFolders = folderId
      ? foldersRef.current.map((f) =>
          f.id === folderId ? { ...f, boardIds: [id, ...f.boardIds] } : f
        )
      : foldersRef.current;
    await persistIndex(nextBoards, nextFolders);

    setCurrentBoardId(id);
    drawingStore.loadSaveData(saveData);
    if (!initialData) {
      drawingStore.requestDefaultSceneCapture();
    }
    setShowWelcome(false);
    setSettingsTool(null);
    setShowScenes(false);
    setShowMore(false);
    setIsCustomizing(false);
  };

  const openBoard = async (id: string) => {
    const data = (await boardStore.loadBoard(id)) ?? {
      strokes: [],
      placedImages: [],
      fills: [],
      scenes: [],
    };
    setCurrentBoardId(id);
    drawingStore.loadSaveData(data);
    setShowWelcome(false);
    setSettingsTool(null);
    setShowScenes(false);
    setShowMore(false);
    setIsCustomizing(false);
    drawingStore.requestRecenter();
  };

  const closeBoard = () => {
    drawingStore.flushAutoSave();
    setShowWelcome(true);
    setSettingsTool(null);
    setShowScenes(false);
    setShowMore(false);
    setIsCustomizing(false);
  };

  const renameBoard = async (id: string, name: string) => {
    const next = boardsRef.current.map((b) => (b.id === id ? { ...b, name } : b));
    await persistIndex(next, foldersRef.current);
  };

  const togglePinBoard = async (id: string) => {
    const next = boardsRef.current.map((b) =>
      b.id === id ? { ...b, isPinned: !b.isPinned } : b
    );
    await persistIndex(next, foldersRef.current);
  };

  const moveBoardToFolder = async (boardId: string, folderId: string | null) => {
    const nextFolders = foldersRef.current.map((f) => {
      const cleaned = f.boardIds.filter((id) => id !== boardId);
      if (folderId && f.id === folderId) return { ...f, boardIds: [boardId, ...cleaned] };
      return { ...f, boardIds: cleaned };
    });
    await persistIndex(boardsRef.current, nextFolders);
  };

  const trashBoard = async (id: string) => {
    const target = boardsRef.current.find((b) => b.id === id);
    if (!target) return;
    const updatedTrash = await boardStore.trashBoard(id, target.name);
    setTrashedBoards(updatedTrash);
    const nextBoards = boardsRef.current.filter((b) => b.id !== id);
    const nextFolders = foldersRef.current.map((f) => ({
      ...f,
      boardIds: f.boardIds.filter((bid) => bid !== id),
    }));
    await persistIndex(nextBoards, nextFolders);
    if (currentBoardId === id) {
      setCurrentBoardId(null);
      setShowWelcome(true);
    }
  };

  const restoreTrash = async (trashId: string) => {
    const newId = generateId();
    const res = await boardStore.restoreBoard(trashId, newId);
    if (!res) return;
    setTrashedBoards(res.remaining);
    const now = Date.now();
    const meta: BoardMeta = { id: newId, name: res.name, created: now, modified: now, isPinned: false };
    await persistIndex([meta, ...boardsRef.current], foldersRef.current);
  };

  const permDeleteTrash = async (trashId: string) => {
    const remaining = await boardStore.permanentlyDeleteTrash(trashId);
    setTrashedBoards(remaining);
  };

  const emptyTrash = async () => {
    const remaining = await boardStore.emptyTrash();
    setTrashedBoards(remaining);
  };

  const createFolder = async (name: string) => {
    const folder: BoardFolder = { id: generateId(), name, boardIds: [] };
    await persistIndex(boardsRef.current, [...foldersRef.current, folder]);
  };

  const renameFolder = async (id: string, name: string) => {
    const next = foldersRef.current.map((f) => (f.id === id ? { ...f, name } : f));
    await persistIndex(boardsRef.current, next);
  };

  const deleteFolder = async (id: string) => {
    const next = foldersRef.current.filter((f) => f.id !== id);
    await persistIndex(boardsRef.current, next);
  };

  // MARK: - Import / Export (.wb, PNG, Vector PDF, Scenes PDF)

  const handleImportWBFile = async (file: File) => {
    try {
      const text = await file.text();
      const decoded = decodeWBJson(text);
      const baseName = file.name.replace(/\.wb$/i, '');
      await createBoard(undefined, decoded, baseName);
    } catch {
      drawingStore.setError('Could not read .wb file. Ensure it is a valid Tissue Box JSON export.');
    }
  };

  const handleExportWB = () => {
    const json = encodeWBJson(drawingStore.exportSaveData());
    downloadBlob(new Blob([json], { type: 'application/json' }), `${currentBoardName}.wb`);
  };

  const handleExportPNG = async (overrideBoardId?: string) => {
    const data = overrideBoardId
      ? await boardStore.loadBoard(overrideBoardId)
      : drawingStore.exportSaveData();
    const name = overrideBoardId
      ? boardsRef.current.find((b) => b.id === overrideBoardId)?.name ?? 'Tissue'
      : currentBoardName;
    if (!data) return;
    const blob = await renderPNGBlob({
      strokes: data.strokes,
      placedImages: data.placedImages,
      fills: data.fills,
      shapes: data.shapes ?? [],
      textLabels: data.textLabels ?? [],
      penPresets: drawingStore.penPresets,
      sharpiePresets: drawingStore.sharpiePresets,
      fillPresets: drawingStore.fillPresets,
      shapePresets: drawingStore.shapePresets,
      textPresets: drawingStore.textPresets,
      isDarkMode: state.appSettings.isDarkMode,
    });
    if (!blob) {
      drawingStore.setError('Nothing on this tissue to export.');
      return;
    }
    downloadBlob(blob, `${name}.png`);
  };

  const handleExportPDF = async () => {
    const data = drawingStore.exportSaveData();
    const bytes = await exportCanvasPDFBytes({
      strokes: data.strokes,
      placedImages: data.placedImages,
      fills: data.fills,
      shapes: data.shapes ?? [],
      textLabels: data.textLabels ?? [],
      penPresets: drawingStore.penPresets,
      sharpiePresets: drawingStore.sharpiePresets,
      fillPresets: drawingStore.fillPresets,
      shapePresets: drawingStore.shapePresets,
      textPresets: drawingStore.textPresets,
      isDarkMode: state.appSettings.isDarkMode,
      isWarmPaper: state.appSettings.isWarmPaper,
    });
    if (!bytes) {
      drawingStore.setError('Nothing on this tissue to export.');
      return;
    }
    downloadBlob(new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' }), `${currentBoardName}.pdf`);
  };

  const handleExportScenesPDF = async () => {
    const data = drawingStore.exportSaveData();
    const bytes = await exportScenesPDFBytes({
      scenes: data.scenes,
      strokes: data.strokes,
      placedImages: data.placedImages,
      fills: data.fills,
      shapes: data.shapes ?? [],
      textLabels: data.textLabels ?? [],
      penPresets: drawingStore.penPresets,
      sharpiePresets: drawingStore.sharpiePresets,
      fillPresets: drawingStore.fillPresets,
      shapePresets: drawingStore.shapePresets,
      textPresets: drawingStore.textPresets,
      isDarkMode: state.appSettings.isDarkMode,
      isWarmPaper: state.appSettings.isWarmPaper,
    });
    if (!bytes) {
      drawingStore.setError('Add at least one scene to export a slide deck PDF.');
      return;
    }
    downloadBlob(new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' }), `${currentBoardName}-Scenes.pdf`);
  };

  // System clipboard image paste (canvas mode only)
  useEffect(() => {
    if (showWelcome) return;
    const onPaste = async (e: ClipboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      const items = Array.from(e.clipboardData?.items ?? []);
      const imgItem = items.find((it) => it.type.startsWith('image/'));
      if (imgItem) {
        const blob = imgItem.getAsFile();
        if (blob) {
          e.preventDefault();
          await drawingStore.addImageFromBlob(blob);
          return;
        }
      }
      if (drawingStore.pasteInternal()) {
        e.preventDefault();
      }
    };
    window.addEventListener('paste', onPaste);
    return () => window.removeEventListener('paste', onPaste);
  }, [showWelcome]);

  // Canvas keyboard shortcuts
  useEffect(() => {
    if (showWelcome || showHelp || showAbout || showClearConfirm || showRenameTissue) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      const mod = e.metaKey || e.ctrlKey;
      const key = e.key.toLowerCase();

      if (mod && !e.altKey) {
        if (key === 'z') {
          e.preventDefault();
          if (e.shiftKey) drawingStore.redo();
          else drawingStore.undo();
          return;
        }
        if (key === 's') {
          e.preventDefault();
          handleExportWB();
          return;
        }
        if (key === 'o') {
          e.preventDefault();
          wbInputRef.current?.click();
          return;
        }
        if (key === 'w') {
          e.preventDefault();
          closeBoard();
          return;
        }
        if (key === 'c') {
          if (drawingStore.hasSelection) {
            e.preventDefault();
            drawingStore.copySelected();
          }
          return;
        }
        if (key === 'i') {
          e.preventDefault();
          imageInputRef.current?.click();
          return;
        }
        if (key === '=' || key === '+') {
          if (state.selectedImageIds.length > 0) {
            e.preventDefault();
            drawingStore.resizeSelectedImages(1.25);
          }
          return;
        }
        if (key === '-') {
          if (state.selectedImageIds.length > 0) {
            e.preventDefault();
            drawingStore.resizeSelectedImages(0.8);
          }
          return;
        }
        return;
      }

      if (!mod && !e.altKey) {
        if (e.key === 'Escape') {
          if (isCustomizing) {
            setIsCustomizing(false);
            return;
          }
          if (showScenes) {
            setShowScenes(false);
            return;
          }
          if (showMore) {
            setShowMore(false);
            return;
          }
          if (
            state.currentTool === 'select' &&
            (drawingStore.hasAnySelectionOrLasso || state.showQuickMenu)
          ) {
            e.preventDefault();
            drawingStore.clearLassoSelection();
            return;
          }
          if (state.showQuickMenu) {
            drawingStore.setQuickMenu(false);
            return;
          }
        }
        if (e.key === 'Tab') {
          e.preventDefault();
          drawingStore.toggleToolbarVisible();
          return;
        }
        if (e.key === 'Backspace' || e.key === 'Delete') {
          if (drawingStore.hasSelection) {
            e.preventDefault();
            drawingStore.deleteSelected();
          }
          return;
        }
        const selectToolWithMoreOptions = (tool: Tool) => {
          drawingStore.selectTool(tool);
          const isUnpinned = !state.pinnedToolbarItems.includes(tool);
          setSettingsTool(
            tool !== 'select' && (isUnpinned || state.appSettings.revealSettingsOnSingleTap)
              ? tool
              : null
          );
        };
        if (key === 'h' && !e.shiftKey && !state.isEditingText) {
          closeBoard();
          return;
        }
        if (key === 'p') {
          selectToolWithMoreOptions('pen');
          return;
        }
        if (key === 's') {
          selectToolWithMoreOptions(e.shiftKey ? 'select' : 'sharpie');
          return;
        }
        if (key === 'f') {
          selectToolWithMoreOptions('fill');
          return;
        }
        if (key === 'r') {
          selectToolWithMoreOptions('shape');
          return;
        }
        if (key === 't') {
          selectToolWithMoreOptions('text');
          return;
        }
        if (key === 'e') {
          const prior = state.currentTool;
          selectToolWithMoreOptions('eraser');
          drawingStore.setEraserSettings({
            eraseTarget:
              prior === 'pen' ? 'pen' : prior === 'sharpie' ? 'sharpie' : prior === 'fill' ? 'fill' : 'all',
          });
          return;
        }
        if (key === 'x' && e.shiftKey) {
          drawingStore.addScene();
          return;
        }
        if (e.key === ',' && !e.shiftKey) {
          drawingStore.goToPreviousScene();
          return;
        }
        if (e.key === '.' && !e.shiftKey) {
          drawingStore.goToNextScene();
          return;
        }
        if (key === '0' && state.currentTool === 'eraser') {
          drawingStore.setEraserSettings({ eraseTarget: 'all' });
          return;
        }
        if (/^[1-8]$/.test(key)) {
          const digit = Number(key);
          if (state.currentTool === 'eraser') {
            if (digit === 1) drawingStore.setEraserSettings({ eraseTarget: 'pen' });
            else if (digit === 2) drawingStore.setEraserSettings({ eraseTarget: 'sharpie' });
            else if (digit === 3) drawingStore.setEraserSettings({ eraseTarget: 'fill' });
            return;
          }
          const idx = digit - 1;
          if (state.currentTool === 'pen') drawingStore.selectPenPreset(idx);
          else if (state.currentTool === 'sharpie') drawingStore.selectSharpiePreset(idx);
          else if (state.currentTool === 'fill') drawingStore.selectFillPreset(idx);
          else if (state.currentTool === 'shape') drawingStore.selectShapePreset(idx);
          else if (state.currentTool === 'text') drawingStore.selectTextPreset(idx);
        }
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [
    showWelcome,
    showHelp,
    showAbout,
    showClearConfirm,
    showRenameTissue,
    state.currentTool,
    state.isEditingText,
    state.pinnedToolbarItems,
    state.appSettings.revealSettingsOnSingleTap,
    state.selectedImageIds,
    state.showQuickMenu,
    showScenes,
    showMore,
    isCustomizing,
  ]);

  return (
    <div className={`app-root ${state.appSettings.isDarkMode ? 'theme-dark' : ''}`}>
      <input
        ref={imageInputRef}
        type="file"
        accept="image/*"
        multiple
        className="sr-only"
        onChange={async (e) => {
          const files = Array.from(e.target.files ?? []);
          for (let i = 0; i < files.length; i++) {
            await drawingStore.addImageFromBlob(files[i], i);
          }
          e.target.value = '';
        }}
      />

      <input
        ref={wbInputRef}
        type="file"
        accept=".wb,application/json"
        className="sr-only"
        onChange={async (e) => {
          const file = e.target.files?.[0];
          if (file) await handleImportWBFile(file);
          e.target.value = '';
        }}
      />

      {showWelcome ? (
        <WelcomeScreen
          boards={boards}
          folders={folders}
          trashedBoards={trashedBoards}
          thumbnails={thumbnails}
          isDarkMode={state.appSettings.isDarkMode}
          onToggleDarkMode={() => drawingStore.toggleDarkMode()}
          onCreateBoard={(folderId) => createBoard(folderId)}
          onOpenBoard={openBoard}
          onOpenWBFile={() => wbInputRef.current?.click()}
          onDropWBFile={handleImportWBFile}
          onRenameBoard={renameBoard}
          onTogglePinBoard={togglePinBoard}
          onMoveBoardToFolder={moveBoardToFolder}
          onExportBoardPNG={(id) => handleExportPNG(id)}
          onTrashBoard={trashBoard}
          onRestoreTrash={restoreTrash}
          onPermanentDeleteTrash={permDeleteTrash}
          onEmptyTrash={emptyTrash}
          onCreateFolder={createFolder}
          onRenameFolder={renameFolder}
          onDeleteFolder={deleteFolder}
          onShowHelp={() => setShowHelp(true)}
          onShowAbout={() => setShowAbout(true)}
        />
      ) : (
        <>
          <CanvasStage
            onBeginDraw={() => {
              if (state.pinnedToolbarItems.includes(state.currentTool)) {
                setSettingsTool(null);
              }
              setShowScenes(false);
              setShowMore(false);
            }}
          />

          <QuickSelectionMenu />

          {state.isToolbarVisible && (
            <div className={`toolbar-overlay dock-${state.appSettings.toolbarDockEdge}`}>
              <Toolbar
                settingsTool={settingsTool}
                setSettingsTool={setSettingsTool}
                showScenes={showScenes}
                setShowScenes={setShowScenes}
                showMore={showMore}
                setShowMore={setShowMore}
                isCustomizing={isCustomizing}
                setIsCustomizing={setIsCustomizing}
                hasActiveBoard={currentBoardId !== null}
                onHome={closeBoard}
                onImportImage={() => imageInputRef.current?.click()}
                onOpenWB={() => wbInputRef.current?.click()}
                onExportWB={handleExportWB}
                onExportPNG={() => handleExportPNG()}
                onExportPDF={handleExportPDF}
                onRenameTissue={() => setShowRenameTissue(true)}
                onClearConfirm={() => setShowClearConfirm(true)}
                onShowHelp={() => setShowHelp(true)}
                onShowAbout={() => setShowAbout(true)}
              />

              {settingsTool && !isCustomizing && <ToolSettingsPill tool={settingsTool} />}
              {!isCustomizing && <SelectionPill />}
              {showScenes && !isCustomizing && (
                <ScenesPopover
                  onClose={() => setShowScenes(false)}
                  onExportScenesPDF={handleExportScenesPDF}
                />
              )}
            </div>
          )}

          {showZoomPill && state.isToolbarVisible && (
            <div
              className={`glass-capsule zoom-pill ${
                state.appSettings.toolbarDockEdge === 'bottom' ? 'raised' : ''
              }`}
              onPointerDown={(e) => e.stopPropagation()}
            >
              <button
                type="button"
                className="zoom-label-btn"
                title="Reset Zoom to 100%"
                onClick={() => drawingStore.requestResetZoom()}
              >
                {Math.round(state.zoomDisplayScale * 100)}%
              </button>
              <div className="pill-divider short" />
              <button
                type="button"
                className="zoom-icon-btn"
                title="Fit All Content"
                onClick={() => drawingStore.requestFitToContent()}
              >
                <Icon name="fit" size={13} />
              </button>
            </div>
          )}
        </>
      )}

      {showHelp && <HelpModal onClose={() => setShowHelp(false)} />}
      {showAbout && <AboutModal onClose={() => setShowAbout(false)} />}

      {showClearConfirm && (
        <ConfirmModal
          title="Clear Canvas?"
          message="This will permanently remove all strokes, fills, and images from this tissue (undoable with Ctrl/⌘Z)."
          confirmLabel="Clear"
          onConfirm={() => {
            drawingStore.clearCanvas();
            setShowClearConfirm(false);
          }}
          onCancel={() => setShowClearConfirm(false)}
        />
      )}

      {showRenameTissue && currentBoardId && (
        <PromptModal
          title="Rename Tissue"
          placeholder="Tissue name"
          initialValue={currentBoardName}
          submitLabel="Rename"
          onSubmit={(name) => {
            renameBoard(currentBoardId, name);
            setShowRenameTissue(false);
          }}
          onCancel={() => setShowRenameTissue(false)}
        />
      )}

      {state.lastErrorMessage && (
        <div className="glass-capsule error-toast">
          <span>{state.lastErrorMessage}</span>
          <button
            type="button"
            className="row-icon-btn"
            onClick={() => drawingStore.setError(null)}
          >
            <Icon name="close" size={14} />
          </button>
        </div>
      )}
    </div>
  );
};

export default App;
