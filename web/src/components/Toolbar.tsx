import React, { useState } from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import {
  colorToCss,
  type CanvasBackground,
  type Tool,
  type ToolbarItemID,
} from '../types/model';
import { Icon, type IconName } from './Icons';

interface ToolbarProps {
  settingsTool: Tool | null;
  setSettingsTool: (t: Tool | null) => void;
  showScenes: boolean;
  setShowScenes: (v: boolean | ((prev: boolean) => boolean)) => void;
  showMore: boolean;
  setShowMore: (v: boolean | ((prev: boolean) => boolean)) => void;
  isCustomizing: boolean;
  setIsCustomizing: (v: boolean) => void;
  hasActiveBoard: boolean;
  onHome: () => void;
  onImportImage: () => void;
  onOpenWB: () => void;
  onExportWB: () => void;
  onExportPNG: () => void;
  onExportPDF: () => void;
  onRenameTissue: () => void;
  onClearConfirm: () => void;
  onShowHelp: () => void;
  onShowAbout: () => void;
}

const ITEM_META: Record<ToolbarItemID, { title: string; icon: IconName; tool?: Tool }> = {
  pen: { title: 'Pen (P)', icon: 'pen', tool: 'pen' },
  sharpie: { title: 'Sharpie (S)', icon: 'sharpie', tool: 'sharpie' },
  fill: { title: 'Fill (F)', icon: 'fill', tool: 'fill' },
  eraser: { title: 'Eraser (E)', icon: 'eraser', tool: 'eraser' },
  select: { title: 'Select (⇧S)', icon: 'select', tool: 'select' },
  scenes: { title: 'Scenes', icon: 'scenes' },
  home: { title: 'Home', icon: 'home' },
  undo: { title: 'Undo', icon: 'undo' },
  redo: { title: 'Redo', icon: 'redo' },
  clear: { title: 'Clear / Delete', icon: 'trash' },
  copy: { title: 'Copy', icon: 'copy' },
  paste: { title: 'Paste', icon: 'paste' },
  importImage: { title: 'Import Image', icon: 'image' },
  center: { title: 'Center Canvas', icon: 'center' },
  fitContent: { title: 'Fit All Content', icon: 'fit' },
  darkMode: { title: 'Theme', icon: 'moon' },
  warmPaper: { title: 'Warm Paper', icon: 'warmPaper' },
  renameTissue: { title: 'Rename Tissue', icon: 'rename' },
  singleTapOptions: { title: 'Single-Tap Options', icon: 'handTap' },
  pencilOnly: { title: 'Stylus Only', icon: 'pencilOnly' },
  exportWB: { title: 'Save .wb', icon: 'saveWB' },
  exportPNG: { title: 'Export PNG', icon: 'exportPNG' },
  exportPDF: { title: 'Export PDF', icon: 'exportPDF' },
  openFile: { title: 'Open .wb', icon: 'openFile' },
  help: { title: 'Help & Shortcuts', icon: 'help' },
  about: { title: 'About Tissue Box', icon: 'about' },
};

function contrastOnColor(c: { r: number; g: number; b: number }): string {
  const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
  return lum > 0.6 ? '#000000' : '#ffffff';
}

export const Toolbar: React.FC<ToolbarProps> = (props) => {
  const state = useDrawingState();
  const [draggedItem, setDraggedItem] = useState<ToolbarItemID | null>(null);
  const [trayDropActive, setTrayDropActive] = useState(false);

  const isVertical =
    state.appSettings.toolbarDockEdge === 'left' || state.appSettings.toolbarDockEdge === 'right';
  const hasSelection = drawingStore.hasSelection;
  const isEmptyCanvas =
    state.strokes.length === 0 && state.fills.length === 0 && state.placedImages.length === 0;

  const getIcon = (id: ToolbarItemID): IconName => {
    if (id === 'darkMode') return state.appSettings.isDarkMode ? 'sun' : 'moon';
    return ITEM_META[id].icon;
  };

  const getTooltip = (id: ToolbarItemID): string => {
    if (id === 'clear') return hasSelection ? 'Delete Selected' : 'Clear Tissue';
    if (id === 'darkMode') return state.appSettings.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode';
    if (id === 'warmPaper')
      return state.appSettings.isWarmPaper
        ? 'Switch to Crisp White Paper'
        : 'Switch to Warm Café Napkin Paper';
    return ITEM_META[id].title;
  };

  const isActive = (id: ToolbarItemID): boolean => {
    const tool = ITEM_META[id].tool;
    if (tool) return state.currentTool === tool;
    if (id === 'warmPaper') return state.appSettings.isWarmPaper && !state.appSettings.isDarkMode;
    if (id === 'singleTapOptions') return state.appSettings.revealSettingsOnSingleTap;
    if (id === 'pencilOnly') return state.appSettings.pencilOnly;
    return false;
  };

  const isDisabled = (id: ToolbarItemID): boolean => {
    if (id === 'undo') return !state.canUndo;
    if (id === 'redo') return !state.canRedo;
    if (id === 'clear') return isEmptyCanvas;
    if (id === 'copy') return !hasSelection;
    if (id === 'renameTissue') return !props.hasActiveBoard;
    return false;
  };

  const activeStyle = (id: ToolbarItemID): React.CSSProperties | undefined => {
    const tool = ITEM_META[id].tool;
    if (!tool || state.currentTool !== tool) return undefined;
    if (tool === 'pen') {
      const c = drawingStore.activePenColor;
      return { backgroundColor: colorToCss(c), color: contrastOnColor(c) };
    }
    if (tool === 'sharpie') {
      const c = drawingStore.activeSharpieColor;
      return { backgroundColor: colorToCss(c), color: contrastOnColor(c) };
    }
    if (tool === 'fill') {
      const c = drawingStore.activeFillColor;
      return { backgroundColor: colorToCss(c), color: contrastOnColor(c) };
    }
    return undefined;
  };

  const performAction = (id: ToolbarItemID, closeMore = false) => {
    const tool = ITEM_META[id].tool;
    if (tool) {
      props.setShowScenes(false);
      if (state.currentTool === tool) {
        props.setSettingsTool(props.settingsTool === tool || tool === 'select' ? null : tool);
      } else {
        drawingStore.selectTool(tool);
        props.setSettingsTool(
          state.appSettings.revealSettingsOnSingleTap && tool !== 'select' ? tool : null
        );
      }
      if (closeMore) props.setShowMore(false);
      return;
    }

    switch (id) {
      case 'scenes':
        if (closeMore) props.setShowMore(false);
        props.setSettingsTool(null);
        props.setShowScenes((v) => !v);
        break;
      case 'home':
        if (closeMore) props.setShowMore(false);
        props.onHome();
        break;
      case 'undo':
        drawingStore.undo();
        break;
      case 'redo':
        drawingStore.redo();
        break;
      case 'clear':
        if (closeMore) props.setShowMore(false);
        if (hasSelection) drawingStore.deleteSelected();
        else props.onClearConfirm();
        break;
      case 'copy':
        drawingStore.copySelected();
        if (closeMore) props.setShowMore(false);
        break;
      case 'paste':
        drawingStore.pasteInternal();
        if (closeMore) props.setShowMore(false);
        break;
      case 'importImage':
        if (closeMore) props.setShowMore(false);
        props.onImportImage();
        break;
      case 'center':
        drawingStore.requestRecenter();
        if (closeMore) props.setShowMore(false);
        break;
      case 'fitContent':
        drawingStore.requestFitToContent();
        if (closeMore) props.setShowMore(false);
        break;
      case 'darkMode':
        drawingStore.toggleDarkMode();
        break;
      case 'warmPaper':
        drawingStore.toggleWarmPaper();
        break;
      case 'renameTissue':
        if (closeMore) props.setShowMore(false);
        props.onRenameTissue();
        break;
      case 'singleTapOptions':
        drawingStore.setAppSettings({
          revealSettingsOnSingleTap: !state.appSettings.revealSettingsOnSingleTap,
        });
        break;
      case 'pencilOnly':
        drawingStore.setAppSettings({ pencilOnly: !state.appSettings.pencilOnly });
        break;
      case 'exportWB':
        if (closeMore) props.setShowMore(false);
        props.onExportWB();
        break;
      case 'exportPNG':
        if (closeMore) props.setShowMore(false);
        props.onExportPNG();
        break;
      case 'exportPDF':
        if (closeMore) props.setShowMore(false);
        props.onExportPDF();
        break;
      case 'openFile':
        if (closeMore) props.setShowMore(false);
        props.onOpenWB();
        break;
      case 'help':
        if (closeMore) props.setShowMore(false);
        props.onShowHelp();
        break;
      case 'about':
        if (closeMore) props.setShowMore(false);
        props.onShowAbout();
        break;
    }
  };

  const unpinned = drawingStore.unpinnedToolbarItems;

  return (
    <>
      <div
        className={`glass-capsule toolbar-bar ${isVertical ? 'vertical' : ''} ${
          props.isCustomizing ? 'customizing' : ''
        }`}
        onPointerDown={(e) => e.stopPropagation()}
        onDragOver={(e) => {
          if (props.isCustomizing) e.preventDefault();
        }}
        onDrop={() => {
          if (props.isCustomizing && draggedItem) {
            drawingStore.pinToolbarItem(draggedItem);
            setDraggedItem(null);
          }
        }}
      >
        {state.pinnedToolbarItems.map((item) => {
          if (props.isCustomizing) {
            return (
              <div
                key={item}
                className="customizing-chip"
                draggable
                title="Drag to reorder or drop in tray to move to More"
                onDragStart={() => setDraggedItem(item)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={(e) => {
                  e.stopPropagation();
                  if (draggedItem && draggedItem !== item) {
                    drawingStore.pinToolbarItem(draggedItem, item);
                  }
                  setDraggedItem(null);
                }}
              >
                <Icon name={getIcon(item)} size={17} />
                <button
                  type="button"
                  className="chip-remove-btn"
                  title={`Move ${ITEM_META[item].title} to More`}
                  onClick={() => drawingStore.unpinToolbarItem(item)}
                >
                  −
                </button>
              </div>
            );
          }

          if (item === 'scenes') {
            return (
              <div key={item} className={`scenes-group ${isVertical ? 'vertical' : ''}`}>
                <button
                  type="button"
                  className="toolbar-btn compact"
                  disabled={state.scenes.length === 0}
                  title="Previous Scene (,)"
                  onClick={() => drawingStore.goToPreviousScene()}
                >
                  <Icon name="chevronLeft" size={14} />
                </button>
                <button
                  type="button"
                  className={`toolbar-btn ${props.showScenes ? 'subtle-active' : ''}`}
                  title="Scenes"
                  onClick={() => {
                    props.setSettingsTool(null);
                    props.setShowMore(false);
                    props.setShowScenes((v) => !v);
                  }}
                >
                  <Icon name="scenes" size={17} />
                  {state.scenes.length > 0 && (
                    <span className="count-badge">{state.scenes.length}</span>
                  )}
                </button>
                <button
                  type="button"
                  className="toolbar-btn compact"
                  disabled={state.scenes.length === 0}
                  title="Next Scene (.)"
                  onClick={() => drawingStore.goToNextScene()}
                >
                  <Icon name="chevronRight" size={14} />
                </button>
              </div>
            );
          }

          return (
            <button
              key={item}
              type="button"
              className={`toolbar-btn ${isActive(item) ? 'active' : ''} ${
                item === 'clear' ? 'destructive' : ''
              }`}
              style={activeStyle(item)}
              disabled={isDisabled(item)}
              title={getTooltip(item)}
              onClick={() => performAction(item)}
            >
              <Icon name={getIcon(item)} size={18} />
            </button>
          );
        })}

        {state.pinnedToolbarItems.length > 0 && <div className="toolbar-divider" />}

        {props.isCustomizing ? (
          <button
            type="button"
            className="primary-pill-btn"
            onClick={() => props.setIsCustomizing(false)}
          >
            Done
          </button>
        ) : (
          <button
            type="button"
            className={`toolbar-btn ${props.showMore ? 'subtle-active' : ''}`}
            title="More Tools & Settings"
            onClick={() => {
              props.setSettingsTool(null);
              props.setShowScenes(false);
              props.setShowMore((v) => !v);
            }}
          >
            <Icon name="more" size={18} />
          </button>
        )}
      </div>

      {/* More Popover */}
      {props.showMore && !props.isCustomizing && (
        <div className="glass-surface more-popover" onPointerDown={(e) => e.stopPropagation()}>
          <div className="more-grid">
            {unpinned.map((item) => (
              <button
                key={item}
                type="button"
                className={`more-tile ${isActive(item) ? 'active' : ''} ${
                  item === 'clear' ? 'destructive' : ''
                }`}
                disabled={isDisabled(item)}
                title={getTooltip(item)}
                onClick={() => performAction(item, true)}
              >
                <Icon name={getIcon(item)} size={16} />
                <span>{ITEM_META[item].title.replace(/\s*\(.*\)$/, '')}</span>
              </button>
            ))}
          </div>

          <div className="more-section">
            <span className="more-section-label">Canvas Background</span>
            <div className="bg-picker-row">
              {(['none', 'grid', 'dots', 'ruled'] as CanvasBackground[]).map((bg) => (
                <button
                  key={bg}
                  type="button"
                  className={`bg-chip ${state.appSettings.canvasBackground === bg ? 'active' : ''}`}
                  title={bg.charAt(0).toUpperCase() + bg.slice(1)}
                  onClick={() => drawingStore.setCanvasBackground(bg)}
                >
                  <Icon name={bg === 'none' ? 'plain' : bg} size={14} />
                  <span>{bg.charAt(0).toUpperCase() + bg.slice(1)}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="more-footer">
            <button
              type="button"
              className="more-footer-btn"
              onClick={() => {
                props.setShowMore(false);
                props.setIsCustomizing(true);
              }}
            >
              <Icon name="sliders" size={14} />
              <span>Customize Toolbar</span>
            </button>
            <button
              type="button"
              className="more-footer-btn"
              title="Dock Toolbar: Top / Bottom / Left / Right"
              onClick={() => drawingStore.cycleToolbarDockEdge()}
            >
              <Icon name="dock" size={14} />
              <span>
                Dock: {state.appSettings.toolbarDockEdge.charAt(0).toUpperCase() + state.appSettings.toolbarDockEdge.slice(1)}
              </span>
            </button>
          </div>
        </div>
      )}

      {/* Customize Toolbar Tray */}
      {props.isCustomizing && (
        <div
          className={`glass-surface customize-tray ${trayDropActive ? 'drop-active' : ''}`}
          onPointerDown={(e) => e.stopPropagation()}
          onDragOver={(e) => {
            e.preventDefault();
            setTrayDropActive(true);
          }}
          onDragLeave={() => setTrayDropActive(false)}
          onDrop={() => {
            setTrayDropActive(false);
            if (draggedItem) {
              drawingStore.unpinToolbarItem(draggedItem);
              setDraggedItem(null);
            }
          }}
        >
          <div className="popover-header">
            <span className="popover-title">Customize Toolbar</span>
            <div className="popover-header-actions">
              <button
                type="button"
                className="accent-chip-btn"
                title="Dock Toolbar: Top / Bottom / Left / Right"
                onClick={() => drawingStore.cycleToolbarDockEdge()}
              >
                <Icon name="dock" size={13} />
                <span>
                  {state.appSettings.toolbarDockEdge.charAt(0).toUpperCase() +
                    state.appSettings.toolbarDockEdge.slice(1)}
                </span>
              </button>
              <button
                type="button"
                className="row-icon-btn"
                style={{ width: 'auto', padding: '0 8px', fontSize: 12 }}
                onClick={() => drawingStore.resetToolbarLayout()}
              >
                Reset
              </button>
            </div>
          </div>

          <div className="customize-hint">
            Drag icons onto the toolbar to add or reorder · Drag or click icons below to pin/unpin
          </div>

          {unpinned.length === 0 ? (
            <div className="customize-empty">
              All tools are pinned to the toolbar. Drag any icon here to unpin it.
            </div>
          ) : (
            <div className="customize-grid">
              {unpinned.map((item) => (
                <button
                  key={item}
                  type="button"
                  className="customize-tile"
                  draggable
                  onDragStart={() => setDraggedItem(item)}
                  onClick={() => drawingStore.pinToolbarItem(item)}
                  title={`Click or drag to pin ${ITEM_META[item].title}`}
                >
                  <span className="customize-tile-icon">
                    <Icon name={getIcon(item)} size={16} />
                  </span>
                  <span className="customize-tile-label">
                    {ITEM_META[item].title.replace(/\s*\(.*\)$/, '')}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </>
  );
};
