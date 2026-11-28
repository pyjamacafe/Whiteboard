import React, { useRef } from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import { colorToCss, colorToHex, hexToColor, type CodableColor, type Tool } from '../types/model';
import { Icon } from './Icons';

interface ToolSettingsPillProps {
  tool: Tool;
}

export const ToolSettingsPill: React.FC<ToolSettingsPillProps> = ({ tool }) => {
  const state = useDrawingState();
  const colorInputRef = useRef<HTMLInputElement>(null);
  const editingSlotRef = useRef<{ kind: 'pen' | 'sharpie' | 'fill'; index: number } | null>(null);
  const lastTapRef = useRef<{ key: string; time: number }>({ key: '', time: 0 });

  if (tool === 'select') return null;

  const openColorPicker = (kind: 'pen' | 'sharpie' | 'fill', index: number, current: CodableColor) => {
    editingSlotRef.current = { kind, index };
    if (colorInputRef.current) {
      colorInputRef.current.value = colorToHex(current);
      colorInputRef.current.click();
    }
  };

  const renderPresetRow = (
    kind: 'pen' | 'sharpie' | 'fill',
    presets: CodableColor[],
    selectedIndex: number,
    onSelect: (idx: number) => void
  ) => (
    <div className="preset-row">
      {presets.map((c, idx) => (
        <button
          key={idx}
          type="button"
          className={`color-swatch ${idx === selectedIndex ? 'selected' : ''}`}
          style={{ backgroundColor: colorToCss(c) }}
          title={`Color ${idx + 1} (double-click to customize)`}
          onClick={() => {
            const now = Date.now();
            const key = `${kind}-${idx}`;
            if (lastTapRef.current.key === key && now - lastTapRef.current.time < 320) {
              lastTapRef.current = { key: '', time: 0 };
              openColorPicker(kind, idx, c);
            } else {
              lastTapRef.current = { key, time: now };
              onSelect(idx);
            }
          }}
        />
      ))}
    </div>
  );

  const fillGapLabel =
    state.fillSettings.gapTolerance < 1.0
      ? 'Strict'
      : state.fillSettings.gapTolerance < 4.0
      ? 'Auto'
      : 'Wide';

  const fillGapIcon =
    state.fillSettings.gapTolerance < 1.0
      ? 'lock'
      : state.fillSettings.gapTolerance < 4.0
      ? 'wand'
      : 'arrowsH';

  const eraseTargetIcon =
    state.eraserSettings.eraseTarget === 'all'
      ? 'layers'
      : state.eraserSettings.eraseTarget === 'pen'
      ? 'pen'
      : state.eraserSettings.eraseTarget === 'sharpie'
      ? 'sharpie'
      : 'fill';

  return (
    <div className="glass-capsule tool-settings-pill" onPointerDown={(e) => e.stopPropagation()}>
      <input
        ref={colorInputRef}
        type="color"
        className="sr-only"
        onChange={(e) => {
          const slot = editingSlotRef.current;
          if (!slot) return;
          const color = hexToColor(e.target.value);
          if (slot.kind === 'pen') drawingStore.updatePenPresetColor(slot.index, color);
          else if (slot.kind === 'sharpie') drawingStore.updateSharpiePresetColor(slot.index, color);
          else drawingStore.updateFillPresetColor(slot.index, color);
        }}
      />

      {tool === 'pen' && (
        <>
          {renderPresetRow('pen', drawingStore.penPresets, state.penPresetIndex, (i) =>
            drawingStore.selectPenPreset(i)
          )}
          <div className="pill-divider" />
          <div className="width-row">
            {state.penSettings.widthOptions.map((w) => (
              <button
                key={w}
                type="button"
                className={`width-btn ${state.penSettings.thickness === w ? 'active' : ''}`}
                title={`Width ${w} pt`}
                onClick={() => drawingStore.setPenThickness(w)}
              >
                <span className="width-dot" style={{ width: 4 + w * 2, height: 4 + w * 2 }} />
              </button>
            ))}
          </div>
        </>
      )}

      {tool === 'sharpie' && (
        <>
          {renderPresetRow('sharpie', drawingStore.sharpiePresets, state.sharpiePresetIndex, (i) =>
            drawingStore.selectSharpiePreset(i)
          )}
          <div className="pill-divider" />
          <div className="width-row">
            {state.sharpieSettings.widthOptions.map((w) => (
              <button
                key={w}
                type="button"
                className={`width-btn ${state.sharpieSettings.thickness === w ? 'active' : ''}`}
                title={`Width ${w} pt`}
                onClick={() => drawingStore.setSharpieThickness(w)}
              >
                <span className="width-dot" style={{ width: 4 + w * 2, height: 4 + w * 2 }} />
              </button>
            ))}
          </div>
        </>
      )}

      {tool === 'fill' && (
        <>
          {renderPresetRow('fill', drawingStore.fillPresets, state.fillPresetIndex, (i) =>
            drawingStore.selectFillPreset(i)
          )}
          <div className="pill-divider" />
          <button
            type="button"
            className="opacity-swatch-btn"
            title={`Opacity: ${Math.round(state.fillSettings.opacity * 100)}% (tap to cycle 25% / 50% / 75% / 100%)`}
            onClick={() => drawingStore.cycleFillOpacity()}
          >
            <span
              className="opacity-swatch-fill"
              style={{
                backgroundColor: colorToCss(drawingStore.activeFillColor, state.fillSettings.opacity),
              }}
            />
          </button>
          <button
            type="button"
            className="mini-icon-btn"
            title={`Gap Closing: ${fillGapLabel} (tap to cycle Strict / Auto / Wide)`}
            onClick={() => drawingStore.cycleFillGapTolerance()}
          >
            <Icon name={fillGapIcon} size={14} />
          </button>
          <button
            type="button"
            className={`mini-icon-btn ${state.fillSettings.overlapMode === 'blend' ? 'active' : ''}`}
            title={
              state.fillSettings.overlapMode === 'replace'
                ? 'Replace Mode: refilling replaces existing color (click to switch to Blend)'
                : 'Blend Mode: refilling layers colors together (click to switch to Replace)'
            }
            onClick={() => drawingStore.toggleFillOverlapMode()}
          >
            <Icon name={state.fillSettings.overlapMode === 'replace' ? 'replace' : 'blend'} size={14} />
          </button>
        </>
      )}

      {tool === 'eraser' && (
        <>
          <div className="eraser-mode-row">
            <button
              type="button"
              className={`mini-icon-btn lg ${state.eraserSettings.mode === 'partial' ? 'active' : ''}`}
              title="Partial Erase"
              onClick={() => drawingStore.setEraserMode('partial')}
            >
              <Icon name="circleDotted" size={16} />
            </button>
            <button
              type="button"
              className={`mini-icon-btn lg ${state.eraserSettings.mode === 'full' ? 'active' : ''}`}
              title="Full Stroke Erase"
              onClick={() => drawingStore.setEraserMode('full')}
            >
              <Icon name="circleFull" size={16} />
            </button>
          </div>
          <div className="pill-divider" />
          <button
            type="button"
            className={`mini-icon-btn lg ${state.eraserSettings.eraseTarget !== 'all' ? 'active' : ''}`}
            title={`Erase Target: ${state.eraserSettings.eraseTarget} (tap to cycle All / Pen / Sharpie / Fill)`}
            onClick={() => drawingStore.cycleEraseTarget()}
          >
            <Icon name={eraseTargetIcon} size={16} />
          </button>
          <div className="pill-divider" />
          <div className="width-row">
            {[10, 20, 30, 40, 50, 60].map((s) => (
              <button
                key={s}
                type="button"
                className={`width-btn ${Math.round(state.eraserSettings.size) === s ? 'active' : ''}`}
                title={`Eraser Size ${s}`}
                onClick={() => drawingStore.setEraserSettings({ size: s })}
              >
                <span className="width-dot" style={{ width: s * 0.35 + 4, height: s * 0.35 + 4 }} />
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
};
