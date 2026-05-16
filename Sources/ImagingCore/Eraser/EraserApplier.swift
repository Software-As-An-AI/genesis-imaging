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
        fillColor: UInt8? = nil
    ) {
        let r = stroke.radius
        let rSquared = r * r
        let color = fillColor ?? stroke.fillColor
        for p in stroke.points {
            stampCircle(
                cx: p.x, cy: p.y, radiusSquared: rSquared,
                radius: r, buffer: &buffer,
                width: width, height: height,
                fillColor: color
            )
        }
    }

    /// Apply a sequence of strokes in order. Each stroke contributes its
    /// own fillColor unless `fillColor` override is passed (rare).
    public static func compose(
        strokes: [BrushStroke],
        onto buffer: inout [UInt8],
        width: Int, height: Int,
        fillColor: UInt8? = nil
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

    // MARK: - Mask + global background flatten (Canva paradigm, v0.3.5.6)

    /// Compose strokes onto `buffer` using a **holistic background color**
    /// sampled from the unmasked region — not per-stroke local sampling.
    ///
    /// Customer report 2026-05-16: per-stroke local sampling produced
    /// biased fill colors when the stroke started near a dark line — the
    /// annular ring caught dark pixels and the whole stroke painted a
    /// muddy mid-grey instead of the page color.
    ///
    /// Pipeline (Canva-style mask-then-flatten):
    ///   1. Build a binary mask from all strokes (radius² stamping).
    ///   2. Sample the median luminance of pixels OUTSIDE the mask in the
    ///      original `buffer` — gives the true page background regardless
    ///      of where strokes started.
    ///   3. Fill every masked pixel with that median color.
    ///
    /// Each stroke's own `fillColor` is ignored in this path — the global
    /// sample wins. Use `compose(strokes:onto:...)` if a per-stroke fill
    /// is needed (legacy callers).
    ///
    /// - Returns: the page background luminance that was used as the fill
    ///   (for callers that want to log it).
    @discardableResult
    public static func composeFlatten(
        strokes: [BrushStroke],
        onto buffer: inout [UInt8],
        width: Int, height: Int
    ) -> UInt8 {
        let n = width * height
        precondition(buffer.count == n)

        // 1. Mask buffer.
        var mask = [Bool](repeating: false, count: n)
        for stroke in strokes {
            stampMask(stroke: stroke, mask: &mask, width: width, height: height)
        }

        // 2. Background color: median luminance of unmasked pixels.
        var unmasked: [UInt8] = []
        unmasked.reserveCapacity(n / 4)  // estimate
        // Stride sampling to keep this fast on 5K images (~25M px). Step 4
        // gives ~1.5M samples — plenty for a stable median.
        var i = 0
        while i < n {
            if !mask[i] { unmasked.append(buffer[i]) }
            i += 4
        }
        // Fallback: if mask covers nearly everything, sample without stride
        // from full unmasked set.
        if unmasked.count < 1024 {
            unmasked.removeAll()
            for k in 0..<n where !mask[k] { unmasked.append(buffer[k]) }
        }
        let bg: UInt8
        if unmasked.isEmpty {
            bg = 255  // entire image masked → fallback to white
        } else {
            unmasked.sort()
            bg = unmasked[unmasked.count / 2]
        }

        // 3. Fill masked pixels with bg.
        for j in 0..<n where mask[j] {
            buffer[j] = bg
        }
        return bg
    }

    /// Rasterize a single stroke's footprint into the binary mask. Mirrors
    /// `stampCircle` geometry — radius² test inside a bounding box.
    private static func stampMask(
        stroke: BrushStroke,
        mask: inout [Bool],
        width: Int, height: Int
    ) {
        let r = stroke.radius
        let rSquared = r * r
        for p in stroke.points {
            let minX = max(0, Int(floor(p.x - r)))
            let maxX = min(width - 1, Int(ceil(p.x + r)))
            let minY = max(0, Int(floor(p.y - r)))
            let maxY = min(height - 1, Int(ceil(p.y + r)))
            if minX > maxX || minY > maxY { continue }
            for y in minY...maxY {
                let dy = CGFloat(y) + 0.5 - p.y
                let dySquared = dy * dy
                if dySquared > rSquared { continue }
                let row = y * width
                for x in minX...maxX {
                    let dx = CGFloat(x) + 0.5 - p.x
                    if dx * dx + dySquared <= rSquared {
                        mask[row + x] = true
                    }
                }
            }
        }
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
