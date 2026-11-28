import React from 'react';
import { Icon, type IconName } from './Icons';

const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad|iPod/i.test(navigator.platform || navigator.userAgent);
const MOD = isMac ? '⌘' : 'Ctrl+';

export const HelpModal: React.FC<{ onClose: () => void }> = ({ onClose }) => {
  const tools: { icon: IconName; color: string; title: string; key: string; detail: string }[] = [
    {
      icon: 'pen',
      color: '#007aff',
      title: 'Pen',
      key: 'P',
      detail: 'Smooth vector strokes with 8 theme-adaptive colors and adjustable width. Hold at the end of a stroke to snap lines, circles, and rectangles.',
    },
    {
      icon: 'sharpie',
      color: '#ff9500',
      title: 'Sharpie',
      key: 'S',
      detail: 'Bold two-pass glow/core stroke with its own independent color presets.',
    },
    {
      icon: 'fill',
      color: '#00b4d8',
      title: 'Fill',
      key: 'F',
      detail: 'Tap inside any closed stroke or shape to fill cleanly without bleeding. Tap the swatch to cycle opacity (25%–100%), or use the icons for gap-closing (Strict / Auto / Wide) and Replace vs. Blend mode.',
    },
    {
      icon: 'shape',
      color: '#34c759',
      title: 'Shapes',
      key: 'R',
      detail: 'Drag to draw crisp rectangles, ellipses, triangles, diamonds, lines, and arrows. Hold ⇧ while dragging for perfect squares, circles, or 15° angles; toggle translucent fill in options.',
    },
    {
      icon: 'text',
      color: '#32ade6',
      title: 'Text',
      key: 'T',
      detail: `Click anywhere to add a monospace text label with Markdown support (# headings, **bold**, *italic*, ~~strike~~, \`code\`, lists, and checklists). While typing, use ${MOD}B / ${MOD}I / ${MOD}U / ${MOD}⇧X / ${MOD}E to format text; press Enter to commit or ⇧Enter for a new line.`,
    },
    {
      icon: 'eraser',
      color: '#ff2d55',
      title: 'Eraser',
      key: 'E',
      detail: 'Switch between Full Stroke and Partial erase, tap the layer icon (or press 0–3) to target All, Pen, Sharpie, or Fill.',
    },
    {
      icon: 'select',
      color: '#af52de',
      title: 'Select',
      key: '⇧S',
      detail: 'Tap any pen, sharpie, fill, or image to select it, or draw a lasso around multiple items. Tap free space or press Esc to unselect; drag to move, drag the top handle to rotate (hold ⇧ for 15° steps), or double-tap for Copy/Paste/Delete.',
    },
    {
      icon: 'scenes',
      color: '#5856d6',
      title: 'Scenes',
      key: '⇧X',
      detail: 'Bookmark regions of your tissue to jump between views like slides. Use ‹ / › (or , / .) to navigate, drag to reorder, and export all scenes as a multi-page PDF.',
    },
  ];

  const shortcuts: [string, string][] = [
    ['Back to Home', 'H'],
    ['Color preset 1–8', '1 – 8'],
    ['Eraser target (All / Pen / Sharpie / Fill)', 'E, 0–3'],
    ['Text Bold / Italic / Underline', `${MOD}B / ${MOD}I / ${MOD}U`],
    ['Text Strike / Inline code', `${MOD}⇧X / ${MOD}E`],
    ['Add scene', '⇧X'],
    ['Previous / Next scene', ', / .'],
    ['Toggle toolbar', 'Tab'],
    ['Undo / Redo', `${MOD}Z / ${MOD}⇧Z`],
    ['Copy / Paste', `${MOD}C / ${MOD}V`],
    ['Delete selected', '⌫ / Del'],
    ['Clear selection', 'Esc'],
    ['Import image', `${MOD}I`],
    ['Resize selected image', `${MOD}+ / ${MOD}-`],
    ['Pan canvas', 'Scroll / Space+Drag / Middle-Drag'],
    ['Zoom canvas', `${MOD}Scroll / Pinch`],
  ];

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="glass-surface modal-card help-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <div className="modal-brand">
            <img src={`${import.meta.env.BASE_URL}logo.png`} alt="Tissue Box" className="modal-logo-sm" />
            <div>
              <h2>Tissue Box Guide</h2>
              <p>Quick sketching like on a café napkin — everything you need at a glance.</p>
            </div>
          </div>
          <button type="button" className="primary-pill-btn" onClick={onClose}>
            Done
          </button>
        </div>

        <div className="modal-body">
          <section className="help-section">
            <h3>Drawing Tools</h3>
            <div className="help-card">
              {tools.map((t) => (
                <div key={t.title} className="tool-guide-row">
                  <div className="tool-guide-badge" style={{ backgroundColor: `${t.color}20`, color: t.color }}>
                    <Icon name={t.icon} size={17} />
                  </div>
                  <div className="tool-guide-text">
                    <div className="tool-guide-title">
                      <span>{t.title}</span>
                      <kbd>{t.key}</kbd>
                    </div>
                    <p>{t.detail}</p>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="help-section">
            <h3>Keyboard Shortcuts</h3>
            <div className="help-card shortcuts-grid">
              {shortcuts.map(([label, keys]) => (
                <div key={label} className="shortcut-row">
                  <span>{label}</span>
                  <kbd>{keys}</kbd>
                </div>
              ))}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
};

export const AboutModal: React.FC<{ onClose: () => void }> = ({ onClose }) => (
  <div className="modal-backdrop" onClick={onClose}>
    <div className="glass-surface modal-card about-modal" onClick={(e) => e.stopPropagation()}>
      <div className="modal-header">
        <h2>About Tissue Box</h2>
        <button type="button" className="primary-pill-btn" onClick={onClose}>
          Done
        </button>
      </div>
      <div className="modal-body about-body">
        <img src={`${import.meta.env.BASE_URL}logo.png`} alt="Tissue Box" className="about-logo" />
        <h1>Tissue Box</h1>
        <div className="about-version">Version 1.6.0 (Web / PWA)</div>
        <p className="about-tagline">
          Like a café napkin for quick sketching — capture and convey ideas effortlessly on Mac, iPad, Windows, Linux, and the Web.
        </p>
        <a
          className="glass-capsule about-link"
          href="https://github.com/pyjamacafe/Whiteboard"
          target="_blank"
          rel="noreferrer"
        >
          <Icon name="externalLink" size={14} />
          <span>github.com/pyjamacafe/Whiteboard</span>
        </a>

        <div className="license-box">
          <h4>MIT License</h4>
          <pre>{`Copyright (c) 2025-2026 Piyush Itankar

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.`}</pre>
        </div>
      </div>
    </div>
  </div>
);

interface ConfirmModalProps {
  title: string;
  message: string;
  confirmLabel: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export const ConfirmModal: React.FC<ConfirmModalProps> = ({
  title,
  message,
  confirmLabel,
  destructive = true,
  onConfirm,
  onCancel,
}) => (
  <div className="modal-backdrop" onClick={onCancel}>
    <div className="glass-surface modal-card confirm-modal" onClick={(e) => e.stopPropagation()}>
      <h3>{title}</h3>
      <p>{message}</p>
      <div className="confirm-actions">
        <button type="button" className="secondary-pill-btn" onClick={onCancel}>
          Cancel
        </button>
        <button
          type="button"
          className={destructive ? 'danger-pill-btn' : 'primary-pill-btn'}
          onClick={onConfirm}
        >
          {confirmLabel}
        </button>
      </div>
    </div>
  </div>
);

interface PromptModalProps {
  title: string;
  placeholder: string;
  initialValue: string;
  submitLabel: string;
  onSubmit: (value: string) => void;
  onCancel: () => void;
}

export const PromptModal: React.FC<PromptModalProps> = ({
  title,
  placeholder,
  initialValue,
  submitLabel,
  onSubmit,
  onCancel,
}) => {
  const [value, setValue] = React.useState(initialValue);
  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <form
        className="glass-surface modal-card confirm-modal"
        onClick={(e) => e.stopPropagation()}
        onSubmit={(e) => {
          e.preventDefault();
          const trimmed = value.trim();
          if (trimmed) onSubmit(trimmed);
        }}
      >
        <h3>{title}</h3>
        <input
          autoFocus
          className="modal-text-input"
          placeholder={placeholder}
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
        <div className="confirm-actions">
          <button type="button" className="secondary-pill-btn" onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="primary-pill-btn" disabled={!value.trim()}>
            {submitLabel}
          </button>
        </div>
      </form>
    </div>
  );
};
