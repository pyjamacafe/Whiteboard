import React, { useEffect, useState } from 'react';
import { CanvasStage } from './components/CanvasStage';
import { Icon } from './components/Icons';
import { ToolSettingsPill } from './components/ToolSettingsPill';
import { drawingStore, useDrawingState } from './store/drawingStore';
import { colorToCss, type CanvasBackground, type Tool } from './types/model';

function contrastOnColor(c: { r: number; g: number; b: number }): string {
  const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
  return lum > 0.6 ? '#000000' : '#ffffff';
}

export const App: React.FC = () => {
  const state = useDrawingState();
  const [settingsTool, setSettingsTool] = useState<Tool | null>(null);

  useEffect(() => {
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
        return;
      }

      if (!mod && !e.altKey) {
        if (e.key === 'Tab') {
          e.preventDefault();
          drawingStore.toggleToolbarVisible();
          return;
        }
        if (key === 'p') {
          drawingStore.selectTool('pen');
          setSettingsTool(null);
          return;
        }
        if (key === 's') {
          drawingStore.selectTool(e.shiftKey ? 'select' : 'sharpie');
          setSettingsTool(null);
          return;
        }
        if (key === 'f') {
          drawingStore.selectTool('fill');
          setSettingsTool(null);
          return;
        }
        if (key === 'e') {
          const prior = state.currentTool;
          drawingStore.selectTool('eraser');
          drawingStore.setEraserSettings({
            eraseTarget:
              prior === 'pen' ? 'pen' : prior === 'sharpie' ? 'sharpie' : prior === 'fill' ? 'fill' : 'all',
          });
          setSettingsTool(null);
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
        }
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [state.currentTool]);

  const handleToolClick = (tool: Tool) => {
    if (state.currentTool === tool) {
      setSettingsTool(settingsTool === tool || tool === 'select' ? null : tool);
    } else {
      drawingStore.selectTool(tool);
      setSettingsTool(state.appSettings.revealSettingsOnSingleTap && tool !== 'select' ? tool : null);
    }
  };

  const toolActiveStyle = (tool: Tool): React.CSSProperties | undefined => {
    if (state.currentTool !== tool) return undefined;
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

  const cycleBackground = () => {
    const order: CanvasBackground[] = ['grid', 'dots', 'ruled', 'none'];
    const idx = order.indexOf(state.appSettings.canvasBackground);
    drawingStore.setCanvasBackground(order[(idx + 1) % order.length]);
  };

  return (
    <div className={`app-root ${state.appSettings.isDarkMode ? 'theme-dark' : ''}`}>
      <CanvasStage onBeginDraw={() => setSettingsTool(null)} />

      {state.isToolbarVisible && (
        <div className={`toolbar-overlay dock-${state.appSettings.toolbarDockEdge}`}>
          <div className="glass-capsule toolbar-bar" onPointerDown={(e) => e.stopPropagation()}>
            {(['pen', 'sharpie', 'fill', 'eraser'] as Tool[]).map((t) => (
              <button
                key={t}
                type="button"
                className={`toolbar-btn ${state.currentTool === t ? 'active' : ''}`}
                style={toolActiveStyle(t)}
                title={t.charAt(0).toUpperCase() + t.slice(1)}
                onClick={() => handleToolClick(t)}
              >
                <Icon name={t} size={18} />
              </button>
            ))}

            <div className="toolbar-divider" />

            <button
              type="button"
              className="toolbar-btn"
              disabled={!state.canUndo}
              title="Undo"
              onClick={() => drawingStore.undo()}
            >
              <Icon name="undo" size={17} />
            </button>
            <button
              type="button"
              className="toolbar-btn"
              disabled={!state.canRedo}
              title="Redo"
              onClick={() => drawingStore.redo()}
            >
              <Icon name="redo" size={17} />
            </button>
            <button
              type="button"
              className="toolbar-btn"
              title={`Background: ${state.appSettings.canvasBackground}`}
              onClick={cycleBackground}
            >
              <Icon
                name={
                  state.appSettings.canvasBackground === 'none'
                    ? 'plain'
                    : state.appSettings.canvasBackground
                }
                size={17}
              />
            </button>
            <button
              type="button"
              className={`toolbar-btn ${state.appSettings.isWarmPaper && !state.appSettings.isDarkMode ? 'active' : ''}`}
              title="Warm Café Napkin Paper"
              onClick={() => drawingStore.toggleWarmPaper()}
            >
              <Icon name="warmPaper" size={17} />
            </button>
            <button
              type="button"
              className="toolbar-btn"
              title={state.appSettings.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
              onClick={() => drawingStore.toggleDarkMode()}
            >
              <Icon name={state.appSettings.isDarkMode ? 'sun' : 'moon'} size={17} />
            </button>
            <button
              type="button"
              className="toolbar-btn destructive"
              title="Clear Canvas"
              disabled={state.strokes.length === 0 && state.fills.length === 0}
              onClick={() => drawingStore.clearCanvas()}
            >
              <Icon name="trash" size={17} />
            </button>
          </div>

          {settingsTool && <ToolSettingsPill tool={settingsTool} />}
        </div>
      )}
    </div>
  );
};

export default App;
