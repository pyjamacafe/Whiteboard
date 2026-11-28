import React from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import { colorToCss } from '../types/model';
import { Icon } from './Icons';

export const SelectionPill: React.FC = () => {
  const state = useDrawingState();
  const hasSelection =
    state.selectedStrokeIds.length > 0 ||
    state.selectedFillIds.length > 0 ||
    state.selectedImageIds.length > 0;

  if (state.currentTool !== 'select' || !hasSelection) return null;

  const canReset = drawingStore.canResetSelectionRotation;
  const presets = drawingStore.penPresets.slice(0, 6);

  return (
    <div className="glass-capsule selection-pill" onPointerDown={(e) => e.stopPropagation()}>
      <button
        type="button"
        className="sel-btn"
        title="Copy Selection"
        onClick={() => drawingStore.copySelected()}
      >
        <Icon name="copy" size={14} />
      </button>
      <button
        type="button"
        className="sel-btn"
        title="Duplicate Selection"
        onClick={() => drawingStore.duplicateSelected()}
      >
        <Icon name="duplicate" size={14} />
      </button>

      {(state.selectedStrokeIds.length > 0 || state.selectedFillIds.length > 0) && (
        <>
          <div className="pill-divider short" />
          <div className="sel-swatches">
            {presets.map((c, idx) => (
              <button
                key={idx}
                type="button"
                className="sel-swatch"
                style={{ backgroundColor: colorToCss(c) }}
                title="Recolor Selection"
                onClick={() => drawingStore.recolorSelected(c, idx)}
              />
            ))}
          </div>
        </>
      )}

      <div className="pill-divider short" />

      <button
        type="button"
        className="sel-btn"
        title="Shrink Selection"
        onClick={() => drawingStore.transformSelected(0.85, 0)}
      >
        <Icon name="zoomOut" size={14} />
      </button>
      <button
        type="button"
        className="sel-btn"
        title="Enlarge Selection"
        onClick={() => drawingStore.transformSelected(1.15, 0)}
      >
        <Icon name="zoomIn" size={14} />
      </button>
      <button
        type="button"
        className="sel-btn"
        disabled={!canReset}
        title={canReset ? `Reset Rotation (${drawingStore.activeRotationLabel} → 0°)` : 'Reset Rotation'}
        onClick={() => drawingStore.resetSelectionRotation()}
      >
        <Icon name="rotateReset" size={14} />
      </button>

      <div className="pill-divider short" />

      <button
        type="button"
        className="sel-btn destructive"
        title="Delete Selection"
        onClick={() => drawingStore.deleteSelected()}
      >
        <Icon name="trash" size={14} />
      </button>
    </div>
  );
};

export const QuickSelectionMenu: React.FC = () => {
  const state = useDrawingState();
  if (!state.showQuickMenu) return null;

  const hasSel =
    state.selectedStrokeIds.length > 0 ||
    state.selectedFillIds.length > 0 ||
    state.selectedImageIds.length > 0;

  return (
    <div
      className="glass-capsule quick-menu"
      style={{
        left: Math.max(12, Math.min(window.innerWidth - 220, state.quickMenuLocation.x)),
        top: Math.max(64, Math.min(window.innerHeight - 64, state.quickMenuLocation.y)),
      }}
      onPointerDown={(e) => e.stopPropagation()}
    >
      {!hasSel ? (
        <button
          type="button"
          className="quick-menu-btn"
          onClick={() => {
            drawingStore.pasteInternal();
            drawingStore.setQuickMenu(false);
          }}
        >
          <Icon name="paste" size={14} />
          <span>Paste</span>
        </button>
      ) : (
        <>
          <button
            type="button"
            className="quick-menu-btn"
            onClick={() => {
              drawingStore.copySelected();
              drawingStore.setQuickMenu(false);
            }}
          >
            <Icon name="copy" size={14} />
            <span>Copy</span>
          </button>
          {state.selectedImageIds.length > 0 && (
            <>
              <button
                type="button"
                className="quick-menu-btn"
                title="Shrink Image"
                onClick={() => {
                  drawingStore.resizeSelectedImages(0.8);
                  drawingStore.setQuickMenu(false);
                }}
              >
                <Icon name="zoomOut" size={14} />
              </button>
              <button
                type="button"
                className="quick-menu-btn"
                title="Enlarge Image"
                onClick={() => {
                  drawingStore.resizeSelectedImages(1.25);
                  drawingStore.setQuickMenu(false);
                }}
              >
                <Icon name="zoomIn" size={14} />
              </button>
            </>
          )}
          <button
            type="button"
            className="quick-menu-btn destructive"
            onClick={() => {
              drawingStore.deleteSelected();
              drawingStore.setQuickMenu(false);
            }}
          >
            <Icon name="trash" size={14} />
            <span>Delete</span>
          </button>
        </>
      )}
    </div>
  );
};
