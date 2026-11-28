// Shared Canvas Markdown parser, layout metrics, and formatting shortcut helper
// Mirrors Whiteboard/MarkdownTextEngine.swift for 1:1 Apple <-> Web parity.

export const MONOSPACE_FONT_FAMILY =
  'ui-monospace, "SF Mono", Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace';

export const MARKDOWN_LINE_HEIGHT_MULT = 1.28;
export const MARKDOWN_CODE_PADDING_X = 4;
export const MARKDOWN_HORIZONTAL_INSET = 4;
export const MARKDOWN_VERTICAL_INSET = 2;

export type MarkdownLineKind =
  | { type: 'paragraph' }
  | { type: 'heading'; level: 1 | 2 | 3 }
  | { type: 'bullet'; indentLevel: number }
  | { type: 'numbered'; marker: string; indentLevel: number }
  | { type: 'checklist'; checked: boolean; indentLevel: number }
  | { type: 'blockquote' };

export interface MarkdownSpan {
  text: string;
  isBold: boolean;
  isItalic: boolean;
  isUnderline: boolean;
  isStrikethrough: boolean;
  isCode: boolean;
}

export interface MarkdownLine {
  kind: MarkdownLineKind;
  spans: MarkdownSpan[];
  fontScale: number;
  forcesBold: boolean;
  defaultsItalic: boolean;
}

export interface MarkdownFormatResult {
  text: string;
  selectionStart: number;
  selectionEnd: number;
}

export function monospaceCanvasFont(size: number, bold: boolean, italic: boolean): string {
  const style = italic ? 'italic ' : '';
  const weight = bold ? '700 ' : '400 ';
  return `${style}${weight}${size}px ${MONOSPACE_FONT_FAMILY}`;
}

function makeLine(kind: MarkdownLineKind, spans: MarkdownSpan[]): MarkdownLine {
  let fontScale = 1;
  let forcesBold = false;
  let defaultsItalic = false;
  if (kind.type === 'heading') {
    fontScale = kind.level === 1 ? 1.45 : kind.level === 2 ? 1.25 : 1.12;
    forcesBold = true;
  } else if (kind.type === 'blockquote') {
    defaultsItalic = true;
  }
  return { kind, spans, fontScale, forcesBold, defaultsItalic };
}

function isWordChar(ch: string): boolean {
  return /[A-Za-z0-9]/.test(ch);
}

function parseInline(
  input: string,
  bold = false,
  italic = false,
  underline = false,
  strikethrough = false
): MarkdownSpan[] {
  const result: MarkdownSpan[] = [];
  let buffer = '';

  const flush = () => {
    if (buffer.length > 0) {
      result.push({
        text: buffer,
        isBold: bold,
        isItalic: italic,
        isUnderline: underline,
        isStrikethrough: strikethrough,
        isCode: false,
      });
      buffer = '';
    }
  };

  const n = input.length;
  let i = 0;

  const findClosing = (token: string, from: number, caseInsensitive = false): number => {
    const tLower = caseInsensitive ? token.toLowerCase() : token;
    let j = from;
    while (j + token.length <= n) {
      if (input[j] === '\\') {
        j += 2;
        continue;
      }
      const slice = input.slice(j, j + token.length);
      if ((caseInsensitive ? slice.toLowerCase() : slice) === tLower) {
        return j;
      }
      j += 1;
    }
    return -1;
  };

  while (i < n) {
    const ch = input[i];

    // Backslash escape
    if (ch === '\\' && i + 1 < n) {
      const next = input[i + 1];
      if ('*_~`#<>\\[]-+'.includes(next)) {
        buffer += next;
        i += 2;
        continue;
      }
    }

    // Inline code: `...`
    if (ch === '`') {
      const closeIdx = findClosing('`', i + 1);
      if (closeIdx > i + 1) {
        flush();
        result.push({
          text: input.slice(i + 1, closeIdx),
          isBold: bold,
          isItalic: italic,
          isUnderline: underline,
          isStrikethrough: strikethrough,
          isCode: true,
        });
        i = closeIdx + 1;
        continue;
      }
    }

    // Underline: <u>...</u>
    if (input.slice(i, i + 3).toLowerCase() === '<u>') {
      const closeIdx = findClosing('</u>', i + 3, true);
      if (closeIdx > i + 3) {
        flush();
        result.push(
          ...parseInline(input.slice(i + 3, closeIdx), bold, italic, true, strikethrough)
        );
        i = closeIdx + 4;
        continue;
      }
    }

    // Bold + Italic: ***...***
    if (input.startsWith('***', i)) {
      const closeIdx = findClosing('***', i + 3);
      if (closeIdx > i + 3) {
        flush();
        result.push(
          ...parseInline(input.slice(i + 3, closeIdx), true, true, underline, strikethrough)
        );
        i = closeIdx + 3;
        continue;
      }
    }

    // Bold: **...**
    if (input.startsWith('**', i)) {
      const closeIdx = findClosing('**', i + 2);
      if (closeIdx > i + 2) {
        flush();
        result.push(
          ...parseInline(input.slice(i + 2, closeIdx), true, italic, underline, strikethrough)
        );
        i = closeIdx + 2;
        continue;
      }
    }

    // Strikethrough: ~~...~~
    if (input.startsWith('~~', i)) {
      const closeIdx = findClosing('~~', i + 2);
      if (closeIdx > i + 2) {
        flush();
        result.push(
          ...parseInline(input.slice(i + 2, closeIdx), bold, italic, underline, true)
        );
        i = closeIdx + 2;
        continue;
      }
    }

    // Italic: *...*
    if (ch === '*' && input[i + 1] !== '*' && i + 1 < n && input[i + 1] !== ' ') {
      let j = i + 1;
      let closeIdx = -1;
      while (j < n) {
        if (input[j] === '\\') {
          j += 2;
          continue;
        }
        if (input[j] === '*') {
          if (input[j + 1] === '*') {
            j += 2;
            continue;
          }
          if (j > i + 1 && input[j - 1] !== ' ') {
            closeIdx = j;
            break;
          }
        }
        j += 1;
      }
      if (closeIdx > i + 1) {
        flush();
        result.push(
          ...parseInline(input.slice(i + 1, closeIdx), bold, true, underline, strikethrough)
        );
        i = closeIdx + 1;
        continue;
      }
    }

    // Italic: _..._ (word-boundary safe so snake_case stays literal)
    if (ch === '_') {
      const prevIsWord = i > 0 && isWordChar(input[i - 1]);
      if (!prevIsWord && i + 1 < n && input[i + 1] !== ' ' && input[i + 1] !== '_') {
        let j = i + 1;
        let closeIdx = -1;
        while (j < n) {
          if (input[j] === '\\') {
            j += 2;
            continue;
          }
          if (input[j] === '_') {
            const nextIsWord = j + 1 < n && isWordChar(input[j + 1]);
            if (!nextIsWord && j > i + 1 && input[j - 1] !== ' ') {
              closeIdx = j;
              break;
            }
          }
          j += 1;
        }
        if (closeIdx > i + 1) {
          flush();
          result.push(
            ...parseInline(input.slice(i + 1, closeIdx), bold, true, underline, strikethrough)
          );
          i = closeIdx + 1;
          continue;
        }
      }
    }

    buffer += ch;
    i += 1;
  }

  flush();
  return result;
}

function parseLine(line: string): MarkdownLine {
  if (line.startsWith('### ')) {
    return makeLine({ type: 'heading', level: 3 }, parseInline(line.slice(4)));
  }
  if (line.startsWith('## ')) {
    return makeLine({ type: 'heading', level: 2 }, parseInline(line.slice(3)));
  }
  if (line.startsWith('# ')) {
    return makeLine({ type: 'heading', level: 1 }, parseInline(line.slice(2)));
  }
  if (line.startsWith('> ')) {
    return makeLine({ type: 'blockquote' }, parseInline(line.slice(2), false, true));
  }
  if (line === '>') {
    return makeLine({ type: 'blockquote' }, []);
  }

  let leadingSpaces = 0;
  let startIdx = 0;
  while (startIdx < line.length) {
    if (line[startIdx] === ' ') {
      leadingSpaces += 1;
      startIdx += 1;
    } else if (line[startIdx] === '\t') {
      leadingSpaces += 2;
      startIdx += 1;
    } else {
      break;
    }
  }
  const indentLevel = Math.min(Math.floor(leadingSpaces / 2), 4);
  const trimmedStart = line.slice(startIdx);

  // Checklist: - [ ] / - [x]
  const checkMatch = /^[-*+]\s+\[([ xX])\]\s+(.*)$/.exec(trimmedStart);
  if (checkMatch) {
    return makeLine(
      { type: 'checklist', checked: checkMatch[1].toLowerCase() === 'x', indentLevel },
      parseInline(checkMatch[2])
    );
  }

  // Bullet list
  if (trimmedStart.startsWith('- ') || trimmedStart.startsWith('* ') || trimmedStart.startsWith('+ ')) {
    return makeLine({ type: 'bullet', indentLevel }, parseInline(trimmedStart.slice(2)));
  }

  // Numbered list
  const numMatch = /^(\d{1,4}\.)\s+(.*)$/.exec(trimmedStart);
  if (numMatch) {
    return makeLine(
      { type: 'numbered', marker: numMatch[1], indentLevel },
      parseInline(numMatch[2])
    );
  }

  return makeLine({ type: 'paragraph' }, parseInline(line));
}

export function parseMarkdown(rawText: string): MarkdownLine[] {
  return rawText.split('\n').map(parseLine);
}

/**
 * Wraps or unwraps the selection with markdown markers (e.g. **bold**, *italic*, <u>underline</u>, ~~strike~~, `code`).
 */
export function toggleMarkdownWrap(
  text: string,
  selectionStart: number,
  selectionEnd: number,
  open: string,
  close: string
): MarkdownFormatResult {
  const len = text.length;
  const start = Math.max(0, Math.min(selectionStart, len));
  const end = Math.max(start, Math.min(selectionEnd, len));
  const openLen = open.length;
  const closeLen = close.length;

  const before = text.slice(0, start);
  const selected = text.slice(start, end);
  const after = text.slice(end);

  if (end > start) {
    // Already wrapped immediately outside selection -> unwrap
    if (
      start >= openLen &&
      end + closeLen <= len &&
      text.slice(start - openLen, start) === open &&
      text.slice(end, end + closeLen) === close
    ) {
      return {
        text: text.slice(0, start - openLen) + selected + text.slice(end + closeLen),
        selectionStart: start - openLen,
        selectionEnd: end - openLen,
      };
    }
    // Selection itself starts/ends with markers -> unwrap
    if (selected.length >= openLen + closeLen && selected.startsWith(open) && selected.endsWith(close)) {
      const inner = selected.slice(openLen, selected.length - closeLen);
      return {
        text: before + inner + after,
        selectionStart: start,
        selectionEnd: start + inner.length,
      };
    }
    // Wrap selection
    return {
      text: before + open + selected + close + after,
      selectionStart: start + openLen,
      selectionEnd: end + openLen,
    };
  }

  // Collapsed caret between empty markers -> unwrap
  if (
    start >= openLen &&
    start + closeLen <= len &&
    text.slice(start - openLen, start) === open &&
    text.slice(start, start + closeLen) === close
  ) {
    return {
      text: text.slice(0, start - openLen) + text.slice(start + closeLen),
      selectionStart: start - openLen,
      selectionEnd: start - openLen,
    };
  }

  // Insert marker pair with caret inside
  return {
    text: before + open + close + after,
    selectionStart: start + openLen,
    selectionEnd: start + openLen,
  };
}

export function measureMarkdownPrefixWidth(
  kind: MarkdownLineKind,
  fontSize: number,
  measureText: (text: string, size: number, bold: boolean, italic: boolean) => number,
  baseBold: boolean
): number {
  switch (kind.type) {
    case 'paragraph':
    case 'heading':
      return 0;
    case 'blockquote':
      return fontSize * 0.85;
    case 'bullet':
      return kind.indentLevel * fontSize * 1.1 + fontSize * 1.05;
    case 'checklist':
      return kind.indentLevel * fontSize * 1.1 + fontSize * 1.4;
    case 'numbered':
      return kind.indentLevel * fontSize * 1.1 + measureText(`${kind.marker} `, fontSize, baseBold, false);
  }
}
