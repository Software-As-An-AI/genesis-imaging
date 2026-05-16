import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Observation

/// Live editing session state for the manual eraser brush. Holds the
/// decoded source image, the in-flight stroke history, and the current
/// brush + viewport parameters.
///
/// Lifecycle:
///   - Created when "🖊 Düzenle" is tapped on a done row (sheet present).
///   - `load(from:)` decodes the PNG to a grayscale UInt8 buffer at full
///     resolution. Display proxy is generated lazily by the view layer.
///   - Strokes are appended in-memory; undo/redo manipulate the stack
///     via NSUndoManager registration in the view.
///   - Discarded on cancel (sheet dismissed without save).
///   - On save, `EraserApplier.compose(...)` flattens strokes into a copy
///     of the buffer, which is encoded by `OutputWriter.atomicWrite`.
///
/// Not `@MainActor`-isolated at the model level — the view binds it through
/// `@Bindable`, and stroke mutations happen on the main thread by virtue
/// of being SwiftUI UI events.
@Observable
public final class EraserSession {
    public let sourceURL: URL
    public let imageWidth: Int
    public let imageHeight: Int

    /// Full-resolution grayscale buffer (0 = black, 255 = white). Reference
    /// state — strokes are NOT applied to this buffer until save. View
    /// layer renders this + overlays strokes on top.
    public let baseBuffer: [UInt8]

    /// Stroke history. Append on stroke commit; remove last on undo.
    public var strokes: [BrushStroke] = []

    /// Brush diameter in image pixels (slider value × 2, since slider
    /// shows diameter but `BrushStroke.radius` stores half).
    public var brushDiameter: CGFloat = 60

    public var brushRadius: CGFloat { brushDiameter / 2 }

    public init(sourceURL: URL, baseBuffer: [UInt8], width: Int, height: Int) {
        self.sourceURL = sourceURL
        self.baseBuffer = baseBuffer
        self.imageWidth = width
        self.imageHeight = height
    }

    /// Sample the dominant background luminance in an annular ring around
    /// `center` (image-space), between `radius` and `radius * 1.6`. Returns
    /// the median value of the ring samples — picks "what the surrounding
    /// page color is" without touching the brush footprint itself.
    ///
    /// Pure white pages (coloring books) return ~255. Sepia / parchment /
    /// tinted pages return their actual luminance. Reads from `baseBuffer`
    /// (original decoded source), so prior strokes don't contaminate the
    /// sample even when strokes overlap.
    ///
    /// Used by `EraserEditorView` at stroke-start to pick a fill color
    /// that mimics the surrounding page rather than a hard white default.
    public func sampleBackgroundLuminance(near center: CGPoint, brushRadius: CGFloat) -> UInt8 {
        let inner = brushRadius
        let outer = brushRadius * 1.6
        let innerSquared = inner * inner
        let outerSquared = outer * outer

        // Bounding box for the annulus.
        let minX = max(0, Int(floor(center.x - outer)))
        let maxX = min(imageWidth - 1, Int(ceil(center.x + outer)))
        let minY = max(0, Int(floor(center.y - outer)))
        let maxY = min(imageHeight - 1, Int(ceil(center.y + outer)))
        if minX > maxX || minY > maxY { return 255 }

        // Sample with stride to stay fast (~few hundred reads max).
        let stride = max(1, Int((outer - inner) / 8))
        var samples: [UInt8] = []
        samples.reserveCapacity(256)
        var y = minY
        while y <= maxY {
            let dy = CGFloat(y) + 0.5 - center.y
            let dySquared = dy * dy
            var x = minX
            while x <= maxX {
                let dx = CGFloat(x) + 0.5 - center.x
                let distSquared = dx * dx + dySquared
                if distSquared >= innerSquared && distSquared <= outerSquared {
                    samples.append(baseBuffer[y * imageWidth + x])
                }
                x += stride
            }
            y += stride
        }

        if samples.isEmpty { return 255 }
        samples.sort()
        return samples[samples.count / 2]  // median
    }

    /// Decode the PNG at `url` into a grayscale UInt8 buffer and return a
    /// fresh session. Throws on decode failure — caller surfaces error.
    public static func load(from url: URL) throws -> EraserSession {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw EraserError.decodeFailed(url)
        }
        let w = cg.width
        let h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let cs = CGColorSpace(name: CGColorSpace.linearGray)
                ?? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        else { throw EraserError.bufferAllocationFailed }
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard let ctx = pixels.withUnsafeMutableBufferPointer({ buf -> CGContext? in
            CGContext(
                data: buf.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        }) else { throw EraserError.bufferAllocationFailed }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return EraserSession(sourceURL: url, baseBuffer: pixels, width: w, height: h)
    }

    public enum EraserError: Error, Equatable {
        case decodeFailed(URL)
        case bufferAllocationFailed
        case encodeFailed(URL)
    }
}
