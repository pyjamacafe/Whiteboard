import React, { useEffect, useState } from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import { renderSceneThumbnailDataUrl } from '../engine/renderer';
import { Icon } from './Icons';

interface ScenesPopoverProps {
  onClose: () => void;
  onExportScenesPDF?: () => void;
}

export const ScenesPopover: React.FC<ScenesPopoverProps> = ({ onClose, onExportScenesPDF }) => {
  const state = useDrawingState();
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameText, setRenameText] = useState('');
  const [thumbs, setThumbs] = useState<Record<string, string>>({});
  const [dragIndex, setDragIndex] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const next: Record<string, string> = {};
      for (const scene of state.scenes) {
        const url = await renderSceneThumbnailDataUrl({
          scene,
          strokes: state.strokes,
          placedImages: state.placedImages,
          fills: state.fills,
          penPresets: drawingStore.penPresets,
          sharpiePresets: drawingStore.sharpiePresets,
          fillPresets: drawingStore.fillPresets,
          isDarkMode: state.appSettings.isDarkMode,
          isWarmPaper: state.appSettings.isWarmPaper,
        });
        if (url) next[scene.id] = url;
      }
      if (!cancelled) setThumbs(next);
    })();
    return () => {
      cancelled = true;
    };
  }, [
    state.scenes,
    state.committedRevision,
    state.appSettings.isDarkMode,
    state.appSettings.isWarmPaper,
  ]);

  return (
    <div className="glass-surface scenes-popover" onPointerDown={(e) => e.stopPropagation()}>
      <div className="popover-header">
        <span className="popover-title">Scenes</span>
        <div className="popover-header-actions">
          {state.scenes.length > 0 && onExportScenesPDF && (
            <button
              type="button"
              className="mini-icon-btn"
              title="Export Scenes as Multi-Page PDF"
              onClick={() => {
                onClose();
                onExportScenesPDF();
              }}
            >
              <Icon name="exportPDF" size={14} />
            </button>
          )}
          <button
            type="button"
            className="accent-chip-btn"
            title="Save Current View as Scene (⇧X)"
            onClick={() => drawingStore.addScene()}
          >
            <Icon name="plus" size={13} />
            <span>Add</span>
          </button>
        </div>
      </div>

      {state.scenes.length === 0 ? (
        <div className="scenes-empty">
          <Icon name="scenes" size={26} className="muted-icon" />
          <div className="scenes-empty-title">No Scenes Yet</div>
          <div className="scenes-empty-sub">
            Bookmark regions of your tissue to jump between ideas like slides.
          </div>
          <button
            type="button"
            className="primary-pill-btn"
            onClick={() => drawingStore.addScene()}
          >
            <Icon name="plus" size={13} />
            <span>Add Current View</span>
          </button>
        </div>
      ) : (
        <div className="scenes-list">
          {state.scenes.map((scene, idx) => {
            const active = scene.id === state.activeSceneId;
            return (
              <div
                key={scene.id}
                className={`scene-row ${active ? 'active' : ''}`}
                draggable
                onDragStart={() => setDragIndex(idx)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (dragIndex !== null && dragIndex !== idx) {
                    drawingStore.moveScene(dragIndex, idx);
                  }
                  setDragIndex(null);
                }}
                onClick={() => {
                  if (renamingId !== scene.id) drawingStore.navigateToScene(scene.id);
                }}
              >
                <div className="scene-thumb">
                  {thumbs[scene.id] ? (
                    <img src={thumbs[scene.id]} alt={scene.name} />
                  ) : (
                    <span>{idx + 1}</span>
                  )}
                </div>

                <div className="scene-meta">
                  {renamingId === scene.id ? (
                    <input
                      autoFocus
                      className="inline-rename-input"
                      value={renameText}
                      onClick={(e) => e.stopPropagation()}
                      onChange={(e) => setRenameText(e.target.value)}
                      onBlur={() => {
                        drawingStore.renameScene(scene.id, renameText);
                        setRenamingId(null);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          drawingStore.renameScene(scene.id, renameText);
                          setRenamingId(null);
                        } else if (e.key === 'Escape') {
                          setRenamingId(null);
                        }
                      }}
                    />
                  ) : (
                    <div className="scene-name">{scene.name}</div>
                  )}
                  <div className="scene-sub">{Math.round(scene.scale * 100)}%</div>
                </div>

                <div className="scene-row-actions" onClick={(e) => e.stopPropagation()}>
                  <button
                    type="button"
                    className="row-icon-btn"
                    title="Update to Current View"
                    onClick={() => drawingStore.updateSceneToCurrentView(scene.id)}
                  >
                    <Icon name="center" size={13} />
                  </button>
                  <button
                    type="button"
                    className="row-icon-btn"
                    title="Rename Scene"
                    onClick={() => {
                      setRenamingId(scene.id);
                      setRenameText(scene.name);
                    }}
                  >
                    <Icon name="rename" size={13} />
                  </button>
                  <button
                    type="button"
                    className="row-icon-btn destructive"
                    title="Delete Scene"
                    onClick={() => drawingStore.deleteScene(scene.id)}
                  >
                    <Icon name="trash" size={13} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
