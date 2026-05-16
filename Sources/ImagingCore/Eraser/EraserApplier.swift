import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Composes brush strokes onto a full-resolution grayscale buffer and
/// encodes the result as PNG. Pure stateless helpers — no SwiftUI, no
/// session state. Caller owns the buffer + stroke list.
public enum EraserApplier {

    /// Fill the brush stroke's footprint (a series of densified circle
    /// stamps) into `buffer` with value `fillColor` (default 255 = white).
    ///
    /// - Points are interpreted as image-space `(x, y)`. Sub-pixel positions
    ///   are floored to the nearest integer (sufficient for ≥10-px brushes
    ///   on 5K canvases; anti-aliasing not needed since pure-white fill).
    /// - Circle rasterization: bounding box + radius² test per pixel.
    /// - Densification: caller is expected to interpolate stroke points
    ///   so adjacent points are ≤ radius apart, avoiding gaps. The
    ///   `densify(_:radius:)` helper does this.
    public static func apply(
        stroke: BrushStroke,
        to buffer: inout [UInt8],
        width: Int, height: Int,
        fillColor: UInt8 = 255
    ) {
        let r = stroke.radius
        let rSquared = r * r
        for p in stroke.points {
            stampCircle(
                cx: p.x, cy: p.y, radiusSquared: rSquared,
                radius: r, buffer: &buffer,
                width: width, height: height,
                fillColor: fillColor
            )
        }
    }

    /// Apply a sequence of strokes in order. Convenience for save-time
    /// composition (caller passes the full undo-respecting strokes list).
    public static func compose(
        strokes: [BrushStroke],
        onto buffer: inout [UInt8],
        width: Int, height: Int,
        fillColor: UInt8 = 255
    ) {
        for stroke in strokes {
            apply(
                stroke: stroke,
                to: &buffer,
                width: width, height: height,
                fillColor: fillColor
            )
        }
    }

    /// Densify a sparse point list so consecutive points are within
    /// `step` pixels of each other. Linear interpolation; sufficient for
    /// brush strokes (Catmull-Rom would smooth tighter but adds
    /// implementation surface).
    public static func densify(_ points: [CGPoint], step: CGFloat) -> [CGPoint] {
        guard points.count >= 2, step > 0 else { return points }
        var out: [CGPoint] = [points[0]]
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist <= step {
                out.append(b)
                continue
            }
            let segments = Int((dist / step).rounded(.up))
            for s in 1...segments {
                let t = CGFloat(s) / CGFloat(segments)
                out.append(CGPoint(x: a.x + dx * t, y: a.y + dy * t))
            }
        }
        return out
    }

    // MARK: - Encode

    /// Encode the buffer as a grayscale PNG to `url`. Mirrors
    /// `LineArtEnhanceFilter.encodeGrayscalePNG` pattern.
    public static func encodePNG(
        buffer: [UInt8],
        width: Int, height: Int,
        to url: URL
    ) throws {
        let cs = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
            ?? CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        let bytesPerRow = width
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else {
            throw EraserSession.EraserError.encodeFailed(url)
        }
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { throw EraserSession.EraserError.encodeFailed(url) }
        guard let dst = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw EraserSession.EraserError.encodeFailed(url) }
        CGImageDestinationAddImage(dst, cgImage, nil)
        guard CGImageDestinationFinalize(dst) else {
            throw EraserSession.EraserError.encodeFailed(url)
        }
    }

    // MARK: - Internal: circle stamp

    /// Rasterize a single filled circle centered at `(cx, cy)` into the
    /// buffer. Bounding box scan with radius² test.
    private static func stampCircle(
        cx: CGFloat, cy: CGFloat,
        radiusSquared rSquared: CGFloat,
        radius r: CGFloat,
        buffer: inout [UInt8],
        width: Int, height: Int,
        fillColor: UInt8
    ) {
        let minX = max(0, Int(floor(cx - r)))
        let maxX = min(width - 1, Int(ceil(cx + r)))
        let minY = max(0, Int(floor(cy - r)))
        let maxY = min(height - 1, Int(ceil(cy + r)))
        if minX > maxX || minY > maxY { return }

        for y in minY...maxY {
            let dy = CGFloat(y) + 0.5 - cy
            let dySquared = dy * dy
            if dySquared > rSquared { continue }
            let rowOffset = y * width
            for x in minX...maxX {
                let dx = CGFloat(x) + 0.5 - cx
                if dx * dx + dySquared <= rSquared {
                    buffer[rowOffset + x] = fillColor
                }
            }
        }
    }
}
