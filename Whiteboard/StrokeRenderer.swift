import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared Core Graphics rendering for exports (PNG/PDF) and board thumbnails so
/// exported output matches the live canvas (Catmull-Rom smoothing, theme presets,
/// Sharpie glow/core, and placed images on both iOS and macOS).
enum StrokeRenderer {

    static func cgColor(from color: Color) -> CGColor {
        #if os(iOS)
        return UIColor(color).cgColor
        #else
        return NSColor(color).usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 0, alpha: 1)
        #endif
    }

    static func resolveDisplayColor(
        for stroke: Stroke,
        penPresets: [Color],
        sharpiePresets: [Color]
    ) -> Color {
        if stroke.presetIndex >= 0 {
            if stroke.isSharpie {
                if stroke.presetIndex < sharpiePresets.count {
                    return sharpiePresets[stroke.presetIndex]
                }
            } else if stroke.presetIndex < penPresets.count {
                return penPresets[stroke.presetIndex]
            }
        }
        return stroke.color.color
    }

    static func drawPlacedImage(_ img: PlacedImage, in ctx: CGContext, cachedImage: PlatformImage? = nil) {
        let rect = CGRect(origin: img.cgPosition, size: img.cgSize)
        guard rect.width > 0, rect.height > 0 else { return }

        let cgImage: CGImage?
        #if os(iOS)
        let uiImage = cachedImage ?? UIImage(data: img.imageData)
        cgImage = uiImage?.cgImage
        #else
        let nsImage = cachedImage ?? NSImage(data: img.imageData)
        var proposed = NSRect(origin: .zero, size: rect.size)
        cgImage = nsImage?.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        #endif

        guard let cgImage else { return }
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func drawStroke(
        _ stroke: Stroke,
        in ctx: CGContext,
        penPresets: [Color],
        sharpiePresets: [Color],
        isDarkMode: Bool,
        eraserWidthOverride: CGFloat? = nil,
        cachedPath: CGPath? = nil
    ) {
        guard let path = cachedPath ?? GeometryEngine.makeCGPath(for: stroke) else { return }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if stroke.isEraser {
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(eraserWidthOverride ?? stroke.lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        } else if stroke.isSharpie {
            ctx.setBlendMode(.normal)
            let glowColor = resolveDisplayColor(for: stroke, penPresets: penPresets, sharpiePresets: sharpiePresets)
            ctx.setStrokeColor(cgColor(from: glowColor))
            ctx.setLineWidth(stroke.lineWidth + 3)
            ctx.addPath(path)
            ctx.strokePath()

            let baseColor = isDarkMode ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
            ctx.setStrokeColor(baseColor)
            ctx.setLineWidth(stroke.lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        } else {
            ctx.setBlendMode(.normal)
            let color = resolveDisplayColor(for: stroke, penPresets: penPresets, sharpiePresets: sharpiePresets)
            ctx.setStrokeColor(cgColor(from: color))
            ctx.setLineWidth(stroke.lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - PNG Export

    static func pngData(
        strokes: [Stroke],
        placedImages: [PlacedImage],
        penPresets: [Color],
        sharpiePresets: [Color],
        isDarkMode: Bool,
        size: CGSize,
        offset: CGPoint = .zero,
        scale: CGFloat = 3
    ) -> Data? {
        guard scale > 0, size.width > 0, size.height > 0 else { return nil }
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        guard w > 0, h > 0, w <= 8192, h <= 8192 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Transparent background; flip Y to match canvas (y-down) coordinate space.
        ctx.translateBy(x: -offset.x * scale, y: CGFloat(h) + offset.y * scale)
        ctx.scaleBy(x: scale, y: -scale)

        for img in placedImages {
            drawPlacedImage(img, in: ctx)
        }
        for s in strokes {
            drawStroke(s, in: ctx, penPresets: penPresets, sharpiePresets: sharpiePresets, isDarkMode: isDarkMode)
        }

        guard let image = ctx.makeImage(),
              let cfData = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(cfData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return cfData as Data
    }

    // MARK: - PDF Export

    static func pdfData(
        strokes: [Stroke],
        placedImages: [PlacedImage],
        penPresets: [Color],
        sharpiePresets: [Color],
        isDarkMode: Bool,
        size: CGSize,
        offset: CGPoint = .zero
    ) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let cfData = CFDataCreateMutable(nil, 0),
              let consumer = CGDataConsumer(data: cfData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        pdf.beginPDFPage(nil)
        pdf.setFillColor(isDarkMode ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
        pdf.fill(CGRect(origin: .zero, size: size))
        pdf.translateBy(x: -offset.x, y: size.height + offset.y)
        pdf.scaleBy(x: 1, y: -1)

        for img in placedImages {
            drawPlacedImage(img, in: pdf)
        }
        for s in strokes {
            drawStroke(s, in: pdf, penPresets: penPresets, sharpiePresets: sharpiePresets, isDarkMode: isDarkMode)
        }
        pdf.endPDFPage()
        pdf.closePDF()
        return cfData as Data
    }

    // MARK: - Thumbnail

    static func renderThumbnail(
        strokes: [Stroke],
        placedImages: [PlacedImage],
        penPresets: [Color],
        sharpiePresets: [Color],
        isDarkMode: Bool,
        size: CGSize
    ) -> PlatformImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return nil }
        guard let bounds = GeometryEngine.boundingBox(of: strokes, images: placedImages, padding: 10) else {
            return nil
        }

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(isDarkMode ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let sc = min(CGFloat(w) / bounds.width, CGFloat(h) / bounds.height) * 0.9
        let ox = (CGFloat(w) - bounds.width * sc) / 2 - bounds.minX * sc
        let oy = (CGFloat(h) - bounds.height * sc) / 2 - bounds.minY * sc

        ctx.translateBy(x: ox, y: CGFloat(h) - oy)
        ctx.scaleBy(x: sc, y: -sc)

        for img in placedImages {
            drawPlacedImage(img, in: ctx)
        }
        for s in strokes where !s.isEraser {
            drawStroke(s, in: ctx, penPresets: penPresets, sharpiePresets: sharpiePresets, isDarkMode: isDarkMode)
        }

        guard let cgImg = ctx.makeImage() else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImg, size: size)
        #else
        return UIImage(cgImage: cgImg)
        #endif
    }
}

/// FileDocument wrapper used by SwiftUI `.fileExporter`.
struct ExportDocument: FileDocument {
    let data: Data

    static var wbType: UTType { UTType(filenameExtension: "wb") ?? .data }
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.data, .png, .pdf, wbType] }

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
