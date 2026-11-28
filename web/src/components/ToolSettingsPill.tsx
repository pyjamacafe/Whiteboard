import React, { useRef } from 'react';
import { drawingStore, useDrawingState } from '../store/drawingStore';
import {
  colorToCss,
  colorToHex,
  hexToColor,
  type CodableColor,
  type ShapeKind,
  type Tool,
} from '../types/model';
import { isLineLikeShape } from '../engine/geometry';
import { Icon, type IconName } from './Icons';

interface ToolSettingsPillProps {
  tool: Tool;
}

type PresetKind = 'pen' | 'sharpie' | 'fill' | 'shape' | 'text';

const SHAPE_OPTIONS: { kind: ShapeKind; label: string; icon: IconName }[] = [
  { kind: 'rectangle', label: 'Rectangle', icon: 'rectShape' },
  { kind: 'ellipse', label: 'Ellipse', icon: 'ellipseShape' },
  { kind: 'triangle', label: 'Triangle', icon: 'triangleShape' },
  { kind: 'diamond', label: 'Diamond', icon: 'diamondShape' },
  { kind: 'line', label: 'Line', icon: 'lineShape' },
  { kind: 'arrow', label: 'Arrow', icon: 'arrowShape' },
];

const TEXT_SIZE_LABELS = ['S', 'M', 'L', 'XL'];

export const ToolSettingsPill: React.FC<ToolSettingsPillProps> = ({ tool }) => {
  const state = useDrawingState();
  const colorInputRef = useRef<HTMLInputElement>(null);
  const editingSlotRef = useRef<{ kind: PresetKind; index: number } | null>(null);
  const lastTapRef = useRef<{ key: string; time: number }>({ key: '', time: 0 });

  if (tool === 'select') return null;

  const openColorPicker = (kind: PresetKind, index: number, current: CodableColor) => {
    editingSlotRef.current = { kind, index };
    if (colorInputRef.current) {
      colorInputRef.current.value = colorToHex(current);
      colorInputRef.current.click();
    }
  };

  const renderPresetRow = (
    kind: PresetKind,
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
          else if (slot.kind === 'fill') drawingStore.updateFillPresetColor(slot.index, color);
          else if (slot.kind === 'shape') drawingStore.updateShapePresetColor(slot.index, color);
          else drawingStore.updateTextPresetColor(slot.index, color);
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

      {tool === 'shape' && (
        <>
          <div className="eraser-mode-row">
            {SHAPE_OPTIONS.map((opt) => (
              <button
                key={opt.kind}
                type="button"
                className={`mini-icon-btn ${state.shapeSettings.kind === opt.kind ? 'active' : ''}`}
                title={opt.label}
                onClick={() => drawingStore.setShapeKind(opt.kind)}
              >
                <Icon name={opt.icon} size={15} />
              </button>
            ))}
          </div>
          <div className="pill-divider" />
          {renderPresetRow('shape', drawingStore.shapePresets, state.shapePresetIndex, (i) =>
            drawingStore.selectShapePreset(i)
          )}
          <div className="pill-divider" />
          <div className="width-row">
            {state.shapeSettings.widthOptions.map((w) => (
              <button
                key={w}
                type="button"
                className={`width-btn ${state.shapeSettings.lineWidth === w ? 'active' : ''}`}
                title={`Stroke Width ${w} pt`}
                onClick={() => drawingStore.setShapeSettings({ lineWidth: w })}
              >
                <span className="width-dot" style={{ width: 4 + w * 2, height: 4 + w * 2 }} />
              </button>
            ))}
          </div>
          {!isLineLikeShape(state.shapeSettings.kind) && (
            <>
              <div className="pill-divider" />
              <button
                type="button"
                className={`mini-icon-btn ${state.shapeSettings.isFilled ? 'active' : ''}`}
                title={
                  state.shapeSettings.isFilled
                    ? 'Filled Shape (click for Outline Only)'
                    : 'Outline Only (click for Translucent Fill)'
                }
                onClick={() =>
                  drawingStore.setShapeSettings({ isFilled: !state.shapeSettings.isFilled })
                }
              >
                <Icon name={state.shapeSettings.isFilled ? 'shapeFillOn' : 'shapeFillOff'} size={15} />
              </button>
            </>
          )}
        </>
      )}

      {tool === 'text' && (
        <>
          {renderPresetRow('text', drawingStore.textPresets, state.textPresetIndex, (i) =>
            drawingStore.selectTextPreset(i)
          )}
          <div className="pill-divider" />
          <div className="eraser-mode-row">
            {state.textSettings.sizeOptions.map((sz, idx) => (
              <button
                key={sz}
                type="button"
                className={`mini-icon-btn text-size-btn ${
                  Math.abs(state.textSettings.fontSize - sz) < 0.5 ? 'active' : ''
                }`}
                title={`Font Size ${sz}pt`}
                onClick={() => drawingStore.setTextFontSize(sz)}
              >
                {TEXT_SIZE_LABELS[idx] ?? sz}
              </button>
            ))}
          </div>
          <div className="pill-divider" />
          <button
            type="button"
            className={`mini-icon-btn ${state.textSettings.isBold ? 'active' : ''}`}
            title="Toggle Bold"
            onClick={() => drawingStore.toggleTextBold()}
          >
            <Icon name="bold" size={14} />
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
