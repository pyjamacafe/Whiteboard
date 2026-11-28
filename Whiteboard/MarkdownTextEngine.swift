import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Markdown AST & Shortcut Formatting Helper

enum MarkdownLineKind: Equatable, Sendable {
    case paragraph
    case heading(level: Int) // 1...3
    case bullet(indentLevel: Int)
    case numbered(marker: String, indentLevel: Int)
    case checklist(checked: Bool, indentLevel: Int)
    case blockquote
}

struct MarkdownSpan: Equatable, Sendable {
    var text: String
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false
    var isCode: Bool = false
}

struct MarkdownLine: Equatable, Sendable {
    var kind: MarkdownLineKind
    var spans: [MarkdownSpan]

    var fontScale: CGFloat {
        switch kind {
        case .heading(let level):
            switch level {
            case 1: return 1.45
            case 2: return 1.25
            default: return 1.12
            }
        default:
            return 1.0
        }
    }

    var forcesBold: Bool {
        if case .heading = kind { return true }
        return false
    }

    var defaultsItalic: Bool {
        if case .blockquote = kind { return true }
        return false
    }
}

struct MarkdownFormatResult: Equatable, Sendable {
    let text: String
    let selectionLocation: Int
    let selectionLength: Int
}

enum MarkdownTextEngine {
    static let lineHeightMultiplier: CGFloat = 1.28
    static let codePaddingX: CGFloat = 4
    static let horizontalInset: CGFloat = 4
    static let verticalInset: CGFloat = 2

    // MARK: - Monospace Platform Font Helper

    #if os(iOS)
    static func monospaceFont(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard italic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if bold { traits.insert(.traitBold) }
        if let desc = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: desc, size: size)
        }
        // Fallback to Menlo italic/bold-italic if SF Mono italic descriptor unavailable
        let name = bold ? "Menlo-BoldItalic" : "Menlo-Italic"
        return UIFont(name: name, size: size) ?? base
    }
    #else
    static func monospaceFont(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard italic else { return base }
        let converted = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        if NSFontManager.shared.traits(of: converted).contains(.italicFontMask) {
            return converted
        }
        let name = bold ? "Menlo-BoldItalic" : "Menlo-Italic"
        return NSFont(name: name, size: size) ?? base
    }
    #endif

    // MARK: - Parsing

    static func parse(_ rawText: String) -> [MarkdownLine] {
        let rawLines = rawText.split(separator: "\n", omittingEmptySubsequences: false)
        return rawLines.map { parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> MarkdownLine {
        // Headings: #, ##, ### followed by space
        if line.hasPrefix("### ") {
            return MarkdownLine(kind: .heading(level: 3), spans: parseInline(String(line.dropFirst(4))))
        }
        if line.hasPrefix("## ") {
            return MarkdownLine(kind: .heading(level: 2), spans: parseInline(String(line.dropFirst(3))))
        }
        if line.hasPrefix("# ") {
            return MarkdownLine(kind: .heading(level: 1), spans: parseInline(String(line.dropFirst(2))))
        }

        // Blockquote
        if line.hasPrefix("> ") {
            return MarkdownLine(kind: .blockquote, spans: parseInline(String(line.dropFirst(2)), italic: true))
        }
        if line == ">" {
            return MarkdownLine(kind: .blockquote, spans: [])
        }

        // Count leading spaces for nested list indentation (2 spaces per level, up to 4)
        var leadingSpaces = 0
        for ch in line {
            if ch == " " { leadingSpaces += 1 }
            else if ch == "\t" { leadingSpaces += 2 }
            else { break }
        }
        let indentLevel = min(leadingSpaces / 2, 4)
        let trimmedStart = String(line.drop(while: { $0 == " " || $0 == "\t" }))

        // Checklist: - [ ] / - [x] / * [ ] / * [X]
        if trimmedStart.count >= 6 {
            let first = trimmedStart.first
            if first == "-" || first == "*" || first == "+" {
                let afterMarker = String(trimmedStart.dropFirst())
                if afterMarker.hasPrefix(" [ ] ") {
                    return MarkdownLine(
                        kind: .checklist(checked: false, indentLevel: indentLevel),
                        spans: parseInline(String(afterMarker.dropFirst(5)))
                    )
                }
                if afterMarker.hasPrefix(" [x] ") || afterMarker.hasPrefix(" [X] ") {
                    return MarkdownLine(
                        kind: .checklist(checked: true, indentLevel: indentLevel),
                        spans: parseInline(String(afterMarker.dropFirst(5)))
                    )
                }
            }
        }

        // Bullet list: -, *, + followed by space
        if trimmedStart.hasPrefix("- ") || trimmedStart.hasPrefix("* ") || trimmedStart.hasPrefix("+ ") {
            return MarkdownLine(
                kind: .bullet(indentLevel: indentLevel),
                spans: parseInline(String(trimmedStart.dropFirst(2)))
            )
        }

        // Numbered list: 1. item
        if let dotIdx = trimmedStart.firstIndex(of: ".") {
            let digits = trimmedStart[..<dotIdx]
            let afterDot = trimmedStart.index(after: dotIdx)
            if !digits.isEmpty,
               digits.count <= 4,
               digits.allSatisfy(\.isNumber),
               afterDot < trimmedStart.endIndex,
               trimmedStart[afterDot] == " " {
                let contentStart = trimmedStart.index(after: afterDot)
                return MarkdownLine(
                    kind: .numbered(marker: "\(digits).", indentLevel: indentLevel),
                    spans: parseInline(String(trimmedStart[contentStart...]))
                )
            }
        }

        return MarkdownLine(kind: .paragraph, spans: parseInline(line))
    }

    private static func parseInline(
        _ input: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) -> [MarkdownSpan] {
        var result: [MarkdownSpan] = []
        var buffer = ""

        func flushBuffer() {
            if !buffer.isEmpty {
                result.append(MarkdownSpan(
                    text: buffer,
                    isBold: bold,
                    isItalic: italic,
                    isUnderline: underline,
                    isStrikethrough: strikethrough,
                    isCode: false
                ))
                buffer = ""
            }
        }

        let chars = Array(input)
        let n = chars.count
        var i = 0

        func matches(_ token: [Character], at index: Int) -> Bool {
            guard index + token.count <= n else { return false }
            for k in 0..<token.count {
                if chars[index + k] != token[k] { return false }
            }
            return true
        }

        func matchesCaseInsensitive(_ token: [Character], at index: Int) -> Bool {
            guard index + token.count <= n else { return false }
            for k in 0..<token.count {
                if chars[index + k].lowercased() != token[k].lowercased() { return false }
            }
            return true
        }

        func findClosing(_ token: [Character], from start: Int, caseInsensitive: Bool = false) -> Int? {
            var j = start
            while j + token.count <= n {
                if chars[j] == "\\" {
                    j += 2
                    continue
                }
                let ok = caseInsensitive ? matchesCaseInsensitive(token, at: j) : matches(token, at: j)
                if ok { return j }
                j += 1
            }
            return nil
        }

        let uOpen: [Character] = ["<", "u", ">"]
        let uClose: [Character] = ["<", "/", "u", ">"]
        let tripleStar: [Character] = ["*", "*", "*"]
        let doubleStar: [Character] = ["*", "*"]
        let doubleTilde: [Character] = ["~", "~"]

        while i < n {
            let ch = chars[i]

            // Backslash escape
            if ch == "\\", i + 1 < n {
                let next = chars[i + 1]
                if "*_~`#<>\\[]-+".contains(next) {
                    buffer.append(next)
                    i += 2
                    continue
                }
            }

            // Inline code: `...`
            if ch == "`" {
                if let closeIdx = findClosing(["`"], from: i + 1), closeIdx > i + 1 {
                    flushBuffer()
                    let codeText = String(chars[(i + 1)..<closeIdx])
                    result.append(MarkdownSpan(
                        text: codeText,
                        isBold: bold,
                        isItalic: italic,
                        isUnderline: underline,
                        isStrikethrough: strikethrough,
                        isCode: true
                    ))
                    i = closeIdx + 1
                    continue
                }
            }

            // Underline: <u>...</u>
            if matchesCaseInsensitive(uOpen, at: i),
               let closeIdx = findClosing(uClose, from: i + 3, caseInsensitive: true),
               closeIdx > i + 3 {
                flushBuffer()
                let inner = String(chars[(i + 3)..<closeIdx])
                result.append(contentsOf: parseInline(
                    inner,
                    bold: bold,
                    italic: italic,
                    underline: true,
                    strikethrough: strikethrough
                ))
                i = closeIdx + 4
                continue
            }

            // Bold + Italic: ***...***
            if matches(tripleStar, at: i),
               let closeIdx = findClosing(tripleStar, from: i + 3),
               closeIdx > i + 3 {
                flushBuffer()
                let inner = String(chars[(i + 3)..<closeIdx])
                result.append(contentsOf: parseInline(
                    inner,
                    bold: true,
                    italic: true,
                    underline: underline,
                    strikethrough: strikethrough
                ))
                i = closeIdx + 3
                continue
            }

            // Bold: **...**
            if matches(doubleStar, at: i),
               let closeIdx = findClosing(doubleStar, from: i + 2),
               closeIdx > i + 2 {
                flushBuffer()
                let inner = String(chars[(i + 2)..<closeIdx])
                result.append(contentsOf: parseInline(
                    inner,
                    bold: true,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough
                ))
                i = closeIdx + 2
                continue
            }

            // Strikethrough: ~~...~~
            if matches(doubleTilde, at: i),
               let closeIdx = findClosing(doubleTilde, from: i + 2),
               closeIdx > i + 2 {
                flushBuffer()
                let inner = String(chars[(i + 2)..<closeIdx])
                result.append(contentsOf: parseInline(
                    inner,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: true
                ))
                i = closeIdx + 2
                continue
            }

            // Italic: *...* (must not be ** and inner must not start/end with space)
            if ch == "*", !(i + 1 < n && chars[i + 1] == "*"), i + 1 < n, chars[i + 1] != " " {
                var j = i + 1
                var closeIdx: Int?
                while j < n {
                    if chars[j] == "\\" {
                        j += 2
                        continue
                    }
                    if chars[j] == "*" {
                        if j + 1 < n && chars[j + 1] == "*" {
                            j += 2
                            continue
                        }
                        if j > i + 1 && chars[j - 1] != " " {
                            closeIdx = j
                            break
                        }
                    }
                    j += 1
                }
                if let closeIdx {
                    flushBuffer()
                    let inner = String(chars[(i + 1)..<closeIdx])
                    result.append(contentsOf: parseInline(
                        inner,
                        bold: bold,
                        italic: true,
                        underline: underline,
                        strikethrough: strikethrough
                    ))
                    i = closeIdx + 1
                    continue
                }
            }

            // Italic: _..._ (word-boundary safe so snake_case stays literal)
            if ch == "_" {
                let prevIsWord = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                if !prevIsWord, i + 1 < n, chars[i + 1] != " ", chars[i + 1] != "_" {
                    var j = i + 1
                    var closeIdx: Int?
                    while j < n {
                        if chars[j] == "\\" {
                            j += 2
                            continue
                        }
                        if chars[j] == "_" {
                            let nextIsWord = j + 1 < n && (chars[j + 1].isLetter || chars[j + 1].isNumber)
                            if !nextIsWord && j > i + 1 && chars[j - 1] != " " {
                                closeIdx = j
                                break
                            }
                        }
                        j += 1
                    }
                    if let closeIdx {
                        flushBuffer()
                        let inner = String(chars[(i + 1)..<closeIdx])
                        result.append(contentsOf: parseInline(
                            inner,
                            bold: bold,
                            italic: true,
                            underline: underline,
                            strikethrough: strikethrough
                        ))
                        i = closeIdx + 1
                        continue
                    }
                }
            }

            buffer.append(ch)
            i += 1
        }

        flushBuffer()
        return result
    }

    // MARK: - Formatting Shortcut Toggle Helper (UTF-16 NSRange compatible)

    static func toggleWrap(
        in text: String,
        selection: NSRange,
        open: String,
        close: String
    ) -> MarkdownFormatResult {
        let ns = text as NSString
        let len = ns.length
        let loc = max(0, min(selection.location, len))
        let selLen = max(0, min(selection.length, len - loc))
        let openNS = open as NSString
        let closeNS = close as NSString
        let openLen = openNS.length
        let closeLen = closeNS.length

        let before = ns.substring(to: loc)
        let selected = ns.substring(with: NSRange(location: loc, length: selLen))
        let after = ns.substring(from: loc + selLen)

        if selLen > 0 {
            // Case A: Already wrapped immediately outside the selection -> unwrap
            if loc >= openLen,
               loc + selLen + closeLen <= len,
               ns.substring(with: NSRange(location: loc - openLen, length: openLen)) == open,
               ns.substring(with: NSRange(location: loc + selLen, length: closeLen)) == close {
                let newText = ns.substring(to: loc - openLen) + selected + ns.substring(from: loc + selLen + closeLen)
                return MarkdownFormatResult(text: newText, selectionLocation: loc - openLen, selectionLength: selLen)
            }
            // Case B: Selection itself includes the open/close markers -> unwrap
            if selLen >= openLen + closeLen,
               selected.hasPrefix(open),
               selected.hasSuffix(close) {
                let innerLen = selLen - openLen - closeLen
                let inner = (selected as NSString).substring(with: NSRange(location: openLen, length: innerLen))
                let newText = before + inner + after
                return MarkdownFormatResult(text: newText, selectionLocation: loc, selectionLength: innerLen)
            }
            // Case C: Wrap selection
            let newText = before + open + selected + close + after
            return MarkdownFormatResult(text: newText, selectionLocation: loc + openLen, selectionLength: selLen)
        } else {
            // Collapsed cursor between empty markers -> unwrap
            if loc >= openLen,
               loc + closeLen <= len,
               ns.substring(with: NSRange(location: loc - openLen, length: openLen)) == open,
               ns.substring(with: NSRange(location: loc, length: closeLen)) == close {
                let newText = ns.substring(to: loc - openLen) + ns.substring(from: loc + closeLen)
                return MarkdownFormatResult(text: newText, selectionLocation: loc - openLen, selectionLength: 0)
            }
            // Insert marker pair and place caret in the middle
            let newText = before + open + close + after
            return MarkdownFormatResult(text: newText, selectionLocation: loc + openLen, selectionLength: 0)
        }
    }

    // MARK: - Measurement & Drawing

    static func measurePrefixWidth(for kind: MarkdownLineKind, fontSize: CGFloat, baseBold: Bool) -> CGFloat {
        switch kind {
        case .paragraph, .heading:
            return 0
        case .blockquote:
            return fontSize * 0.85
        case .bullet(let indent):
            return CGFloat(indent) * fontSize * 1.1 + fontSize * 1.05
        case .checklist(_, let indent):
            return CGFloat(indent) * fontSize * 1.1 + fontSize * 1.4
        case .numbered(let marker, let indent):
            let text = marker + " "
            let w = measureRunWidth(text, fontSize: fontSize, bold: baseBold, italic: false)
            return CGFloat(indent) * fontSize * 1.1 + w
        }
    }

    static func measureRunWidth(_ text: String, fontSize: CGFloat, bold: Bool, italic: Bool) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = monospaceFont(size: fontSize, bold: bold, italic: italic)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func measureLabelSize(text: String, fontSize: CGFloat, baseBold: Bool) -> CGSize {
        let parsed = parse(text)
        var maxW: CGFloat = 0
        var totalH: CGFloat = 0

        for line in parsed {
            let lineFontSize = fontSize * line.fontScale
            let lineHeight = lineFontSize * lineHeightMultiplier
            var lineW = measurePrefixWidth(for: line.kind, fontSize: lineFontSize, baseBold: baseBold)
            if line.spans.isEmpty {
                lineW = max(lineW, measureRunWidth(" ", fontSize: lineFontSize, bold: baseBold || line.forcesBold, italic: line.defaultsItalic))
            } else {
                for span in line.spans {
                    let isBold = baseBold || line.forcesBold || span.isBold
                    let isItalic = line.defaultsItalic || span.isItalic
                    let w = measureRunWidth(span.text, fontSize: lineFontSize, bold: isBold, italic: isItalic)
                    lineW += w + (span.isCode ? codePaddingX * 2 : 0)
                }
            }
            if lineW > maxW { maxW = lineW }
            totalH += lineHeight
        }

        let minLineH = fontSize * lineHeightMultiplier
        return CGSize(
            width: max(24, ceil(maxW) + horizontalInset * 2),
            height: max(minLineH, ceil(totalH) + verticalInset * 2)
        )
    }

    static func drawTextLabel(
        _ label: TextLabel,
        in ctx: CGContext,
        color: Color
    ) {
        guard !label.text.isEmpty else { return }
        let parsed = parse(label.text)
        let center = label.cgCenter
        let cgInk = StrokeRenderer.cgColor(from: color)

        ctx.saveGState()
        ctx.setBlendMode(.normal)
        if label.rotation != 0 {
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: label.cgRotation)
            ctx.translateBy(x: -center.x, y: -center.y)
        }

        #if os(iOS)
        let platformColor = UIColor(color)
        let mutedColor = platformColor.withAlphaComponent(0.75)
        let codeBgColor = platformColor.withAlphaComponent(0.12).cgColor
        UIGraphicsPushContext(ctx)
        #else
        let platformColor = NSColor(color)
        let mutedColor = platformColor.withAlphaComponent(0.75)
        let codeBgColor = platformColor.withAlphaComponent(0.12).cgColor
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        #endif

        var cursorY = label.cgPosition.y + verticalInset
        let startX = label.cgPosition.x + horizontalInset

        for line in parsed {
            let lineFontSize = label.fontSize * line.fontScale
            let lineHeight = lineFontSize * lineHeightMultiplier
            let prefixW = measurePrefixWidth(for: line.kind, fontSize: lineFontSize, baseBold: label.isBold)

            // Draw block prefix decoration
            switch line.kind {
            case .paragraph, .heading:
                break
            case .blockquote:
                let barRect = CGRect(
                    x: startX + 2,
                    y: cursorY + lineFontSize * 0.12,
                    width: max(2, lineFontSize * 0.12),
                    height: lineHeight * 0.78
                )
                ctx.saveGState()
                ctx.setFillColor(cgInk.copy(alpha: 0.45) ?? cgInk)
                ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                ctx.fillPath()
                ctx.restoreGState()
            case .bullet(let indent):
                let bulletX = startX + CGFloat(indent) * lineFontSize * 1.1 + lineFontSize * 0.35
                let bulletY = cursorY + lineFontSize * 0.62
                let r = max(2, lineFontSize * 0.14)
                ctx.saveGState()
                ctx.setFillColor(cgInk)
                ctx.fillEllipse(in: CGRect(x: bulletX - r, y: bulletY - r, width: r * 2, height: r * 2))
                ctx.restoreGState()
            case .numbered(let marker, let indent):
                let markerX = startX + CGFloat(indent) * lineFontSize * 1.1
                let markerFont = monospaceFont(size: lineFontSize, bold: label.isBold, italic: false)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: markerFont,
                    .foregroundColor: platformColor,
                ]
                (marker as NSString).draw(at: CGPoint(x: markerX, y: cursorY), withAttributes: attrs)
            case .checklist(let checked, let indent):
                let boxSize = max(10, lineFontSize * 0.76)
                let boxX = startX + CGFloat(indent) * lineFontSize * 1.1 + lineFontSize * 0.1
                let boxY = cursorY + (lineFontSize * 1.15 - boxSize) / 2
                let boxRect = CGRect(x: boxX, y: boxY, width: boxSize, height: boxSize)
                let boxPath = CGPath(roundedRect: boxRect, cornerWidth: max(2, boxSize * 0.2), cornerHeight: max(2, boxSize * 0.2), transform: nil)
                ctx.saveGState()
                if checked {
                    ctx.setFillColor(cgInk.copy(alpha: 0.18) ?? cgInk)
                    ctx.addPath(boxPath)
                    ctx.fillPath()
                }
                ctx.setStrokeColor(cgInk)
                ctx.setLineWidth(max(1.2, lineFontSize * 0.08))
                ctx.addPath(boxPath)
                ctx.strokePath()
                if checked {
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: boxRect.minX + boxSize * 0.22, y: boxRect.minY + boxSize * 0.52))
                    ctx.addLine(to: CGPoint(x: boxRect.minX + boxSize * 0.44, y: boxRect.minY + boxSize * 0.74))
                    ctx.addLine(to: CGPoint(x: boxRect.minX + boxSize * 0.80, y: boxRect.minY + boxSize * 0.28))
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }

            // Draw inline spans
            var cursorX = startX + prefixW
            let isCheckedChecklist: Bool = {
                if case .checklist(let checked, _) = line.kind { return checked }
                return false
            }()

            for span in line.spans {
                let isBold = label.isBold || line.forcesBold || span.isBold
                let isItalic = line.defaultsItalic || span.isItalic
                let font = monospaceFont(size: lineFontSize, bold: isBold, italic: isItalic)
                let spanText = span.text as NSString
                let runSize = spanText.size(withAttributes: [.font: font])

                if span.isCode {
                    let pillRect = CGRect(
                        x: cursorX,
                        y: cursorY + lineFontSize * 0.04,
                        width: runSize.width + codePaddingX * 2,
                        height: max(runSize.height, lineFontSize * 1.12)
                    )
                    ctx.saveGState()
                    ctx.setFillColor(codeBgColor)
                    ctx.addPath(CGPath(roundedRect: pillRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
                    ctx.fillPath()
                    ctx.restoreGState()
                    cursorX += codePaddingX
                }

                let fgColor = (line.kind == .blockquote || isCheckedChecklist) ? mutedColor : platformColor
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: fgColor,
                ]
                if span.isUnderline {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if span.isStrikethrough || isCheckedChecklist {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }

                spanText.draw(at: CGPoint(x: cursorX, y: cursorY), withAttributes: attrs)
                cursorX += runSize.width + (span.isCode ? codePaddingX : 0)
            }

            cursorY += lineHeight
        }

        #if os(iOS)
        UIGraphicsPopContext()
        #else
        NSGraphicsContext.restoreGraphicsState()
        #endif
        ctx.restoreGState()
    }
}
