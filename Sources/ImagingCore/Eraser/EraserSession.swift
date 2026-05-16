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
